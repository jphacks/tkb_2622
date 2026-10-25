// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConnectJSONClient",
    platforms: [.iOS(.v16)],
    products: [.library(name: "ConnectJSONClient", targets: ["ConnectJSONClient"])],
    targets: [
        .target(name: "ConnectJSONClient"),
        .testTarget(name: "ConnectJSONClientTests", dependencies: ["ConnectJSONClient"]),
    ]
)
