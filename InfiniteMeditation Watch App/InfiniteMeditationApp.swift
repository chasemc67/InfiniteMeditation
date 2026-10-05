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
            ContentView(controller: controller)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.appBecameActive() }
        }
    }
}
