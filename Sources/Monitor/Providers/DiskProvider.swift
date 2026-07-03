import Foundation

struct DiskStats {
    var free: Int64
    var total: Int64
}

class DiskProvider {
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
}
