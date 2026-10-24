"""Pure result gates, also exercised by offline harness failure injection."""
CANDIDATES = {kind: (["original", "render", "rewrite"] if kind in ["local-ll", "ts", "fmp4"]
                     else ["original", "rewrite"])
              for kind in ["local-ll", "ts", "fmp4", "aes", "range", "live", "ll", "fairplay", "tracks"]}
CASES = [f"{kind}/{candidate}" for kind, candidates in CANDIDATES.items() for candidate in candidates] + ["recovery/recovery"]
def verify(report, expected, rejections=(), origins=None):
    if not expected or report.get("simulator") is not False or report.get("complete") is not True:
        raise AssertionError("Requires completed, nonempty real-device results")
    rows = report["results"]
    if report.get("plannedCases") != expected or [x["kind"] + "/" + x["candidate"] for x in rows] != expected:
        raise AssertionError("Device case identity/order/count mismatch")
    checks = []
    for row in rows:
        name = row["kind"] + "/" + row["candidate"]
        keys = ["firstFrame", "progress10s", "pause", "resume"]
        if row["kind"] not in ["local-ll", "live", "ll"]:
            keys.append("seek")
        if row["kind"] == "tracks":
            keys += ["audioSwitchCovered", "subtitleSwitchCovered", "audioSelection", "subtitleSelection", "afterTrackSwitch"]
        met = all(row.get(key) is True for key in keys)
        if row["kind"] == "fairplay":
            met = met and row.get("licenses", 0) >= 1 and not row.get("keyErrors")
        if row["kind"] == "local-ll":
            met = met and not any("http2" in x.get("comment", "").lower() for x in row.get("errorLogs", []))
        checks.append({"name": name, "expectation": "playback", "met": bool(met)})
    return checks
