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
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        // Mask the material to rounded corners (a behind-window material is not
        // clipped by layer.cornerRadius), which removes the square color block.
        visualEffect.roundedMask(cornerRadius: popoverCornerRadius)

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
    // Kept alive across open/close so reopening is instant. While closed we swap
    // its rootView to an empty view (see close()) so the popover's SwiftUI body
    // stops observing SystemMonitor's per-second stats and no longer re-renders
    // off-screen — the source of idle CPU when a popover had been opened once.
    private var hostingController: NSHostingController<AnyView>?
    private var eventMonitor: Any?
    private var globalEventMonitor: Any?
    private var isFadingOut = false
    private weak var anchorButton: NSStatusBarButton?
    private var cancellables = Set<AnyCancellable>()

    // The panel auto-resizes to fit its SwiftUI content (e.g. expanding the
    // Display resolution list). An AppKit window keeps its bottom-left origin
    // fixed on resize, so it would grow upward and drag the top-pinned content
    // with it. We instead pin the panel's TOP edge (just below the status item)
    // and reposition on every resize so it grows downward, keeping content still.
    private var frameObserver: NSObjectProtocol?
    private var pinnedTopY: CGFloat?
    private var pinnedX: CGFloat?

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

    /// Builds the popover's SwiftUI root for this monitor type. Called on first
    /// show and on every reopen (close() swaps in an empty view in between).
    private func makeRootView() -> AnyView {
        switch type {
        case .cpu: return AnyView(RootEnvironmentView { CPUPopoverView() })
        case .memory: return AnyView(RootEnvironmentView { MemoryPopoverView() })
        case .disk: return AnyView(RootEnvironmentView { DiskPopoverView() })
        case .network: return AnyView(RootEnvironmentView { NetworkPopoverView() })
        case .battery: return AnyView(RootEnvironmentView { BatteryPopoverView() })
        case .time: return AnyView(RootEnvironmentView { TimePopoverView() })
        case .display: return AnyView(RootEnvironmentView { DisplayPopoverView() })
        }
    }

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
            let hosting = NSHostingController(rootView: makeRootView())
            hosting.view.setFrameSize(hosting.view.fittingSize)
            hostingController = hosting
            panel = CustomPopoverPanel(contentView: hosting.view)
        } else if let hosting = hostingController {
            // Re-attach the live view (close() had blanked it) so it observes
            // stats and lays out again before we show the window. Blanking may
            // have shrunk the hidden window, so resize it back synchronously
            // here so the positioning math below reads the correct frame.
            hosting.rootView = makeRootView()
            hosting.view.layoutSubtreeIfNeeded()
            panel?.setContentSize(hosting.view.fittingSize)
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

            // Pin the top edge so later content-driven resizes grow downward.
            pinnedX = xPos
            pinnedTopY = yPos + window.frame.height
            if frameObserver == nil {
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in
                    guard let self = self,
                          let window = self.panel,
                          let topY = self.pinnedTopY,
                          let x = self.pinnedX else { return }
                    let newY = topY - window.frame.height
                    if abs(window.frame.origin.y - newY) > 0.5 || abs(window.frame.origin.x - x) > 0.5 {
                        window.setFrameOrigin(NSPoint(x: x, y: newY))
                    }
                }
            }

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
                // Keep the panel alive for future use to avoid rendering delay,
                // but blank its rootView so the popover's SwiftUI body stops
                // observing SystemMonitor's per-second stats and no longer
                // re-renders while off-screen (idle-CPU fix). show() re-attaches.
                self?.hostingController?.rootView = AnyView(EmptyView())
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
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
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

/// Everything that reaches the pixels for one monitor, captured at display
/// precision. Comparing it against the previous frame lets the controllers skip
/// both the image generation and the `button.image` assignment (the latter
/// forces a menu bar relayout even when the image is identical).
///
/// Values are deliberately rounded to integers: every menu bar graphic is at
/// most 18pt tall and the history chart normalizes over a range of 100+, so a
/// sub-1% change moves the drawing by well under a pixel. Trading that for
/// skipped redraws is invisible.
struct MenuBarRenderSignature: Equatable {
    var style = ""
    var text = ""
    var values: [Int] = []
    var series: [[Int]] = []
    var options: [String] = []
}

/// Stateless menu bar image composition for one monitor type, reading the
/// user's style/color preferences. Shared by the standalone status items and
/// Combined Mode segments.
enum MenuBarItemRenderer {

    private static func quantized(_ series: [Double]) -> [Int] {
        series.map { Int($0.rounded()) }
    }

    static func displayResolutionText() -> String {
        if let mainDisplay = DisplayManager.shared.displays.first(where: { $0.isMain }) ?? DisplayManager.shared.displays.first,
           let mode = mainDisplay.currentMode {
            return " \(mode.width)x\(mode.height)"
        }
        return " Display"
    }

    /// Captures only the inputs the *current style* actually draws from, so e.g.
    /// a Gauge is not invalidated by the history buffer shifting underneath it.
    static func signature(for type: MonitorType) -> MenuBarRenderSignature {
        let monitor = SystemMonitor.shared
        let defaults = UserDefaults.standard
        let key = type.rawValue.lowercased()
        var sig = MenuBarRenderSignature()

        // Time renders straight to the button title and must stay live. The
        // rendered string *is* the signature: a new second always lands, an
        // identical one was a no-op anyway.
        if type == .time {
            sig.style = "Time"
            sig.text = TimeFormatHelper.shared.generateTimeString()
            return sig
        }

        let style = defaults.string(forKey: "\(key)DisplayStyle") ?? DisplayStyle.icon.rawValue
        sig.style = style

        if type == .display {
            sig.options.append(defaults.string(forKey: "displayUIStyle") ?? "Glass")
        }

        // The battery symbol backs both Icon Only and Text, and changes with the
        // charge bucket and the charging bolt.
        if type == .battery {
            let stats = monitor.batteryStats
            sig.values.append(Int(stats.percentage.rounded()))
            sig.options.append(stats.isCharging ? "charging" : "onBattery")
        }

        if style == DisplayStyle.icon.rawValue {
            return sig // a static symbol; battery already accounted for above
        }

        if style == DisplayStyle.text.rawValue {
            switch type {
            case .cpu: sig.values.append(Int(monitor.cpuUsage.rounded()))
            case .memory: sig.values.append(Int((monitor.memoryUsageRatio * 100).rounded()))
            case .disk: sig.values.append(Int((monitor.diskUsageRatio * 100).rounded()))
            case .network: sig.text = networkSpeedText()
            case .display: sig.text = displayResolutionText()
            case .battery, .time: break
            }
            return sig
        }

        // Graphical styles: colors and toggles are baked into the image
        sig.options.append(defaults.string(forKey: "\(key)ChartColor") ?? MenuBarColor.auto.rawValue)
        sig.options.append(defaults.string(forKey: "\(key)SecondaryColor") ?? MenuBarColor.auto.rawValue)
        sig.options.append(defaults.bool(forKey: "\(key)ShowValue") ? "value" : "")
        sig.options.append(defaults.bool(forKey: "\(key)GaugeValueInside") ? "inside" : "")

        let showLabel = defaults.bool(forKey: "\(key)ShowLabel")
        sig.options.append(showLabel ? "label" : "")
        if showLabel && type == .network {
            sig.text = networkSpeedText()
        }

        if style == DisplayStyle.coreBars.rawValue {
            sig.series.append(quantized(monitor.cpuCoreUsages))
            return sig
        }

        if style == DisplayStyle.history.rawValue {
            switch type {
            case .cpu: sig.series.append(quantized(monitor.cpuUsageHistory))
            case .memory: sig.series.append(quantized(monitor.memoryUsageHistory))
            case .disk:
                sig.series.append(quantized(monitor.diskReadHistory))
                sig.series.append(quantized(monitor.diskWriteHistory))
            case .network:
                sig.series.append(quantized(monitor.networkDownloadHistory))
                sig.series.append(quantized(monitor.networkUploadHistory))
            case .battery, .time, .display: break
            }
            return sig
        }

        // Value-driven charts: pie / gauge / bar / capacity bar
        switch type {
        case .cpu: sig.values.append(Int(monitor.cpuUsage.rounded()))
        case .memory: sig.values.append(Int((monitor.memoryUsageRatio * 100).rounded()))
        case .disk: sig.values.append(Int((monitor.diskUsageRatio * 100).rounded()))
        case .network:
            sig.values.append(Int(min(100, (monitor.networkDownloadSpeed / 1024 / 10000.0) * 100.0).rounded()))
            sig.values.append(Int(min(100, (monitor.networkUploadSpeed / 1024 / 10000.0) * 100.0).rounded()))
        case .battery, .time, .display: break
        }
        return sig
    }

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
    private var lastSignature: MenuBarRenderSignature?

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

        if type == .network {
            MenuBarImageGenerator.resetSpeedTextWidth()
        }

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

        scheduleNextTimeTick(hasSeconds: hasSeconds)
        self.updateButtonUI()
    }

    /// Schedules a single tick at the next wall-clock boundary, re-anchored from
    /// the live clock on every fire. A plain repeating `Timer` is dangerous here:
    /// its fire dates are spaced by elapsed time, not re-checked against the wall
    /// clock, so NTP slew / sleep drift / timer slop can leave it firing a hair
    /// *before* the true `:00`. When that happens `generateTimeString()` reads the
    /// old minute, the signature gate (identical text) drops the redraw, and every
    /// later +60s fire stays just-early too — locking the menu bar a permanent
    /// minute behind. Re-anchoring each tick makes that self-heal, and the small
    /// epsilon guarantees the formatted string has already rolled to the new unit.
    private func scheduleNextTimeTick(hasSeconds: Bool) {
        let interval: TimeInterval = hasSeconds ? 1.0 : 60.0
        let epsilon: TimeInterval = 0.05
        let ref = Date().timeIntervalSinceReferenceDate
        let nextBoundary = (floor(ref / interval) + 1) * interval
        let fireDate = Date(timeIntervalSinceReferenceDate: nextBoundary + epsilon)

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.updateButtonUI()
            self.scheduleNextTimeTick(hasSeconds: hasSeconds)
        }
        RunLoop.main.add(timer, forMode: .common)
        timeTimerCancellable = AnyCancellable { timer.invalidate() }
    }

    /// Skips the redraw when nothing visible changed. The stats publishers fire
    /// every tick regardless of whether the rendered output would differ, and
    /// assigning `button.image` forces a menu bar relayout each time — for a
    /// static Icon Only item that is pure waste. Cached NSImages still track
    /// light/dark mode on their own: the generators draw inside an
    /// `NSImage(size:flipped:)` handler that re-runs on appearance changes.
    @objc private func updateButtonUI() {
        guard let button = statusItem?.button else { return }

        let signature = MenuBarItemRenderer.signature(for: type)
        guard signature != lastSignature else { return }
        lastSignature = signature

        render(signature, into: button)
    }

    private func render(_ signature: MenuBarRenderSignature, into button: NSStatusBarButton) {
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
            button.title = signature.text // already generated for the signature
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
                button.title = MenuBarItemRenderer.displayResolutionText()
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
