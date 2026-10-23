#!/usr/bin/env python3
"""Fixed normative acceptance/rejection oracles, independent of Probe output."""
from run import RESULTS, probe, write

def media(tags, version=13):
    return f"#EXTM3U\n#EXT-X-VERSION:{version}\n#EXT-X-TARGETDURATION:6\n{tags}\n"

cases = []
def case(name, text, accepted, reference):
    cases.append({"name": name, "text": text, "accepted": accepted, "reference": reference})

for value in ["+1", "-1", "1e3", " 1", "１２", "18446744073709551616", "000000000000000000000"]:
    case("integer-" + value, media("#EXT-X-MEDIA-SEQUENCE:" + value), False, "bis §4.2 decimal-integer")
case("uint64-max", media("#EXT-X-MEDIA-SEQUENCE:18446744073709551615\n#EXTINF:6,\ns"), True, "bis §4.2 / §4.4.3.2")
case("sequence-overflow", media("#EXT-X-MEDIA-SEQUENCE:18446744073709551615\n#EXTINF:6,\ns\n#EXTINF:6,\nt"), False, "bis §4.2 / §4.4.3.2")
for value in ["+1", "-1", "1e0", "NaN", "inf", "1..0"]:
    case("decimal-" + value, media(f"#EXTINF:{value},\ns"), False, "bis §4.2 / §4.4.4.1")
for name, tags, reference in [
    ("duplicate-target", "#EXT-X-TARGETDURATION:6", "§4.4.3"),
    ("flag-value", "#EXT-X-ENDLIST:YES", "§4.4.3.4"),
    ("missing-key-method", '#EXT-X-KEY:URI="key"', "§4.4.4.4"),
    ("none-with-uri", '#EXT-X-KEY:METHOD=NONE,URI="key"', "§4.4.4.4"),
    ("ctr-with-iv", '#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI="key",IV=0x1', "§4.4.4.4"),
    ("gcm-with-iv", '#EXT-X-KEY:METHOD=AES-256-GCM,URI="key",IV=0x1', "§4.4.4.4"),
    ("invalid-iv", '#EXT-X-KEY:METHOD=AES-128,URI="key",IV=0xabcdef', "§4.2"),
    ("map-offset", '#EXT-X-MAP:URI="init",BYTERANGE="10"', "§4.4.4.5"),
    ("implicit-range", '#EXT-X-BYTERANGE:10\n#EXTINF:1,\ns', "§4.4.4.2"),
    ("late-sequence", '#EXTINF:1,\ns\n#EXT-X-MEDIA-SEQUENCE:1', "§4.4.3.2"),
    ("skip-bound", '#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=35.99', "§4.4.3.8"),
    ("hold-bound", '#EXT-X-SERVER-CONTROL:HOLD-BACK=17.99', "§4.4.3.8"),
    ("part-without-info", '#EXT-X-PART:DURATION=1,URI="p"', "§4.4.3.7"),
    ("part-hold", '#EXT-X-PART-INF:PART-TARGET=1', "§4.4.3.8"),
    ("preload-endlist", '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p"\n#EXT-X-ENDLIST', "§4.4.5.3"),
    ("report-absolute", '#EXT-X-RENDITION-REPORT:URI="https://x/r"', "§4.4.5.4"),
    ("define-missing-value", '#EXT-X-DEFINE:NAME="x"', "§4.4.2.3"),
    ("date-calendar", '#EXT-X-PROGRAM-DATE-TIME:2026-02-30T00:00:00Z', "§4.4.4.6 / ISO 8601"),
    ("daterange-no-pdt", '#EXT-X-DATERANGE:ID="x",START-DATE="2026-01-01T00:00:00Z"', "§4.4.5.1"),
    ("variable-numeric", '#EXT-X-DEFINE:NAME="n",VALUE="1"\n#EXTINF:{$n},\ns', "§4.3"),
]:
    case(name, media(tags), False, "bis " + reference)
case("missing-version", media("#EXTINF:1.0,\ns", 1), False, "bis §8")
case("duration-v5", media("#EXTINF:6.1,\ns", 5), False, "bis §8")
case("duration-v6", media("#EXTINF:6.1,\ns", 6), True, "bis §8")
case("duration-v6-too-large", media("#EXTINF:6.5,\ns", 6), False, "bis §8")
case("ignored-preload-key", media('#EXT-X-PRELOAD-HINT:TYPE=KEY,URI="k"'), True, "bis §6.3.9")
case("ignored-method", media('#EXT-X-KEY:METHOD=NEW,URI="k"\n#EXTINF:1,\ns'), True, "bis §6.3.1")
case("short-iv", media('#EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x1\n#EXTINF:1,\ns'), True, "bis §4.4.4.4")
case("hex-variable", media('#EXT-X-DEFINE:NAME="iv",VALUE="1A"\n#EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x{$iv}\n#EXTINF:1,{$not-subject-to-substitution}\ns'), True, "bis §4.3")
case("pdt-without-zone", media('#EXT-X-PROGRAM-DATE-TIME:2024-02-29T00:00:00\n#EXTINF:1,\ns'), True, "bis §4.4.4.6")
case("relative-report-omitted-counters", media('#EXT-X-RENDITION-REPORT:URI="../r"'), True, "bis §4.4.5.4")
case("required-extension", '#EXTM3U\n#EXT-X-VERSION:12\n#EXT-X-STREAM-INF:BANDWIDTH=1,REQ-NEW="x"\nignored\n#EXT-X-STREAM-INF:BANDWIDTH=2\nkept\n', True, "bis §6.3.1")
case("ll-valid", media('#EXT-X-SERVER-CONTROL:PART-HOLD-BACK=2\n#EXT-X-PART-INF:PART-TARGET=1\n#EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x1\n#EXT-X-MAP:URI="init"\n#EXT-X-PART:DURATION=0.1,URI="p0",INDEPENDENT=YES\n#EXT-X-PART:DURATION=0.85,URI="p1"\n#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p2"\n#EXT-X-RENDITION-REPORT:URI="../r"'), True, "bis §4.4.4.9 / §4.4.3.8")
case("ll-short-part", cases[-1]["text"].replace("DURATION=0.85", "DURATION=0.84"), False, "bis §4.4.4.9")
case("bad-percent", media("#EXTINF:1,\ns%Q0"), False, "RFC 3986 §2.1")
case("BOM", "\ufeff" + media(""), False, "bis §4.1")
case("not-NFC", media("#EXTINF:1,e\u0301\ns"), False, "bis §4.1")

if __name__ == "__main__":
    output = probe([{**row, "rewrite": True} for row in cases])
    results = []
    for source, row in zip(cases, output):
        met = (row["status"] == "accepted") == source["accepted"]
        if source["accepted"]:
            met = met and row["idempotent"]
        results.append({"input": {**source, "rewrite": True}, "output": row, "met": bool(met)})
    write(RESULTS / "standards-oracles.json", results)
    print("fixed normative cases:", len(results), "failures:", sum(not x["met"] for x in results), flush=True)
    if len(results) != len(cases) or any(not x["met"] for x in results):
        raise SystemExit(1)
