//
//  TimerViewModel.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import Foundation
import Combine
import WatchKit

class TimerViewModel: NSObject, ObservableObject {
    @Published var elapsedTime: TimeInterval = 0
    @Published var isRunning: Bool = false
    
    private var timer: Timer?
    private var startTime: Date?
    private var accumulatedTime: TimeInterval = 0
    private var lastHapticInterval: Int = 0
    private var extendedRuntimeSession: WKExtendedRuntimeSession?
    
    private let connectivity = ConnectivityManager.shared
    
    // Called when a haptic interval is reached, with the count of how many intervals
    var onHapticInterval: ((Int) -> Void)?
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        startTime = Date()
        
        // Start extended runtime session to keep app running in background
        startExtendedRuntimeSession()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.elapsedTime = self.accumulatedTime + Date().timeIntervalSince(startTime)
            
            // Check for custom interval from ConnectivityManager
            let intervalSeconds = self.connectivity.hapticIntervalMinutes * 60
            let currentInterval = Int(self.elapsedTime) / intervalSeconds
            if currentInterval > self.lastHapticInterval && currentInterval > 0 {
                self.lastHapticInterval = currentInterval
                self.onHapticInterval?(currentInterval)
            }
        }
    }
    
    func stop() {
        isRunning = false
        if let startTime = startTime {
            accumulatedTime += Date().timeIntervalSince(startTime)
        }
        timer?.invalidate()
        timer = nil
        startTime = nil
        
        // End extended runtime session
        stopExtendedRuntimeSession()
    }
    
    func reset() {
        stop()
        elapsedTime = 0
        accumulatedTime = 0
        lastHapticInterval = 0
    }
    
    // MARK: - Extended Runtime Session
    
    private func startExtendedRuntimeSession() {
        // Clean up any existing session
        stopExtendedRuntimeSession()
        
        let session = WKExtendedRuntimeSession()
        extendedRuntimeSession = session
        
        session.delegate = self
        session.start()
    }
    
    private func stopExtendedRuntimeSession() {
        extendedRuntimeSession?.invalidate()
        extendedRuntimeSession = nil
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension TimerViewModel: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session started")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session will expire")
        // Session is about to expire, clean up
        stopExtendedRuntimeSession()
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("Extended runtime session invalidated: \(reason)")
        if let error = error {
            print("Error: \(error.localizedDescription)")
        }
        self.extendedRuntimeSession = nil
    }
} 
