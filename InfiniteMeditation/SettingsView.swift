//
//  SettingsView.swift
//  InfiniteMeditation
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: PhoneSessionController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var timer: MeditationTimer
    @ObservedObject var connectivity: ConnectivityService
    @Environment(\.dismiss) private var dismiss

    init(controller: PhoneSessionController) {
        self.controller = controller
        settings = controller.settings
        timer = controller.timer
        connectivity = controller.connectivity
    }

    private var hasWatch: Bool {
        switch connectivity.counterpart {
        case .unsupported, .notPaired: false
        default: true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Interval", selection: $settings.values.intervalMinutes) {
                        ForEach(MeditationSettings.intervalOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    Picker("Major mark", selection: $settings.values.majorEvery) {
                        ForEach(MeditationSettings.majorEveryOptions, id: \.self) { every in
                            Text(MeditationSettings.majorLabel(majorEvery: every, intervalMinutes: settings.values.intervalMinutes)).tag(every)
                        }
                    }
                } header: {
                    Text("Marks")
                } footer: {
                    Text(timer.phase == .idle
                         ? "A mark every interval; major marks get a deeper bowl on iPhone and a different tap on Apple Watch."
                         : "Interval changes apply to your next session.")
                }

                Section {
                    Toggle("Play chime", isOn: $settings.values.chimeEnabled)
                    if settings.values.chimeEnabled {
                        HStack {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                            Slider(value: $settings.values.chimeVolume, in: 0.1...1)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        }
                        Button("Preview regular chime") { controller.previewChime(major: false) }
                        Button("Preview major chime") { controller.previewChime(major: true) }
                    }
                } header: {
                    Text("iPhone chime")
                } footer: {
                    Text("Chimes keep playing with your phone locked. The ring/silent switch doesn't mute them; use the volume buttons. Sounds are synthesized singing bowls generated for this app.")
                }

                Section {
                    Toggle("Mindful Minutes", isOn: $settings.values.recordMindfulMinutes)
                } header: {
                    Text("Health")
                } footer: {
                    Text("On by default. Ending a session saves the time you were actually meditating to Apple Health as Mindful Minutes. Each uninterrupted stretch is its own entry, so pauses are not counted. If the iPhone and Watch are mirroring one session, only the device you tap End on writes it.")
                }

                if hasWatch {
                    Section {
                        Picker("Regular tap", selection: $settings.values.minorHaptic) {
                            ForEach(HapticStyle.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Major tap", selection: $settings.values.majorHaptic) {
                            ForEach(HapticStyle.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Background mode", selection: $settings.values.watchMode) {
                            ForEach(WatchSessionMode.allCases) { Text($0.label).tag($0) }
                        }
                        if settings.values.watchMode == .long {
                            Toggle("Save workout to Health", isOn: $settings.values.saveLongSessionsToHealth)
                        }
                        Toggle("Mirror start / pause / end", isOn: $settings.values.mirrorSessions)
                        LabeledContent("Status", value: connectivity.counterpart.label)
                    } header: {
                        Text("Apple Watch")
                    } footer: {
                        Text(watchFooter)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var watchFooter: String {
        let mode = settings.values.watchMode == .standard
            ? "Standard mode keeps taps going with your wrist down for up to 1 hour (a watchOS limit). Raise your wrist to renew."
            : "Long mode runs as a Mind & Body workout with no time limit. Save workout to Health keeps that workout; otherwise it is discarded. Mindful Minutes are saved separately."
        return mode + " Start, pause, and end catch up when the watch reconnects, even if it was asleep with your wrist down."
    }
}

#Preview {
    SettingsView(controller: .shared)
}
