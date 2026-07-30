// swift-tools-version:6.0
import PackageDescription

var targets: [Target] = [
    // Foundation-only support lets attribution and RTTM/DER tests run in
    // Linux CI even though Quill inference itself is macOS/Core-ML-only.
    .target(name: "quillDiarizationSupport", path: "Sources/quillDiarizationSupport"),
    .target(
        name: "quillDiarizationTestSupport",
        path: "Tests/quillTests",
        exclude: ["Fixtures", "DiarizationBenchmarkTests.swift", "PortableDiarizationScorerTests.swift", "DiarizationAttributionTests.swift"],
        sources: ["PortableDiarizationScorer.swift"]
    ),
]

#if os(macOS)
targets += [
    .executableTarget(
        name: "quill",
        dependencies: [
            "quillDiarizationSupport",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "FluidAudio", package: "FluidAudio"),
        ],
        exclude: ["Info.plist"],
        linkerSettings: [
            // Embed Info.plist into the binary so TCC can attribute the
            // system-audio-capture permission to quill itself when it runs as
            // a LaunchAgent (no .app bundle to carry a plist).
            .unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Sources/quill/Info.plist",
            ]),
        ]
    ),
    .testTarget(
        name: "quillTests",
        dependencies: [
            "quillDiarizationTestSupport",
            "quillDiarizationSupport",
            "quill",
            .product(name: "FluidAudio", package: "FluidAudio"),
        ],
        path: "Tests/quillTests",
        exclude: ["Fixtures", "PortableDiarizationScorer.swift"],
        sources: ["PortableDiarizationScorerTests.swift", "DiarizationAttributionTests.swift", "DiarizationBenchmarkTests.swift"]
    ),
]
#else
targets.append(
    .testTarget(
        name: "quillTests",
        dependencies: ["quillDiarizationTestSupport", "quillDiarizationSupport"],
        path: "Tests/quillTests",
        exclude: ["Fixtures", "PortableDiarizationScorer.swift", "DiarizationBenchmarkTests.swift"],
        sources: ["PortableDiarizationScorerTests.swift", "DiarizationAttributionTests.swift"]
    )
)
#endif

let package = Package(
    name: "quill",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
    ],
    targets: targets
)
