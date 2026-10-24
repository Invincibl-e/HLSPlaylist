#!/usr/bin/env python3
"""Deterministic feature combinations with independently constructed expectations."""
import itertools
from run import RESULTS, probe, write
from standards import cases as fixed


def cases():
    rows = []
    # Every maintained grammar oracle also runs with CRLF and without final LF.
    for case in fixed:
        for label, text in [("crlf", case["text"].replace("\n", "\r\n")),
                            ("no-final-lf", case["text"].removesuffix("\n"))]:
            rows.append({**case, "name": case["name"] + "/" + label, "text": text})
    # RFC §4.3.2, §7 / bis §4.4.4, §8: exercise context interactions,
    # not random strings whose expected acceptance is guessed from the parser.
    for version, container, encryption, ranges, discontinuity, ending in itertools.product(
            [3, 4, 5, 6, 7, 10, 13], ["ts", "fmp4"], ["none", "aes", "sample"],
            [False, True], [False, True], ["\n", "\r\n"]):
        minimum = max(3, 6 if container == "fmp4" else 1,
                      5 if encryption == "sample" else 1, 4 if ranges else 1)
        name = f"vod-v{version}-{container}-{encryption}-range{ranges}-disc{discontinuity}-{len(ending)}"
        text = f"#EXTM3U\n#EXT-X-VERSION:{version}\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:17\n#EXT-X-PLAYLIST-TYPE:VOD\n"
        for index in range(3):
            if index == 1 and discontinuity:
                text += "#EXT-X-DISCONTINUITY\n"
            if encryption == "aes":
                text += f'#EXT-X-KEY:METHOD=AES-128,URI="key{index}",IV=0x{index+1:x}\n'
            elif encryption == "sample":
                text += f'#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://key{index}",KEYFORMAT="com.apple.streamingkeydelivery"\n'
            if container == "fmp4":
                text += f'#EXT-X-MAP:URI="init{index}.mp4",BYTERANGE="100@0"\n'
            if ranges:
                text += "#EXT-X-BYTERANGE:100" + ("@0" if index == 0 else "") + "\n"
            text += f"#EXTINF:{index+1}.25,title-{index}\n" + (
                "all.m4s?sig=a%2Fb%2B%3D\n" if ranges else f"s{index}.ts?sig=a%2Fb%2B%3D\n")
        text += "#EXT-X-ENDLIST\n"
        rows.append({"name": name, "text": text.replace("\n", ending), "accepted": version >= minimum,
                     "durations": [1.25, 2.25, 3.25], "reference": "RFC 8216 §4.3.2 / §7; bis §4.4.4 / §8",
                     "minimum": minimum})
    # LL state snapshots: SKIP, discontinuity, changed key and map, completed
    # parent plus trailing PART/PRELOAD/REPORT. No claim of server simulation.
    for skip, sequence, discontinuity, key, map_id, ending in itertools.product(
            [0, 1, 10], [0, 25], [False, True], [0, 1], [0, 1], ["\n", "\r\n"]):
        name = f"ll-{skip}-{sequence}-{discontinuity}-{key}-{map_id}-{len(ending)}"
        text = (
            "#EXTM3U\n#EXT-X-VERSION:10\n#EXT-X-TARGETDURATION:6\n"
            f"#EXT-X-MEDIA-SEQUENCE:{sequence}\n#EXT-X-DISCONTINUITY-SEQUENCE:3\n"
            "#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=2,CAN-SKIP-UNTIL=36,CAN-SKIP-DATERANGES=YES\n"
            "#EXT-X-PART-INF:PART-TARGET=1\n"
            f'#EXT-X-SKIP:SKIPPED-SEGMENTS={skip},RECENTLY-REMOVED-DATERANGES="ad-a\tad-b"\n'
            + ("#EXT-X-DISCONTINUITY\n" if discontinuity else "") +
            f'#EXT-X-KEY:METHOD=AES-128,URI="key{key}",IV=0x1\n#EXT-X-MAP:URI="init{map_id}"\n'
            '#EXT-X-PART:DURATION=1,URI="p0",INDEPENDENT=YES\n'
            '#EXT-X-PART:DURATION=1,URI="p1"\n#EXTINF:2,\nparent\n'
            '#EXT-X-PART:DURATION=1,URI="p2",INDEPENDENT=YES\n'
            '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p3"\n'
            '#EXT-X-RENDITION-REPORT:URI="../other.m3u8",LAST-MSN=26,LAST-PART=0\n')
        rows.append({"name": name, "text": text.replace("\n", ending), "accepted": True,
                     "durations": [2], "reference": "bis §4.4.3–§4.4.5 LL snapshot semantics"})
    return rows


def verify(inputs, outputs):
    failures = []
    for source, out in zip(inputs, outputs):
        if source["accepted"]:
            met = (out["status"] == "accepted" and out.get("idempotent") is True
                   and out.get("rewriteIdempotent") is True and out.get("rewritePreserved") is True)
            if "durations" in source:
                met = met and [float(x) for x in out.get("durations", [])] == source["durations"]
        else:
            met = out["status"] == "rejected" and out.get("parseAccepted") is not True
        if not met:
            failures.append({"input": source, "output": out})
    return failures


if __name__ == "__main__":
    inputs = cases()
    outputs = probe([{**row, "rewrite": True} for row in inputs], timeout=180)
    failures = verify(inputs, outputs)
    write(RESULTS / "generated.json", {"cases": len(inputs), "failures": failures,
                                      "scope": "grammar variants, version/container/key/range/discontinuity combinations, LL snapshots"})
    print("Generated combinations:", len(inputs), "failures:", len(failures), flush=True)
    if failures:
        raise SystemExit(1)
