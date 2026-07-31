// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WellSpentAPI",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "WellSpentAPI", targets: ["WellSpentAPI"])
    ],
    dependencies: [
        .package(url: "https://github.com/connectrpc/connect-swift", from: "1.2.3"),
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "WellSpentAPI",
            dependencies: [
                .product(name: "Connect", package: "connect-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "WellSpentAPITests",
            dependencies: ["WellSpentAPI"]
        ),
    ]
)
