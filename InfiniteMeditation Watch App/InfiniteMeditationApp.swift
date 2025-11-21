//
//  InfiniteMeditationApp.swift
//  InfiniteMeditation Watch App
//
//  Created by Chase McCarty on 11/21/25.
//

import SwiftUI

@main
struct HapticTimerWatch_Watch_AppApp: App {
    @State private var selectedTab = 1 // Start on main timer (ContentView)
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                SettingsView(selectedTab: $selectedTab)
                    .tag(0)
                ContentView()
                    .tag(1)
                HapticTestView()
                    .tag(2)
            }
            .tabViewStyle(.page)
        }
    }
}
