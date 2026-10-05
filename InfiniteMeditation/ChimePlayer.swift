//
//  ChimePlayer.swift
//  InfiniteMeditation
//
//  Plays the singing-bowl chimes and keeps the app alive while the phone is locked.
//
//  With the "audio" background mode, iOS keeps an app running as long as it has an active
//  playback audio session with a running audio engine. The engine runs for the whole
//  meditation (outputting silence between chimes), so the mark scheduler keeps firing with the
//  screen off. `.mixWithOthers` lets the user's music or another app's audio continue.
//

import Foundation
import AVFoundation
import Combine

final class ChimePlayer: ObservableObject {
    nonisolated enum Status: Equatable, Sendable {
        case idle
        case active
        case interrupted
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var minorBuffer: AVAudioPCMBuffer?
    private var majorBuffer: AVAudioPCMBuffer?
    /// True while a meditation wants the audio session held open.
    private var isHolding = false
    private var previewGeneration = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        minorBuffer = Self.loadBuffer(named: "chime_minor")
        majorBuffer = Self.loadBuffer(named: "chime_major")
        buildGraph()
        observeSystemEvents()
    }

    /// Activates background audio for a meditation session.
    func beginSession() {
        isHolding = true
        startAudio()
    }

    func endSession() {
        isHolding = false
        stopAudio()
    }

    func play(major: Bool, volume: Double) {
        guard let buffer = major ? majorBuffer : minorBuffer else {
            status = .failed("Chime sound files are missing from the app bundle.")
            return
        }
        if !engine.isRunning {
            startAudio()
        }
        guard engine.isRunning else { return }
        player.volume = Float(max(0, min(1, volume)))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Plays a chime from Settings, releasing the audio session afterwards if no session is running.
    func preview(major: Bool, volume: Double) {
        play(major: major, volume: volume)
        previewGeneration += 1
        let generation = previewGeneration
        let duration = Double((major ? majorBuffer : minorBuffer)?.frameLength ?? 0)
            / ((major ? majorBuffer : minorBuffer)?.format.sampleRate ?? 44_100)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.5))
            guard let self, generation == self.previewGeneration, !self.isHolding else { return }
            self.stopAudio()
        }
    }

    // MARK: Audio session and engine

    private func startAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            player.play()
            status = isHolding ? .active : status
        } catch {
            status = .failed("Audio couldn't start: \(error.localizedDescription)")
        }
    }

    private func stopAudio() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = .idle
    }

    private func buildGraph() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        engine.attach(player)
        let format = minorBuffer?.format ?? majorBuffer?.format
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    private static func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            print("Chime: missing \(name).wav")
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            print("Chime: failed to load \(name).wav: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Interruptions (calls, Siri, alarms), route changes, media server resets

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(rawType: rawType)
            }
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartIfHolding()
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.buildGraph()
                self.restartIfHolding()
            }
        })
    }

    private func handleInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            if isHolding { status = .interrupted }
        case .ended:
            // Resume even without .shouldResume: a meditation timer should keep chiming after a call.
            restartIfHolding()
        @unknown default:
            break
        }
    }

    private func restartIfHolding() {
        guard isHolding else { return }
        startAudio()
    }
}
