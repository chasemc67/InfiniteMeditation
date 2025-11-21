//
//  HapticTestView.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import SwiftUI
import WatchKit

struct HapticTestView: View {
    @State private var selectedHaptic: WKHapticType = .notification
    
    // All available haptic types
    let hapticTypes: [(String, WKHapticType)] = [
        ("Notification", .notification),
        ("Direction Up", .directionUp),
        ("Direction Down", .directionDown),
        ("Success", .success),
        ("Failure", .failure),
        ("Retry", .retry),
        ("Start", .start),
        ("Stop", .stop),
        ("Click", .click)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Haptic Test")
                .font(.headline)
                .padding(.top, 8)
            
            Picker("Haptic Type", selection: $selectedHaptic) {
                ForEach(hapticTypes, id: \.1) { name, type in
                    Text(name).tag(type)
                }
            }
            .labelsHidden()
            
            Button(action: {
                WKInterfaceDevice.current().play(selectedHaptic)
            }) {
                Text("Play Haptic")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            
            Text(hapticTypes.first(where: { $0.1 == selectedHaptic })?.0 ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HapticTestView()
}

