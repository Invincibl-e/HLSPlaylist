#!/usr/bin/env python3
"""Run the same library/Probe sources directly on the authorized iOS lab phone."""
import argparse
import json
import subprocess
from run import CORPUS, RESULTS, SCRATCH, probe, probe_input, write

parser = argparse.ArgumentParser()
parser.add_argument("--ssh-port", type=int, default=2239)
parser.add_argument("--device-os", default="unknown")
parser.add_argument("--extended", action="store_true", help="Also compare external fixtures and strict boundary inputs")
args = parser.parse_args()
options = ["-o", "ControlPath=" + str(SCRATCH / "ssh-control"), "-o", "BatchMode=yes"]
ssh = ["ssh", *options, "-p", str(args.ssh_port), "root@127.0.0.1"]
remote = "/var/jb/tmp/hlsplaylist-verification"
subprocess.run(ssh + ["mkdir -p " + remote], check=True, timeout=15)
# Replace the inode, avoiding a cached code-signature identity after rebuilding.
subprocess.run(ssh + ["rm -f " + remote + "/Probe"], check=True, timeout=15)
subprocess.run(["scp", "-O", *options, "-P", str(args.ssh_port),
                str(SCRATCH / "ios-probe/Probe"), "root@127.0.0.1:" + remote + "/Probe"], check=True, timeout=30)
rows = [{"name": str(path.relative_to(CORPUS / "archive")),
         "text": path.read_text(), "rewrite": True}
        for path in sorted((CORPUS / "archive").rglob("*.m3u8"))]
if args.extended:
    rows += [{**row, "rewrite": True} for row in json.loads((CORPUS / "external-inputs.json").read_text())]
    rows += [row["input"] for row in json.loads((RESULTS / "boundaries.json").read_text())]
    rows += [row["input"] for row in json.loads((RESULTS / "standards-oracles.json").read_text())]
process = subprocess.run(ssh + [remote + "/Probe"],
                         input="".join(probe_input(row) for row in rows),
                         text=True, capture_output=True, timeout=90)
label = "extended" if args.extended else "archive"
(RESULTS / f"ios-probe-{label}.stderr.log").write_text(process.stderr)
if process.returncode:
    raise SystemExit(process.returncode)
output = [json.loads(line) for line in process.stdout.splitlines() if line.startswith("{")]
write(RESULTS / f"ios-{label}.json", output)
mac = probe(rows) if args.extended else json.loads((RESULTS / "archive.json").read_text())
write(RESULTS / f"mac-{label}.json", mac)
different = [a["name"] for a, b in zip(mac, output) if a != b]
summary = {"deviceOS": args.device_os, "inputs": len(rows), "outputs": len(output),
           "accepted": sum(row.get("status") == "accepted" for row in output),
           "exactlyEqualToMac": len(output) == len(mac) and not different,
           "differentCases": different}
write(RESULTS / f"ios-{label}-summary.json", summary)
print(json.dumps(summary))
if not summary["exactlyEqualToMac"]:
    raise SystemExit(1)
