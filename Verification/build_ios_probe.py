#!/usr/bin/env python3
"""Compile the actual library sources plus the same CLI probe for an iOS lab device."""
import pathlib
import subprocess
import argparse
import platform
from run import HERE, SCRATCH

parser = argparse.ArgumentParser()
parser.add_argument("--simulator", action="store_true")
args = parser.parse_args()
sdk_name = "iphonesimulator" if args.simulator else "iphoneos"
target = (("arm64" if platform.machine() == "arm64" else "x86_64") + "-apple-ios15.0-simulator"
          if args.simulator else "arm64-apple-ios15.0")
directory = SCRATCH / ("simulator-probe" if args.simulator else "ios-probe")
directory.mkdir(parents=True, exist_ok=True)
main = directory / "main.swift"
main.write_text((HERE / "Sources/Probe/main.swift").read_text().replace("import HLSPlaylist\n", ""))
sdk = subprocess.check_output(["xcrun", "--sdk", sdk_name, "--show-sdk-path"], text=True).strip()
sources = sorted((HERE.parent / "Sources/HLSPlaylist").glob("*.swift"))
subprocess.run(["xcrun", "--sdk", sdk_name, "swiftc", "-swift-version", "6",
                "-enable-upcoming-feature", "ExistentialAny", "-target", target,
                "-sdk", sdk, "-O", "-module-cache-path", str(SCRATCH / (sdk_name + "-probe-module-cache")),
                *map(str, sources), str(main), "-o", str(directory / "Probe")], check=True)
subprocess.run(["codesign", "-f", "-s", "-", str(directory / "Probe")], check=True)
print(directory / "Probe")
