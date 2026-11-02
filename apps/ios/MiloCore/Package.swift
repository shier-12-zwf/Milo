// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiloCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MiloCore", targets: ["MiloCore"])],
    // Command Line Tools does not ship the Testing module. This test-only
    // release avoids the newer _TestingInterop runtime absent from that SDK.
    dependencies: [.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")],
    targets: [
        .target(name: "MiloCore"),
        .testTarget(name: "MiloCoreTests", dependencies: [
            "MiloCore", .product(name: "Testing", package: "swift-testing"),
        ]),
    ]
)
