import Foundation
import IOKit.ps

struct BatteryStats {
    var isPresent: Bool
    var isCharging: Bool
    var capacity: Double
    var maxCapacity: Double
    var cycleCount: Int
    var timeRemaining: Int // in minutes, -1 means calculating
    var health: String
    
    var percentage: Double {
        return maxCapacity > 0 ? (capacity / maxCapacity) * 100.0 : 0
    }
    
    static let empty = BatteryStats(isPresent: false, isCharging: false, capacity: 0, maxCapacity: 0, cycleCount: 0, timeRemaining: 0, health: "Unknown")
}

class BatteryProvider {
    
    func getBatteryStats() -> BatteryStats {
        var stats = BatteryStats.empty
        
        // Use AppleSmartBattery to get accurate raw capacity in mAh and cycle count
        let matchingDict = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
            var regEntry = IOIteratorNext(iterator)
            if regEntry != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(regEntry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess {
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
                        
                        // Infer health
                        if stats.maxCapacity > 0, let designCap = properties["DesignCapacity"] as? Int, designCap > 0 {
                            let healthRatio = stats.maxCapacity / Double(designCap)
                            if healthRatio > 0.8 { stats.health = "Good" }
                            else if healthRatio > 0.6 { stats.health = "Fair" }
                            else { stats.health = "Poor" }
                        } else {
                            stats.health = "Good"
                        }
                    }
                }
                IOObjectRelease(regEntry)
            }
            IOObjectRelease(iterator)
        }
        
        return stats
    }
}
