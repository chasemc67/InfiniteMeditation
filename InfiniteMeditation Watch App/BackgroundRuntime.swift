//
//  BackgroundRuntime.swift
//  InfiniteMeditation Watch App
//
//  Keeps the watch app alive (and allowed to play haptics) with the wrist down.
//
//  Standard mode: WKExtendedRuntimeSession. The session type comes from WKBackgroundModes in
//  Info.plist ("mindfulness"); without that entry watchOS refuses to start the session.
//  Mindfulness sessions keep the app frontmost with the screen off for up to 1 hour, and end
//  early if the user leaves the app (Digital Crown, switching apps).
//
//  Long mode: HKWorkoutSession (Mind & Body). Runs until ended, at the cost of a Health
//  permission prompt and the workout indicator. Saving a workout is optional.
//

import Foundation
import Combine
import HealthKit
import WatchKit

final class BackgroundRuntime: NSObject, ObservableObject {
    nonisolated enum Status: Equatable, Sendable {
        case off
        case starting
        case running(WatchSessionMode, until: Date?)
        case expiringSoon(until: Date?)
        /// The session stopped while the meditation is still going. Haptics will stop when the wrist is down.
        case stopped(String)
        case failed(String)

        var isHealthy: Bool {
            if case .running = self { return true }
            return false
        }
    }

    @Published private(set) var status: Status = .off
    /// Non-fatal information, e.g. why Long mode fell back to Standard.
    @Published private(set) var notice: String?

    private var extendedSession: WKExtendedRuntimeSession?
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var activeMode: WatchSessionMode?
    private var saveWorkout = false
    private let healthStore = HKHealthStore()

    var wantsRuntime: Bool { activeMode != nil }

    /// Starts keeping the app alive. Must be called while the app is in the foreground.
    func begin(mode: WatchSessionMode, saveWorkout: Bool) {
        end()
        activeMode = mode
        self.saveWorkout = saveWorkout
        notice = nil
        status = .starting
        switch mode {
        case .standard:
            startExtendedSession()
        case .long:
            Task { await startWorkoutSession() }
        }
    }

    /// Called when the app becomes active. Restarts the session if it expired or was dropped
    /// while the meditation kept going (e.g. the user raised their wrist after the 1-hour cap).
    func renewIfNeeded() {
        guard let mode = activeMode else { return }
        switch mode {
        case .standard:
            if let session = extendedSession, session.state == .running || session.state == .notStarted {
                return
            }
            startExtendedSession()
        case .long:
            if workoutSession == nil, status != .starting {
                status = .starting
                Task { await startWorkoutSession() }
            }
        }
    }

    func end() {
        activeMode = nil
        if let session = extendedSession {
            extendedSession = nil
            session.invalidate()
        }
        if let session = workoutSession {
            let builder = workoutBuilder
            workoutSession = nil
            workoutBuilder = nil
            session.end()
            finish(builder, save: saveWorkout, at: Date())
        }
        status = .off
    }

    private func finish(_ builder: HKLiveWorkoutBuilder?, save: Bool, at date: Date) {
        guard let builder else { return }
        Task {
            do {
                try await builder.endCollection(at: date)
                if save {
                    _ = try await builder.finishWorkout()
                } else {
                    builder.discardWorkout()
                }
            } catch {
                print("Workout cleanup failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Extended runtime (standard)

    private func startExtendedSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedSession = session
        status = .starting
        session.start()
    }

    private func extendedSessionStarted(_ id: ObjectIdentifier) {
        guard let session = extendedSession, ObjectIdentifier(session) == id else { return }
        status = .running(.standard, until: session.expirationDate)
    }

    private func extendedSessionWillExpire(_ id: ObjectIdentifier) {
        guard let session = extendedSession, ObjectIdentifier(session) == id else { return }
        status = .expiringSoon(until: session.expirationDate)
        HapticPlayer.playExpiryWarning()
    }

    private func extendedSessionInvalidated(_ id: ObjectIdentifier, reason: String) {
        guard let session = extendedSession, ObjectIdentifier(session) == id else { return }
        extendedSession = nil
        guard activeMode != nil else { return }
        status = .stopped(reason)
    }

    // MARK: Workout (long)

    private func startWorkoutSession() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            fallBackToStandard("Health isn't available on this watch.")
            return
        }
        let workoutType = HKObjectType.workoutType()
        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [])
        } catch {
            fallBackToStandard("Health permission request failed: \(error.localizedDescription)")
            return
        }
        guard activeMode == .long else { return }
        guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
            fallBackToStandard("Long sessions need permission to save workouts. Allow it in Settings › Health › Data Access.")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            workoutSession = session
            workoutBuilder = builder
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
        } catch {
            workoutSession?.end()
            fallBackToStandard("Couldn't start workout session: \(error.localizedDescription)")
        }
    }

    private func fallBackToStandard(_ reason: String) {
        guard activeMode != nil else { return }
        workoutSession = nil
        workoutBuilder = nil
        activeMode = .standard
        notice = "\(reason) Using Standard mode (1 hr limit)."
        startExtendedSession()
    }

    private func workoutStateChanged(_ id: ObjectIdentifier, to state: HKWorkoutSessionState, date: Date) {
        guard let session = workoutSession, ObjectIdentifier(session) == id else { return }
        switch state {
        case .running:
            if activeMode == .long { status = .running(.long, until: nil) }
        case .ended, .stopped:
            if state == .stopped {
                session.end()
                return
            }
            let builder = workoutBuilder
            workoutSession = nil
            workoutBuilder = nil
            if activeMode == .long {
                status = .stopped("The workout session ended unexpectedly. Raise your wrist to restart it.")
            }
            finish(builder, save: saveWorkout, at: date)
        default:
            break
        }
    }

    private func workoutFailed(_ id: ObjectIdentifier, message: String) {
        guard let session = workoutSession, ObjectIdentifier(session) == id else { return }
        guard activeMode != nil else { return }
        status = .failed("Workout session error: \(message)")
    }
}

extension BackgroundRuntime: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let id = ObjectIdentifier(extendedRuntimeSession)
        Task { @MainActor in self.extendedSessionStarted(id) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let id = ObjectIdentifier(extendedRuntimeSession)
        Task { @MainActor in self.extendedSessionWillExpire(id) }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        let id = ObjectIdentifier(extendedRuntimeSession)
        let message: String
        switch reason {
        case .none:
            message = "Background session ended."
        case .expired:
            message = "Reached watchOS's 1-hour limit. Raise your wrist to renew, or use Long session mode."
        case .resignedFrontmost:
            message = "You left the app, so watchOS stopped the session. Reopen it to resume taps."
        case .sessionInProgress:
            message = "Another background session is already running."
        case .suppressedBySystem:
            message = "watchOS suppressed the session (Low Power Mode or system load)."
        case .error:
            message = "Couldn't start: \(error?.localizedDescription ?? "unknown error"). Check that WKBackgroundModes includes mindfulness."
        @unknown default:
            message = "Background session stopped (\(reason.rawValue))."
        }
        Task { @MainActor in self.extendedSessionInvalidated(id, reason: message) }
    }
}

extension BackgroundRuntime: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in self.workoutStateChanged(id, to: toState, date: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let id = ObjectIdentifier(workoutSession)
        let message = error.localizedDescription
        Task { @MainActor in self.workoutFailed(id, message: message) }
    }
}
