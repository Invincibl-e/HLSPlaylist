#!/usr/bin/env python3
"""Fail-closed device profile: build, install, run, assert evidence and clean up."""
import argparse
import contextlib
import http.server
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import threading
import time
import urllib.parse
from cmaf import prepare
from ll_origin import serving
from tls_transport import transport
from device_trust import trusted
from device_checks import CASES, verify
import playback_server
from run import HERE, RESULTS, SCRATCH, write


def run(args):
    if not args.helper:
        raise RuntimeError("Lab TrollStore helper path required via --helper or HLS_DEVICE_HELPER")
    control = args.ssh_control or str(SCRATCH / "ssh-control")
    env = {**os.environ, "HLS_SSH_CONTROL": control}
    ssh = ["ssh", "-o", "ControlPath=" + control, "-o", "BatchMode=yes",
           "-o", "ConnectTimeout=10", "-p", str(args.ssh_port), "root@127.0.0.1"]
    device_os = plistlib.loads(subprocess.check_output(
        ssh + ["cat /System/Library/CoreServices/SystemVersion.plist"], timeout=15))["ProductVersion"]
    RESULTS.mkdir(parents=True, exist_ok=True)
    def command(script, *arguments):
        subprocess.run([sys.executable, str(HERE / script), *map(str, arguments)], env=env, check=True, timeout=240)
    media = args.media or SCRATCH / "cmaf"
    if not media.exists():
        prepare(media)
    if args.fixtures:
        playback_server.FIXTURES = args.fixtures
    elif not (playback_server.FIXTURES / "aes.m3u8").exists():
        playback_server.prepare()
    expected = CASES if args.cases is None else args.cases.split(",")
    if not expected or len(set(expected)) != len(expected) or any(x not in CASES for x in expected):
        raise ValueError("Unknown, duplicate or empty device case selection")
    expected = [x for x in CASES if x in expected]
    command("build_app.py", "--cases", ",".join(expected), "--run", "full")
    command("build_ios_probe.py")
    command("run_ios_probe.py", "--ssh-port", args.ssh_port, "--ssh-control", control, "--device-os", device_os, "--extended")
    result = RESULTS / "avplayer-device-full.json"
    if result.exists():
        raise RuntimeError("Refusing to reuse device evidence")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 8899), playback_server.Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    installed = False
    forwarded = []
    try:
        with serving(media, RESULTS / "device-ll") as origin, contextlib.ExitStack() as stack:
            ready = stack.enter_context(transport(origin.base, RESULTS / "device-ll/tls", None))
            stack.enter_context(trusted(ssh, ready["certificate"], RESULTS / "device-ll"))
            backend_port = urllib_port(ready["url"])
            origin.base = "https://localhost:8898"
            for spec in ["8899:127.0.0.1:8899", f"8898:127.0.0.1:{backend_port}"]:
                subprocess.run(ssh[:-1] + ["-O", "forward", "-R", spec, ssh[-1]], check=True, timeout=15)
                forwarded.append(spec)
            installed = True
            command("phone.py", "install", "--ssh-port", args.ssh_port, "--helper", args.helper)
            command("phone.py", "launch", "--ssh-port", args.ssh_port)
            deadline = time.monotonic() + len(expected) * 100 + 60
            seen = 0
            while time.monotonic() < deadline:
                if result.exists():
                    report = json.loads(result.read_text())
                    if len(report["results"]) != seen:
                        seen = len(report["results"])
                        print(f"Device {seen}/{len(expected)}: {report['results'][-1]['kind']}/{report['results'][-1]['candidate']}", flush=True)
                    if report.get("complete"):
                        rejection_file = RESULTS / "playback-rejections.jsonl"
                        rejections = [json.loads(x) for x in rejection_file.read_text().splitlines()] if rejection_file.exists() else []
                        checks = verify(report, expected, rejections, playback_server.URLS)
                        write(RESULTS / "device-checks.json", checks)
                        if any(not x["met"] for x in checks):
                            raise AssertionError("Device playback failed; see device-checks.json")
                        break
                time.sleep(1)
            else:
                raise TimeoutError(f"Device did not finish {len(expected)} cases")
            request_file = RESULTS / "playback-requests.jsonl"
            requests = [json.loads(line) for line in request_file.read_text().splitlines()] if request_file.exists() else []
            if "aes/rewrite" in expected:
                keys = {x["source"] for x in requests if "/key-" in x["source"] and x["status"] == 200}
                if len(keys) < 2:
                    raise AssertionError("Key rotation did not fetch distinct keys")
            if "recovery/recovery" in expected and not any(x["candidate"] == "recovery" and x["status"] == 503 for x in requests):
                raise AssertionError("Recovery failure was not injected")
            wire = [urllib.parse.unquote(line) for line in (RESULTS / "device-ll/tls/http2.log").read_text().splitlines()]
            transport_checks = []
            for name in expected:
                if name.startswith("local-ll/"):
                    candidate = name.split("/")[1]
                    lines = [line for line in wire if f"/ll/{candidate}/" in line]
                    transport_checks.append({"name": name, "met": bool(lines) and
                        all("HTTP/2.0" in line for line in lines) and
                        any("_HLS_msn=" in line and "_HLS_part=" in line and "_HLS_skip=v2" in line for line in lines)})
            write(RESULTS / "device-transport-checks.json", transport_checks)
            if any(not row["met"] for row in transport_checks):
                raise AssertionError("Device did not exercise HTTP/2 blocking delta reload")
    finally:
        cleanup_errors = []
        try:
            actions = [("stop",), ("uninstall", "--helper", args.helper)] if installed else []
            for action in [*actions, ("remove-upload",)]:
                try:
                    command("phone.py", *action, "--ssh-port", args.ssh_port)
                except Exception as error:
                    cleanup_errors.append(str(error))
        finally:
            for spec in forwarded:
                try:
                    subprocess.run(ssh[:-1] + ["-O", "cancel", "-R", spec, ssh[-1]], timeout=15, check=True)
                except Exception as error:
                    cleanup_errors.append(str(error))
            server.shutdown()
            server.server_close()
            thread.join()
            write(RESULTS / "device-cleanup.json", {"errors": cleanup_errors})
        if cleanup_errors:
            raise RuntimeError("Device cleanup failed: " + "; ".join(cleanup_errors))


def urllib_port(url):
    import urllib.parse
    return urllib.parse.urlsplit(url).port


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssh-port", type=int, default=int(os.environ.get("HLS_DEVICE_SSH_PORT") or "2239"))
    parser.add_argument("--ssh-control", default=os.environ.get("HLS_SSH_CONTROL"))
    parser.add_argument("--helper", default=os.environ.get("HLS_DEVICE_HELPER"))
    parser.add_argument("--media", type=pathlib.Path)
    parser.add_argument("--fixtures", type=pathlib.Path)
    parser.add_argument("--cases", help="Explicit subset for diagnosis; full profile does not set this")
    run(parser.parse_args())
