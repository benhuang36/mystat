import SwiftUI

@main
struct MyStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Window("MyStat Settings", id: "settings") {
            SettingsView()
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
