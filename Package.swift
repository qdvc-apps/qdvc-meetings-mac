// swift-tools-version: 5.10
//
// QDVC Meetings for macOS — a native SwiftUI app for keeping a record of your
// meetings, their people and locations, and the notes, decisions and action
// items that come out of them. The workspace is a folder of plain YAML files
// (see docs/FILE_FORMAT.md).
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "MeetingsCore", targets: ["MeetingsCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation (+ Yams) only, no AppKit/SwiftUI,
    // unit-testable.
    .target(
        name: "MeetingsCore",
        dependencies: [.product(name: "Yams", package: "Yams")]
    ),
    .testTarget(
        name: "MeetingsCoreTests",
        dependencies: ["MeetingsCore"]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md).
products.insert(.executable(name: "QDVCMeetings", targets: ["QDVCMeetings"]), at: 0)
targets.insert(.executableTarget(name: "QDVCMeetings", dependencies: ["MeetingsCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCMeetings",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: targets
)
