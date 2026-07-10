import Cocoa
import CoreGraphics
import Combine

struct DisplayModeInfo: Hashable, Identifiable {
    let id = UUID()
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let isHiDPI: Bool
    let refreshRate: Double
    let rawMode: CGDisplayMode
    
    var resolutionString: String {
        return "\(width) x \(height)"
    }
    
    // CoreGraphics uses Int for display mode dimensions. We define equality based on these core traits.
    static func == (lhs: DisplayModeInfo, rhs: DisplayModeInfo) -> Bool {
        return lhs.width == rhs.width &&
               lhs.height == rhs.height &&
               lhs.isHiDPI == rhs.isHiDPI &&
               abs(lhs.refreshRate - rhs.refreshRate) < 0.1
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(isHiDPI)
        hasher.combine(Int(refreshRate))
    }
}

class DisplayInfo: Identifiable, ObservableObject {
    let id: CGDirectDisplayID
    let isMain: Bool
    let name: String
    
    @Published var currentMode: DisplayModeInfo?
    @Published var availableModes: [DisplayModeInfo] = []
    
    init(id: CGDirectDisplayID) {
        self.id = id
        self.isMain = CGDisplayIsMain(id) != 0
        
        // Try to get display name
        if let info = DDCGetDisplayName(displayID: id) {
            self.name = info
        } else {
            self.name = self.isMain ? "Main Display" : "Display \(id)"
        }
        
        refreshModes()
    }
    
    func refreshModes() {
        if let cgMode = CGDisplayCopyDisplayMode(id) {
            self.currentMode = createModeInfo(from: cgMode)
        }
        
        // Fetch all modes
        let options = [
            kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue,
        ] as CFDictionary
        
        if let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] {
            var allInfos = modes.map { createModeInfo(from: $0) }
            
            // Explicitly inject current mode and previously accumulated modes
            if let current = self.currentMode {
                DisplayManager.addAccumulatedMode(current, for: id)
            }
            
            if let cached = DisplayManager.getAccumulatedModes(for: id) {
                allInfos.append(contentsOf: cached)
            }
            
            // Deduplicate modes with same resolution, hidpi, and refresh rate (sometimes CG returns exact duplicates)
            var uniqueModes = [DisplayModeInfo]()
            var seen = Set<String>()
            for mode in allInfos {
                let key = "\(mode.width)x\(mode.height)-\(mode.isHiDPI)-\(Int(round(mode.refreshRate)))"
                if !seen.contains(key) {
                    seen.insert(key)
                    uniqueModes.append(mode)
                }
            }
            
            // Sort: Width desc, Height desc, HiDPI desc, RefreshRate desc
            uniqueModes.sort { a, b in
                if a.width != b.width { return a.width > b.width }
                if a.height != b.height { return a.height > b.height }
                if a.isHiDPI != b.isHiDPI { return a.isHiDPI && !b.isHiDPI }
                return a.refreshRate > b.refreshRate
            }
            
            self.availableModes = uniqueModes
        }
    }
    
    private func createModeInfo(from mode: CGDisplayMode) -> DisplayModeInfo {
        let isHiDPI = mode.pixelWidth != mode.width || mode.pixelHeight != mode.height
        return DisplayModeInfo(
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            isHiDPI: isHiDPI,
            refreshRate: mode.refreshRate,
            rawMode: mode
        )
    }
}

// Helper to get DDC Name if available
func DDCGetDisplayName(displayID: CGDirectDisplayID) -> String? {
    // In macOS to get display name you typically use NSScreen
    for screen in NSScreen.screens {
        if let screenId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID, screenId == displayID {
            if #available(macOS 10.15, *) {
                return screen.localizedName
            }
        }
    }
    return nil
}


class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    
    @Published var displays: [DisplayInfo] = []
    private static var accumulatedModes: [CGDirectDisplayID: Set<DisplayModeInfo>] = [:]
    
    private var displayReconfigurationToken: Any?
    
    private init() {
        refreshDisplays()
        
        // Register for display configuration changes
        CGDisplayRegisterReconfigurationCallback({ display, flags, userInfo in
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async {
                DisplayManager.shared.refreshDisplays()
            }
        }, nil)
    }
    
    deinit {
        CGDisplayRemoveReconfigurationCallback({ _, _, _ in }, nil)
    }
    
    static func addAccumulatedMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) {
        if accumulatedModes[displayID] == nil {
            accumulatedModes[displayID] = []
        }
        accumulatedModes[displayID]?.insert(mode)
    }
    
    static func getAccumulatedModes(for displayID: CGDirectDisplayID) -> Set<DisplayModeInfo>? {
        return accumulatedModes[displayID]
    }
    
    func refreshDisplays() {
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        let error = CGGetActiveDisplayList(16, &activeDisplays, &displayCount)
        if error == .success {
            let validDisplays = activeDisplays.prefix(Int(displayCount)).map { DisplayInfo(id: $0) }
            self.displays = validDisplays
        }
    }
    
    func setResolution(for display: DisplayInfo, width: Int, height: Int, isHiDPI: Bool) {
        // Find the best mode matching the width, height, and hidpi, trying to preserve current refresh rate
        let currentRefreshRate = display.currentMode?.refreshRate ?? 60.0
        
        let candidates = display.availableModes.filter {
            $0.width == width && $0.height == height && $0.isHiDPI == isHiDPI
        }
        
        guard !candidates.isEmpty else { return }
        
        // Try to find one with the exact refresh rate, otherwise take the highest refresh rate available for that resolution
        let bestMode = candidates.min(by: { abs($0.refreshRate - currentRefreshRate) < abs($1.refreshRate - currentRefreshRate) }) ?? candidates.first!
        
        applyMode(bestMode.rawMode, to: display.id)
    }
    
    func setRefreshRate(for display: DisplayInfo, refreshRate: Double) {
        guard let current = display.currentMode else { return }
        
        let candidates = display.availableModes.filter {
            $0.width == current.width && $0.height == current.height && $0.isHiDPI == current.isHiDPI
        }
        
        guard !candidates.isEmpty else { return }
        
        let bestMode = candidates.min(by: { abs($0.refreshRate - refreshRate) < abs($1.refreshRate - refreshRate) }) ?? candidates.first!
        
        applyMode(bestMode.rawMode, to: display.id)
    }
    
    private func applyMode(_ mode: CGDisplayMode, to displayID: CGDirectDisplayID) {
        let targetWidth = mode.width
        let targetHeight = mode.height
        let targetIsHiDPI = mode.pixelWidth != mode.width || mode.pixelHeight != mode.height
        
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success {
            CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
            CGCompleteDisplayConfiguration(config, .forSession)
            
            // Check if it really changed by looking at current mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let current = CGDisplayCopyDisplayMode(displayID) {
                    if current.width != targetWidth || current.height != targetHeight {
                        // Stale CGDisplayMode! Fallback to CGS API
                        self.fallbackApplyMode(width: targetWidth, height: targetHeight, isHiDPI: targetIsHiDPI, to: displayID)
                    }
                }
            }
        }
    }
    
    private func fallbackApplyMode(width: Int, height: Int, isHiDPI: Bool, to displayID: CGDirectDisplayID) {
        var count: Int32 = 0
        CGSGetNumberOfDisplayModes(displayID, &count)
        
        let length: Int32 = 212 // 0xD4
        guard let desc = malloc(Int(length)) else { return }
        defer { free(desc) }
        
        var bestModeNumber: Int32? = nil
        var highestRefresh: UInt16 = 0
        
        for i in 0..<count {
            CGSGetDisplayModeDescriptionOfLength(displayID, i, desc, length)
            let ptr32 = desc.bindMemory(to: UInt32.self, capacity: Int(length) / 4)
            let modeNum = ptr32[0]
            let mWidth = ptr32[2]
            let mHeight = ptr32[3]
            
            let ptr16 = desc.bindMemory(to: UInt16.self, capacity: Int(length) / 2)
            let freq = ptr16[0xBC / 2]
            
            let ptrFloat = desc.bindMemory(to: Float.self, capacity: Int(length) / 4)
            let density = ptrFloat[0xD0 / 4]
            let mIsHiDPI = density > 1.5
            
            if Int(mWidth) == width && Int(mHeight) == height && mIsHiDPI == isHiDPI {
                if bestModeNumber == nil || freq > highestRefresh {
                    bestModeNumber = Int32(modeNum)
                    highestRefresh = freq
                }
            }
        }
        
        if let modeNumber = bestModeNumber {
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success {
                CGSConfigureDisplayMode(config!, displayID, modeNumber)
                CGCompleteDisplayConfiguration(config, .forSession)
            }
        }
    }
}

@_silgen_name("CGSGetNumberOfDisplayModes")
func CGSGetNumberOfDisplayModes(_ display: CGDirectDisplayID, _ count: inout Int32)

@_silgen_name("CGSGetDisplayModeDescriptionOfLength")
func CGSGetDisplayModeDescriptionOfLength(_ display: CGDirectDisplayID, _ index: Int32, _ desc: UnsafeMutableRawPointer, _ length: Int32)

@_silgen_name("CGSConfigureDisplayMode")
func CGSConfigureDisplayMode(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ modeNumber: Int32) -> CGError
