#!/usr/bin/env python3
"""Build a test-only AVPlayer app; does not modify the player project.

Device build is ad-hoc signed for the previously authorized rootless test phone.
For ordinary devices, use an Xcode development signing profile instead.
"""
import argparse
import pathlib
import plistlib
import subprocess
from run import HERE, SCRATCH

parser = argparse.ArgumentParser()
parser.add_argument("--simulator", action="store_true")
parser.add_argument("--cases", help="Optional kind/candidate subset, comma separated")
parser.add_argument("--run", default="main")
parser.add_argument("--repeat", type=int, choices=range(1, 21), default=1)
parser.add_argument("--certificate-delay", type=int, choices=range(46), default=0,
                    help="Controlled delay in the local certificate response, for diagnosing cancellation")
parser.add_argument("--on-demand-certificate", action="store_true",
                    help="Reproduce the earlier test harness fetching its certificate during an active key request")
args = parser.parse_args()
sdk = "iphonesimulator" if args.simulator else "iphoneos"
target = "arm64-apple-ios15.0-simulator" if args.simulator else "arm64-apple-ios15.0"
app = SCRATCH / ("sim" if args.simulator else "device") / "HLSVerification.app"
app.mkdir(parents=True, exist_ok=True)
sdkpath = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
subprocess.run(["xcrun", "--sdk", sdk, "swiftc", "-swift-version", "5", "-parse-as-library",
                "-sdk", sdkpath, "-target", target, "-O", "-module-cache-path", str(SCRATCH / "app-module-cache"),
                str(HERE / "AVPlayerApp.swift"), "-o", str(app / "HLSVerification")], check=True)
info = {
    "CFBundleIdentifier": "org.hlsplaylist.verification",
    "CFBundleName": "HLS Verification",
    "CFBundleExecutable": "HLSVerification",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1",
    "CFBundleShortVersionString": "1",
    "MinimumOSVersion": "15.0",
    "UIDeviceFamily": [1, 2],
    "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True, "NSAllowsArbitraryLoadsForMedia": True},
    "UILaunchScreen": {},
    "HLSVerificationRun": args.run,
    "HLSVerificationRepeat": args.repeat,
    "HLSVerificationCertificateDelay": args.certificate_delay,
    "HLSVerificationCertificatePrefetch": not args.on_demand_certificate,
}
if args.cases:
    info["HLSVerificationCases"] = args.cases
(app / "Info.plist").write_bytes(plistlib.dumps(info))
subprocess.run(["codesign", "-f", "-s", "-", str(app)], check=True)
print(app)
