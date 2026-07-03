import Foundation
import IOKit

func getRealBatteryCapacity() {
    let matchingDict = IOServiceMatching("AppleSmartBattery")
    var iterator: io_iterator_t = 0
    if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
        let regEntry = IOIteratorNext(iterator)
        if regEntry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(regEntry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess {
                if let properties = props?.takeRetainedValue() as? [String: Any] {
                    let current = properties["AppleRawCurrentCapacity"] as? Int ?? properties["CurrentCapacity"] as? Int ?? 0
                    let max = properties["AppleRawMaxCapacity"] as? Int ?? properties["MaxCapacity"] as? Int ?? 0
                    let cycle = properties["CycleCount"] as? Int ?? 0
                    print("Current: \(current) mAh, Max: \(max) mAh, Cycle: \(cycle)")
                }
            }
            IOObjectRelease(regEntry)
        }
        IOObjectRelease(iterator)
    }
}
getRealBatteryCapacity()
