"""Ephemeral localhost TLS trust on an authorized rootless lab device."""
import contextlib
import json
import pathlib
import plistlib
import shlex
import subprocess
from run import HERE, SCRATCH, write


@contextlib.contextmanager
def trusted(ssh, certificate, evidence):
    directory = SCRATCH / "device-trust"
    directory.mkdir(exist_ok=True)
    binary = directory / "DeviceTrust"
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    subprocess.run(["xcrun", "clang", "-isysroot", sdk, "-target", "arm64-apple-ios15.0", "-fobjc-arc",
                    "-framework", "Foundation", "-framework", "Security", str(HERE / "DeviceTrust.m"),
                    "-o", str(binary)], check=True)
    entitlements = directory / "entitlements.plist"
    entitlements.write_bytes(plistlib.dumps({"platform-application": True, "modify-anchor-certificates": True}))
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(entitlements), str(binary)], check=True)
    der = directory / "localhost.der"
    subprocess.run(["openssl", "x509", "-in", str(certificate), "-outform", "DER", "-out", str(der)], check=True)
    remote = "/var/jb/tmp/hlsplaylist-device-trust"
    subprocess.run(ssh + ["mkdir -p " + remote], check=True, timeout=15)
    # Stream uploads over the existing SSH connection, avoiding new credentials.
    for path in [binary, der]:
        subprocess.run(ssh + ["cat > " + remote + "/" + shlex.quote(path.name)], input=path.read_bytes(), check=True, timeout=30)
    subprocess.run(ssh + ["chmod 700 " + remote + "/DeviceTrust"], check=True, timeout=15)
    results = []
    def action(name):
        process = subprocess.run(ssh + [remote + "/DeviceTrust " + name + " " + remote + "/localhost.der"],
                                 capture_output=True, text=True, timeout=30)
        row = {"action": name, "exit": process.returncode, "stdout": process.stdout, "stderr": process.stderr}
        results.append(row)
        write(evidence / "device-trust.json", results)
        if process.returncode:
            raise RuntimeError(f"Device trust {name} failed: {row}")
        return json.loads(process.stdout)
    try:
        state = action("add")
        if not state["trustedLocalhost"]:
            raise RuntimeError("Device did not trust localhost")
        yield
    finally:
        state = action("remove")
        if state["present"] or state["trustedLocalhost"]:
            raise RuntimeError("Device test certificate was not removed")
        subprocess.run(ssh + ["rm -rf " + remote], check=True, timeout=15)
