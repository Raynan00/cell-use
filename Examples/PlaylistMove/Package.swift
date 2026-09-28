// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaylistMoveCore",
    products: [.library(name: "PlaylistMoveCore", targets: ["PlaylistMoveCore"])],
    dependencies: [.package(name: "CellUse", path: "../..")],
    targets: [
        .target(name: "PlaylistMoveCore", dependencies: [.product(name: "CellUse", package: "CellUse")]),
        .testTarget(name: "PlaylistMoveCoreTests", dependencies: ["PlaylistMoveCore"])
    ]
)
