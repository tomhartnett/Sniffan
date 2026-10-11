// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SniffanKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SniffanKit", targets: ["SniffanKit"]),
    ],
    targets: [
        .target(name: "SniffanKit"),
        .testTarget(name: "SniffanKitTests", dependencies: ["SniffanKit"]),
    ]
)
