#!/usr/bin/env python3
"""Install/launch/stop the isolated test app on an authorized rootless lab phone.

SSH keys are preferred; if SSHPASS is already set, sshpass -e is used.
No credentials are stored in this project.
"""
import argparse
import os
import shlex
import subprocess
import zipfile
from run import SCRATCH

parser = argparse.ArgumentParser()
parser.add_argument("action", choices=["install", "launch", "stop", "remove-upload", "uninstall"])
parser.add_argument("--ssh-port", type=int, default=2239)
parser.add_argument("--helper", help="Existing TrollStore trollstorehelper path (install/uninstall)")
args = parser.parse_args()
prefix = ["sshpass", "-e"] if os.environ.get("SSHPASS") else []
options = ["-o", "PubkeyAuthentication=no"] if prefix else []
options += ["-o", "NumberOfPasswordPrompts=1", "-o", "ConnectTimeout=10",
            "-o", "ControlMaster=auto", "-o", "ControlPersist=600",
            "-o", "ControlPath=" + os.environ.get("HLS_SSH_CONTROL", str(SCRATCH / "ssh-control")),
            "-o", "UserKnownHostsFile=" + str(SCRATCH / "phone-known-hosts"),
            "-o", "StrictHostKeyChecking=accept-new"]
ssh = prefix + ["ssh", *options, "-p", str(args.ssh_port), "root@127.0.0.1"]

def remote(command):
    return subprocess.check_output(ssh + [command], text=True, timeout=60)

if args.action == "install":
    if not args.helper:
        parser.error("--helper is required for install")
    app = SCRATCH / "device/HLSVerification.app"
    ipa = SCRATCH / "HLSVerification.ipa"
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in app.rglob("*"):
            if path.is_file():
                archive.write(path, "Payload/HLSVerification.app/" + str(path.relative_to(app)))
    subprocess.run(prefix + ["scp", "-O", *options, "-P", str(args.ssh_port), str(ipa),
                              "root@127.0.0.1:/tmp/HLSVerification.ipa"], check=True, timeout=60)
    print(remote(shlex.quote(args.helper) + " install force /tmp/HLSVerification.ipa"))
elif args.action == "launch":
    print(remote("uiopen --bundleid org.hlsplaylist.verification"))
elif args.action == "stop":
    listing = remote("ps -A -o pid=,comm=")
    for line in listing.splitlines():
        pieces = line.strip().split(None, 1)
        if len(pieces) == 2 and pieces[1].endswith("/HLSVerification.app/HLSVerification"):
            print(remote("kill -TERM " + str(int(pieces[0]))))
elif args.action == "remove-upload":
    print(remote("rm -f /tmp/HLSVerification.ipa"))
elif args.action == "uninstall":
    if not args.helper:
        parser.error("--helper is required for uninstall")
    print(remote(shlex.quote(args.helper) + " uninstall org.hlsplaylist.verification"))
