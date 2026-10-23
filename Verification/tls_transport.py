"""Task-owned HTTP/2 proxy; official validation reuses pre-provisioned trust."""
import contextlib
import json
import shutil
import subprocess
import time
from run import HERE, SCRATCH
from tls_identity import identity, require_trust


@contextlib.contextmanager
def transport(backend, directory, validator):
    reusable = identity() if validator is not None else None
    if reusable:
        require_trust(reusable[0])  # Read-only. Missing trust fails without dialogs.
    directory.mkdir(parents=True, exist_ok=False)
    executable = SCRATCH / "http2proxy"
    subprocess.run(["go", "build", "-o", str(executable), str(HERE / "http2/main.go")], check=True)
    log = (directory / "http2.log").open("w")
    process = None
    try:
        command = [str(executable), "-work", str(directory), "-backend", backend]
        if reusable:
            # Archive only the public certificate. Read the key from lab storage.
            shutil.copyfile(reusable[0], directory / "localhost.pem")
            command += ["-cert", str(directory / "localhost.pem"), "-key", str(reusable[1])]
        process = subprocess.Popen(command,
                                   stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 10
        while not (directory / "ready.json").exists():
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("HTTP/2 proxy failed to start")
            time.sleep(0.05)
        ready = json.loads((directory / "ready.json").read_text())
        cert = ready["certificate"]
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
        # Ephemeral identity is used only for the device's separate trust store.
        # Never remove the runner's persistent certificate or private key.
        (directory / "localhost-key.pem").unlink(missing_ok=True)
