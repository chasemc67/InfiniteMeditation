//
//  ScreenshotSeed.swift
//  Shared by the iPhone and Apple Watch apps. DEBUG builds only.
//

#if DEBUG
import Foundation

/// Launch arguments used to stage App Store screenshots in the Simulator:
///
///     -screenshotState running|settings|settingsLong   -screenshotElapsed <seconds>
///
/// Compiled out of Release builds.
nonisolated enum ScreenshotSeed {
    static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-\(key)"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static var state: String? { value(for: "screenshotState") }

    static var elapsed: TimeInterval { value(for: "screenshotElapsed").flatMap(TimeInterval.init) ?? 754 }
}
#endif
