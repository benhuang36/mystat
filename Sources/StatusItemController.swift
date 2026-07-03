import Cocoa
import SwiftUI
import Combine

class StatusItemController {
    let type: MonitorType
    private var statusItem: NSStatusItem?
    private var popover: NSPopover
    private var eventMonitor: Any?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(type: MonitorType) {
        self.type = type
        self.popover = NSPopover()
        self.popover.behavior = .transient
        
        switch type {
        case .cpu:
            popover.contentViewController = NSHostingController(rootView: CPUPopoverView())
        case .memory:
            popover.contentViewController = NSHostingController(rootView: MemoryPopoverView())
        case .disk:
            popover.contentViewController = NSHostingController(rootView: DiskPopoverView())
        case .network:
            popover.contentViewController = NSHostingController(rootView: NetworkPopoverView())
        case .battery:
            popover.contentViewController = NSHostingController(rootView: BatteryPopoverView())
        }
        
        createStatusItem()
        setupSubscriptions()
    }
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "MyStat_\(type.rawValue)"
        
        if let button = statusItem?.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        updateButtonUI()
        setupEventMonitor()
    }
    
    private func setupSubscriptions() {
        // Observe system monitor changes to update UI
        switch type {
        case .cpu:
            SystemMonitor.shared.$cpuUsage
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .memory:
            SystemMonitor.shared.$memoryUsageRatio
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .disk:
            SystemMonitor.shared.$diskUsageRatio
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .network:
            SystemMonitor.shared.$networkUploadSpeed
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .battery:
            SystemMonitor.shared.$batteryStats
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        }
        
        // Observe UserDefaults for display style change
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButtonUI() }
            .store(in: &cancellables)
    }
    
    private func updateButtonUI() {
        guard let button = statusItem?.button else { return }
        
        let styleRaw = UserDefaults.standard.string(forKey: "\(type.rawValue.lowercased())DisplayStyle") ?? "Icon Only"
        
        let getSymbolImage: () -> NSImage? = {
            if self.type == .battery {
                let stats = SystemMonitor.shared.batteryStats
                let percentage = stats.percentage
                let isCharging = stats.isCharging
                let symbolName: String
                
                switch percentage {
                case 0..<12.5: symbolName = "battery.0"
                case 12.5..<37.5: symbolName = "battery.25"
                case 37.5..<62.5: symbolName = "battery.50"
                case 62.5..<87.5: symbolName = "battery.75"
                default: symbolName = "battery.100"
                }
                
                guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: self.type.rawValue) else {
                    return nil
                }
                
                if !isCharging {
                    return baseImage
                }
                
                // Composite bolt over battery
                guard let boltImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) else {
                    return baseImage
                }
                
                // Expand canvas height by 30% to fit the protruding bolt
                let finalSize = NSSize(width: baseImage.size.width, height: baseImage.size.height * 1.3)
                let newImage = NSImage(size: finalSize)
                newImage.lockFocus()
                
                // Draw base image vertically centered
                let baseRect = NSRect(
                    x: 0,
                    y: (finalSize.height - baseImage.size.height) / 2.0,
                    width: baseImage.size.width,
                    height: baseImage.size.height
                )
                baseImage.draw(in: baseRect)
                
                // Scale bolt to be 1.2x the height of the battery
                let boltHeight = baseImage.size.height * 1.2
                let scale = boltHeight / boltImage.size.height
                let boltWidth = boltImage.size.width * scale
                
                // Center bolt, slightly offset to the left due to the battery terminal
                let centerX = (finalSize.width / 2.0) - 1.5
                let centerY = finalSize.height / 2.0
                
                let boltRect = NSRect(
                    x: centerX - (boltWidth / 2.0),
                    y: centerY - (boltHeight / 2.0),
                    width: boltWidth,
                    height: boltHeight
                )
                
                let haloRect = NSRect(
                    x: boltRect.origin.x - 1.5,
                    y: boltRect.origin.y - 1.5,
                    width: boltRect.width + 3.0,
                    height: boltRect.height + 3.0
                )
                
                boltImage.draw(in: haloRect, from: .zero, operation: .destinationOut, fraction: 1.0)
                boltImage.draw(in: boltRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                
                newImage.unlockFocus()
                newImage.isTemplate = true
                
                return newImage
            } else {
                return NSImage(systemSymbolName: self.type.sfSymbolName, accessibilityDescription: self.type.rawValue)
            }
        }
        
        if styleRaw == "Icon Only" {
            button.image = getSymbolImage()
            button.title = ""
        } else if styleRaw == "Text" {
            button.image = getSymbolImage()
            switch type {
            case .cpu:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.cpuUsage)
            case .memory:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.memoryUsageRatio * 100)
            case .disk:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.diskUsageRatio * 100)
            case .network:
                let formatSpeed: (Double) -> String = { bytes in
                    let kb = bytes / 1024.0
                    if kb < 1024.0 {
                        return String(format: "%.0f K/s", kb)
                    }
                    let mb = kb / 1024.0
                    return String(format: "%.1f M/s", mb)
                }
                
                let text = "\(formatSpeed(SystemMonitor.shared.networkDownloadSpeed))\n\(formatSpeed(SystemMonitor.shared.networkUploadSpeed))"
                if let currentImage = button.image {
                    button.image = MenuBarImageGenerator.addSpeedText(text, to: currentImage)
                }
                button.attributedTitle = NSAttributedString(string: "")
                button.title = ""
            case .battery:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.batteryStats.percentage)
            }
        } else {
            // Graphical Modes
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            var value: Double = 0
            var history: [Double] = []
            var color: NSColor = .controlTextColor
            var secondaryValue: Double? = nil
            var secondaryHistory: [Double]? = nil
            var secondaryColor: NSColor? = nil
            
            switch type {
            case .cpu:
                value = SystemMonitor.shared.cpuUsage
                history = SystemMonitor.shared.cpuUsageHistory
                color = .systemRed
            case .memory:
                value = SystemMonitor.shared.memoryUsageRatio * 100
                history = SystemMonitor.shared.memoryUsageHistory
                color = .systemBlue
            case .disk:
                value = SystemMonitor.shared.diskUsageRatio * 100
                history = []
                color = .systemPurple
            case .network:
                let kbOut = SystemMonitor.shared.networkUploadSpeed / 1024
                let kbIn = SystemMonitor.shared.networkDownloadSpeed / 1024
                // Primary: Download
                value = min(100, (kbIn / 10000.0) * 100.0) 
                history = SystemMonitor.shared.networkDownloadHistory
                color = NSColor(calibratedRed: 0.0, green: 0.6, blue: 1.0, alpha: 1.0) // Cyan/Blue
                
                // Secondary: Upload
                secondaryValue = min(100, (kbOut / 10000.0) * 100.0)
                secondaryHistory = SystemMonitor.shared.networkUploadHistory
                secondaryColor = NSColor(calibratedRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Red
            case .battery:
                value = SystemMonitor.shared.batteryStats.percentage
                history = []
                color = SystemMonitor.shared.batteryStats.isCharging ? .systemGreen : .systemYellow
            }
            
            if styleRaw == DisplayStyle.history.rawValue {
                button.image = MenuBarImageGenerator.generateHistoryChart(history: history, color: color, secondaryHistory: secondaryHistory, secondaryColor: secondaryColor)
            } else if styleRaw == DisplayStyle.pieChart.rawValue {
                button.image = MenuBarImageGenerator.generatePieChart(value: value, color: color, secondaryValue: secondaryValue, secondaryColor: secondaryColor)
            } else if styleRaw == DisplayStyle.gauge.rawValue {
                button.image = MenuBarImageGenerator.generateGauge(value: value, color: color, secondaryValue: secondaryValue, secondaryColor: secondaryColor)
            } else if styleRaw == DisplayStyle.barChart.rawValue {
                button.image = MenuBarImageGenerator.generateBarChart(value: value, color: color, secondaryValue: secondaryValue, secondaryColor: secondaryColor)
            } else {
                button.image = getSymbolImage()
            }
            
            // Add label if toggled and not falling back to standard icon
            let showLabel = UserDefaults.standard.bool(forKey: "\(type.rawValue.lowercased())ShowLabel")
            if showLabel && styleRaw != DisplayStyle.icon.rawValue {
                if type == .network {
                    let formatSpeed: (Double) -> String = { bytes in
                        let kb = bytes / 1024.0
                        if kb < 1024.0 {
                            return String(format: "%.0f K/s", kb)
                        }
                        let mb = kb / 1024.0
                        return String(format: "%.1f M/s", mb)
                    }
                    
                    let text = "\(formatSpeed(SystemMonitor.shared.networkDownloadSpeed))\n\(formatSpeed(SystemMonitor.shared.networkUploadSpeed))"
                    if let currentImage = button.image {
                        button.image = MenuBarImageGenerator.addSpeedText(text, to: currentImage)
                    }
                    button.attributedTitle = NSAttributedString(string: "")
                    button.title = ""
                } else {
                    var label = ""
                    switch type {
                    case .cpu: label = "C\nP\nU"
                    case .memory: label = "M\nE\nM"
                    case .disk: label = "S\nS\nD"
                    case .battery: label = "B\nA\nT"
                    default: break
                    }
                    if let currentImage = button.image, !label.isEmpty {
                        button.image = MenuBarImageGenerator.addLabel(label, to: currentImage)
                    }
                }
            }
        }
    }
    
    func setVisible(_ visible: Bool) {
        statusItem?.isVisible = visible
    }
    
    func remove() {
        cancellables.removeAll()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
    
    func showPopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
    
    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.popover.isShown == true {
                self?.closePopover(event)
            }
        }
    }
}
