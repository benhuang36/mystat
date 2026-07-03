import Foundation

struct MemoryStats {
    var wired: UInt64
    var active: UInt64
    var compressed: UInt64
    var free: UInt64
    var total: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
}

class MemoryProvider {
    func getMemoryStats() -> MemoryStats {
        var stats = MemoryStats(wired: 0, active: 0, compressed: 0, free: 0, total: ProcessInfo.processInfo.physicalMemory, swapUsed: 0, swapTotal: 0)
        
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()
        
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(getpagesize())
            stats.wired = UInt64(vmStats.wire_count) * pageSize
            stats.active = UInt64(vmStats.active_count) * pageSize
            stats.compressed = UInt64(vmStats.compressor_page_count) * pageSize
            stats.free = UInt64(vmStats.free_count) * pageSize
        }
        
        var mib = [CTL_VM, VM_SWAPUSAGE]
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctl(&mib, 2, &swapUsage, &size, nil, 0) == 0 {
            stats.swapUsed = UInt64(swapUsage.xsu_used)
            stats.swapTotal = UInt64(swapUsage.xsu_total)
        }
        
        return stats
    }
}
