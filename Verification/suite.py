#!/usr/bin/env python3
"""One fail-closed entry point; every invocation has an immutable results path."""
import argparse
import contextlib
import datetime
import hashlib
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
from lab_connection import connected

ROOT = pathlib.Path(__file__).resolve().parent.parent

def run_step(command, env, log, timeout):
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log,
                               stderr=subprocess.STDOUT, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except BaseException:
        # Give Python finally/atexit handlers time to remove trust and device
        # uploads before killing the remaining process group.
        try:
            os.killpg(process.pid, signal.SIGINT)
            process.wait(timeout=90)
        except ProcessLookupError:
            pass
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise

def source_hashes():
    return {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for pattern in ["Package.swift", "HLSPlaylist.podspec", "Sources/**/*.swift", "Tests/**/*.swift",
                        "Verification/*.py", "Verification/*.swift", "Verification/*.m", "Verification/http2/*.go",
                        "Verification/Sources/**/*.swift", ".github/workflows/*.yml"]
        for path in sorted(ROOT.glob(pattern))
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-root", type=pathlib.Path, default=ROOT / "Verification/results")
    parser.add_argument("--work-root", type=pathlib.Path, default=pathlib.Path("/tmp/hlsplaylist-validation"))
    parser.add_argument("--live", action="store_true", help="also fetch current Apple public playlists")
    parser.add_argument("--apple", action="store_true", help="require installed Apple tools and prepared real media")
    parser.add_argument("--profile", choices=["offline", "full"], default="offline",
                        help="full requires Apple tools and a connected, provisioned lab device; no skips")
    parser.add_argument("--fixtures", type=pathlib.Path)
    args = parser.parse_args()
    full = args.profile == "full"
    args.apple = args.apple or full
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
    if full:
        steps.insert(0, ("full-prerequisites", [sys.executable, "Verification/preflight.py"]))
    if args.apple and not args.fixtures:
        steps.append(("prepare-media", [sys.executable, "Verification/playback_server.py", "--prepare"]))
    if args.apple:
        command = [sys.executable, "Verification/apple_valid.py"]
        if args.fixtures:
            command += ["--fixtures", str(args.fixtures.resolve())]
        steps.append(("apple-official", command))
    if full:
        steps.append(("ll-http2-dynamic", [sys.executable, "Verification/ll_validate.py"]))
        command = [sys.executable, "Verification/device.py"]
        if args.fixtures:
            command += ["--fixtures", str(args.fixtures.resolve())]
        steps.append(("device", command))
    summary = {"status": "running", "results": str(results), "work": str(work),
               "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "live": "requested" if args.live else "skipped: offline run",
               "apple": "requested" if args.apple else "skipped: opt in with --apple; requires official tools and media",
               "profile": args.profile, "steps": []}
    summary["sourceSHA256"] = source_hashes()
    summary["python"] = sys.version
    summary["swift"] = subprocess.check_output(["swift", "--version"], cwd=ROOT, text=True).strip()
    def save():
        (results / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    save()
    print(f"Results: {results}", flush=True)
    def interrupted(*_):
        raise KeyboardInterrupt("Verification interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        with connected(env, work) if full else contextlib.nullcontext():
            for label, command in steps:
                started = time.monotonic()
                print(f"Running {label}", flush=True)
                try:
                    with (results / f"{label}.log").open("w") as log:
                        code = run_step(command, env, log, 2700 if label == "device" else 900)
                    row = {"name": label, "command": command, "exit": code, "seconds": time.monotonic() - started}
                except Exception as error:
                    row = {"name": label, "command": command, "error": str(error), "exit": None}
                summary["steps"].append(row)
                save()
                if row["exit"] != 0:
                    raise RuntimeError(f"Failed {label}; see {results / (label + '.log')}")
    except (Exception, KeyboardInterrupt) as error:
            summary.update(status="failed", error=str(error))
            save()
            print(str(error), flush=True)
            return 1
    summary["status"] = "passed"
    if args.apple:
        summary["apple"] = json.loads((results / "apple-valid-media/summary.json").read_text())
    if source_hashes() != summary["sourceSHA256"]:
        summary["status"] = "failed"
        summary["error"] = "Source files changed during validation"
        save()
        return 1
    summary["evidenceSHA256"] = {
        str(path.relative_to(results)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(results.rglob("*")) if path.is_file() and path.name != "summary.json"
    }
    save()
    print(f"{summary['status']}; evidence: {results}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
