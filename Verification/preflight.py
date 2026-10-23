#!/usr/bin/env python3
"""The full profile never silently skips an unavailable official tool/device."""
import importlib.util
import os
import pathlib
import shutil
import subprocess
from apple import TOOLS

missing = [name for name in ["go", "ffmpeg", "ffprobe", "curl", "security", "xcrun", "codesign", "ssh", "scp"]
           if not shutil.which(name)]
missing += [str(TOOLS / name) for name in ["mediastreamvalidator", "hlsreport"] if not (TOOLS / name).is_file()]
if importlib.util.find_spec("requests") is None:
    missing.append("Python requests (same interpreter as suite.py)")
if not os.environ.get("HLS_DEVICE_HELPER"):
    missing.append("HLS_DEVICE_HELPER: authorized lab device TrollStore helper path")
if missing:
    raise SystemExit("Full profile prerequisites missing: " + ", ".join(missing))
command = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
if os.environ.get("HLS_SSH_CONTROL"):
    command += ["-o", "ControlPath=" + os.environ["HLS_SSH_CONTROL"]]
command += ["-p", os.environ.get("HLS_DEVICE_SSH_PORT") or "2239", "root@127.0.0.1",
            "test -r /System/Library/CoreServices/SystemVersion.plist"]
subprocess.run(command, check=True, timeout=15)
print("Full profile tools and real-device SSH available; no skipped prerequisite")
