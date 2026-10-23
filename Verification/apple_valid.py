#!/usr/bin/env python3
"""Offline Apple validation of known media, served only during this invocation.

Use --fixtures with playback_server.py's prepared media directory. No public
playlist is normalized into a positive fixture. Generated manifests describe
the downloaded media, whose hashes are included in the result.
"""
import argparse
import hashlib
import http.server
import json
import pathlib
import re
import subprocess
import threading
import urllib.parse
from apple import TOOLS, codes
from run import RESULTS, SCRATCH, probe, write
from tls_transport import transport


def run(fixtures):
    for tool in ["mediastreamvalidator", "hlsreport"]:
        if not (TOOLS / tool).is_file():
            raise RuntimeError(f"Required Apple tool missing: {TOOLS / tool}")
    directory = RESULTS / "apple-valid-media"
    directory.mkdir(parents=True, exist_ok=False)
    manifests = {}
    # Six real MPEG-TS and six fMP4 segments; AES rotates key URI/bytes/IV.
    for kind in ["ts", "fmp4"]:
        entries = json.loads((fixtures / f"{kind}.json").read_text())
        header = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-TARGETDURATION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n"
        if kind == "fmp4":
            range_text = (fixtures / "range.m3u8").read_text()
            init_length = int(re.search(r'BYTERANGE="(\d+)@0"', range_text)[1])
            header += f'#EXT-X-MAP:URI="range.mp4",BYTERANGE="{init_length}@0"\n'
        manifests[kind] = header + "".join(f'#EXTINF:{x["duration"]},\n{x["file"]}\n' for x in entries) + "#EXT-X-ENDLIST\n"
    for kind in ["aes", "range"]:
        manifests[kind] = (fixtures / f"{kind}.m3u8").read_text()
    # Legal partial-segment metadata over complete fMP4 fragments. This tests
    # PART parsing/serving/media identity, not blocking live reload timing.
    entries = json.loads((fixtures / "fmp4.json").read_text())
    target = max(float(x["duration"]) for x in entries)
    ll = manifests["fmp4"].split("#EXTINF:", 1)[0]
    ll += f"#EXT-X-PART-INF:PART-TARGET={target}\n#EXT-X-SERVER-CONTROL:PART-HOLD-BACK={3 * target}\n"
    for entry in entries:
        ll += f'#EXT-X-PART:DURATION={entry["duration"]},URI="{entry["file"]}",INDEPENDENT=YES\n#EXTINF:{entry["duration"]},\n{entry["file"]}\n'
    manifests["ll-vod"] = ll + '#EXT-X-RENDITION-REPORT:URI="{report-uri}",LAST-MSN=5,LAST-PART=0\n#EXT-X-ENDLIST\n'
    write(directory / "fixture-hashes.json", {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(fixtures.iterdir()) if p.is_file()
    })
    write(directory / "manifests.json", manifests)
    errors = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_HEAD(self):
            self.serve(False)
        def do_GET(self):
            self.serve(True)
        def serve(self, body):
            try:
                path = urllib.parse.urlsplit(self.path)
                if path.path == "/fetch":
                    resource = urllib.parse.urlsplit(urllib.parse.parse_qs(path.query)["url"][0])
                    path = resource
                relative = pathlib.PurePosixPath(path.path.lstrip("/"))
                if ".." in relative.parts:
                    self.send_error(403)
                    return
                if path.path.startswith("/manifest/"):
                    _, _, kind, candidate = path.path.split("/")
                    if kind == "ll-vod":
                        bandwidth = int(max((fixtures / x["file"]).stat().st_size * 8 / float(x["duration"]) for x in entries)) + 1
                        text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n" + "".join(
                            f"#EXT-X-STREAM-INF:BANDWIDTH={bandwidth},CLOSED-CAPTIONS=NONE\n{base}/manifest/{rendition}/{candidate}\n"
                            for rendition in ["ll-a", "ll-b"]
                        )
                    elif kind in ["ll-a", "ll-b"]:
                        other = "ll-b" if kind == "ll-a" else "ll-a"
                        text = manifests["ll-vod"].replace("{report-uri}", f"/manifest/{other}/{candidate}")
                    else:
                        text = manifests[kind]
                    if candidate != "original":
                        row = probe([{"name": kind, "text": text, "url": base + "/media/master.m3u8",
                                      "resolve": candidate == "render", "rewrite": candidate == "rewrite",
                                      "proxy": base + "/fetch"}])[0]
                        if row["status"] != "accepted":
                            raise RuntimeError(f"Valid fixture rejected: {row}")
                        text = row["text"]
                    else:
                        text = "\n".join(urllib.parse.urljoin(base + "/media/", line) if line and not line.startswith("#") else line
                                         for line in text.split("\n"))
                        text = re.sub(r'URI="([^"]+)"', lambda m: 'URI="' + (
                            m[1] if m[1].startswith("/manifest/") else urllib.parse.urljoin(base + "/media/", m[1])
                        ) + '"', text)
                    data = text.encode()
                    content_type = "application/vnd.apple.mpegurl"
                else:
                    data = (fixtures / relative.name).read_bytes()
                    content_type = "video/mp2t" if relative.name.startswith(("ts-", "aes-")) else "video/mp4"
                status = 200
                if self.headers.get("Range"):
                    match = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers["Range"])
                    if not match:
                        self.send_error(416)
                        return
                    start, end = int(match[1]), int(match[2]) if match[2] else len(data) - 1
                    if start >= len(data) or end < start:
                        self.send_error(416)
                        return
                    end = min(end, len(data) - 1)
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
                    data = data[start:end + 1]
                else:
                    self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if body:
                    self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception as error:
                errors.append(str(error))
                self.send_error(500)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    base = f"http://127.0.0.1:{server.server_port}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    results = []
    tls = transport(base, directory / "tls", TOOLS / "mediastreamvalidator")
    tls_started = False
    try:
        ready = tls.__enter__()
        tls_started = True
        base = ready["url"]
        for kind in manifests:
            for candidate in ["original", "render", "rewrite"]:
                report = directory / f"{kind}-{candidate}.json"
                command = [str(TOOLS / "mediastreamvalidator"), "--compatible-output", "v1.x",
                           "--timeout", "25", "--exit-code.threshold", "must_auth", "-O", str(report),
                           f"{base}/manifest/{kind}/{candidate}"]
                row = {"kind": kind, "candidate": candidate, "command": command}
                try:
                    with report.with_suffix(".log").open("w") as log:
                        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=45)
                    row["exit"] = process.returncode
                    data = json.loads(report.read_text())
                    row["codes"] = codes(data)
                    html = report.with_suffix(".html")
                    with report.with_suffix(".report.log").open("w") as log:
                        rendered = subprocess.run([str(TOOLS / "hlsreport"), "-R", "standard", "-o", str(html), str(report)],
                                                  stdout=log, stderr=subprocess.STDOUT, timeout=30)
                    row["reportExit"] = rendered.returncode
                    row["met"] = process.returncode == 0 and rendered.returncode == 0 and html.is_file()
                except Exception as error:
                    row.update(met=False, error=str(error))
                results.append(row)
                write(directory / "index.json", results)
                print(json.dumps(row), flush=True)
    finally:
        try:
            if tls_started:
                tls.__exit__(None, None, None)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            write(directory / "server-errors.json", errors)
    write(directory / "summary.json", {
        "positivePasses": sum(x["met"] is True for x in results),
        "llContentChecks": sum(x["kind"] == "ll-vod" and x["met"] is True for x in results),
        "llServerValidation": "HTTP/2 static PART validation; dynamic LL cases recorded separately",
        "aesDecryption": "not performed by mediastreamvalidator; requires AVPlayer device evidence",
    })
    if len(results) != len(manifests) * 3 or errors or any(
        not x["met"] for x in results
    ):
        raise RuntimeError("Apple positive-fixture validation failed")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", type=pathlib.Path, default=SCRATCH / "playback-fixtures")
    run(parser.parse_args().fixtures)
