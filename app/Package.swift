// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrellisReverse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrellisCore", targets: ["TrellisCore"]),
        .executable(name: "trellis-probe", targets: ["TrellisApp"]),
    ],
    targets: [
        .target(name: "TrellisCore"),
        // A compilable macOS agent skeleton. Default mode is dry-run: it never
        // asks for Accessibility and never moves a real window.
        .executableTarget(name: "TrellisApp", dependencies: ["TrellisCore"]),
        .testTarget(name: "TrellisCoreTests", dependencies: ["TrellisCore"]),
    ]
)
