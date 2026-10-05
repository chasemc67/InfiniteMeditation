//
//  HapticPlayer.swift
//  InfiniteMeditation Watch App
//

import Foundation
import WatchKit

enum HapticPlayer {
    /// Spacing between taps in multi-tap patterns. Much closer and watchOS may merge or drop taps.
    private static let tapSpacing: Duration = .milliseconds(450)

    static func play(_ style: HapticStyle) {
        let device = WKInterfaceDevice.current()
        switch style {
        case .single:
            device.play(.notification)
        case .double:
            repeated(.notification, count: 2)
        case .triple:
            repeated(.notification, count: 3)
        case .rising:
            device.play(.directionUp)
        case .success:
            device.play(.success)
        case .gentle:
            device.play(.click)
        }
    }

    /// Played when the background session is about to run out, so a wrist-down user notices.
    static func playExpiryWarning() {
        repeated(.retry, count: 2)
    }

    private static func repeated(_ type: WKHapticType, count: Int) {
        Task { @MainActor in
            for i in 0..<count {
                if i > 0 { try? await Task.sleep(for: tapSpacing) }
                WKInterfaceDevice.current().play(type)
            }
        }
    }
}
