import Foundation

var mib = [CTL_VM, VM_SWAPUSAGE]
var swapUsage = xsw_usage()
var size = MemoryLayout<xsw_usage>.size

if sysctl(&mib, 2, &swapUsage, &size, nil, 0) == 0 {
    print("Total: \(swapUsage.xsu_total)")
    print("Used: \(swapUsage.xsu_used)")
    print("Avail: \(swapUsage.xsu_avail)")
} else {
    print("sysctl failed")
}
