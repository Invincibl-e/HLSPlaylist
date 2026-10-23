"""Task-owned HTTP/2 TLS proxy and localhost-only trust, cleaned on exit."""
import contextlib
import json
import os
import pathlib
import secrets
import subprocess
import time
from run import HERE, SCRATCH


@contextlib.contextmanager
def transport(backend, directory, validator):
    directory.mkdir(parents=True, exist_ok=False)
    executable = SCRATCH / "http2proxy"
    subprocess.run(["go", "build", "-o", str(executable), str(HERE / "http2/main.go")], check=True)
    keychain = directory / "test.keychain-db"
    log = (directory / "http2.log").open("w")
    process = None
    cert = None
    trusted = False
    try:
        process = subprocess.Popen([str(executable), "-work", str(directory), "-backend", backend],
                                   stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 10
        while not (directory / "ready.json").exists():
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("HTTP/2 proxy failed to start")
            time.sleep(0.05)
        ready = json.loads((directory / "ready.json").read_text())
        cert = ready["certificate"]
        if validator is not None:
            subprocess.run(["security", "create-keychain", "-p", secrets.token_hex(24), str(keychain)], check=True)
            # Limit this ephemeral trust to TLS localhost and the official validator.
            subprocess.run(["security", "add-trusted-cert", "-r", "trustRoot", "-p", "ssl", "-s", "localhost",
                            "-a", str(validator), "-k", str(keychain), cert], check=True, timeout=30)
            trusted = True
        health = subprocess.check_output(["curl", "--noproxy", "*", "--http2", "--cacert", cert, "--fail", "--silent",
                                          ready["url"] + "/__http2_health"], text=True, timeout=10)
        if json.loads(health).get("http2") is not True:
            raise RuntimeError("Test connection did not negotiate HTTP/2")
        yield ready
    finally:
        if process:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        log.close()
        try:
            if trusted:
                subprocess.run(["security", "remove-trusted-cert", cert], check=True, timeout=60)
        finally:
            try:
                if keychain.exists():
                    subprocess.run(["security", "delete-keychain", str(keychain)], check=True, timeout=30)
            finally:
                # Keep public certificate/wire log; never archive a private key.
                (directory / "localhost-key.pem").unlink(missing_ok=True)
