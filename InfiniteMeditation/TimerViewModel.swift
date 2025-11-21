//
//  TimerViewModel.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import Foundation
import Combine

class TimerViewModel: ObservableObject {
    @Published var elapsedTime: TimeInterval = 0
    @Published var isRunning: Bool = false
    
    private var timer: Timer?
    private var lastHapticInterval: Int = 0
    
    // Called when a 5-minute interval is reached
    var onFiveMinuteInterval: (() -> Void)?
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedTime += 1
            let interval = Int(self.elapsedTime) / 300
            if interval > self.lastHapticInterval {
                self.lastHapticInterval = interval
                self.onFiveMinuteInterval?()
            }
        }
    }
    
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        lastHapticInterval = 0
    }
    
    func reset() {
        stop()
        elapsedTime = 0
    }
}
