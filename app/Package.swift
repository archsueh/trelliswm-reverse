// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrellisReverse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrellisCore", targets: ["TrellisCore"]),
        .library(name: "TrellisAX", targets: ["TrellisAX"]),
        .executable(name: "trellis-probe", targets: ["TrellisApp"]),
        .executable(name: "TrellisStudio", targets: ["TrellisStudio"]),
        .executable(name: "TrellisWM", targets: ["TrellisWM"]),
    ],
    targets: [
        .target(name: "TrellisCore"),
        // Accessibility bridge shared by the read-only probe and the real WM.
        .target(name: "TrellisAX", dependencies: ["TrellisCore"]),
        // A compilable macOS agent skeleton. Default mode is dry-run: it never
        // asks for Accessibility and never moves a real window.
        .executableTarget(name: "TrellisApp", dependencies: ["TrellisCore", "TrellisAX"]),
        // Native AppKit workbench packaged as Trellis Reverse.app. Visualises the
        // derived layout grammar and camera; still never touches real windows.
        .executableTarget(name: "TrellisStudio", dependencies: ["TrellisCore"]),
        // Menu-bar tiling agent packaged as Trellis WM.app. Moves real windows
        // only after Accessibility is granted and the user enables tiling.
        .executableTarget(name: "TrellisWM", dependencies: ["TrellisCore", "TrellisAX"]),
        .testTarget(name: "TrellisCoreTests", dependencies: ["TrellisCore"]),
    ]
)
