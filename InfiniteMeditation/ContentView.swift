//
//  ContentView.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @ObservedObject var connectivity = ConnectivityManager.shared
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Timer Display
            Text(timeString(from: viewModel.elapsedTime))
                .font(.system(size: 48, weight: .medium, design: .monospaced))
            
            // Start/Stop Button
            Button(action: {
                if viewModel.isRunning {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            }) {
                Text(viewModel.isRunning ? "Stop" : "Start")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            
            // Reset Button
            Button(action: {
                viewModel.reset()
            }) {
                Text("Reset")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            
            Spacer()
            
            // Interval Picker
            VStack(spacing: 8) {
                Text("Haptic Interval")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Interval", selection: $connectivity.hapticIntervalMinutes) {
                    ForEach(1...60, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.bottom, 16)
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
