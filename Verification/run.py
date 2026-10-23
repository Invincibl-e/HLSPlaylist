#!/usr/bin/env python3
"""Reproducible validation of the actual local Swift package; no player adapter."""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import random
import re
import shutil
import subprocess
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
SCRATCH = pathlib.Path(os.environ.get("HLS_VERIFICATION_WORK", "/tmp/hlsplaylist-validation")).resolve()
RESULTS = pathlib.Path(os.environ.get("HLS_VERIFICATION_RESULTS", str(HERE / "results")))
CORPUS = HERE / "corpus"
PROBE = SCRATCH / "probe-build/debug/Probe"

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

def probe_input(row):
    return json.dumps({**row, "textUTF8": base64.b64encode(row["text"].encode("utf-8")).decode("ascii")}) + "\n"

def probe(rows, timeout=60):
    environment = os.environ.copy()
    environment["LLVM_PROFILE_FILE"] = str(SCRATCH / "probe-%p.profraw")
    p = subprocess.run([str(PROBE)], input="".join(probe_input(x) for x in rows),
                       text=True, capture_output=True, timeout=timeout, env=environment)
    if p.returncode:
        raise RuntimeError(f"Probe exited {p.returncode}: {p.stderr[-6000:]}")
    output = [json.loads(x) for x in p.stdout.splitlines()]
    if len(output) != len(rows) or [x.get("name") for x in output] != [x.get("name") for x in rows]:
        raise RuntimeError("Probe output count or input identity mismatch")
    if any(x.get("status") not in ("accepted", "rejected") for x in output):
        raise RuntimeError("Probe returned an invalid status")
    return output

def require_results(results, label):
    if any(not row["met"] for row in results):
        raise RuntimeError(f"{label}: failed expectations; see {RESULTS}")

def extract():
    provenance = json.loads((CORPUS / "provenance.json").read_text())
    extracted = []
    quoted = r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*" """
    quoted = quoted.strip()
    def decode(value):
        def replace(match):
            code = match[1]
            if code.startswith(("u", "x")):
                return chr(int(code[1:], 16))
            return {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f"}.get(code, code)
        return re.sub(r"\\(u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)", replace, value)
    for source in provenance:
        if source["path"].endswith("LICENSE"):
            continue
        text = (CORPUS / "external" / source["project"] / source["path"]).read_text()
        def add(value, offset, kind):
            if value.lstrip("\ufeff \t\r\n").startswith("#EXTM3U"):
                extracted.append({"name": f"{source['project']}/{source['path']}:{text.count(chr(10),0,offset)+1}",
                                  "text": value, "source": source["url"], "extraction": kind})
        for match in re.finditer(r"`((?:\\.|[^`])*)`", text, re.S):
            if "${" not in match[1]:
                add(decode(match[1]), match.start(), "static-template")
        array_spans = []
        pattern = r"\[\s*((?:(?:" + quoted + r")\s*,?\s*)+)\]\.join\((['\"])(.*?)\2\)"
        for match in re.finditer(pattern, text, re.S):
            values = [decode(token[1:-1]) for token in re.findall(quoted, match[1])]
            add(decode(match[3]).join(values), match.start(), "static-array-join")
            array_spans.append(match.span())
        pattern = r"(?:(?:" + quoted + r")\s*(?:\+\s*)?)+"
        for match in re.finditer(pattern, text):
            if any(start <= match.start() < end for start, end in array_spans):
                continue
            # Quoted fragments inside other (dynamic) arrays are not standalone manifests.
            if source["project"] == "shaka":
                line_start = text.rfind("\n", 0, match.start()) + 1
                if not re.search(r"(?:=|\+)\s*$", text[line_start:match.start()]):
                    continue
            values = [decode(token[1:-1]) for token in re.findall(quoted, match[0])]
            add("".join(values), match.start(), "static-concatenation")
    unique = {x["text"]: x for x in extracted}
    write(CORPUS / "external-inputs.json", list(unique.values()))
    print("external static inputs", len(unique), flush=True)

def prepare():
    if (SCRATCH / "archive/playlists/original").exists():
        shutil.copytree(SCRATCH / "archive/playlists/original", CORPUS / "archive", dirs_exist_ok=True)
        shutil.copy2(SCRATCH / "archive/results/sources.json", CORPUS / "archive-sources.json")
    elif not (CORPUS / "archive").exists():
        raise RuntimeError("Restore the archived corpus before running prepare")
    sources = [
        ("hls.js", "video-dev/hls.js", ["tests/unit/loader/m3u8-parser.ts"], "LICENSE"),
        ("shaka", "shaka-project/shaka-player",
         ["test/hls/hls_parser_unit.js", "test/hls/manifest_text_parser_unit.js", "test/hls/hls_live_unit.js"], "LICENSE"),
    ]
    provenance = []
    pinned = {}
    if (CORPUS / "provenance.json").exists():
        pinned = {row["project"]: row["revision"] for row in json.loads((CORPUS / "provenance.json").read_text())}
    for name, repo, paths, license_path in sources:
        sha = pinned.get(name) or subprocess.check_output(
            ["git", "ls-remote", "https://github.com/" + repo + ".git", "HEAD"],
            text=True, timeout=45).split()[0]
        for path in paths + [license_path]:
            url = f"https://raw.githubusercontent.com/{repo}/{sha}/{path}"
            data = urllib.request.urlopen(url, timeout=45).read()
            target = CORPUS / "external" / name / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            provenance.append({"project": name, "revision": sha, "path": path, "url": url,
                               "sha256": hashlib.sha256(data).hexdigest()})
    write(CORPUS / "provenance.json", provenance)
    extract()

def corpus():
    rows = [{"name": str(p.relative_to(CORPUS / "archive")), "text": p.read_text(), "rewrite": True}
            for p in sorted((CORPUS / "archive").rglob("*.m3u8"))]
    for label, inputs in [("archive", rows), ("external", json.loads((CORPUS / "external-inputs.json").read_text()))]:
        outputs = probe(inputs)
        write(RESULTS / (label + ".json"), outputs)
        if isinstance(outputs, list):
            print(label, len(outputs), {s: sum(x["status"] == s for x in outputs) for s in ["accepted", "rejected"]},
                  "non-idempotent", sum(x.get("idempotent") is False for x in outputs), flush=True)
            if any(x["status"] == "accepted" and x.get("idempotent") is not True for x in outputs):
                raise RuntimeError(f"{label}: accepted input did not round-trip")

def player():
    rows = [{"name": str(p.relative_to(CORPUS / "archive")), "text": p.read_text()}
            for p in sorted((CORPUS / "archive").rglob("*.m3u8"))]
    process = subprocess.run(["dart", str(HERE / "PlayerProbe.dart")],
                             input="".join(json.dumps(row) + "\n" for row in rows),
                             text=True, capture_output=True, timeout=60)
    if process.returncode:
        raise RuntimeError(process.stderr)
    output = [json.loads(line) for line in process.stdout.splitlines()]
    write(RESULTS / "player-integration.json", output)
    print("actual player Dart mapper", len(output), "rejected",
          sum(row["status"] == "rejected" for row in output), flush=True)

def tail():
    header = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:6\n#EXT-X-PROGRAM-DATE-TIME:2026-10-23T00:00:00Z\n"
    segment = "#EXTINF:6,\nsegment.ts\n"
    tag = '#EXT-X-DATERANGE:ID="ad",CLASS="com.apple.hls.interstitial",START-DATE="2026-10-23T00:00:00Z",X-ASSET-LIST="assets.json"\n'
    inputs = [{"name": name, "text": header + body + "#EXT-X-ENDLIST\n", "rewrite": True}
              for name, body in [("before-segment", tag + segment), ("after-last-segment", segment + tag)]]
    output = probe(inputs)
    results = []
    for source, row in zip(inputs, output):
        met = row["status"] == "accepted" and row.get("roles", []).count("interstitialAssetList") == 1
        results.append({"input": source, "output": row, "met": met})
    write(RESULTS / "trailing-interstitial.json", results)
    print("interstitial URI placement", [(row["input"]["name"], row["met"]) for row in results], flush=True)
    require_results(results, "tail")

def boundaries():
    base = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n"
    cases = [
        ("nan-duration", base + "#EXTINF:NaN,\ns.ts\n#EXT-X-ENDLIST\n", "reject"),
        ("infinite-duration", base + "#EXTINF:inf,\ns.ts\n#EXT-X-ENDLIST\n", "reject"),
        ("negative-duration", base + "#EXTINF:-1,\ns.ts\n#EXT-X-ENDLIST\n", "reject"),
        ("unclosed-key-quote", base + '#EXT-X-KEY:METHOD=AES-128,URI="key\n#EXTINF:6,\ns.ts\n', "reject"),
        ("duplicate-target", base + "#EXT-X-TARGETDURATION:7\n#EXTINF:6,\ns.ts\n", "reject"),
        ("missing-target", "#EXTM3U\n#EXTINF:6,\ns.ts\n#EXT-X-ENDLIST\n", "reject"),
        ("image-stream-uri", '#EXTM3U\n#EXT-X-IMAGE-STREAM-INF:BANDWIDTH=2000,URI="tiles.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=100000\nv.m3u8\n', "rewrite-all"),
        ("preload-extension", base + '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="next.m4s",X-NEW="preserve-me"\n', "preserve"),
        ("rendition-extension", base + '#EXT-X-RENDITION-REPORT:URI="other.m3u8",LAST-MSN=2,X-NEW="preserve-me"\n', "preserve"),
        ("precision-duration", base + "#EXT-X-VERSION:3\n#EXTINF:0.123456789,\ns.ts\n#EXT-X-ENDLIST\n", "precision"),
        ("max-target-live-offset", "#EXTM3U\n#EXT-X-TARGETDURATION:9223372036854775807\n#EXTINF:6,\ns.ts\n", "no-trap"),
    ]
    results = []
    for name, text, expected in cases:
        row = {"name": name, "text": text, "strict": True, "rewrite": True,
               "liveOffset": expected == "no-trap"}
        output = probe([row], timeout=10)
        if isinstance(output, list):
            output = output[0]
        met = (output.get("status") == "rejected" if expected == "reject" else
               output.get("status") == "accepted" and output.get("roles", []).count("imageVariant") == 1 and "https://routed.test/" in output.get("text", "") if expected == "rewrite-all" else
               "preserve-me" in output.get("text", "") if expected == "preserve" else
               "0.123456789" in output.get("rendered", "") if expected == "precision" else
               output.get("status") == "accepted" and "liveOffset" in output)
        result = {"input": row, "expectation": expected, "met": met, "output": output}
        if expected == "no-trap":
            result["controlWithoutLiveOffset"] = probe([{**row, "liveOffset": False}], timeout=10)
        results.append(result)
    write(RESULTS / "boundaries.json", results)
    print("boundary expectations met", sum(x["met"] for x in results), "/", len(results), flush=True)
    require_results(results, "boundaries")

def properties():
    rng = random.Random(8216)
    rows = []
    expected = {}
    for i in range(2000):
        count = rng.randrange(1, 30)
        durations = [rng.randrange(1, 6_000_000) / 1_000_000 for _ in range(count)]
        uris = [f"part{i}-{j}.ts?token=a%2Fb%2B%3D&n={j}" for j in range(count)]
        text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:12\n"
        text += "".join(f"#EXTINF:{d:.6f},\n{u}\n" for d, u in zip(durations, uris)) + "#EXT-X-ENDLIST\n"
        rows.append({"name": str(i), "text": text, "rewrite": True})
        expected[str(i)] = (durations, uris)
    outputs = probe(rows, timeout=120)
    failures = []
    for row in outputs:
        durations, uris = expected[row["name"]]
        checks = {
            "accepted": row["status"] == "accepted",
            "segment-count": row.get("segments") == len(uris),
            "duration-values": [float(x) for x in row.get("durations", [])] == durations,
            "render-idempotent": row.get("idempotent") is True,
            "rewrite-count": row.get("roles", []).count("segment") == len(uris),
            "signed-query-preserved": [
                urllib.parse.parse_qs(urllib.parse.urlsplit(line).query).get("url", [""])[0]
                for line in row.get("text", "").splitlines() if line.startswith("https://routed.test/")
            ] == ["https://fixture.test/path/" + u for u in uris],
        }
        if not all(checks.values()):
            failures.append({"name": row["name"], "checks": checks, "output": row})
    write(RESULTS / "properties.json", {"seed": 8216, "cases": len(rows), "checksPerCase": 6, "failures": failures})
    print("properties", len(rows), "failures", len(failures), flush=True)
    if failures:
        raise RuntimeError("Property expectations failed")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("steps", nargs="+", choices=["prepare", "extract", "corpus", "player", "tail", "boundaries", "properties"])
    args = parser.parse_args()
    RESULTS.mkdir(parents=True, exist_ok=True)
    for step in args.steps:
        globals()[step]()
