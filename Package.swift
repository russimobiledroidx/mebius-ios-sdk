// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mebius",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Mebius",
            targets: ["Mebius"]
        )
    ],
    targets: [
        // The core SDK target. This compiles with `swift build` and contains the
        // full public API plus the scale-mode playback path (AVPlayer).
        //
        // The real-time transport (libwebrtc) is intentionally NOT a hard
        // dependency of this SPM target: libwebrtc on iOS ships as a CocoaPods
        // binary and is not SPM-friendly. The transport sits behind a Swift
        // protocol so the public surface compiles without it. CocoaPods
        // consumers get the concrete real-time transport wired in via the
        // `MEBIUS_RTC` compilation condition (see Mebius.podspec).
        .target(
            name: "Mebius",
            path: "Sources/Mebius"
        ),
        .testTarget(
            name: "MebiusTests",
            dependencies: ["Mebius"],
            path: "Tests/MebiusTests"
        )
    ]
)
