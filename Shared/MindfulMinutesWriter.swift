//
//  MindfulMinutesWriter.swift
//  Shared by the iPhone and Apple Watch apps.
//
//  Writes completed meditations as HKCategoryType.mindfulSession samples.
//  The device where the user taps End requests share permission and performs the save.
//  Samples carry HKMetadataKeySyncIdentifier / HKMetadataKeySyncVersion so a double end
//  (phone and watch ending the same session together) cannot insert two copies.
//
//  This is separate from Long session mode. That mode runs an HKWorkoutSession so the
//  watch can stay awake, and discards the workout unless "Save workout to Health" is on.
//  A Mind & Body workout does not count as Mindful Minutes, and Mindful Minutes are saved
//  even when the workout is discarded.
//

import Foundation
import HealthKit

nonisolated enum MindfulSaveResult: Equatable, Sendable {
    case saved(sampleCount: Int)
    case alreadySaved
    case nothingToSave
    case denied
    case unavailable
    case failed(String)
}

final class MindfulMinutesWriter {
    static let shared = MindfulMinutesWriter()

    private let store = HKHealthStore()
    private let ledgerKey = "mindfulMinutes.recordedSessionIDs"
    private var inFlight: Set<UUID> = []

    var isAuthorized: Bool {
        guard HKHealthStore.isHealthDataAvailable(), let type = mindfulType else { return false }
        return store.authorizationStatus(for: type) == .sharingAuthorized
    }

    func hasRecorded(_ id: UUID) -> Bool {
        recordedIDs().contains(id.uuidString)
    }

    /// Requests permission to share mindful sessions when it has not been asked yet,
    /// then saves one sample per uninterrupted segment.
    func record(_ snapshot: SessionSnapshot) async -> MindfulSaveResult {
        let samples = MindfulMinutesPlan.samples(for: snapshot)
        guard !samples.isEmpty else { return .nothingToSave }
        if hasRecorded(snapshot.sessionID) || inFlight.contains(snapshot.sessionID) {
            return .alreadySaved
        }
        inFlight.insert(snapshot.sessionID)

        guard HKHealthStore.isHealthDataAvailable(), let type = mindfulType else {
            inFlight.remove(snapshot.sessionID)
            return .unavailable
        }

        do {
            try await store.requestAuthorization(toShare: [type], read: [])
        } catch {
            inFlight.remove(snapshot.sessionID)
            return .failed(error.localizedDescription)
        }

        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            inFlight.remove(snapshot.sessionID)
            return .denied
        }

        var saved = 0
        var duplicates = 0
        var failure: String?
        for draft in samples {
            let sample = HKCategorySample(
                type: type,
                value: HKCategoryValue.notApplicable.rawValue,
                start: draft.start,
                end: draft.end,
                metadata: [
                    HKMetadataKeySyncIdentifier: draft.syncIdentifier,
                    HKMetadataKeySyncVersion: NSNumber(value: draft.syncVersion),
                    "com.AnomalousResearch.MeditationTimer.sessionID": snapshot.sessionID.uuidString,
                ]
            )
            do {
                try await store.save(sample)
                saved += 1
            } catch {
                let nsError = error as NSError
                if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorInvalidArgument.rawValue {
                    duplicates += 1
                } else if nsError.domain == HKErrorDomain && (
                    nsError.code == HKError.Code.errorAuthorizationDenied.rawValue
                        || nsError.code == HKError.Code.errorRequiredAuthorizationDenied.rawValue
                ) {
                    inFlight.remove(snapshot.sessionID)
                    return .denied
                } else {
                    failure = error.localizedDescription
                }
            }
        }

        inFlight.remove(snapshot.sessionID)
        if saved > 0 || (duplicates > 0 && failure == nil) {
            markRecorded(snapshot.sessionID)
            return .saved(sampleCount: max(saved, 1))
        }
        return .failed(failure ?? "Couldn't save Mindful Minutes.")
    }

    private var mindfulType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .mindfulSession)
    }

    private func recordedIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: ledgerKey) ?? []
    }

    private func markRecorded(_ id: UUID) {
        var ids = recordedIDs()
        ids.removeAll { $0 == id.uuidString }
        ids.append(id.uuidString)
        if ids.count > 50 {
            ids.removeFirst(ids.count - 50)
        }
        UserDefaults.standard.set(ids, forKey: ledgerKey)
    }
}
