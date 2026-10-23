#!/usr/bin/env python3
"""Inventory every normative paragraph in pinned standards, without certification.

The section-to-test links are navigation aids, not proof that every sentence in
that section is implemented. Keep media, server and player obligations visible.
"""
import argparse
import hashlib
import json
import pathlib
import re
from standards import cases

SOURCES = {
    "bis-22": "https://www.ietf.org/archive/id/draft-pantos-hls-rfc8216bis-22.txt",
    "rfc8216": "https://www.rfc-editor.org/rfc/rfc8216.txt",
}

def inventory(path, standard):
    data = path.read_bytes()
    section = ""
    paragraphs = []
    current = []
    start = 0
    def flush():
        nonlocal current
        text = " ".join(current)
        if section and re.search(r"\b(MUST|REQUIRED|SHALL|SHOULD|RECOMMENDED)\b", text):
            paragraphs.append({"section": section, "sourceLine": start, "text": text})
        current = []
    for number, line in enumerate(data.decode().splitlines(), 1):
        if re.match(r"^(Pantos|Internet-Draft|RFC 8216|\s*Pantos\s+&\s+May)", line) or "[Page " in line:
            continue
        heading = re.match(r"^([0-9]+(?:\.[0-9]+)*|[A-H](?:\.[0-9]+)*)\.\s{2,}(\S.*)$", line)
        if heading and ". . ." not in line:
            flush()
            section = heading[1]
            continue
        appendix = re.match(r"^Appendix ([A-H])\.\s+", line)
        if appendix and ". . ." not in line:
            flush()
            section = appendix[1]
            continue
        if not line.strip():
            flush()
        else:
            if not current:
                start = number
            current.append(line.strip())
    flush()
    for index, row in enumerate(paragraphs):
        section = row["section"]
        if section.startswith("3") or section.startswith("5"):
            scope = "media-bytes-or-crypto"
        elif section.startswith("6.2") or section in ["B", "B.1", "C"]:
            scope = "server-and-refresh"
        elif section.startswith("6.3") and section not in ["6.3.1", "6.3.9"]:
            scope = "player-and-refresh"
        elif section.startswith("7") or section.startswith(("D", "E", "F", "G")):
            scope = "optional-extension; playlist fields and external behavior"
        elif section.startswith("4") or section == "8" or section in ["6.3.1", "6.3.9"]:
            scope = "playlist; some obligations require media or cross-playlist context"
        else:
            scope = "context-or-security"
        row.update(id=f"{standard}:{section}:{index + 1}", scope=scope,
                   verification="inventory only; no automatic clause-level compliance claim")
        row["sectionOracleNames"] = [
            case["name"] for case in cases
            if standard == "bis-22" and re.search(r"§" + re.escape(section) + r"(?![\d.])", case["reference"])
        ]
    return {"standard": standard, "url": SOURCES[standard],
            "sha256": hashlib.sha256(data).hexdigest(), "paragraphs": paragraphs}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bis", required=True, type=pathlib.Path)
    parser.add_argument("--rfc", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    output = {"purpose": "Complete normative paragraph inventory, not a certification matrix",
              "standards": [inventory(args.bis, "bis-22"), inventory(args.rfc, "rfc8216")]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print([(x["standard"], len(x["paragraphs"])) for x in output["standards"]])
