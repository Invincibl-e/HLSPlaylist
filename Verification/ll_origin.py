"""Finite, real-time LL-HLS lab origin; generated CMAF has no timestamp resets."""
import contextlib
import datetime
import http.server
import json
import pathlib
import re
import threading
import time
import urllib.parse
from run import probe


class Origin:
    def __init__(self, media, evidence):
        self.media = media
        self.evidence = evidence
        self.base = ""
        self.started = time.monotonic() - 20
        self.epoch = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=20)
        self.limit = json.loads((media / "provenance.json").read_text())["parts"]
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.errors = []

    def available(self):
        return min(self.limit, int((time.monotonic() - self.started) * 2))

    def playlist(self, rendition, candidate, count, skip=None):
        complete, partial = divmod(count, 4)
        first = max(0, complete - 8)
        first_range = max(0, first - 1)
        omitted = max(0, complete - first - 6) if skip else 0
        lines = ["#EXTM3U", "#EXT-X-VERSION:10", "#EXT-X-INDEPENDENT-SEGMENTS",
                 "#EXT-X-TARGETDURATION:2", f"#EXT-X-MEDIA-SEQUENCE:{first}",
                 "#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,CAN-SKIP-UNTIL=12,CAN-SKIP-DATERANGES=YES,HOLD-BACK=6,PART-HOLD-BACK=1.5",
                 "#EXT-X-PART-INF:PART-TARGET=0.5", '#EXT-X-MAP:URI="/media/init.mp4"']
        if skip:
            removed = "\t".join(f"range-{n}" for n in range(max(0, first_range - 6), first_range))
            lines.append(f'#EXT-X-SKIP:SKIPPED-SEGMENTS={omitted}' +
                         (f',RECENTLY-REMOVED-DATERANGES="{removed}"' if skip == "v2" else ""))
        # Retain the range ending exactly at the first segment's PDT boundary.
        for segment in range(first_range, complete):
            if skip == "v2" and count * 0.5 - segment * 2 > 12:
                continue
            stamp = self.epoch + datetime.timedelta(seconds=segment * 2)
            lines.append(f'#EXT-X-DATERANGE:ID="range-{segment}",CLASS="org.hlsplaylist.lab",START-DATE="' +
                         stamp.isoformat(timespec="milliseconds").replace("+00:00", "Z") + '",DURATION=2')
        for segment in range(first + omitted, complete + 1):
            stamp = self.epoch + datetime.timedelta(seconds=segment * 2)
            lines.append("#EXT-X-PROGRAM-DATE-TIME:" + stamp.isoformat(timespec="milliseconds").replace("+00:00", "Z"))
            if segment >= complete - 2:
                for part in range(4 if segment < complete else partial):
                    lines.append(f'#EXT-X-PART:DURATION=0.5,URI="/media/part-{segment * 4 + part}.m4s",INDEPENDENT=YES')
            if segment < complete:
                lines += ["#EXTINF:2,", f"/media/segment-{segment}.m4s"]
        lines.append(f'#EXT-X-PRELOAD-HINT:TYPE=PART,URI="/media/part-{count}.m4s"')
        last_msn, last_part = divmod(count - 1, 4)
        other = "b" if rendition == "a" else "a"
        lines.append(f'#EXT-X-RENDITION-REPORT:URI="/ll/{candidate}/{other}.m3u8",LAST-MSN={last_msn},LAST-PART={last_part}')
        return "\n".join(lines) + "\n"

    def transform(self, text, url, candidate):
        output = text
        if candidate != "original":
            row = probe([{"name": url, "text": text, "url": url, "resolve": candidate == "render",
                          "rewrite": candidate == "rewrite", "proxy": self.base + "/fetch"}])[0]
            if row["status"] != "accepted":
                raise RuntimeError(f"Dynamic legal playlist rejected: {row}")
            output = row["text"]
        with self.lock:
            with (self.evidence / "manifests.jsonl").open("a") as file:
                file.write(json.dumps({"input": text, "output": output, "candidate": candidate, "url": url,
                                       "time": time.time()}) + "\n")
        return output

    def handler(self):
        origin = self
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_HEAD(self):
                self.serve(False)

            def do_GET(self):
                self.serve(True)

            def serve(self, body):
                started = time.monotonic()
                status = 500
                try:
                    path = urllib.parse.urlsplit(self.path)
                    query = urllib.parse.parse_qs(path.query, keep_blank_values=True)
                    if path.path == "/fetch":
                        resource = urllib.parse.urlsplit(query["url"][0])
                        forwarded = urllib.parse.parse_qs(resource.query, keep_blank_values=True)
                        forwarded.update({k: v for k, v in query.items() if k.startswith("_HLS_")})
                        path, query = resource, forwarded
                    if path.path.startswith("/ll/"):
                        _, _, candidate, name = path.path.split("/")
                        if candidate not in ["original", "render", "rewrite"]:
                            raise ValueError("candidate")
                        if name == "master.m3u8":
                            text = "#EXTM3U\n#EXT-X-VERSION:10\n#EXT-X-INDEPENDENT-SEGMENTS\n" + "".join(
                                '#EXT-X-STREAM-INF:BANDWIDTH=600000,CODECS="avc1.42c00c",RESOLUTION=256x144,FRAME-RATE=30,CLOSED-CAPTIONS=NONE\n'
                                f"/ll/{candidate}/{r}.m3u8\n" for r in ["a", "b"])
                        else:
                            if name not in ["a.m3u8", "b.m3u8"]:
                                raise ValueError("rendition")
                            for key in ["_HLS_msn", "_HLS_part"]:
                                if key in query and (len(query[key]) != 1 or not re.fullmatch(r"[0-9]+", query[key][0])):
                                    raise ValueError(key)
                            if "_HLS_part" in query and "_HLS_msn" not in query:
                                raise ValueError("PART requires MSN")
                            skip = query.get("_HLS_skip", [None])[0]
                            if skip not in [None, "YES", "v2"]:
                                raise ValueError("skip")
                            if "_HLS_msn" in query:
                                msn = int(query["_HLS_msn"][0])
                                part = int(query["_HLS_part"][0]) if "_HLS_part" in query else None
                                available = origin.available()
                                if msn > (available - 1) // 4 + 2 or (part is not None and part > (available - 1) % 4 + 6):
                                    raise ValueError("future directive")
                                required = (msn + 1) * 4 if part is None else msn * 4 + min(part, 4) + 1
                                while origin.available() < required:
                                    if origin.stop.wait(0.02):
                                        return
                                    if time.monotonic() - started > 6:
                                        self.send_error(503)
                                        status = 503
                                        return
                            text = origin.playlist(name[0], candidate, origin.available(), skip)
                        url = origin.base + path.path
                        data = origin.transform(text, url, candidate).encode()
                        mime = "application/vnd.apple.mpegurl"
                    elif path.path.startswith("/media/"):
                        name = pathlib.PurePosixPath(path.path).name
                        match = re.fullmatch(r"part-(\d+)\.m4s", name)
                        if match:
                            needed = int(match[1]) + 1
                            if needed > origin.limit or needed > origin.available() + 12:
                                self.send_error(404)
                                status = 404
                                return
                            while origin.available() < needed:
                                if origin.stop.wait(0.02):
                                    return
                        elif name != "init.mp4" and not re.fullmatch(r"segment-\d+\.m4s", name):
                            raise ValueError("resource")
                        data = (origin.media / name).read_bytes()
                        mime = "video/mp4"
                    else:
                        self.send_error(404)
                        status = 404
                        return
                    status = 200
                    full_length = len(data)
                    range_header = self.headers.get("Range")
                    if range_header:
                        match = re.fullmatch(r"bytes=(\d+)-(\d*)", range_header)
                        if not match:
                            raise ValueError("range")
                        start = int(match[1])
                        end = min(int(match[2]) if match[2] else full_length - 1, full_length - 1)
                        if start >= full_length or end < start:
                            self.send_response(416)
                            self.send_header("Content-Range", f"bytes */{full_length}")
                            self.send_header("Content-Length", "0")
                            self.end_headers()
                            status = 416
                            return
                        status = 206
                        data = data[start:end + 1]
                    self.send_response(status)
                    if status == 206:
                        self.send_header("Content-Range", f"bytes {start}-{end}/{full_length}")
                    self.send_header("Content-Type", mime)
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Accept-Ranges", "bytes")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    if body:
                        self.wfile.write(data)
                except ValueError:
                    status = 400
                    self.send_error(400)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception as error:
                    origin.errors.append(str(error))
                    self.send_error(500)
                finally:
                    with origin.lock:
                        with (origin.evidence / "requests.jsonl").open("a") as file:
                            file.write(json.dumps({"path": self.path, "status": status,
                                                   "seconds": time.monotonic() - started}) + "\n")
        return Handler


@contextlib.contextmanager
def serving(media, evidence):
    evidence.mkdir(parents=True, exist_ok=True)
    origin = Origin(media, evidence)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), origin.handler())
    origin.base = f"http://127.0.0.1:{server.server_port}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield origin
    finally:
        origin.stop.set()
        server.shutdown()
        server.server_close()
        thread.join()
        (evidence / "server-errors.json").write_text(json.dumps(origin.errors, indent=2))
        if origin.errors:
            raise RuntimeError(f"LL origin errors: {origin.errors}")
