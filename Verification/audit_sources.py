#!/usr/bin/env python3
"""Independent decisive checks for archived inputs; not a full HLS validator."""
import hashlib
import json
from run import CORPUS, RESULTS, write

observed = {row["name"]: row for row in json.loads((RESULTS / "archive.json").read_text())}
rows = []
for path in sorted((CORPUS / "archive").rglob("*.m3u8")):
    data = path.read_bytes()
    text = data.decode("utf-8")
    violations = []
    # The production compatibility contract exempts informative EXTINF titles.
    # Preserve the original bytes and still inspect the duration/tag/URI fields.
    syntax = "\n".join(line.split(",", 1)[0] if line.startswith("#EXTINF:") and "," in line else line
                       for line in text.split("\n"))
    controls = [ord(char) for char in syntax if (ord(char) < 32 and char not in "\r\n") or 127 <= ord(char) <= 159]
    if "\0" in text:
        controls.append(0)
    if controls:
        violations.append({"rule": "bis-22 §4.1", "reason": "forbidden control characters",
                           "codepoints": sorted(set(controls)), "count": len(controls)})
    targets = [line for line in text.splitlines() if line.startswith("#EXT-X-TARGETDURATION:")]
    is_media = any(line.startswith(("#EXTINF:", "#EXT-X-PART:", "#EXT-X-TARGETDURATION:")) for line in text.splitlines())
    if is_media and len(targets) != 1:
        violations.append({"rule": "bis-22 §4.4.3 / §4.4.3.1", "reason": "TARGETDURATION count", "count": len(targets)})
    parts_started = False
    for number, line in enumerate(text.split("\n"), 1):
        if line.startswith("#EXT-X-PART:"):
            parts_started = True
        elif line.startswith("#EXT-X-PROGRAM-DATE-TIME:") and parts_started:
            violations.append({"rule": "bis-22 §4.4.4.9", "reason": "PDT after first parent PART", "line": number})
        elif line and not line.startswith("#"):
            parts_started = False
    name = str(path.relative_to(CORPUS / "archive"))
    row = observed[name]
    rows.append({"name": name, "sha256": hashlib.sha256(data).hexdigest(),
                 "decisiveViolations": violations, "probeStatus": row["status"],
                 "decisiveRejectionMet": row["status"] == "rejected" if violations else None})
write(RESULTS / "archive-independent-audit.json", rows)
violating = [row for row in rows if row["decisiveViolations"]]
print("Independent decisive violations:", len(violating),
      "correctly rejected:", sum(row["decisiveRejectionMet"] for row in violating), flush=True)
if any(not row["decisiveRejectionMet"] for row in violating):
    raise SystemExit(1)
