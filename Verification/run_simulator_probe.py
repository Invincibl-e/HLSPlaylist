#!/usr/bin/env python3
"""Run normative URI expectations on the actual iOS simulator runtime."""
import json
import os
import subprocess
import sys
from run import HERE, SCRATCH, RESULTS, probe_input, write
from uri_oracles import cases, require

def main():
    subprocess.run([sys.executable, str(HERE / "build_ios_probe.py"), "--simulator"], check=True, timeout=240)
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
    devices = [(runtime, device) for runtime, group in inventory["devices"].items()
               if ".iOS-" in runtime for device in group if device.get("isAvailable")]
    requested = os.environ.get("HLS_SIMULATOR_UDID")
    candidates = [(runtime, device) for runtime, device in devices
                  if device["udid"] == requested] if requested else (
                      [(runtime, device) for runtime, device in devices if device["state"] == "Booted"] or devices)
    if not candidates:
        raise RuntimeError("An available iOS simulator is required")
    runtime, device = candidates[0]
    udid = device["udid"]
    owned = device["state"] != "Booted"
    try:
        if owned:
            subprocess.run(["xcrun", "simctl", "boot", udid], check=True, timeout=60)
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, timeout=180)
        expected = cases()
        process = subprocess.run(["xcrun", "simctl", "spawn", udid, str(SCRATCH / "simulator-probe/Probe")],
                                 input="".join(probe_input(row["input"]) for row in expected),
                                 text=True, capture_output=True, timeout=120)
        (RESULTS / "simulator-probe.stderr.log").write_text(process.stderr)
        if process.returncode:
            raise RuntimeError(f"Simulator Probe exited {process.returncode}")
        output = [json.loads(line) for line in process.stdout.splitlines()]
        write(RESULTS / "simulator-uri-output.json", output)
        summary = require(expected, output, "ios-simulator")
        write(RESULTS / "simulator-summary.json",
              {**summary, "runtime": runtime, "device": device, "ownedBoot": owned})
    finally:
        if owned:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=True, timeout=60)

if __name__ == "__main__":
    main()
