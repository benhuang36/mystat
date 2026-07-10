import SwiftUI

@main
struct MyStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguage = "system"
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
