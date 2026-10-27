// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FFmpegSwiftSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "FFmpegSwiftSDK",
            targets: ["FFmpegSwiftSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        // CFFmpeg: C bridging target with bundled headers
        .target(
            name: "CFFmpeg",
            dependencies: [
                .target(name: "FFmpegLibs", condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/CFFmpeg",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.iOS])),
                .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
                .linkedFramework("AudioToolbox", .when(platforms: [.iOS])),
                .linkedFramework("CoreFoundation", .when(platforms: [.iOS])),
                .linkedFramework("CoreImage", .when(platforms: [.iOS])),
                .linkedFramework("CoreMedia", .when(platforms: [.iOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.iOS])),
                .linkedFramework("Foundation", .when(platforms: [.iOS])),
                .linkedFramework("Metal", .when(platforms: [.iOS])),
                .linkedFramework("VideoToolbox", .when(platforms: [.iOS])),
                .linkedLibrary("bz2", .when(platforms: [.iOS])),
                .linkedLibrary("iconv", .when(platforms: [.iOS])),
                .linkedLibrary("m", .when(platforms: [.iOS])),
                .linkedLibrary("z", .when(platforms: [.iOS])),
            ]
        ),

        // Single merged XCFramework for iOS (device + simulator)
        .binaryTarget(
            name: "FFmpegLibs",
            url: "https://github.com/Lincb522/MonoFrame/releases/download/ffmpeg-8.0-lame-3.100/FFmpegLibs.xcframework.zip",
            checksum: "67240fb0f1248758072d2c17af6f54b90f2a550f43929edeb56d3b5d8f299770"
        ),

        .target(
            name: "FFmpegSwiftSDK",
            dependencies: [
                "CFFmpeg",
                .target(name: "FFmpegLibs", condition: .when(platforms: [.iOS])),
            ]
        ),
    ]
)
