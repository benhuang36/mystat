import Cocoa
import SwiftUI
import Combine

class DisplayMenuBuilder: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        menu.delegate = self
        
        // Listen for display changes to rebuild the menu if it's currently open
        DisplayManager.shared.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        NotificationCenter.default.post(name: NSNotification.Name("CloseAllPopovers"), object: nil)
    }
    
    func buildMenu() {
        menu.removeAllItems()
        
        let displays = DisplayManager.shared.displays
        if displays.isEmpty {
            menu.addItem(withTitle: "No Displays Found", action: nil, keyEquivalent: "")
            return
        }
        
        for display in displays {
            // Display Name Header
            let nameItem = NSMenuItem(title: display.name, action: nil, keyEquivalent: "")
            nameItem.isEnabled = false
            menu.addItem(nameItem)
            
            // Current Resolution Item with Submenu for all resolutions
            if let currentMode = display.currentMode {
                let resTitle = currentMode.isHiDPI ? "\(currentMode.resolutionString) ⚡" : currentMode.resolutionString
                let resItem = NSMenuItem(title: resTitle, action: nil, keyEquivalent: "")
                
                let resMenu = NSMenu()
                
                // Group modes by resolution + HiDPI to show unique resolution entries
                var uniqueResolutions = [DisplayModeInfo]()
                var seen = Set<String>()
                for mode in display.availableModes {
                    let key = "\(mode.width)x\(mode.height)-\(mode.isHiDPI)"
                    if !seen.contains(key) {
                        seen.insert(key)
                        uniqueResolutions.append(mode)
                    }
                }
                
                for mode in uniqueResolutions {
                    let title = mode.isHiDPI ? "\(mode.resolutionString) ⚡" : mode.resolutionString
                    let item = NSMenuItem(title: title, action: #selector(resolutionSelected(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = ["display": display, "mode": mode]
                    if mode.width == currentMode.width && mode.height == currentMode.height && mode.isHiDPI == currentMode.isHiDPI {
                        item.state = .on
                    }
                    resMenu.addItem(item)
                }
                
                resItem.submenu = resMenu
                menu.addItem(resItem)
                
                // Current Refresh Rate with Submenu for all refresh rates at this resolution
                let refreshStr = String(format: "%.0f Hz", currentMode.refreshRate)
                let refreshItem = NSMenuItem(title: refreshStr, action: nil, keyEquivalent: "")
                
                let refreshMenu = NSMenu()
                let rates = display.availableModes
                    .filter { $0.width == currentMode.width && $0.height == currentMode.height && $0.isHiDPI == currentMode.isHiDPI }
                    .map { round($0.refreshRate) }
                
                let uniqueRates = Array(Set(rates)).sorted(by: >)
                
                for rate in uniqueRates {
                    let rTitle = String(format: "%.0f Hz", rate)
                    let item = NSMenuItem(title: rTitle, action: #selector(refreshRateSelected(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = ["display": display, "rate": rate]
                    if abs(rate - round(currentMode.refreshRate)) < 0.1 {
                        item.state = .on
                    }
                    refreshMenu.addItem(item)
                }
                
                refreshItem.submenu = refreshMenu
                menu.addItem(refreshItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
    }
    
    @objc func openSettings(_ sender: NSMenuItem) {
        AppDelegate.shared.openSettings()
    }
    
    @objc func resolutionSelected(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let display = dict["display"] as? DisplayInfo,
              let mode = dict["mode"] as? DisplayModeInfo else { return }
        
        DisplayManager.shared.setResolution(for: display, width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI)
    }
    
    @objc func refreshRateSelected(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let display = dict["display"] as? DisplayInfo,
              let rate = dict["rate"] as? Double else { return }
        
        DisplayManager.shared.setRefreshRate(for: display, refreshRate: rate)
    }
}
