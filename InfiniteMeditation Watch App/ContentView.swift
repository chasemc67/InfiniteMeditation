//
//  ContentView.swift
//  InfiniteMeditation Watch App
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: WatchSessionController
    @ObservedObject var timer: MeditationTimer
    @ObservedObject var runtime: BackgroundRuntime
    @ObservedObject var settings: SettingsStore

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    init(controller: WatchSessionController = .shared) {
        self.controller = controller
        timer = controller.timer
        runtime = controller.runtime
        settings = controller.settings
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                ElapsedTimeText(timer: timer)
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(isLuminanceReduced ? Color.secondary : Color.primary)

                NextMarkText(timer: timer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                StatusLine(timer: timer, runtime: runtime, settings: settings.values, summary: controller.lastSessionSummary)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 4)

                controls
                    .opacity(isLuminanceReduced ? 0.4 : 1)
            }
            .padding(.horizontal, 4)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SessionHistoryView(store: controller.history, showsDoneButton: false) { id in
                            controller.deleteHistory(id: id)
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(controller: controller)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch timer.phase {
        case .idle:
            Button {
                controller.start()
            } label: {
                Label("Begin", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.teal)
        case .running, .paused:
            HStack(spacing: 8) {
                Button {
                    controller.end()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.gray)
                .accessibilityLabel("End session")

                Button {
                    if timer.phase == .running { controller.pause() } else { controller.resume() }
                } label: {
                    Image(systemName: timer.phase == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.teal)
                .accessibilityLabel(timer.phase == .running ? "Pause" : "Resume")
            }
        }
    }
}

/// Shows the schedule (or last session) when idle. During a session it stays empty unless
/// something is wrong: the background session stopped or failed, or is about to expire.
private struct StatusLine: View {
    @ObservedObject var timer: MeditationTimer
    @ObservedObject var runtime: BackgroundRuntime
    let settings: MeditationSettings
    let summary: String?

    var body: some View {
        VStack(spacing: 2) {
            primary
            if let notice = runtime.notice, timer.phase != .idle {
                Text(notice).foregroundStyle(.yellow)
            }
        }
        .lineLimit(2)
    }

    @ViewBuilder
    private var primary: some View {
        if timer.phase == .idle {
            if let summary {
                Text("Last: \(summary)").foregroundStyle(.secondary)
            } else {
                Text(scheduleDescription).foregroundStyle(.secondary)
            }
        } else if timer.phase == .running {
            switch runtime.status {
            case .off, .starting, .running:
                EmptyView()
            case .expiringSoon:
                Text("Taps ending soon. Raise wrist.").foregroundStyle(.orange)
            case .stopped(let message), .failed(let message):
                Text(message).foregroundStyle(.red)
            }
        }
    }

    private var scheduleDescription: String {
        let major = settings.majorEvery > 0 ? " · major every \(settings.majorEvery * settings.intervalMinutes) min" : ""
        return "Tap every \(settings.intervalMinutes) min\(major)"
    }
}

#Preview {
    ContentView()
}
