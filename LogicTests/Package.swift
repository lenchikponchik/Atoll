// swift-tools-version:5.9
// Fast unit tests for Atoll's pure logic. They compile the files in
// DynamicIsland/Logic directly (symlinked into Sources/AtollLogic), so the app
// itself is never launched and the user's settings are never touched.
//
//   cd LogicTests && swift test
import PackageDescription

let package = Package(
    name: "AtollLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AtollLogic", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "AtollLogicTests", dependencies: ["AtollLogic"])
    ]
)
