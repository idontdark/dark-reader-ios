// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ReaderCoreRegressions", platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/readium/ZIPFoundation.git", exact: "3.0.1")],
    targets: [.executableTarget(name: "ReaderCoreRegressions", dependencies: [.product(name: "ReadiumZIPFoundation", package: "ZIPFoundation")], path: "Harness")]
)
