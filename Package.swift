// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CellUse",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CellUse", targets: ["CellUse"]),
        .library(name: "CellUseTunnel", targets: ["CellUseTunnel"])
    ],
    targets: [
        .target(name: "CellUse"),
        .target(name: "CellUseTunnel"),
        .testTarget(name: "CellUseTests", dependencies: ["CellUse"]),
        .testTarget(name: "CellUseTunnelTests", dependencies: ["CellUseTunnel"])
    ]
)
