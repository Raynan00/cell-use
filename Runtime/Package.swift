// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CellUseNative",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [.library(name: "PhoneProbeCore", targets: ["PhoneProbeCore"])],
    targets: [
        .target(name: "PhoneProbeCore", path: "Sources/PhoneProbeCore"),
        .testTarget(name: "PhoneProbeCoreTests", dependencies: ["PhoneProbeCore"], path: "Tests/PhoneProbeCoreTests")
    ]
)

// The adapter uses Darwin and DeviceHub's Apple transport. Linux keeps the
// dependency-free core suite; the macOS build also tests the real Swift boundary.
#if os(macOS)
package.dependencies.append(.package(path: "../.build/devicehub/Packages/DeviceHubKit"))
// Match the pinned upstream Package.resolved. A fresh resolver otherwise pulls
// the renamed swift-issue-reporting alongside xctest-dynamic-overlay, which
// declare conflicting targets. Root constraints also apply to Xcode consumers.
package.dependencies += [
    .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.2.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.9.1"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.1.0"),
    .package(url: "https://github.com/apple/swift-collections", exact: "1.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.1"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", exact: "1.4.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.6.1"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.14.1"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", exact: "2.10.3"),
    .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.11"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.9.1"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.3"),
    .package(url: "https://github.com/swiftlang/swift-syntax", exact: "603.0.2"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.11.0")
]
package.dependencies.append(.package(name: "CellUse", path: ".."))
package.products.append(.library(name: "CellUseRuntime", targets: ["CellUseRuntime"]))
package.targets.append(.target(name: "CellUseRuntime", dependencies: [
    .product(name: "CellUse", package: "CellUse"),
    .product(name: "DeviceHubClient", package: "DeviceHubKit"),
    .product(name: "DeviceHubCore", package: "DeviceHubKit"),
    .product(name: "DeviceHubMedia", package: "DeviceHubKit")
], path: "Sources/CellUseRuntime"))
package.targets.append(.testTarget(name: "CellUseRuntimeTests", dependencies: [
    "CellUseRuntime", .product(name: "CellUse", package: "CellUse"),
    .product(name: "DeviceHubClient", package: "DeviceHubKit"),
    .product(name: "DeviceHubCore", package: "DeviceHubKit")
], path: "Tests/CellUseRuntimeTests"))
package.targets.append(.target(name: "PhoneProbeRouting", dependencies: [
    "PhoneProbeCore", .product(name: "DeviceHubTransport", package: "DeviceHubKit")
], path: "Sources/PhoneProbeRouting"))
package.targets.append(.testTarget(name: "PhoneProbeRoutingTests", dependencies: [
    .product(name: "DeviceHubMedia", package: "DeviceHubKit"),
    "PhoneProbeRouting", "PhoneProbeCore", .product(name: "DeviceHubCore", package: "DeviceHubKit"),
    .product(name: "DeviceHubTransport", package: "DeviceHubKit")
], path: "Tests/PhoneProbeRoutingTests"))
#endif
