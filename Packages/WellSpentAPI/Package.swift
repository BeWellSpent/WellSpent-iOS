// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WellSpentAPI",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "WellSpentAPI", targets: ["WellSpentAPI"]),
        .library(name: "WellSpentREST", targets: ["WellSpentREST"]),
    ],
    dependencies: [
        .package(url: "https://github.com/connectrpc/connect-swift", from: "1.2.3"),
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.28.0"),
        // The REST half of the API. Apple's own generator, run as a build
        // plugin so there is no checked-in generated code and no extra step in
        // ci_post_clone.sh beyond fetching the contract itself.
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.2"),
        // Declared explicitly even though swift-openapi-runtime already pulls
        // it in: RESTClient's middleware names HTTPRequest/HTTPFields directly,
        // and relying on the transitive import links fine under `swift build`
        // (static) but fails at link time under Xcode's dynamic package
        // frameworks with "Undefined symbol: HTTPTypes.HTTPFields.init".
        // Same class of issue as the app target's direct Connect/SwiftProtobuf
        // dependencies — see this repo's CLAUDE.md.
        .package(url: "https://github.com/apple/swift-http-types", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "WellSpentAPI",
            dependencies: [
                .product(name: "Connect", package: "connect-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        // Separate target rather than more files in WellSpentAPI: the generator
        // plugin owns its target's sources, and mixing buf-generated Connect
        // code into a directory a second generator writes into is asking for
        // trouble. It also keeps the dependency graph honest — nothing in the
        // Connect target can accidentally reach for a REST type.
        .target(
            name: "WellSpentREST",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .testTarget(
            name: "WellSpentAPITests",
            dependencies: ["WellSpentAPI", "WellSpentREST"]
        ),
    ]
)
