import Foundation
import IOKit

let matchingDict = IOServiceMatching("AppleSmartBattery")
var iterator: io_iterator_t = 0
if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
    let regEntry = IOIteratorNext(iterator)
    if regEntry != 0 {
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(regEntry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess {
            if let properties = props?.takeRetainedValue() as? [String: Any] {
                for (key, _) in properties {
                    print(key)
                }
            }
        }
        IOObjectRelease(regEntry)
    }
    IOObjectRelease(iterator)
}
