//
//  MeditationSettings.swift
//  Shared by the iPhone and Apple Watch apps.
//

import Foundation
import Combine

nonisolated enum HapticStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case double
    case triple
    case rising
    case success
    case gentle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: "Single tap"
        case .double: "Double tap"
        case .triple: "Triple tap"
        case .rising: "Rising"
        case .success: "Chord"
        case .gentle: "Gentle click"
        }
    }
}

nonisolated enum WatchSessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// WKExtendedRuntimeSession (mindfulness). No permissions, capped at 1 hour by watchOS.
    case standard
    /// HKWorkoutSession (Mind & Body). Requires Health permission, runs as long as you meditate.
    case long

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard (up to 1 hr)"
        case .long: "Long session (workout)"
        }
    }
}

nonisolated struct MeditationSettings: Codable, Equatable, Sendable {
    static let intervalOptions = [1, 2, 3, 5, 10, 15, 20, 30]
    /// 0 means "no major marks".
    static let majorEveryOptions = [0, 2, 3, 4, 6]

    var intervalMinutes = 5
    var majorEvery = 2
    var minorHaptic = HapticStyle.single
    var majorHaptic = HapticStyle.double
    var chimeEnabled = true
    var chimeVolume = 0.8
    var watchMode = WatchSessionMode.standard
    var saveLongSessionsToHealth = false
    var mirrorSessions = true

    var schedule: MarkSchedule {
        MarkSchedule(intervalSeconds: TimeInterval(intervalMinutes * 60), majorEvery: majorEvery)
    }

    static func majorLabel(majorEvery: Int, intervalMinutes: Int) -> String {
        guard majorEvery > 0 else { return "Off" }
        return "Every \(majorEvery) marks (\(majorEvery * intervalMinutes) min)"
    }

    init() {}

    // Decoded field by field so settings saved by an older build keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeditationSettings()
        intervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .intervalMinutes)) ?? d.intervalMinutes
        majorEvery = (try? c.decodeIfPresent(Int.self, forKey: .majorEvery)) ?? d.majorEvery
        minorHaptic = (try? c.decodeIfPresent(HapticStyle.self, forKey: .minorHaptic)) ?? d.minorHaptic
        majorHaptic = (try? c.decodeIfPresent(HapticStyle.self, forKey: .majorHaptic)) ?? d.majorHaptic
        chimeEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .chimeEnabled)) ?? d.chimeEnabled
        chimeVolume = (try? c.decodeIfPresent(Double.self, forKey: .chimeVolume)) ?? d.chimeVolume
        watchMode = (try? c.decodeIfPresent(WatchSessionMode.self, forKey: .watchMode)) ?? d.watchMode
        saveLongSessionsToHealth = (try? c.decodeIfPresent(Bool.self, forKey: .saveLongSessionsToHealth)) ?? d.saveLongSessionsToHealth
        mirrorSessions = (try? c.decodeIfPresent(Bool.self, forKey: .mirrorSessions)) ?? d.mirrorSessions
        if intervalMinutes < 1 { intervalMinutes = d.intervalMinutes }
        if majorEvery < 0 { majorEvery = 0 }
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> MeditationSettings? {
        try? JSONDecoder().decode(MeditationSettings.self, from: data)
    }
}

/// Persists settings and tells the connectivity layer when the user changes them locally.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let defaultsKey = "meditationSettings.v1"
    private static let updatedAtKey = "meditationSettings.updatedAt"

    @Published var values: MeditationSettings {
        didSet {
            guard values != oldValue else { return }
            if let data = values.encoded() {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
            if !isApplyingRemote {
                updatedAt = Date()
                onLocalChange?(values, updatedAt)
            }
        }
    }

    /// When the settings last changed on either device; the newer side wins when syncing.
    private(set) var updatedAt: Date {
        didSet { UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: Self.updatedAtKey) }
    }

    var onLocalChange: ((MeditationSettings, Date) -> Void)?
    private var isApplyingRemote = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = MeditationSettings.decode(data) {
            values = saved
        } else {
            values = MeditationSettings()
        }
        updatedAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.updatedAtKey))
    }

    func applyRemote(_ settings: MeditationSettings, updatedAt remoteDate: Date) {
        guard remoteDate > updatedAt else { return }
        isApplyingRemote = true
        values = settings
        isApplyingRemote = false
        updatedAt = remoteDate
    }
}
