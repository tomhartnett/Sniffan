// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HunterFanKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HunterFanKit", targets: ["HunterFanKit"]),
    ],
    targets: [
        .target(name: "HunterFanKit"),
        .testTarget(name: "HunterFanKitTests", dependencies: ["HunterFanKit"]),
    ]
)
