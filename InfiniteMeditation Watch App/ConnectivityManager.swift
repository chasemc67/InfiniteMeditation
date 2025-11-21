//
//  ConnectivityManager.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import Foundation
import Combine
import WatchConnectivity

class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()
    
    @Published var hapticIntervalMinutes: Int = 5 {
        didSet {
            guard oldValue != hapticIntervalMinutes else { return }
            saveAndSync()
        }
    }
    
    private let session = WCSession.default
    private var isSyncing = false
    private var isSessionActivated = false
    private var pendingSync = false
    private var hasInitialSyncAttempted = false
    
    private override init() {
        super.init()
        
        // Load saved value first
        let saved = UserDefaults.standard.integer(forKey: "hapticIntervalMinutes")
        let initialValue = saved > 0 ? saved : 5
        
        // Set without triggering didSet
        _hapticIntervalMinutes = Published(initialValue: initialValue)
        print("⌚️ Watch: Loaded initial interval: \(initialValue) min")
        
        // Setup WatchConnectivity after loading value
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        } else {
            print("⌚️ Watch: WatchConnectivity not supported")
        }
    }
    
    private func saveAndSync() {
        guard !isSyncing else { return }
        
        // Save locally
        UserDefaults.standard.set(hapticIntervalMinutes, forKey: "hapticIntervalMinutes")
        
        // Check if session is ready
        guard isSessionActivated else {
            print("⌚️ Watch: Session not ready yet, will sync when activated")
            pendingSync = true
            return
        }
        
        syncToiPhone()
    }
    
    private func syncToiPhone() {
        guard session.activationState == .activated else {
            return
        }
        
        let context = ["hapticIntervalMinutes": hapticIntervalMinutes]
        do {
            try session.updateApplicationContext(context)
            print("⌚️ Watch: ✅ Synced interval to iPhone: \(hapticIntervalMinutes) min")
            pendingSync = false
        } catch {
            // Only log if it's not a "counterpart not installed" error
            let errorMessage = error.localizedDescription
            if !errorMessage.contains("not installed") {
                print("⌚️ Watch: ❌ Error syncing to iPhone: \(errorMessage)")
            }
        }
    }
}

extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("⌚️ Watch: ❌ WCSession activation error: \(error.localizedDescription)")
            return
        }
        
        print("⌚️ Watch: ✅ WCSession activated successfully")
        
        isSessionActivated = true
        hasInitialSyncAttempted = true
        
        // Attempt initial sync (silent if iPhone not ready yet)
        if pendingSync {
            syncToiPhone()
        }
    }
    
    // Receive updates from iPhone
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let interval = applicationContext["hapticIntervalMinutes"] as? Int {
                print("⌚️ Watch: ✅ Received interval from iPhone: \(interval) min")
                // Update without triggering sync back
                self.isSyncing = true
                self.hapticIntervalMinutes = interval
                UserDefaults.standard.set(interval, forKey: "hapticIntervalMinutes")
                self.isSyncing = false
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        // When iPhone becomes reachable, try syncing any pending changes
        if session.isReachable && pendingSync {
            print("⌚️ Watch: iPhone is now reachable, syncing...")
            syncToiPhone()
        }
    }
}
