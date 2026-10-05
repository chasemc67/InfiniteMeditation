//
//  InfiniteMeditationApp.swift
//  InfiniteMeditation Watch App
//

import SwiftUI

@main
struct InfiniteMeditationWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let controller = WatchSessionController.shared

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let state = ScreenshotSeed.state, state.hasPrefix("settings") {
                ScreenshotSettingsRoot(controller: controller, showLongSession: state == "settingsLong")
            } else {
                ContentView(controller: controller)
                    .onAppear {
                        if ScreenshotSeed.state == "running" {
                            controller.startForScreenshots(elapsed: ScreenshotSeed.elapsed)
                        }
                    }
            }
            #else
            ContentView(controller: controller)
            #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { controller.appBecameActive() }
        }
    }
}

#if DEBUG
/// Opens Settings directly (optionally scrolled to the Background section in Long mode). Screenshot staging only.
private struct ScreenshotSettingsRoot: View {
    let controller: WatchSessionController
    let showLongSession: Bool

    var body: some View {
        NavigationStack {
            SettingsView(controller: controller)
        }
        .onAppear {
            if showLongSession { controller.settings.values.watchMode = .long }
        }
    }
}
#endif
