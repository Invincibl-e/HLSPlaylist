#!/usr/bin/env python3
"""Actual HTTP/2 LL reload semantics and official Apple media validation."""
import argparse
import json
import pathlib
import re
import subprocess
import time
import urllib.parse
from apple import TOOLS, codes
from cmaf import prepare
from ll_origin import serving
from run import RESULTS, SCRATCH, write
from tls_transport import transport


def assertions(origin, ready, directory):
    checks = []
    def check(name, value):
        checks.append({"name": name, "met": bool(value)})
        write(directory / "http-assertions.json", checks)
        if not value:
            raise AssertionError(name)

    def get(url, status=200, extra=()):
        started = time.monotonic()
        response = subprocess.run(
            ["curl", "--noproxy", "*", "--http2", "--cacert", ready["certificate"],
             "--silent", "--show-error", "--max-time", "10", "-D", str(directory / "headers.tmp"),
             "-o", str(directory / "body.tmp"), "-w", "%{http_version} %{http_code}", *extra, url],
            text=True, capture_output=True, check=True)
        if response.stdout != f"2 {status}":
            raise AssertionError(f"{url}: {response.stdout}, wanted HTTP/2 {status}")
        return (directory / "body.tmp").read_bytes(), time.monotonic() - started

    def media_uri(value):
        parsed = urllib.parse.urlsplit(value)
        if parsed.path == "/fetch":
            return urllib.parse.urlsplit(urllib.parse.parse_qs(parsed.query)["url"][0]).path
        return parsed.path

    for candidate in ["original", "render", "rewrite"]:
        base = origin.base + f"/ll/{candidate}/a.m3u8"
        def request(query="", status=200):
            # Exercise delivery directives appended to a rewritten playlist URL.
            url = (origin.base + "/fetch?url=" + urllib.parse.quote(base, safe="") +
                   ("&" + query if query else "")) if candidate == "rewrite" else base + ("?" + query if query else "")
            return get(url, status)
        data, _ = request()
        text = data.decode()
        first = int(re.search(r"#EXT-X-MEDIA-SEQUENCE:(\d+)", text)[1])
        segments = [media_uri(line) for line in text.splitlines() if line and not line.startswith("#")]
        check(candidate + "/window", segments == [f"/media/segment-{n}.m4s" for n in range(first, first + 8)])
        check(candidate + "/parts", len(re.findall("#EXT-X-PART:", text)) >= 8)
        report = re.search(r'#EXT-X-RENDITION-REPORT:URI="([^"]+)",LAST-MSN=(\d+),LAST-PART=(\d+)', text)
        hint = re.search(r'#EXT-X-PRELOAD-HINT:TYPE=PART,URI="([^"]+)"', text)
        next_part = int(re.search(r"part-(\d+)\.m4s", media_uri(hint[1]))[1])
        check(candidate + "/report", report and media_uri(report[1]) == f"/ll/{candidate}/b.m3u8" and
              (int(report[2]), int(report[3])) == divmod(next_part - 1, 4))
        for skip in ["YES", "v2"]:
            delta, _ = request("_HLS_skip=" + skip)
            check(candidate + "/delta-" + skip, "#EXT-X-SKIP:SKIPPED-SEGMENTS=2" in delta.decode() and
                  len([x for x in delta.decode().splitlines() if x and not x.startswith("#")]) == 6)
            delta_text = delta.decode()
            if skip == "v2":
                window_first = int(re.search(r"#EXT-X-MEDIA-SEQUENCE:(\d+)", delta_text)[1])
                removed_end = max(0, window_first - 1)
                expected_removed = "\t".join(f"range-{n}" for n in range(max(0, removed_end - 6), removed_end))
                check(candidate + "/delta-v2-removed-ids",
                      re.search(r'RECENTLY-REMOVED-DATERANGES="([^"]*)"', delta_text)[1] == expected_removed)
            else:
                check(candidate + "/delta-YES-retains-dateranges", delta_text.count("#EXT-X-DATERANGE:") == 9)
        for invalid in ["_HLS_part=1", "_HLS_msn=-1", "_HLS_msn=x", "_HLS_msn=",
                        "_HLS_msn=1&_HLS_msn=2", "_HLS_msn=999999", "_HLS_msn=1&_HLS_part=99",
                        "_HLS_skip=invalid"]:
            request(invalid, 400)
            check(candidate + "/reject-" + invalid, True)
        # Ask two PARTs ahead, guaranteeing a measurable wait despite scheduling.
        target = origin.available() + 1
        msn, part = divmod(target, 4)
        blocked, elapsed = request(f"_HLS_msn={msn}&_HLS_part={part}")
        check(candidate + "/blocking", 0.25 < elapsed < 3 and
              f"part-{target}.m4s" in urllib.parse.unquote(blocked.decode()))
        msn = origin.available() // 4
        blocked, _ = request(f"_HLS_msn={msn}&_HLS_part=4")
        check(candidate + "/part-index-rollover", f"part-{(msn + 1) * 4}.m4s" in urllib.parse.unquote(blocked.decode()))
        msn = origin.available() // 4
        blocked, _ = request(f"_HLS_msn={msn}")
        check(candidate + "/complete-parent-reload", f"segment-{msn}.m4s" in urllib.parse.unquote(blocked.decode()))
        target = origin.available() + 1
        body, elapsed = get(origin.base + f"/media/part-{target}.m4s")
        check(candidate + "/preload-wait", 0.25 < elapsed < 3 and body == (origin.media / f"part-{target}.m4s").read_bytes())
        body, _ = get(origin.base + "/media/init.mp4", 206, ["-H", "Range: bytes=8-31"])
        check(candidate + "/range", body == (origin.media / "init.mp4").read_bytes()[8:32])
        get(origin.base + "/media/init.mp4", 416, ["-H", "Range: bytes=999999999-"])
        check(candidate + "/unsatisfied-range", True)
        _, elapsed = request("_HLS_msn=0")
        check(candidate + "/old-msn-immediate", elapsed < 1)
        target = origin.available() + 3
        cancelled = subprocess.run(["curl", "--noproxy", "*", "--http2", "--cacert", ready["certificate"],
                                    "--silent", "--max-time", "0.1", origin.base + f"/media/part-{target}.m4s"],
                                   capture_output=True)
        check(candidate + "/cancel", cancelled.returncode == 28)
        get(origin.base + "/media/init.mp4")
        check(candidate + "/responsive-after-cancel", True)
        later, _ = request()
        check(candidate + "/sequence-advances", int(re.search(rb"#EXT-X-MEDIA-SEQUENCE:(\d+)", later)[1]) > first)
        limit = origin.limit
        try:
            origin.limit = origin.available()
            _, elapsed = request(f"_HLS_msn={origin.limit // 4 + 1}", 503)
            check(candidate + "/blocked-source-timeout", 6 <= elapsed < 8)
        finally:
            origin.limit = limit
    (directory / "headers.tmp").unlink()
    (directory / "body.tmp").unlink()


def run(media):
    directory = RESULTS / "ll-dynamic"
    directory.mkdir(parents=True, exist_ok=False)
    if not media.exists():
        prepare(media)
    write(directory / "media-provenance.json", json.loads((media / "provenance.json").read_text()))
    results = []
    with serving(media, directory) as origin:
        with transport(origin.base, directory / "tls", TOOLS / "mediastreamvalidator") as ready:
            origin.base = ready["url"]
            assertions(origin, ready, directory)
            for candidate in ["original", "render", "rewrite"]:
                output = directory / f"apple-{candidate}.json"
                command = [str(TOOLS / "mediastreamvalidator"), "--compatible-output", "v1.x",
                           "--timeout", "35", "--limit.video", "35", "--exit-code.threshold", "must_auth", "-O", str(output),
                           origin.base + f"/ll/{candidate}/master.m3u8"]
                with output.with_suffix(".log").open("w") as log:
                    process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=70)
                with output.with_suffix(".report.log").open("w") as log:
                    rendered = subprocess.run([str(TOOLS / "hlsreport"), "-R", "standard", "-o",
                                               str(output.with_suffix(".html")), str(output)],
                                              stdout=log, stderr=subprocess.STDOUT, timeout=30)
                row = {"candidate": candidate, "exit": process.returncode, "reportExit": rendered.returncode,
                       "codes": codes(json.loads(output.read_text())), "command": command,
                       "met": process.returncode == 0 and rendered.returncode == 0 and output.with_suffix(".html").is_file()}
                results.append(row)
                write(directory / "apple-index.json", results)
                print(json.dumps(row), flush=True)
    if len(results) != 3 or not all(x["met"] for x in results):
        raise RuntimeError("Official dynamic LL validation failed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--media", type=pathlib.Path, default=SCRATCH / "cmaf")
    run(parser.parse_args().media)
