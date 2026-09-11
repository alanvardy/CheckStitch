// swift-tools-version: 6.0
import PackageDescription

// Sources only: the package is tested by the app-hosted CheckStitchTests target
// (@testable import CheckStitchCore), never by `swift test` — no Tests/ dir.
let package = Package(
    name: "CheckStitchCore",
    platforms: [
        .iOS("18.7"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "CheckStitchCore", targets: ["CheckStitchCore"])
    ],
    targets: [
        .target(name: "CheckStitchCore")
    ])