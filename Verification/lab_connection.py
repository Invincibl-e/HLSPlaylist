"""Own a USB SSH connection for one full run, or reuse an explicit lab connection."""
import contextlib
import os
import subprocess
import time


@contextlib.contextmanager
def connected(env, work):
    if env.get("HLS_SSH_CONTROL"):
        yield
        return
    udid = env.get("HLS_DEVICE_UDID")
    if not udid:
        raise RuntimeError("Set HLS_DEVICE_UDID for automatic USB connection, or HLS_SSH_CONTROL to reuse one")
    port = env.get("HLS_DEVICE_SSH_PORT") or "2239"
    env["HLS_DEVICE_SSH_PORT"] = port
    env["HLS_SSH_CONTROL"] = str(work / "ssh-control")
    options = ["-o", "ControlPath=" + env["HLS_SSH_CONTROL"], "-p", port]
    endpoint = "root@127.0.0.1"
    prefix = ["sshpass", "-e"] if env.get("SSHPASS") else []
    auth = ["-o", "NumberOfPasswordPrompts=1"] if prefix else ["-o", "BatchMode=yes"]
    with (work / "iproxy.log").open("w") as log:
        proxy = subprocess.Popen(["iproxy", "-u", udid, port, "22"], stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(0.5)
            if proxy.poll() is not None:
                raise RuntimeError("USB forwarding failed; see work/iproxy.log")
            subprocess.run(prefix + ["ssh", *options, *auth, "-o", "ConnectTimeout=10",
                "-o", "UserKnownHostsFile=" + str(work / "phone-known-hosts"),
                "-o", "StrictHostKeyChecking=accept-new", "-o", "ControlMaster=yes",
                "-o", "ControlPersist=no", "-fN", endpoint], env=env, check=True, timeout=20)
            yield
        finally:
            try:
                subprocess.run(["ssh", *options, "-O", "exit", endpoint], timeout=15, check=False)
            finally:
                proxy.terminate()
                try:
                    proxy.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proxy.kill()
                    proxy.wait()
