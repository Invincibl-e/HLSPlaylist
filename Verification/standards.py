#!/usr/bin/env python3
"""Fixed normative acceptance/rejection oracles, independent of Probe output."""
from run import RESULTS, probe, write

def media(tags, version=13):
    return f"#EXTM3U\n#EXT-X-VERSION:{version}\n#EXT-X-TARGETDURATION:6\n{tags}\n"

cases = []
def case(name, text, accepted, reference):
    cases.append({"name": name, "text": text, "accepted": accepted, "reference": reference})

for name, ids in [("empty", ""), ("tab-delimited", "ad-a\tad-b")]:
    case("delta-v2-" + name, media(f'#EXT-X-SKIP:SKIPPED-SEGMENTS=2,RECENTLY-REMOVED-DATERANGES="{ids}"', 10),
         True, "bis §4.4.5.2 empty quoted-string / TAB-delimited IDs")
case("delta-v2-tab-outside-field", media('#EXT-X-SKIP:SKIPPED-SEGMENTS=2,RECENTLY-REMOVED-DATERANGES="a\tb",X-OTHER="c\td"', 10),
     False, "bis §4.1 / §4.4.5.2 scoped TAB exception")

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

def master(tags, version=13):
    return f"#EXTM3U\n#EXT-X-VERSION:{version}\n{tags}\n"

# Attribute grammar is checked independently, including unknown extensions.
for bad in ['URI="x",URI="y"', 'uri="x"', 'URI ="x"', 'URI= "x"',
            'URI="x",', 'URI="x"junk', 'URI="', 'URI=""', 'URI=x y']:
    case("attributes-" + bad, media("#EXT-X-MAP:" + bad), False, "bis §4.2")
for flag in ["ENDLIST", "I-FRAMES-ONLY", "INDEPENDENT-SEGMENTS"]:
    case("duplicate-" + flag, media(f"#EXT-X-{flag}\n#EXT-X-{flag}"), False, "bis §4.4")
for tag, attributes, required, context, reference in [
    ("STREAM-INF", 'BANDWIDTH=1', ["BANDWIDTH"], "master-uri", "§4.4.6.2"),
    ("I-FRAME-STREAM-INF", 'BANDWIDTH=1,URI="v"', ["BANDWIDTH", "URI"], "master", "§4.4.6.3"),
    ("MEDIA", 'TYPE=AUDIO,GROUP-ID="g",NAME="n"', ["TYPE", "GROUP-ID", "NAME"], "master", "§4.4.6.1"),
    ("SESSION-DATA", 'DATA-ID="id",VALUE="v"', ["DATA-ID"], "master", "§4.4.6.4"),
    ("SESSION-KEY", 'METHOD=AES-128,URI="k"', ["METHOD", "URI"], "master", "§4.4.6.5"),
    ("CONTENT-STEERING", 'SERVER-URI="s"', ["SERVER-URI"], "master", "§4.4.6.6"),
    ("MAP", 'URI="init"', ["URI"], "media", "§4.4.4.5"),
    ("PART", 'DURATION=1,URI="p"', ["DURATION", "URI"], "ll", "§4.4.4.9"),
    ("PART-INF", 'PART-TARGET=1', ["PART-TARGET"], "ll", "§4.4.3.7"),
    ("PRELOAD-HINT", 'TYPE=PART,URI="p"', ["TYPE", "URI"], "media", "§4.4.5.3"),
    ("RENDITION-REPORT", 'URI="../r"', ["URI"], "media", "§4.4.5.4"),
    ("SKIP", 'SKIPPED-SEGMENTS=1', ["SKIPPED-SEGMENTS"], "media", "§4.4.5.2"),
    ("START", 'TIME-OFFSET=1', ["TIME-OFFSET"], "media", "§4.4.2.2"),
]:
    for missing in required:
        remaining = ",".join(x for x in attributes.split(",") if not x.startswith(missing + "="))
        tag_text = "#EXT-X-" + tag + ":" + (remaining or 'X-EXTENSION="v"')
        if context.startswith("master"):
            text = master(tag_text + ("\nv" if context == "master-uri" else ""))
        else:
            text = media(('#EXT-X-SERVER-CONTROL:PART-HOLD-BACK=2\n' +
                          ('#EXT-X-PART-INF:PART-TARGET=1\n' if tag != "PART-INF" else ""))
                         + tag_text if context == "ll" else tag_text)
        case("required-" + tag + "-" + missing, text, False, "bis " + reference)

for value, accepted in [("2", True), ("6/JOC", True), ("2/-/BINAURAL", True),
                        ("16/3OA/IMMERSIVE", True), ("x", False), ("2//BINAURAL", False),
                        ("2/joc", False), ("2/JOC,", False), ("2/", False)]:
    case("channels-" + value, master(f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="g",NAME="n",CHANNELS="{value}"'),
         accepted, "bis §4.4.6.1 CHANNELS")
for value, accepted in [('JSON', True), ('RAW', True), ('NEW', True), ('"JSON"', False)]:
    case("session-format-" + value, master(f'#EXT-X-SESSION-DATA:DATA-ID="id",URI="data",FORMAT={value}\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv'),
         accepted, "bis §4.4.6.4 / §6.3.1")
case("ignored-format-with-value", master('#EXT-X-SESSION-DATA:DATA-ID="id",VALUE="v",FORMAT="NEW"'), True, "bis §4.4.6.4")
case("duplicate-steering", master('#EXT-X-CONTENT-STEERING:SERVER-URI="a"\n#EXT-X-CONTENT-STEERING:SERVER-URI="b"'), False, "bis §4.4.6.6")
case("missing-pathway", master('#EXT-X-CONTENT-STEERING:SERVER-URI="a",PATHWAY-ID="p"\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv'), False, "bis §4.4.6.6")
groups = '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English",LANGUAGE="en",CHANNELS="2",URI="a"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="b",NAME="English",LANGUAGE="en",CHANNELS="6",URI="b"'
case("equivalent-groups", master(groups), True, "bis §4.4.6.1.1")
case("different-group-members", master(groups.replace('NAME="English",LANGUAGE="en",CHANNELS="6"', 'NAME="French",LANGUAGE="fr",CHANNELS="6"')), False, "bis §4.4.6.1.1")
case("different-group-attributes", master(groups.replace('LANGUAGE="en",CHANNELS="6"', 'LANGUAGE="fr",CHANNELS="6"')), False, "bis §4.4.6.1.1")
case("duplicate-group-name", master(groups + '\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English"'), False, "bis §4.4.6.1.1")
case("duplicate-default", master('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="A",DEFAULT=YES\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="B",DEFAULT=YES'), False, "bis §4.4.6.1.1")
case("duplicate-session-data", master('#EXT-X-SESSION-DATA:DATA-ID="id",VALUE="a"\n#EXT-X-SESSION-DATA:DATA-ID="id",VALUE="b"'), False, "bis §4.4.6.4")
case("duplicate-session-key", master('#EXT-X-SESSION-KEY:METHOD=AES-128,URI="k"\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI="k"'), False, "bis §4.4.6.5")

pdt = "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00Z\n"
for attributes, accepted in [
    ('X-ASSET-URI="https://example.test/ad.m3u8"', True),
    ('X-ASSET-LIST="../ads.json"', True),
    ('X-ASSET-URI="../ad.m3u8"', False),
    ('X-ASSET-URI="https://example.test/ad",X-ASSET-LIST="ads.json"', False),
    ('X-EXTENSION="v"', False),
]:
    case("interstitial-" + attributes, media(pdt + '#EXT-X-DATERANGE:ID="ad",CLASS="com.apple.hls.interstitial",START-DATE="2026-01-01T00:00:00Z",' + attributes),
         accepted, "bis Appendix D.2")
ranges = pdt + '#EXT-X-DATERANGE:ID="a",CLASS="c",START-DATE="2026-01-01T00:00:00Z",END-ON-NEXT=YES\n#EXT-X-DATERANGE:ID="b",CLASS="c",START-DATE="2026-01-01T00:00:01Z",END-ON-NEXT=YES'
case("end-on-next-adjacent", media(ranges), True, "bis §4.4.5.1")
case("end-on-next-same-start", media(ranges.replace("00:00:01Z", "00:00:00Z")), False, "bis §4.4.5.1")
case("end-on-next-overlap", media(ranges.replace("END-ON-NEXT=YES", "DURATION=2", 1)), False, "bis §4.4.5.1")
case("end-on-next-unknown-prior-end", media(ranges.replace("END-ON-NEXT=YES", 'X-NOTE="unknown duration"', 1)), True, "bis §4.4.5.1")
for change in ['END-ON-NEXT=YES', 'DURATION=-1', 'END-DATE="2025-01-01T00:00:00Z"', 'CUE="PRE,POST"']:
    case("daterange-" + change, media(pdt + '#EXT-X-DATERANGE:ID="a",START-DATE="2026-01-01T00:00:00Z",' + change), False, "bis §4.4.5.1")
for feature, minimum in [
    ('#EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x1', 2),
    ('#EXTINF:0.5,\ns', 3),
    ('#EXT-X-BYTERANGE:10@0\n#EXTINF:1,\ns', 4),
    ('#EXT-X-I-FRAMES-ONLY', 4),
    ('#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k"', 5),
    ('#EXT-X-KEY:METHOD=AES-128,URI="k",KEYFORMAT="identity"', 5),
    ('#EXT-X-MAP:URI="init"', 6),
    ('#EXT-X-SKIP:SKIPPED-SEGMENTS=1', 9),
    ('#EXT-X-SKIP:SKIPPED-SEGMENTS=1,RECENTLY-REMOVED-DATERANGES="a"', 10),
]:
    case("version-below-" + str(minimum) + "-" + feature, media(feature, minimum - 1), False, "bis §8")
    case("version-at-" + str(minimum) + "-" + feature, media(feature, minimum), True, "bis §8")
for tag in ["DISCONTINUITY", "KEY:METHOD=NONE", 'MAP:URI="init"', "PROGRAM-DATE-TIME:2026-01-01T00:00:00Z"]:
    case("after-part-" + tag, media('#EXT-X-SERVER-CONTROL:PART-HOLD-BACK=2\n#EXT-X-PART-INF:PART-TARGET=1\n#EXT-X-PART:DURATION=1,URI="p"\n#EXT-X-' + tag), False, "bis §4.4.4.9")

for value, accepted in [("VOD", True), ("EVENT", True), ("NEW", True),
                        ('"VOD"', False), ("VOD,EVENT", False), (" VOD", False), ("", False)]:
    case("playlist-type-" + value, media("#EXT-X-PLAYLIST-TYPE:" + value), accepted, "bis §4.2 / §4.4.3.5")
for value, accepted in [("PRE,ONCE", True), ("NEW,ONCE", True), ("ONCE,ONCE", True),
                        ("PRE,,ONCE", False), ("PRE, ONCE", False), ("ONCE,", False)]:
    case("cue-list-" + value, media(pdt + '#EXT-X-DATERANGE:ID="c",START-DATE="2026-01-01T00:00:00Z",CUE="' + value + '"'),
         accepted, "bis §4.2 / §4.4.5.1")
case("import-value", media('#EXT-X-DEFINE:IMPORT="token"\n#EXTINF:1,\ns?token={$token}'), True, "bis §4.4.2.3")
cases[-1]["imports"] = {"token": "a%2Fb"}
case("import-without-parent", media('#EXT-X-DEFINE:IMPORT="token"'), False, "bis §4.4.2.3")
case("query-value", media('#EXT-X-DEFINE:QUERYPARAM="token"\n#EXTINF:1,\ns?token={$token}'), True, "bis §4.4.2.3")
cases[-1]["url"] = "https://fixture.test/path/master.m3u8?token=a%252Fb"
case("query-without-value", media('#EXT-X-DEFINE:QUERYPARAM="token"'), False, "bis §4.4.2.3")
cases[-1]["url"] = "https://fixture.test/path/master.m3u8?token"
case("query-disallowed-quote", media('#EXT-X-DEFINE:QUERYPARAM="token"'), False, "bis §4.4.2.3")
cases[-1]["url"] = "https://fixture.test/path/master.m3u8?token=%22"
case("undefined-variable", media("#EXTINF:1,\ns?token={$undefined}"), False, "bis §4.3 / §6.3.1")
case("late-variable", media('#EXTINF:1,\ns?token={$later}\n#EXT-X-DEFINE:NAME="later",VALUE="v"'), False, "bis §6.3.1")
semantic_roles = {
    "ignored-method": {"key": 0, "segment": 1},
    "ignored-preload-key": {"preloadHint": 0},
    "required-extension": {"variant": 1},
    "session-format-NEW": {"sessionData": 0, "variant": 1},
    "ll-valid": {"partialSegment": 2, "key": 1, "initializationSection": 1, "preloadHint": 1, "renditionReport": 1},
}
for row in cases:
    if row["name"] in semantic_roles:
        row["expectedRoleCounts"] = semantic_roles[row["name"]]
case("consecutive-discontinuities", media("#EXT-X-DISCONTINUITY-SEQUENCE:5\n#EXT-X-DISCONTINUITY\n#EXT-X-DISCONTINUITY\n#EXTINF:1,\ns\n#EXT-X-DISCONTINUITY\n#EXT-X-DISCONTINUITY"),
     True, "bis §4.4.3.3 / §6.2.4")
cases[-1]["expectedDiscontinuityCounts"] = ["2"]
cases[-1]["expectedTrailingDiscontinuityCount"] = "2"
case("consecutive-discontinuity-overflow", cases[-1]["text"].replace("SEQUENCE:5", "SEQUENCE:18446744073709551612"),
     False, "bis §4.4.3.3 / §6.2.2")

if __name__ == "__main__":
    output = probe([{**row, "rewrite": True} for row in cases])
    results = []
    for source, row in zip(cases, output):
        met = (row["status"] == "accepted") == source["accepted"]
        if source["accepted"]:
            met = met and row["idempotent"]
            met = met and all(row.get("roles", []).count(role) == count
                              for role, count in source.get("expectedRoleCounts", {}).items())
            if "expectedDiscontinuityCounts" in source:
                met = met and row.get("discontinuityCounts") == source["expectedDiscontinuityCounts"]
                met = met and row.get("trailingDiscontinuityCount") == source["expectedTrailingDiscontinuityCount"]
        else:
            met = met and row.get("parseAccepted") is not True
        results.append({"input": {**source, "rewrite": True}, "output": row, "met": bool(met)})
    write(RESULTS / "standards-oracles.json", results)
    print("fixed normative cases:", len(results), "failures:", sum(not x["met"] for x in results), flush=True)
    if len(results) != len(cases) or any(not x["met"] for x in results):
        raise SystemExit(1)
