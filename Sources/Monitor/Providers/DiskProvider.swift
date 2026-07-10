import Foundation
import IOKit

struct DiskStats {
    var free: Int64
    var total: Int64
}

class DiskProvider {
    private var lastReadBytes: Int64 = 0
    private var lastWriteBytes: Int64 = 0
    private var lastUpdateTime = Date()
    
    private var cachedDrives: [io_registry_entry_t] = []
    private var driveCacheAge: Int = 0
    
    deinit {
        for drive in cachedDrives {
            IOObjectRelease(drive)
        }
    }
    
    func getDiskStats() -> DiskStats? {
        let rootURL = URL(fileURLWithPath: "/")
        do {
            let values = try rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            if let free = values.volumeAvailableCapacityForImportantUsage,
               let total = values.volumeTotalCapacity {
                return DiskStats(free: free, total: Int64(total))
            }
        } catch {
            print("Error retrieving disk stats: \(error)")
        }
        return nil
    }
    
    func getDiskIO() -> (readBytesPerSec: Double, writeBytesPerSec: Double) {
        if cachedDrives.isEmpty || driveCacheAge >= 10 {
            for drive in cachedDrives {
                IOObjectRelease(drive)
            }
            cachedDrives.removeAll()
            
            var driveList: io_iterator_t = 0
            let matchDict = IOServiceMatching("IOMedia")
            let status = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &driveList)
            
            if status == KERN_SUCCESS {
                var drive = IOIteratorNext(driveList)
                while drive != 0 {
                    cachedDrives.append(drive)
                    drive = IOIteratorNext(driveList)
                }
                IOObjectRelease(driveList)
            }
            driveCacheAge = 0
        }
        driveCacheAge += 1
        
        var totalRead: Int64 = 0
        var totalWrite: Int64 = 0
        
        for drive in cachedDrives {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(drive, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let propsDict = props?.takeRetainedValue() as? [String: Any],
               let statInfo = propsDict["Statistics"] as? [String: Any] {
                if let bytesRead = statInfo["Bytes read from block device"] as? Int64 {
                    totalRead += bytesRead
                }
                if let bytesWritten = statInfo["Bytes written to block device"] as? Int64 {
                    totalWrite += bytesWritten
                }
            }
        }
        
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastUpdateTime)
        
        var readSpeed: Double = 0
        var writeSpeed: Double = 0
        
        if lastReadBytes > 0 && lastWriteBytes > 0 && timeDiff > 0 {
            readSpeed = Double(totalRead - lastReadBytes) / timeDiff
            writeSpeed = Double(totalWrite - lastWriteBytes) / timeDiff
        }
        
        lastReadBytes = totalRead
        lastWriteBytes = totalWrite
        lastUpdateTime = now
        
        return (max(0, readSpeed), max(0, writeSpeed))
    }
}
