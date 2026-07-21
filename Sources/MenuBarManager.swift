import Cocoa
import SwiftUI
import Combine

/// One NSStatusItem showing several monitors side by side (iStat-style
/// Combined Mode). Each monitor keeps its configured menu bar style; clicking
/// a segment opens that monitor's popover under it.
class CombinedStatusItemController: NSObject {
    /// Monitors that can join the combined item (Time/Display stay standalone)
    static let combinableTypes: [MonitorType] = [.cpu, .memory, .disk, .network, .battery]

    static var orderedTypes: [MonitorType] {
        let saved = UserDefaults.standard.stringArray(forKey: "combinedOrder") ?? []
        var order = saved.compactMap(MonitorType.init(rawValue:)).filter { combinableTypes.contains($0) }
        for type in combinableTypes where !order.contains(type) {
            order.append(type)
        }
        return order
    }

    static var spacing: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "combinedSpacing") as? Double ?? 8)
    }

    private var statusItem: NSStatusItem?
    private var presenters: [MonitorType: MonitorPopoverPresenter] = [:]
    private var segments: [(type: MonitorType, hitRange: ClosedRange<CGFloat>, midX: CGFloat)] = []
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MyStat_Combined"
        item.isVisible = false
        if let button = item.button {
            button.action = #selector(handleClick(_:))
            button.target = self
        }
        statusItem = item
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        let monitor = SystemMonitor.shared
        // All stats publish on the same 1 s tick; coalesce the burst into one redraw
        Publishers.MergeMany(
            monitor.$cpuUsage.map { _ in () }.eraseToAnyPublisher(),
            monitor.$memoryUsageRatio.map { _ in () }.eraseToAnyPublisher(),
            monitor.$diskReadSpeed.map { _ in () }.eraseToAnyPublisher(),
            monitor.$networkDownloadSpeed.map { _ in () }.eraseToAnyPublisher(),
            monitor.$batteryStats.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] in self?.updateButtonUI() }
        .store(in: &cancellables)
    }

    func setVisible(_ visible: Bool) {
        statusItem?.isVisible = visible
        if visible {
            updateButtonUI()
        }
    }

    private func updateButtonUI() {
        guard statusItem?.isVisible == true, let button = statusItem?.button else { return }

        let types = Self.orderedTypes.filter { UserDefaults.standard.bool(forKey: "show\($0.rawValue)") }
        let images: [(type: MonitorType, image: NSImage)] = types.compactMap { type in
            MenuBarItemRenderer.segmentImage(for: type).map { (type, $0) }
        }
        guard !images.isEmpty else {
            button.image = nil
            segments = []
            return
        }

        let spacing = Self.spacing
        let height = images.map { $0.image.size.height }.max() ?? 18
        let totalWidth = images.map { $0.image.size.width }.reduce(0, +) + spacing * CGFloat(images.count - 1)

        var frames: [(image: NSImage, rect: NSRect)] = []
        var newSegments: [(type: MonitorType, hitRange: ClosedRange<CGFloat>, midX: CGFloat)] = []
        var x: CGFloat = 0
        for (type, image) in images {
            let rect = NSRect(x: x, y: (height - image.size.height) / 2, width: image.size.width, height: image.size.height)
            frames.append((image, rect))
            newSegments.append((type, (x - spacing / 2)...(x + image.size.width + spacing / 2), rect.midX))
            x += image.size.width + spacing
        }

        let composite = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            for (image, rect) in frames {
                image.draw(in: rect)
                if image.isTemplate {
                    // Template images (e.g. the battery symbol) are normally
                    // tinted by the button; tint manually inside the composite
                    NSColor.controlTextColor.set()
                    rect.fill(using: .sourceAtop)
                }
            }
            return true
        }

        segments = newSegments
        button.title = ""
        button.image = composite
    }

    @objc private func handleClick(_ sender: AnyObject?) {
        guard let button = statusItem?.button,
              let event = NSApp.currentEvent,
              let imageWidth = button.image?.size.width,
              !segments.isEmpty else { return }

        // The image is centered inside the button; map the click into image space
        let originX = (button.bounds.width - imageWidth) / 2
        let x = button.convert(event.locationInWindow, from: nil).x - originX

        let hit = segments.first { $0.hitRange.contains(x) }
            ?? segments.min { abs($0.midX - x) < abs($1.midX - x) }
        guard let segment = hit else { return }

        let presenter: MonitorPopoverPresenter
        if let existing = presenters[segment.type] {
            presenter = existing
        } else {
            presenter = MonitorPopoverPresenter(type: segment.type)
            presenters[segment.type] = presenter
        }
        presenter.toggle(anchor: button, segmentMidX: originX + segment.midX)
    }
}

class MenuBarManager {
    static let shared = MenuBarManager()

    private var controllers: [MonitorType: StatusItemController] = [:]
    private let combinedController = CombinedStatusItemController()
    private var cancellable: AnyCancellable?

    private init() {
        for type in MonitorType.allCases {
            controllers[type] = StatusItemController(type: type)
        }

        setupObservers()
        refreshAll()
    }

    private func setupObservers() {
        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAll()
            }
    }

    private func refreshAll() {
        let defaults = UserDefaults.standard
        let combinedEnabled = defaults.bool(forKey: "combinedModeEnabled")

        for (type, controller) in controllers {
            let shown = defaults.bool(forKey: "show\(type.rawValue)")
            let absorbed = combinedEnabled && CombinedStatusItemController.combinableTypes.contains(type)
            controller.setVisible(shown && !absorbed)
        }
        combinedController.setVisible(combinedEnabled)
    }
}
