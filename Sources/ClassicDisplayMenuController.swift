import Cocoa

class ClassicDisplayMenuController {
    private var statusItem: NSStatusItem?
    private let menuBuilder = DisplayMenuBuilder()
    
    init() {
        createStatusItem()
    }
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "MyStat_ClassicDisplay"
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "Classic Display Menu")
        }
        
        statusItem?.menu = menuBuilder.menu
    }
    
    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
}
