// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Beam",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BeamApp", targets: ["BeamApp"]),
        .library(name: "BeamCore", targets: ["BeamCore"]),
    ],
    targets: [
        .target(
            name: "BeamCore",
            path: "Sources/BeamCore"
        ),
        .executableTarget(
            name: "BeamApp",
            dependencies: ["BeamCore"],
            path: "Sources/BeamApp"
        ),
        .testTarget(
            name: "BeamCoreTests",
            dependencies: ["BeamCore"],
            path: "Tests/BeamCoreTests"
        ),
        .testTarget(
            name: "BeamAppTests",
            dependencies: ["BeamApp", "BeamCore"],
            path: "Tests/BeamAppTests"
        ),
    ]
)
