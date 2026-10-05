//
//  ContentView.swift
//  InfiniteMeditation
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: PhoneSessionController
    @ObservedObject var timer: MeditationTimer
    @ObservedObject var chimes: ChimePlayer
    @ObservedObject var settings: SettingsStore
    @ObservedObject var connectivity: ConnectivityService

    @State private var showingSettings = false

    init(controller: PhoneSessionController = .shared) {
        self.controller = controller
        timer = controller.timer
        chimes = controller.chimes
        settings = controller.settings
        connectivity = controller.connectivity
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.02, green: 0.03, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .padding(10)
                    }
                    .accessibilityLabel("Settings")
                }

                Spacer()

                ZStack {
                    BreathingRing(isActive: timer.phase == .running)
                        .frame(width: 280, height: 280)
                    VStack(spacing: 10) {
                        ElapsedTimeText(timer: timer)
                            .font(.system(size: 64, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        NextMarkText(timer: timer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 230)
                }

                statusText
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(minHeight: 44)

                Spacer()

                controls
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(.white)
        .tint(Color(red: 0.55, green: 0.80, blue: 0.80))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsView(controller: controller)
        }
        #if DEBUG
        .onAppear {
            switch ScreenshotSeed.state {
            case "running": controller.startForScreenshots(elapsed: ScreenshotSeed.elapsed)
            case "settings": showingSettings = true
            default: break
            }
        }
        #endif
    }

    @ViewBuilder
    private var controls: some View {
        switch timer.phase {
        case .idle:
            Button {
                controller.start()
            } label: {
                Text("Begin")
                    .font(.title3.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        case .running, .paused:
            HStack(spacing: 16) {
                Button {
                    controller.end()
                } label: {
                    Text("End")
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button {
                    if timer.phase == .running { controller.pause() } else { controller.resume() }
                } label: {
                    Text(timer.phase == .running ? "Pause" : "Resume")
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        VStack(spacing: 6) {
            if timer.phase == .idle {
                if let summary = controller.lastSessionSummary {
                    Text("Last session: \(summary)").foregroundStyle(.secondary)
                } else {
                    Text(scheduleDescription).foregroundStyle(.secondary)
                }
            } else {
                switch chimes.status {
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                case .interrupted:
                    Text("Audio interrupted. Chimes resume when the interruption ends.").foregroundStyle(.orange)
                case .idle, .active:
                    if settings.values.chimeEnabled {
                        Text("Chimes on. Safe to lock your phone.").foregroundStyle(.secondary)
                    } else {
                        Text("Chimes off. iPhone won't alert while locked.").foregroundStyle(.secondary)
                    }
                }
            }
            if connectivity.counterpart != .notPaired, connectivity.counterpart != .unsupported {
                Text(connectivity.counterpart.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var scheduleDescription: String {
        let values = settings.values
        let sound = values.chimeEnabled ? "Chime" : "Silent mark"
        let major = values.majorEvery > 0 ? ", deeper bowl every \(values.majorEvery * values.intervalMinutes) min" : ""
        return "\(sound) every \(values.intervalMinutes) min\(major)"
    }
}

private struct BreathingRing: View {
    let isActive: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
            .background(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.35, green: 0.55, blue: 0.65).opacity(0.25), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 160
                        )
                    )
            )
            .scaleEffect(isActive && expanded ? 1.0 : 0.92)
            .animation(
                isActive ? .easeInOut(duration: 5).repeatForever(autoreverses: true) : .easeOut(duration: 1),
                value: expanded
            )
            .animation(.easeOut(duration: 1), value: isActive)
            .onAppear { expanded = isActive }
            .onChange(of: isActive) { _, active in expanded = active }
    }
}

#Preview {
    ContentView()
}
