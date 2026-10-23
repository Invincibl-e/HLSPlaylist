// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HLSVerification",
    platforms: [.macOS(.v12), .iOS(.v15)],
    dependencies: [.package(path: "..")],
    targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "HLSPlaylist", package: "HLSPlaylist")])],
    swiftLanguageModes: [.v6]
)
