// swift-tools-version: 6.2
// Reconciliation and Mindful Minutes planning are Foundation-only so `swift test`
// can run them on Linux. The Xcode app compiles SessionSync.swift as part of Shared/.

import PackageDescription

let package = Package(
    name: "BoundlessSyncCore",
    targets: [
        .target(
            name: "BoundlessSyncCore",
            path: "Shared",
            exclude: [
                "ConnectivityService.swift",
                "MeditationSettings.swift",
                "MeditationTimer.swift",
                "MindfulMinutesWriter.swift",
                "SessionHistoryStore.swift",
                "SessionHistoryView.swift",
                "ScreenshotSeed.swift",
                "TimerDisplay.swift",
            ],
            sources: ["SessionSync.swift", "SessionHistory.swift", "SyncCommand.swift"]
        ),
        .testTarget(
            name: "BoundlessSyncCoreTests",
            dependencies: ["BoundlessSyncCore"],
            path: "InfiniteMeditationTests",
            exclude: ["InfiniteMeditationTests.swift"],
            sources: ["SessionSyncTests.swift", "SessionHistoryTests.swift"]
        ),
    ]
)
