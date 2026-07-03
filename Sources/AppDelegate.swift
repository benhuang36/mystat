import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register default preferences
        let defaultPrefs: [String: Any] = [
            "showCPU": true,
            "showMemory": true,
            "showDisk": false
        ]
        UserDefaults.standard.register(defaults: defaultPrefs)
        
        // Initialize the Menu Bar Manager to spawn icons based on settings
        _ = MenuBarManager.shared
    }
}
