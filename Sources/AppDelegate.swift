import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var settingsWindow: NSWindow?
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
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
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    @objc func openSettings() {
        NotificationCenter.default.post(name: NSNotification.Name("CloseAllPopovers"), object: nil)
        
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "MyStat Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 850, height: 600)
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: RootEnvironmentView { SettingsView() })
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
