import Foundation
import IOKit.ps

struct BatteryStats {
    var isPresent: Bool
    var isCharging: Bool
    var capacity: Double
    var maxCapacity: Double
    var designCapacity: Double
    var cycleCount: Int
    var timeRemaining: Int // in minutes, -1 means calculating
    var health: String

    var percentage: Double {
        return maxCapacity > 0 ? (capacity / maxCapacity) * 100.0 : 0
    }

    /// Health as Full Charge Capacity / Design Capacity, 0 if unknown
    var healthPercentage: Double {
        return designCapacity > 0 ? (maxCapacity / designCapacity) * 100.0 : 0
    }

    static let empty = BatteryStats(isPresent: false, isCharging: false, capacity: 0, maxCapacity: 0, designCapacity: 0, cycleCount: 0, timeRemaining: 0, health: "Unknown")
}

class BatteryProvider {
    
    private var cachedBatteryEntry: io_registry_entry_t = 0
    private var batteryCacheAge: Int = 0
    
    deinit {
        if cachedBatteryEntry != 0 {
            IOObjectRelease(cachedBatteryEntry)
        }
    }
    
    func getBatteryStats() -> BatteryStats {
        var stats = BatteryStats.empty
        
        if cachedBatteryEntry == 0 || batteryCacheAge >= 10 {
            if cachedBatteryEntry != 0 {
                IOObjectRelease(cachedBatteryEntry)
                cachedBatteryEntry = 0
            }
            
            let matchingDict = IOServiceMatching("AppleSmartBattery")
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
                let regEntry = IOIteratorNext(iterator)
                if regEntry != 0 {
                    cachedBatteryEntry = regEntry
                }
                IOObjectRelease(iterator)
            }
            batteryCacheAge = 0
        }
        batteryCacheAge += 1
        
        if cachedBatteryEntry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(cachedBatteryEntry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess {
                if let properties = props?.takeRetainedValue() as? [String: Any] {
                    stats.isPresent = true
                    if let extConnected = properties["ExternalConnected"] {
                        if let boolVal = extConnected as? Bool {
                            stats.isCharging = boolVal
                        } else if let intVal = extConnected as? Int {
                            stats.isCharging = intVal != 0
                        }
                    } else {
                        stats.isCharging = false
                    }
                    stats.capacity = Double(properties["AppleRawCurrentCapacity"] as? Int ?? properties["CurrentCapacity"] as? Int ?? 0)
                    stats.maxCapacity = Double(properties["AppleRawMaxCapacity"] as? Int ?? properties["MaxCapacity"] as? Int ?? 0)
                    stats.cycleCount = properties["CycleCount"] as? Int ?? 0
                    stats.timeRemaining = properties["TimeRemaining"] as? Int ?? -1
                    
                    stats.designCapacity = Double(properties["DesignCapacity"] as? Int ?? 0)

                    // Infer health
                    if stats.maxCapacity > 0, stats.designCapacity > 0 {
                        let healthRatio = stats.maxCapacity / stats.designCapacity
                        if healthRatio > 0.8 { stats.health = "Good" }
                        else if healthRatio > 0.6 { stats.health = "Fair" }
                        else { stats.health = "Poor" }
                    } else {
                        stats.health = "Good"
                    }
                }
            }
        }
        
        return stats
    }
}

public struct BatteryDataPoint: Codable, Identifiable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let percentage: Double
    public let isCharging: Bool
}

public class BatteryHistoryManager: ObservableObject {
    public static let shared = BatteryHistoryManager()
    
    @Published public var history: [BatteryDataPoint] = []
    
    private let maxHistoryAge: TimeInterval = 24 * 60 * 60 // 24 hours
    private let recordInterval: TimeInterval = 5 * 60 // 5 minutes
    private let userDefaultsKey = "BatteryHistoryData"
    
    private init() {
        loadHistory()
    }
    
    public func record(percentage: Double, isCharging: Bool) {
        let now = Date()
        
        // Always record if empty
        if history.isEmpty {
            addPoint(percentage: percentage, isCharging: isCharging, at: now)
            return
        }
        
        let lastPoint = history.last!
        
        // Record if 5 minutes have passed, OR if charging state changed
        if lastPoint.isCharging != isCharging {
            // To prevent a 1-pixel gap between segments, we overlap them by 1 second
            addPoint(percentage: percentage, isCharging: lastPoint.isCharging, at: now)
            addPoint(percentage: percentage, isCharging: isCharging, at: now.addingTimeInterval(-1))
        } else if now.timeIntervalSince(lastPoint.timestamp) >= recordInterval {
            addPoint(percentage: percentage, isCharging: isCharging, at: now)
        }
    }
    
    private func addPoint(percentage: Double, isCharging: Bool, at timestamp: Date) {
        let newPoint = BatteryDataPoint(timestamp: timestamp, percentage: percentage, isCharging: isCharging)
        
        DispatchQueue.main.async {
            self.history.append(newPoint)
            
            // Prune old data
            let cutoff = timestamp.addingTimeInterval(-self.maxHistoryAge)
            self.history.removeAll { $0.timestamp < cutoff }
            
            self.saveHistory()
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([BatteryDataPoint].self, from: data) {
            
            // Prune on load
            let cutoff = Date().addingTimeInterval(-maxHistoryAge)
            DispatchQueue.main.async {
                self.history = decoded.filter { $0.timestamp >= cutoff }
                
                // Re-save if we pruned
                if self.history.count != decoded.count {
                    self.saveHistory()
                }
            }
        }
    }
}
