#!/usr/bin/env python3
"""Exercise vendored C APIs under ASan/UBSan, including synthetic int limits."""
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    work = pathlib.Path(os.environ.get("HLS_VERIFICATION_WORK", tempfile.mkdtemp(prefix="uri-native-")))
    work.mkdir(parents=True, exist_ok=True)
    results = pathlib.Path(os.environ.get("HLS_VERIFICATION_RESULTS", work))
    binary = work / "native-uri"
    source = ROOT / "Sources/CURIParser"
    command = ["xcrun", "clang", "-g", "-O1", "-fsanitize=address,undefined",
               "-fno-sanitize-recover=all", "-DURI_NO_UNICODE", "-DURI_STATIC_BUILD",
               "-I", str(source / "include"), str(ROOT / "Verification/native_uri.c"),
               *[str(path) for path in sorted((source / "src").glob("*.c"))
                 if path.name != "UriQuery.c"], "-o", str(binary)]
    subprocess.run(command, check=True)
    rows = []
    for name in ["normalize", "resolve", "parse-failure", "query", "append",
                 "allocation-failure", "scheme", "authority", "ipv4", "ipv6",
                 "query-delimiter", "fragment", "path", "separator"]:
        argument = "query-mark" if name == "query-delimiter" else name
        process = subprocess.run([str(binary), argument], text=True, capture_output=True)
        print(process.stdout + process.stderr, end="", flush=True)
        rows.append({"case": name, "exit": process.returncode,
                     "stdout": process.stdout, "stderr": process.stderr})
    (results / "native-uri-summary.json").write_text(json.dumps(rows, indent=2) + "\n")
    return int(any(row["exit"] != 0 for row in rows))


if __name__ == "__main__":
    raise SystemExit(main())
