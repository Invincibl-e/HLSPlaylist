#!/usr/bin/env python3
"""Apple validator comparison: original vs Swift render vs Swift mapURIs.

HLS_APPLE_BIN points to the installed/extracted Apple tools directory.
The server exists only for this run and is closed even after failures.
"""
import argparse
import collections
import http.server
import json
import os
import pathlib
import subprocess
import threading
import urllib.parse
import urllib.request
from run import CORPUS, RESULTS, probe, write

TOOLS = pathlib.Path(os.environ.get("HLS_APPLE_BIN", "/tmp/hlsplaylist-validation/apple-tools-extracted/component.pkg/Payload/usr/local/bin"))
ROOT = CORPUS / "archive"

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.serve(False)

    def do_GET(self):
        self.serve(True)

    def serve(self, body):
        try:
            if self.path.startswith("/fetch?"):
                url = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)["url"][0]
                request = urllib.request.Request(url)
                if self.headers.get("Range"):
                    request.add_header("Range", self.headers["Range"])
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = response.read()
                    self.send_response(response.status)
                    for key in ["Content-Type", "Content-Range", "Accept-Ranges"]:
                        if response.headers.get(key):
                            self.send_header(key, response.headers[key])
            else:
                path = urllib.parse.urlsplit(self.path).path
                _, mode, relative = path.split("/", 2)
                target = (ROOT / relative).resolve()
                if not target.is_relative_to(ROOT.resolve()):
                    self.send_error(403)
                    return
                data = target.read_bytes()
                if target.suffix == ".m3u8":
                    prefix = f"http://127.0.0.1:{self.server.server_port}/" + mode + "/" + str(pathlib.PurePosixPath(relative).parent) + "/"
                    text = data.decode().replace("http://fixture.local/", prefix)
                    if mode != "original":
                        row = probe([{"name": relative, "text": text,
                                      "url": f"http://127.0.0.1:{self.server.server_port}{path}",
                                      "rewrite": mode == "rewrite",
                                      "proxy": f"http://127.0.0.1:{self.server.server_port}/fetch"}])[0]
                        if row["status"] != "accepted":
                            with self.server.audit_lock:
                                with (RESULTS / "apple" / mode / "rejections.jsonl").open("a") as file:
                                    file.write(json.dumps({"name": relative, "error": row["error"]}) + "\n")
                            self.send_error(422)
                            return
                        text = row["text"]
                    data = text.encode()
                self.send_response(200)
                content_type = ("application/vnd.apple.mpegurl" if target.suffix == ".m3u8" else
                                "application/vnd.apple.steering-list" if target.name == "steering.json" else
                                "application/octet-stream")
                self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if body:
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            self.send_error(502)

def codes(data):
    counts = collections.Counter()
    def visit(node):
        if isinstance(node, dict):
            for message in node.get("messages", []):
                counts[str(message["errorStatusCode"])] += 1
            for key, value in node.items():
                if key != "messages":
                    visit(value)
        elif isinstance(node, list):
            for value in node:
                visit(value)
    visit(data)
    return dict(counts)

def run(candidate):
    directory = RESULTS / "apple" / candidate
    directory.mkdir(parents=True, exist_ok=False)
    if not (TOOLS / "mediastreamvalidator").is_file():
        raise RuntimeError(f"Required Apple tool missing: {TOOLS / 'mediastreamvalidator'}")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.audit_lock = threading.Lock()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    results = []
    try:
        cases = json.loads((CORPUS / "archive-sources.json").read_text())
        for mode in ["structure", "media"]:
            for case, source in cases.items():
                if mode == "media" and not case.endswith("_media"):
                    continue
                report = directory / f"{case}-{mode}.json"
                command = [str(TOOLS / "mediastreamvalidator"), "--compatible-output", "v1.x",
                           "--timeout", "25" if mode == "media" else "8",
                           "--exit-code.threshold", "must_auth", "-O", str(report)]
                if mode == "structure":
                    command.append("-p")
                command.append(f"http://127.0.0.1:{server.server_port}/{candidate}/{case}/master.m3u8")
                with report.with_suffix(".log").open("w") as log:
                    try:
                        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=45)
                        result = {"case": case, "mode": mode, "expectedNegative": source.get("expectedNegative", False),
                                  "exit": process.returncode}
                    except subprocess.TimeoutExpired:
                        result = {"case": case, "mode": mode, "status": "tool-timeout"}
                if report.exists():
                    data = json.loads(report.read_text())
                    result["codes"] = codes(data)
                    if result.get("status") != "tool-timeout":
                        result["status"] = "issues" if result.get("exit", 1) != 0 else "pass"
                else:
                    result.setdefault("status", "no-report")
                results.append(result)
                write(directory / "index.json", results)
                print(candidate, case, mode, result["status"], result.get("codes"), flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    # Archived public sources are diagnostic comparisons, not positive oracles.
    # Infrastructure failure is still fatal; Apple findings are retained.
    if not results or any(row["status"] in ["tool-timeout", "no-report"] for row in results):
        raise RuntimeError("Apple archive comparison did not complete")
    return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate", choices=["original", "render", "rewrite"])
    run(parser.parse_args().candidate)
