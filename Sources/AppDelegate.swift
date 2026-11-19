import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        
        // Disable automatic termination to ensure the app stays in the menu bar
        ProcessInfo.processInfo.disableAutomaticTermination("MyStat is a continuous menu bar utility")
        
        // Initialize the Menu Bar Manager to spawn icons based on settings
        _ = MenuBarManager.shared
    }
    
    /// The window is kept for reuse (frame, position), but closing it does not
    /// fire SwiftUI's onDisappear, so a live tree would keep observing and
    /// re-rendering off-screen. Swap in an empty view, as popovers do on close.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        let frame = window.frame
        window.contentView = NSView()
        window.setFrame(frame, display: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    @objc func openSettings() {
        openSettings(for: nil)
    }
    
    func openSettings(for type: MonitorType?) {
        if let type = type {
            SettingsNavigationManager.shared.selection = .monitor(type)
        } else {
            SettingsNavigationManager.shared.selection = .general
        }
        
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
            window.delegate = self
            settingsWindow = window
        }
        // (Re)attach the SwiftUI tree on every open; windowWillClose drops it.
        if let window = settingsWindow, !(window.contentView is NSHostingView<RootEnvironmentView<SettingsView>>) {
            window.contentView = NSHostingView(rootView: RootEnvironmentView { SettingsView() })
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
