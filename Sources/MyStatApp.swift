import SwiftUI

@main
struct MyStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguage = "system"
    
    var body: some Scene {
        // App needs at least one scene. It used to be `Settings { EmptyView() }`,
        // but SwiftUI can present that scene on its own (titled "MyStat設定"),
        // which showed up as a blank window. The real settings window is built
        // by AppDelegate.openSettings, so the placeholder scene is a menu bar
        // extra that is never inserted: no window, no "Settings…" menu item.
        MenuBarExtra("MyStat", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
