// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParakeetVAD",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "ParakeetVAD",
            targets: ["ParakeetVAD"]
        )
    ],
    targets: [
        .target(
            name: "ParakeetVAD",
            path: "Sources/ParakeetVAD"
        ),
        .testTarget(
            name: "ParakeetVADTests",
            dependencies: ["ParakeetVAD"],
            path: "Tests/ParakeetVADTests"
        ),
    ]
)
