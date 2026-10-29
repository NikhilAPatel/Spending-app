// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorthCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorthCore", targets: ["WorthCore"]),
    ],
    targets: [
        .target(name: "WorthCore"),
        .testTarget(name: "WorthCoreTests", dependencies: ["WorthCore"]),
    ]
)
