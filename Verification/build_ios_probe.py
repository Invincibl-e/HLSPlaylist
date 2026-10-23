#!/usr/bin/env python3
"""Compile the actual library sources plus the same CLI probe for an iOS lab device."""
import pathlib
import subprocess
from run import HERE, SCRATCH

directory = SCRATCH / "ios-probe"
directory.mkdir(parents=True, exist_ok=True)
main = directory / "main.swift"
main.write_text((HERE / "Sources/Probe/main.swift").read_text().replace("import HLSPlaylist\n", ""))
sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
sources = sorted((HERE.parent / "Sources/HLSPlaylist").glob("*.swift"))
subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", "-swift-version", "6",
                "-enable-upcoming-feature", "ExistentialAny", "-target", "arm64-apple-ios15.0",
                "-sdk", sdk, "-O", "-module-cache-path", str(SCRATCH / "ios-probe-module-cache"),
                *map(str, sources), str(main), "-o", str(directory / "Probe")], check=True)
subprocess.run(["codesign", "-f", "-s", "-", str(directory / "Probe")], check=True)
print(directory / "Probe")
