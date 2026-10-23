#!/usr/bin/env python3
"""Validate independently generated valid media fixtures on playback_server.py."""
import json
import subprocess
from apple import TOOLS, codes
from run import RESULTS, write

directory = RESULTS / "apple-valid-media"
directory.mkdir(parents=True, exist_ok=True)
results = []
for kind in ["aes", "range"]:
    for candidate in ["original", "render", "rewrite"]:
        url = (f"http://127.0.0.1:8899/fixture/{kind}.m3u8" if candidate == "original"
               else f"http://127.0.0.1:8899/start/{kind}/{candidate}")
        report = directory / f"{kind}-{candidate}.json"
        command = [str(TOOLS / "mediastreamvalidator"), "--compatible-output", "v1.x",
                   "--timeout", "25", "--exit-code.threshold", "must_auth", "-O", str(report), url]
        with report.with_suffix(".log").open("w") as log:
            try:
                process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=45)
                row = {"kind": kind, "candidate": candidate, "exit": process.returncode,
                       "status": "pass" if process.returncode == 0 else "issues"}
            except subprocess.TimeoutExpired:
                row = {"kind": kind, "candidate": candidate, "status": "tool-timeout"}
        if report.exists():
            row["codes"] = codes(json.loads(report.read_text()))
        results.append(row)
        write(directory / "index.json", results)
        print(json.dumps(row), flush=True)
