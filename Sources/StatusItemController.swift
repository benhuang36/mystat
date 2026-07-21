import Cocoa
import SwiftUI
import Combine

class CustomPopoverPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height),
                   styleMask: [.nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        self.isFloatingPanel = true
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.level = .popUpMenu
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor)
        ])

        self.contentView = visualEffect
    }

    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

/// Owns the popover panel + event monitors for one monitor type.
/// Shared between the standalone status items and Combined Mode, where several
/// presenters anchor to segments of the same status item button.
class MonitorPopoverPresenter {
    let type: MonitorType
    private var panel: CustomPopoverPanel?
    private var eventMonitor: Any?
    private var globalEventMonitor: Any?
    private var isFadingOut = false
    private weak var anchorButton: NSStatusBarButton?
    private var cancellables = Set<AnyCancellable>()

    init(type: MonitorType) {
        self.type = type

        // Mutual exclusion: close this popover if another one is opened
        NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopovers"))
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let sender = notification.object as? MonitorPopoverPresenter, sender === self { return }
                if self.panel != nil {
                    self.close()
                }
            }
            .store(in: &cancellables)
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// `segmentMidX`: horizontal center of the clicked segment in the anchor
    /// button's coordinates (Combined Mode); nil centers on the whole button.
    func toggle(anchor: NSStatusBarButton, segmentMidX: CGFloat? = nil) {
        if isShown {
            close()
        } else {
            show(anchor: anchor, segmentMidX: segmentMidX)
        }
    }

    func show(anchor: NSStatusBarButton, segmentMidX: CGFloat? = nil) {
        NotificationCenter.default.post(name: NSNotification.Name("CloseAllPopovers"), object: self)

        // Count every open (close decrements every close); the panel itself
        // is created once and kept alive for reuse, so this must NOT be tied to creation.
        SystemMonitor.shared.activePopoversCount += 1
        anchorButton = anchor

        if panel == nil {
            let view: AnyView
            switch type {
            case .cpu: view = AnyView(RootEnvironmentView { CPUPopoverView() })
            case .memory: view = AnyView(RootEnvironmentView { MemoryPopoverView() })
            case .disk: view = AnyView(RootEnvironmentView { DiskPopoverView() })
            case .network: view = AnyView(RootEnvironmentView { NetworkPopoverView() })
            case .battery: view = AnyView(RootEnvironmentView { BatteryPopoverView() })
            case .time: view = AnyView(RootEnvironmentView { TimePopoverView() })
            case .display: view = AnyView(RootEnvironmentView { DisplayPopoverView() })
            }

            let hostingController = NSHostingController(rootView: view)
            hostingController.view.setFrameSize(hostingController.view.fittingSize)
            panel = CustomPopoverPanel(contentView: hostingController.view)
        }

        if let window = panel {
            let buttonFrame = anchor.window?.convertToScreen(anchor.frame) ?? .zero
            let anchorMidX = segmentMidX.map { buttonFrame.minX + $0 } ?? buttonFrame.midX
            var xPos = anchorMidX - window.frame.width / 2
            let yPos = buttonFrame.minY - window.frame.height - 8

            if let screen = anchor.window?.screen {
                let screenRect = screen.visibleFrame
                if xPos + window.frame.width > screenRect.maxX - 8 {
                    xPos = screenRect.maxX - window.frame.width - 8
                }
                if xPos < screenRect.minX + 8 {
                    xPos = screenRect.minX + 8
                }
            }

            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))

            window.alphaValue = 0.0
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: NSNotification.Name("PopoverDidOpen"), object: type.rawValue)

            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    window.animator().alphaValue = 1.0
                }
            }

            setupEventMonitors()
        }
    }

    func close() {
        guard let window = panel else { return }
        guard window.isVisible else { return } // Already closed

        if !isFadingOut {
            isFadingOut = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                window.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                window.orderOut(nil)
                // Keep the panel alive for future use to avoid rendering delay
                self?.isFadingOut = false
                SystemMonitor.shared.activePopoversCount = max(0, SystemMonitor.shared.activePopoversCount - 1)
                self?.removeEventMonitors()
            })
        }
    }

    func invalidate() {
        removeEventMonitors()
        cancellables.removeAll()
    }

    private func setupEventMonitors() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.close()
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }

            if let button = self.anchorButton {
                let pointInButtonWindow = event.locationInWindow
                let viewPoint = button.convert(pointInButtonWindow, from: nil)
                if button.bounds.contains(viewPoint) {
                    return event
                }
            }

            let pointInPanel = event.locationInWindow
            if !panel.contentView!.bounds.contains(pointInPanel) {
                self.close()
            }

            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

/// Stateless menu bar image composition for one monitor type, reading the
/// user's style/color preferences. Shared by the standalone status items and
/// Combined Mode segments.
enum MenuBarItemRenderer {

    static func networkSpeedText() -> String {
        let formatSpeed: (Double) -> String = { bytes in
            let kb = bytes / 1024.0
            if kb < 1024.0 {
                return String(format: "%.0f K/s", kb)
            }
            let mb = kb / 1024.0
            return String(format: "%.1f M/s", mb)
        }
        return "\(formatSpeed(SystemMonitor.shared.networkDownloadSpeed))\n\(formatSpeed(SystemMonitor.shared.networkUploadSpeed))"
    }

    /// The SF Symbol image for the type; battery composes charge level + bolt.
    static func symbolImage(for type: MonitorType) -> NSImage? {
        guard type == .battery else {
            return NSImage(systemSymbolName: type.sfSymbolName, accessibilityDescription: type.rawValue)
        }

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

        guard let rawImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: type.rawValue) else {
            return nil
        }

        // Scale so the battery BODY is as tall as the drawn Capacity
        // Bar battery (11pt). The SF Symbol canvas has padding: the
        // glyph itself only fills ~82% of the canvas height (measured),
        // so scale against the glyph, not the canvas.
        let glyphHeightRatio: CGFloat = 0.82
        let targetHeight: CGFloat = 11
        let scaleRatio = targetHeight / (rawImage.size.height * glyphHeightRatio)
        let scaledSize = NSSize(width: rawImage.size.width * scaleRatio, height: rawImage.size.height * scaleRatio)
        let baseImage = NSImage(size: scaledSize, flipped: false) { rect in
            rawImage.draw(in: rect)
            return true
        }
        baseImage.isTemplate = true

        if !isCharging {
            return baseImage
        }

        guard let boltImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) else {
            return baseImage
        }

        let finalSize = NSSize(width: baseImage.size.width, height: baseImage.size.height * 1.3)
        let newImage = NSImage(size: finalSize)
        newImage.lockFocus()

        let baseRect = NSRect(
            x: 0,
            y: (finalSize.height - baseImage.size.height) / 2.0,
            width: baseImage.size.width,
            height: baseImage.size.height
        )
        baseImage.draw(in: baseRect)

        let boltHeight = baseImage.size.height * 1.2
        let scale = boltHeight / boltImage.size.height
        let boltWidth = boltImage.size.width * scale

        let centerX = (finalSize.width / 2.0) - 1.5
        let centerY = finalSize.height / 2.0

        let boltRect = NSRect(
            x: centerX - (boltWidth / 2.0),
            y: centerY - (boltHeight / 2.0),
            width: boltWidth,
            height: boltHeight
        )

        // Punch the bolt's silhouette at offsets all around it
        // (morphological dilation) for an even outline gap — a single
        // enlarged copy makes the gap wider at points and thinner on flats
        let haloRadius: CGFloat = 1.3
        let steps = 12
        for i in 0..<steps {
            let angle = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let offsetRect = boltRect.offsetBy(dx: cos(angle) * haloRadius, dy: sin(angle) * haloRadius)
            boltImage.draw(in: offsetRect, from: .zero, operation: .destinationOut, fraction: 1.0)
        }
        boltImage.draw(in: boltRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        newImage.unlockFocus()
        newImage.isTemplate = true

        return newImage
    }

    /// Full composed image for the graphical styles (chart + value text + label).
    /// Falls back to the symbol image for unknown styles.
    static func graphicalImage(for type: MonitorType, styleRaw: String) -> NSImage? {
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
            // History style shows read (top) / write (bottom) activity
            history = SystemMonitor.shared.diskReadHistory
            secondaryHistory = SystemMonitor.shared.diskWriteHistory
            color = .systemPurple
            secondaryColor = .systemOrange
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
            let stats = SystemMonitor.shared.batteryStats
            value = stats.percentage
            history = []
            if stats.isCharging {
                color = .systemGreen
            } else if stats.percentage <= 20 {
                color = .systemRed
            } else {
                color = .controlTextColor
            }
        case .time, .display:
            return symbolImage(for: type)
        }

        // User-selected chart colors override the per-monitor defaults
        let colorPref = UserDefaults.standard.string(forKey: "\(type.rawValue.lowercased())ChartColor") ?? MenuBarColor.auto.rawValue
        if let customColor = MenuBarColor(rawValue: colorPref)?.nsColor {
            color = customColor
        }
        let secondaryPref = UserDefaults.standard.string(forKey: "\(type.rawValue.lowercased())SecondaryColor") ?? MenuBarColor.auto.rawValue
        if secondaryColor != nil, let customSecondary = MenuBarColor(rawValue: secondaryPref)?.nsColor {
            secondaryColor = customSecondary
        }

        let showValue = UserDefaults.standard.bool(forKey: "\(type.rawValue.lowercased())ShowValue")
        var valueShownInsideGauge = false
        var image: NSImage?

        if styleRaw == DisplayStyle.history.rawValue {
            image = MenuBarImageGenerator.generateHistoryChart(history: history, color: color, secondaryHistory: secondaryHistory, secondaryColor: secondaryColor)
        } else if styleRaw == DisplayStyle.pieChart.rawValue {
            image = MenuBarImageGenerator.generatePieChart(value: value, color: color, secondaryValue: secondaryValue, secondaryColor: secondaryColor)
        } else if styleRaw == DisplayStyle.gauge.rawValue {
            let insideGauge = showValue && secondaryValue == nil
                && UserDefaults.standard.bool(forKey: "\(type.rawValue.lowercased())GaugeValueInside")
            valueShownInsideGauge = insideGauge
            image = MenuBarImageGenerator.generateGauge(
                value: value,
                color: color,
                secondaryValue: secondaryValue,
                secondaryColor: secondaryColor,
                centerText: insideGauge ? String(format: "%.0f", value) : nil
            )
        } else if styleRaw == DisplayStyle.barChart.rawValue {
            image = MenuBarImageGenerator.generateBarChart(value: value, color: color, secondaryValue: secondaryValue, secondaryColor: secondaryColor)
        } else if styleRaw == DisplayStyle.coreBars.rawValue {
            image = MenuBarImageGenerator.generateCoreBars(usages: SystemMonitor.shared.cpuCoreUsages, color: color)
        } else if styleRaw == DisplayStyle.capacityBar.rawValue {
            image = MenuBarImageGenerator.generateCapacityBar(value: value, color: color, showNub: type == .battery)
        } else {
            return symbolImage(for: type)
        }

        // Append current value text (e.g. "42%") if enabled and not already inside the gauge.
        // Battery uses menu-bar-sized text to match the Percentage Text style.
        if showValue && !valueShownInsideGauge && type != .network, let chartImage = image {
            image = MenuBarImageGenerator.addValueText(
                String(format: "%.0f%%", value),
                to: chartImage,
                fontSize: type == .battery ? 13 : 11
            )
        }

        // Add label if toggled and not falling back to standard icon
        let showLabel = UserDefaults.standard.bool(forKey: "\(type.rawValue.lowercased())ShowLabel")
        if showLabel && styleRaw != DisplayStyle.icon.rawValue {
            if type == .network {
                if let currentImage = image {
                    image = MenuBarImageGenerator.addSpeedText(networkSpeedText(), to: currentImage)
                }
            } else {
                var label = ""
                switch type {
                case .cpu: label = "C\nP\nU"
                case .memory: label = "M\nE\nM"
                case .disk: label = "S\nS\nD"
                case .battery: label = "B\nA\nT"
                default: break
                }
                if let currentImage = image, !label.isEmpty {
                    image = MenuBarImageGenerator.addLabel(label, to: currentImage)
                }
            }
        }

        return image
    }

    /// Everything rendered into one image — the form Combined Mode needs.
    /// Text styles (which the standalone items render as button titles) are
    /// composed into the image here.
    static func segmentImage(for type: MonitorType) -> NSImage? {
        let styleRaw = UserDefaults.standard.string(forKey: "\(type.rawValue.lowercased())DisplayStyle") ?? "Icon Only"

        if styleRaw == DisplayStyle.icon.rawValue {
            return symbolImage(for: type)
        }
        if styleRaw == DisplayStyle.text.rawValue {
            guard let base = symbolImage(for: type) else { return nil }
            switch type {
            case .network:
                return MenuBarImageGenerator.addSpeedText(networkSpeedText(), to: base)
            case .cpu:
                return MenuBarImageGenerator.addValueText(String(format: "%.0f%%", SystemMonitor.shared.cpuUsage), to: base, fontSize: 13)
            case .memory:
                return MenuBarImageGenerator.addValueText(String(format: "%.0f%%", SystemMonitor.shared.memoryUsageRatio * 100), to: base, fontSize: 13)
            case .disk:
                return MenuBarImageGenerator.addValueText(String(format: "%.0f%%", SystemMonitor.shared.diskUsageRatio * 100), to: base, fontSize: 13)
            case .battery:
                return MenuBarImageGenerator.addValueText(String(format: "%.0f%%", SystemMonitor.shared.batteryStats.percentage), to: base, fontSize: 13)
            default:
                return base
            }
        }
        return graphicalImage(for: type, styleRaw: styleRaw)
    }
}

class StatusItemController: NSObject {
    let type: MonitorType
    private var statusItem: NSStatusItem?
    private lazy var presenter = MonitorPopoverPresenter(type: type)

    private var classicMenuBuilder: DisplayMenuBuilder?

    private var cancellables = Set<AnyCancellable>()

    init(type: MonitorType) {
        self.type = type
        super.init()
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
            // Read speed updates every tick; needed to animate the history graph
            SystemMonitor.shared.$diskReadSpeed
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .network:
            SystemMonitor.shared.$networkDownloadSpeed
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .battery:
            SystemMonitor.shared.$batteryStats
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateButtonUI() }
                .store(in: &cancellables)
        case .time:
            setupTimeTimer()

            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.setupTimeTimer() // Re-evaluate if seconds were toggled
                }
                .store(in: &cancellables)
        case .display:
            DisplayManager.shared.$displays
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

    private var timeTimerCancellable: AnyCancellable?
    private var lastTimerModeHasSeconds: Bool? = nil

    private func setupTimeTimer() {
        let hasSeconds = TimeFormatHelper.shared.formatTokens.contains(.second)

        // Prevent recreating the exact same timer unnecessarily
        if let lastMode = lastTimerModeHasSeconds, lastMode == hasSeconds, timeTimerCancellable != nil {
            return
        }

        timeTimerCancellable?.cancel()
        lastTimerModeHasSeconds = hasSeconds

        if hasSeconds {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateButtonUI() }
            RunLoop.main.add(timer, forMode: .common)
            timeTimerCancellable = AnyCancellable { timer.invalidate() }
        } else {
            let now = Date()
            let calendar = Calendar.current
            let nextMinute = calendar.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)

            let timer = Timer(fire: nextMinute, interval: 60.0, repeats: true) { [weak self] _ in self?.updateButtonUI() }
            RunLoop.main.add(timer, forMode: .common)
            timeTimerCancellable = AnyCancellable { timer.invalidate() }

            self.updateButtonUI()
        }
    }

    @objc private func updateButtonUI() {
        guard let button = statusItem?.button else { return }

        if type == .display {
            let uiStyle = UserDefaults.standard.string(forKey: "displayUIStyle") ?? "Glass"
            if uiStyle == "Classic" {
                if classicMenuBuilder == nil {
                    classicMenuBuilder = DisplayMenuBuilder()
                }
                statusItem?.menu = classicMenuBuilder?.menu
                button.action = nil
            } else {
                classicMenuBuilder = nil
                statusItem?.menu = nil
                button.action = #selector(togglePopover(_:))
                button.target = self
            }
        }

        if type == .time {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.title = TimeFormatHelper.shared.generateTimeString()
            return
        }

        let styleRaw = UserDefaults.standard.string(forKey: "\(type.rawValue.lowercased())DisplayStyle") ?? "Icon Only"

        if styleRaw == "Icon Only" {
            button.image = MenuBarItemRenderer.symbolImage(for: type)
            button.title = ""
        } else if styleRaw == "Text" {
            button.image = MenuBarItemRenderer.symbolImage(for: type)
            switch type {
            case .cpu:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.cpuUsage)
            case .memory:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.memoryUsageRatio * 100)
            case .disk:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.diskUsageRatio * 100)
            case .network:
                if let currentImage = button.image {
                    button.image = MenuBarImageGenerator.addSpeedText(MenuBarItemRenderer.networkSpeedText(), to: currentImage)
                }
                button.attributedTitle = NSAttributedString(string: "")
                button.title = ""
            case .battery:
                button.title = String(format: " %.0f%%", SystemMonitor.shared.batteryStats.percentage)
            case .time:
                break // Handled above
            case .display:
                if let mainDisplay = DisplayManager.shared.displays.first(where: { $0.isMain }) ?? DisplayManager.shared.displays.first,
                   let mode = mainDisplay.currentMode {
                    button.title = " \(mode.width)x\(mode.height)"
                } else {
                    button.title = " Display"
                }
            }
        } else {
            // Graphical Modes
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.image = MenuBarItemRenderer.graphicalImage(for: type, styleRaw: styleRaw)
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
        presenter.invalidate()
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        presenter.toggle(anchor: button)
    }

    func showPopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        presenter.show(anchor: button)
    }

    func closePopover(_ sender: AnyObject?) {
        presenter.close()
    }
}

struct RootEnvironmentView<Content: View>: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, appLanguage == "system" ? .current : Locale(identifier: appLanguage))
    }
}
