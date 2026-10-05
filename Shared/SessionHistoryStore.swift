//
//  SessionHistoryStore.swift
//  Shared by the iPhone and Apple Watch apps.
//

import Foundation
import Combine

final class SessionHistoryStore: ObservableObject {
    static let shared = SessionHistoryStore()

    private static let storageKey = "sessionHistory.v1"

    @Published private(set) var entries: [SessionHistoryEntry] = []
    private(set) var state: SessionHistoryState = .empty

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = SessionHistoryState.decode(data) {
            state = saved
            entries = saved.entries
        }
    }

    /// Records an ended session. Returns the new state when the log changed.
    @discardableResult
    func record(_ snapshot: SessionSnapshot, at now: Date = Date()) -> SessionHistoryState? {
        guard let entry = SessionHistoryLog.entry(from: snapshot) else { return nil }
        let next = SessionHistoryLog.record(entry, into: state, at: now)
        guard SessionHistoryLog.changed(next, from: state) else { return nil }
        apply(next)
        return next
    }

    /// Removes a row locally. Does not delete the Mindful Minutes sample in Health.
    @discardableResult
    func delete(id: UUID, at now: Date = Date()) -> SessionHistoryState? {
        let next = SessionHistoryLog.delete(id: id, from: state, at: now)
        guard SessionHistoryLog.changed(next, from: state) else { return nil }
        apply(next)
        return next
    }

    /// Folds in a log from the other device. Returns the merged state when anything changed.
    @discardableResult
    func merge(_ remote: SessionHistoryState) -> SessionHistoryState? {
        let next = SessionHistoryLog.merge(local: state, remote: remote)
        guard SessionHistoryLog.changed(next, from: state) else { return nil }
        apply(next)
        return next
    }

    private func apply(_ next: SessionHistoryState) {
        state = next
        entries = next.entries
        if let data = next.encoded() {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
