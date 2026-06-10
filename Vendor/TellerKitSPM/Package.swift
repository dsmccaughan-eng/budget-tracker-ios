// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TellerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TellerKit", targets: ["TellerKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "TellerKit",
            path: "TellerKit.xcframework"
        ),
    ]
)
