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
uri_root = HERE.parent / "Sources/CURIParser"
objects = []
for source in sorted((uri_root / "src").glob("*.c")):
    obj = directory / (source.stem + ".o")
    subprocess.run(["xcrun", "--sdk", sdk_name, "clang", "-target", target,
                    "-isysroot", sdk, "-std=c99", "-O2",
                    "-DURI_NO_UNICODE", "-DURI_STATIC_BUILD",
                    "-I", str(uri_root / "include"), "-c", str(source), "-o", str(obj)], check=True)
    objects.append(obj)
subprocess.run(["xcrun", "--sdk", sdk_name, "swiftc", "-swift-version", "6",
                "-D", "SWIFT_PACKAGE", "-enable-upcoming-feature", "ExistentialAny", "-target", target,
                "-sdk", sdk, "-O", "-I", str(uri_root / "include"),
                "-module-cache-path", str(SCRATCH / (sdk_name + "-probe-module-cache")),
                *map(str, sources), str(main), *map(str, objects), "-o", str(directory / "Probe")], check=True)
subprocess.run(["codesign", "-f", "-s", "-", str(directory / "Probe")], check=True)
print(directory / "Probe")
