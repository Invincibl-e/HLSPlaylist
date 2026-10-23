#!/usr/bin/env python3
"""Aggregate completed runs while retaining every original failure artifact."""
import json
from run import RESULTS, write

files = ["avplayer-device.json", "avplayer-device-fairplay-auth.json", "avplayer-device-tracks.json"]
observed = {}
incomplete = []
for filename in files:
    path = RESULTS / filename
    if not path.exists():
        incomplete.append(filename)
        continue
    run = json.loads(path.read_text())
    if not run.get("complete"):
        incomplete.append(filename)
        continue
    for row in run["results"]:
        observed[(row["kind"], row["candidate"])] = {**row, "evidence": filename}

expected = []
for kind in ["ts", "fmp4", "aes", "range", "live", "ll", "fairplay", "tracks"]:
    for candidate in (["original", "render", "rewrite"] if kind in ["ts", "fmp4"] else ["original", "rewrite"]):
        expected.append((kind, candidate))
expected.append(("recovery", "recovery"))

rows = []
for kind, candidate in expected:
    row = observed.get((kind, candidate), {"kind": kind, "candidate": candidate})
    checks = {key: row.get(key) is True for key in ["firstFrame", "progress10s", "pause", "resume"]}
    if kind not in ["live", "ll"]:
        checks["seek"] = row.get("seek") is True
    if kind in ["fmp4", "tracks"]:
        checks.update({key: row.get(key) is True for key in ["audioSelection", "subtitleSelection", "afterTrackSwitch"]})
    if kind == "tracks":
        checks.update({key: row.get(key) is True for key in ["audioSwitchCovered", "subtitleSwitchCovered"]})
    if kind == "fairplay":
        # AVError.h defines -11879 as AVErrorContentKeyRequestCancelled.
        # Preserve raw errors from the earlier harness; classify only this documented code.
        cancelled = [error for error in row.get("keyErrors", [])
                     if "AVFoundationErrorDomain Code=-11879 " in error]
        failures = [error for error in row.get("keyErrors", []) if error not in cancelled]
        row["classifiedKeyCancellations"] = row.get("keyCancellations", 0) + len(cancelled)
        row["nonCancellationKeyErrors"] = failures
        checks["drm"] = row.get("certificates", 0) > 0 and row.get("licenses", 0) > 0 and not failures
    rows.append({**row, "checks": checks, "passed": all(checks.values())})
summary = {"expectedCases": len(expected), "passed": sum(row["passed"] for row in rows),
           "incompleteRuns": incomplete, "rows": rows}
write(RESULTS / "avplayer-summary.json", summary)

original = {(row["case"], row["mode"]): row for row in json.loads((RESULTS / "apple/original/index.json").read_text())}
comparisons = {}
for candidate in ["render", "rewrite"]:
    rows = json.loads((RESULTS / f"apple/{candidate}/index.json").read_text())
    differences = []
    for row in rows:
        base = original[(row["case"], row["mode"])]
        if row["codes"] != base["codes"] or row["status"] != base["status"]:
            differences.append({"case": row["case"], "mode": row["mode"],
                                "original": {"status": base["status"], "codes": base["codes"]},
                                "output": {"status": row["status"], "codes": row["codes"]}})
    comparisons[candidate] = differences
write(RESULTS / "apple-comparison.json", comparisons)
print(f"AVPlayer {summary['passed']}/{summary['expectedCases']}; incomplete runs: {incomplete}")
