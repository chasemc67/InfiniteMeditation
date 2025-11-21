//
//  SettingsView.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import SwiftUI
import WatchKit

struct SettingsView: View {
    @ObservedObject var connectivity = ConnectivityManager.shared
    @State private var selectedInterval: Int = 5
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Haptic Interval")
                .font(.headline)
                .padding(.top, 8)
            
            Picker("Minutes", selection: $selectedInterval) {
                ForEach(1...60, id: \.self) { minutes in
                    Text("\(minutes)").tag(minutes)
                }
            }
            .labelsHidden()
            .frame(height: 80)
            
            Text("\(selectedInterval) min")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button(action: {
                // Save the setting and sync to iPhone
                connectivity.hapticIntervalMinutes = selectedInterval
                
                // Play light haptic feedback
                WKInterfaceDevice.current().play(.click)
                
                // Navigate back to main timer screen
                selectedTab = 1
            }) {
                Text("Apply")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .onAppear {
            selectedInterval = connectivity.hapticIntervalMinutes
        }
        .onChange(of: connectivity.hapticIntervalMinutes) { _, newValue in
            // Update the picker if the value changed from iPhone
            selectedInterval = newValue
        }
    }
}

#Preview {
    SettingsView(selectedTab: .constant(0))
}

