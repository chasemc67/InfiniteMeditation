//
//  ConnectivityManager.swift
//  InfiniteMeditation
//
//  Created by Chase McCarty on 11/21/25.
//

import Foundation
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
        print("📱 iOS: Loaded initial interval: \(initialValue) min")
        
        // Setup WatchConnectivity after loading value
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        } else {
            print("📱 iOS: WatchConnectivity not supported")
        }
    }
    
    private func saveAndSync() {
        guard !isSyncing else { return }
        
        // Save locally
        UserDefaults.standard.set(hapticIntervalMinutes, forKey: "hapticIntervalMinutes")
        
        // Check if session is ready
        guard isSessionActivated else {
            print("📱 iOS: Session not ready yet, will sync when activated")
            pendingSync = true
            return
        }
        
        syncToWatch()
    }
    
    private func syncToWatch() {
        guard session.activationState == .activated else {
            return
        }
        
        guard session.isPaired else {
            if hasInitialSyncAttempted {
                print("📱 iOS: Watch not paired")
            }
            return
        }
        
        guard session.isWatchAppInstalled else {
            if hasInitialSyncAttempted {
                print("📱 iOS: Watch app not installed (may be installing...)")
            }
            return
        }
        
        let context = ["hapticIntervalMinutes": hapticIntervalMinutes]
        do {
            try session.updateApplicationContext(context)
            print("📱 iOS: ✅ Synced interval to Watch: \(hapticIntervalMinutes) min")
            pendingSync = false
        } catch {
            // Only log if it's not a "counterpart not installed" error (which is common during dev)
            let errorMessage = error.localizedDescription
            if !errorMessage.contains("not installed") {
                print("📱 iOS: ❌ Error syncing to Watch: \(errorMessage)")
            }
        }
    }
}

extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("📱 iOS: ❌ WCSession activation error: \(error.localizedDescription)")
            return
        }
        
        print("📱 iOS: ✅ WCSession activated successfully")
        
        isSessionActivated = true
        hasInitialSyncAttempted = true
        
        // Attempt initial sync (silent if watch not ready yet)
        if pendingSync {
            syncToWatch()
        }
        
        // Log status for debugging
        if session.isPaired && session.isWatchAppInstalled {
            print("📱 iOS: Watch paired and app installed ✅")
        } else if !session.isPaired {
            print("📱 iOS: Watch not paired")
        } else if !session.isWatchAppInstalled {
            print("📱 iOS: Watch app not yet installed (may still be deploying...)")
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Normal during watch switching, no need to log
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate session (happens when switching watches)
        isSessionActivated = false
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        // When watch becomes reachable, try syncing any pending changes
        if session.isReachable && pendingSync {
            print("📱 iOS: Watch is now reachable, syncing...")
            syncToWatch()
        }
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        // When watch state changes (app installed/uninstalled), try syncing
        if session.isWatchAppInstalled && pendingSync {
            print("📱 iOS: Watch app now detected, syncing...")
            syncToWatch()
        }
    }
    
    // Receive updates from Watch
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let interval = applicationContext["hapticIntervalMinutes"] as? Int {
                print("📱 iOS: Received interval from Watch: \(interval) min")
                // Update without triggering sync back
                self.isSyncing = true
                self.hapticIntervalMinutes = interval
                UserDefaults.standard.set(interval, forKey: "hapticIntervalMinutes")
                self.isSyncing = false
            }
        }
    }
}
