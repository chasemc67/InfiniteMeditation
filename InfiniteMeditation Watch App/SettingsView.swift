//
//  SettingsView.swift
//  InfiniteMeditation Watch App
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: WatchSessionController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var timer: MeditationTimer
    @ObservedObject var connectivity: ConnectivityService

    init(controller: WatchSessionController) {
        self.controller = controller
        settings = controller.settings
        timer = controller.timer
        connectivity = controller.connectivity
    }

    private var sessionActive: Bool { timer.phase != .idle }

    var body: some View {
        ScrollViewReader { proxy in
        List {
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
                if sessionActive { Text("Interval changes apply to your next session.") }
            }

            Section("Haptics") {
                Picker("Regular", selection: $settings.values.minorHaptic) {
                    ForEach(HapticStyle.allCases) { Text($0.label).tag($0) }
                }
                Picker("Major", selection: $settings.values.majorHaptic) {
                    ForEach(HapticStyle.allCases) { Text($0.label).tag($0) }
                }
                Button("Try regular") { controller.previewHaptic(major: false) }
                Button("Try major") { controller.previewHaptic(major: true) }
            }

            Section {
                Picker("Mode", selection: $settings.values.watchMode) {
                    ForEach(WatchSessionMode.allCases) { Text($0.label).tag($0) }
                }
                .id("backgroundMode")
                if settings.values.watchMode == .long {
                    Toggle("Save to Health", isOn: $settings.values.saveLongSessionsToHealth)
                }
            } header: {
                Text("Background")
            } footer: {
                Text(settings.values.watchMode == .standard
                     ? "watchOS allows up to 1 hour with the wrist down. Raise your wrist to renew."
                     : "Runs as a Mind & Body workout with no time limit. Asks for Health permission once.")
            }

            Section {
                Toggle("Mirror iPhone", isOn: $settings.values.mirrorSessions)
                Text(connectivity.counterpart.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Start, pause and end are mirrored while both apps are open.")
            }
        }
        #if DEBUG
        .task {
            guard ScreenshotSeed.state == "settingsLong" else { return }
            try? await Task.sleep(for: .milliseconds(800))
            proxy.scrollTo("backgroundMode", anchor: .top)
        }
        #endif
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView(controller: .shared) }
}
