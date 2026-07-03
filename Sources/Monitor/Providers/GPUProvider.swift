import Foundation
import IOKit

class GPUProvider {
    
    func getGPUUsage() -> Double {
        var utilization: Double = 0.0
        let matchingDict = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
            var regEntry: io_registry_entry_t = IOIteratorNext(iterator)
            while regEntry != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(regEntry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess {
                    if let properties = props?.takeRetainedValue() as? [String: Any],
                       let perfStats = properties["PerformanceStatistics"] as? [String: Any],
                       let util = perfStats["Device Utilization %"] as? NSNumber {
                        utilization = max(utilization, util.doubleValue)
                    }
                }
                IOObjectRelease(regEntry)
                regEntry = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        return utilization
    }
}
