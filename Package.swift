// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CellUse",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CellUse", targets: ["CellUse"])],
    targets: [
        .target(name: "CellUse"),
        .testTarget(name: "CellUseTests", dependencies: ["CellUse"])
    ]
)
