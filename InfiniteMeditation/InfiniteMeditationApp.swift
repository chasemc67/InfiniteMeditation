//
//  InfiniteMeditationApp.swift
//  InfiniteMeditation
//

import SwiftUI

@main
struct InfiniteMeditationApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let controller = PhoneSessionController.shared

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { controller.appBecameActive() }
        }
    }
}
