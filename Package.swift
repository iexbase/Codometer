// swift-tools-version: 6.2
import PackageDescription

/// Every module compiles in Swift 6 language mode (complete concurrency checking)
/// with warnings promoted to errors, so type or isolation mistakes never ship.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]

/// Code that runs inside the widget extension must only use APIs available to app extensions.
let applicationExtensionSettings: [SwiftSetting] = strictSettings + [
    .unsafeFlags(["-application-extension"]),
]

let package = Package(
    name: "Codometer",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Codometer", targets: ["CodometerApp"]),
        .executable(name: "CodometerWidgets", targets: ["CodometerWidgets"]),
    ],
    targets: [
        // Localized text: typed English and Russian phrase tables, plural rules and locale-aware formats.
        // Foundation only, no resources: every module that shows text (and the widget extension) links it.
        .target(name: "CodometerL10n", swiftSettings: strictSettings),

        // Pure domain: models, validation, pace/alert math. No I/O.
        .target(
            name: "CodometerCore",
            dependencies: ["CodometerL10n"],
            swiftSettings: strictSettings
        ),

        // OS adapters: files, FSEvents, processes, code signatures, network state.
        .target(
            name: "CodometerPlatform",
            dependencies: ["CodometerCore"],
            swiftSettings: strictSettings
        ),

        // Settings file and SQLite usage history.
        .target(
            name: "CodometerStorage",
            dependencies: ["CodometerCore", "CodometerPlatform"],
            swiftSettings: strictSettings
        ),

        // Provider adapters. Each one only turns local data into domain values.
        .target(
            name: "CodometerClaude",
            dependencies: ["CodometerCore", "CodometerPlatform"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "CodometerCodex",
            dependencies: ["CodometerCore", "CodometerPlatform"],
            swiftSettings: strictSettings
        ),

        // Orchestration: per-account monitors, scheduling, alerts, history.
        .target(
            name: "CodometerEngine",
            dependencies: [
                "CodometerCore",
                "CodometerPlatform",
                "CodometerStorage",
                "CodometerClaude",
                "CodometerCodex",
            ],
            swiftSettings: strictSettings
        ),

        // SwiftUI design system, components and screens. Depends on the domain only.
        .target(
            name: "CodometerUI",
            dependencies: ["CodometerCore", "CodometerL10n"],
            swiftSettings: strictSettings
        ),

        // AppKit shell: panels, status item, windows, notifications, composition root.
        .executableTarget(
            name: "CodometerApp",
            dependencies: [
                "CodometerCore",
                "CodometerPlatform",
                "CodometerStorage",
                "CodometerEngine",
                "CodometerUI",
                "CodometerL10n",
            ],
            swiftSettings: strictSettings
        ),

        // Desktop widget: views and timeline, built extension-safe. Depends on the domain only.
        .target(
            name: "CodometerWidgetsUI",
            dependencies: ["CodometerCore", "CodometerL10n"],
            path: "Sources/CodometerWidgets/UI",
            swiftSettings: applicationExtensionSettings
        ),

        // WidgetKit extension executable, packaged as Codometer.app/Contents/PlugIns/CodometerWidgets.appex.
        // Extensions start at NSExtensionMain, which runs the Swift `@main` widget bundle.
        .executableTarget(
            name: "CodometerWidgets",
            dependencies: ["CodometerCore", "CodometerL10n", "CodometerWidgetsUI"],
            path: "Sources/CodometerWidgets/Extension",
            swiftSettings: applicationExtensionSettings,
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
            ]
        ),

        .testTarget(
            name: "CodometerL10nTests",
            dependencies: ["CodometerL10n"],
            swiftSettings: strictSettings
        ),
        // Policy and localization lints over `Sources/**` (found through `#filePath`), so every test run checks them.
        .testTarget(
            name: "CodometerSourceLintTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerCoreTests",
            // The widget views are rendered by the gated snapshot test in WidgetSnapshotTests.
            dependencies: ["CodometerCore", "CodometerL10n", "CodometerWidgetsUI"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerPlatformTests",
            dependencies: ["CodometerCore", "CodometerPlatform"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerStorageTests",
            dependencies: ["CodometerCore", "CodometerPlatform", "CodometerStorage"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerClaudeTests",
            dependencies: ["CodometerCore", "CodometerPlatform", "CodometerClaude"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerCodexTests",
            dependencies: ["CodometerCore", "CodometerPlatform", "CodometerCodex"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerEngineTests",
            // The history tests open stores and temporary folders directly, so these are explicit, not transitive.
            dependencies: ["CodometerCore", "CodometerL10n", "CodometerPlatform", "CodometerStorage", "CodometerEngine"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CodometerUITests",
            dependencies: ["CodometerCore", "CodometerL10n", "CodometerUI"],
            swiftSettings: strictSettings
        ),
        // App shell logic (routing, activation policy, persistence rules, debug fixtures), linked with the executable.
        .testTarget(
            name: "CodometerAppTests",
            dependencies: ["CodometerApp", "CodometerCore", "CodometerL10n", "CodometerPlatform", "CodometerUI"],
            swiftSettings: strictSettings
        ),
    ]
)
