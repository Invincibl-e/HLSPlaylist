#!/usr/bin/env python3
"""One fail-closed entry point; every invocation has an immutable results path."""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-root", type=pathlib.Path, default=ROOT / "Verification/results")
    parser.add_argument("--work-root", type=pathlib.Path, default=pathlib.Path("/tmp/hlsplaylist-validation"))
    parser.add_argument("--live", action="store_true", help="also fetch current Apple public playlists")
    parser.add_argument("--apple", action="store_true", help="require installed Apple tools and prepared real media")
    parser.add_argument("--fixtures", type=pathlib.Path)
    args = parser.parse_args()
    name = "suite-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    results, work = args.results_root.resolve() / name, args.work_root.resolve() / name
    results.mkdir(parents=True, exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    env = {**os.environ, "HLS_VERIFICATION_RESULTS": str(results), "HLS_VERIFICATION_WORK": str(work),
           "HLS_LIVE_TESTS": "1" if args.live else "0", "HLS_PERFORMANCE_TESTS": "0"}
    steps = [
        ("harness", [sys.executable, "Verification/test_runner.py"]),
        ("swift-asan", ["swift", "test", "--scratch-path", str(work / "swift-build"), "--sanitize", "address", "--enable-code-coverage"]),
        ("probe-asan", ["swift", "build", "--package-path", "Verification", "--scratch-path", str(work / "probe-build"), "--sanitize", "address", "--enable-code-coverage"]),
        ("oracles", [sys.executable, "Verification/standards.py"]),
        ("properties-corpus-boundaries", [sys.executable, "Verification/run.py", "corpus", "tail", "boundaries", "properties"]),
        ("archive-independent", [sys.executable, "Verification/audit_sources.py"]),
        ("swift-release", ["env", "HLS_LIVE_TESTS=0", "HLS_PERFORMANCE_TESTS=1", "swift", "test", "-c", "release",
                           "--scratch-path", str(work / "release-build")]),
    ]
    if args.apple:
        command = [sys.executable, "Verification/apple_valid.py"]
        if args.fixtures:
            command += ["--fixtures", str(args.fixtures.resolve())]
        steps.append(("apple-official", command))
    summary = {"status": "running", "results": str(results), "work": str(work),
               "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "live": "requested" if args.live else "skipped: offline run",
               "apple": "requested" if args.apple else "skipped: opt in with --apple; requires official tools and media",
               "steps": []}
    summary["sourceSHA256"] = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for pattern in ["Sources/**/*.swift", "Tests/**/*.swift", "Verification/*.py",
                        "Verification/Sources/**/*.swift", ".github/workflows/*.yml"]
        for path in sorted(ROOT.glob(pattern))
    }
    summary["python"] = sys.version
    summary["swift"] = subprocess.check_output(["swift", "--version"], cwd=ROOT, text=True).strip()
    def save():
        (results / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    save()
    print(f"Results: {results}", flush=True)
    for label, command in steps:
        started = time.monotonic()
        print(f"Running {label}", flush=True)
        try:
            with (results / f"{label}.log").open("w") as log:
                process = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=900)
            row = {"name": label, "command": command, "exit": process.returncode, "seconds": time.monotonic() - started}
        except Exception as error:
            row = {"name": label, "command": command, "error": str(error), "exit": None}
        summary["steps"].append(row)
        save()
        if row["exit"] != 0:
            summary["status"] = "failed"
            save()
            print(f"Failed {label}; see {results / (label + '.log')}", flush=True)
            return 1
    summary["status"] = "passed"
    if args.apple:
        summary["apple"] = json.loads((results / "apple-valid-media/summary.json").read_text())
        if summary["apple"].get("llServerValidation", "").startswith("not passed"):
            summary["status"] = "passed-with-limitations"
    summary["evidenceSHA256"] = {
        str(path.relative_to(results)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(results.rglob("*")) if path.is_file() and path.name != "summary.json"
    }
    save()
    print(f"{summary['status']}; evidence: {results}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
