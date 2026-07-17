import Foundation

class CPUProvider {
    private var previousCPUInfo: processor_info_array_t?
    private var numPrevCPUInfo: mach_msg_type_number_t = 0
    private var numCPUs: natural_t = 0
    private var cpuInfoLock = NSLock()
    
    init() {
        let mibKeys: [Int32] = [CTL_HW, HW_NCPU]
        var sizeOfNumCPUs = MemoryLayout<natural_t>.size
        sysctl(UnsafeMutablePointer<Int32>(mutating: mibKeys), 2, &numCPUs, &sizeOfNumCPUs, nil, 0)
    }
    
    func getCPUUsage() -> (total: Double, user: Double, system: Double, perCore: [Double]) {
        var numCPUInfo: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?

        var numCPUsU: natural_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCPUInfo)

        if err == KERN_SUCCESS {
            cpuInfoLock.lock()

            var totalUsage = 0.0
            var userUsage = 0.0
            var systemUsage = 0.0
            var perCoreUsages = [Double](repeating: 0.0, count: Int(numCPUs))

            if let prevInfo = previousCPUInfo, let curInfo = cpuInfo {
                var userTotal: Int32 = 0
                var systemTotal: Int32 = 0
                var totalAll: Int32 = 0

                for i in 0 ..< Int(numCPUs) {
                    // User includes nice'd processes, matching Activity Monitor
                    let userTick = curInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)]
                        - prevInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)]
                        + curInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)]
                        - prevInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)]

                    let systemTick = curInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)]
                        - prevInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)]

                    let inUseTick = userTick + systemTick

                    let totalTick = inUseTick + curInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)]
                        - prevInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)]

                    userTotal += userTick
                    systemTotal += systemTick
                    totalAll += totalTick

                    if totalTick > 0 {
                        perCoreUsages[i] = (Double(inUseTick) / Double(totalTick)) * 100.0
                    }
                }

                if totalAll > 0 {
                    userUsage = (Double(userTotal) / Double(totalAll)) * 100.0
                    systemUsage = (Double(systemTotal) / Double(totalAll)) * 100.0
                    totalUsage = userUsage + systemUsage
                }
            }

            if let prevInfo = previousCPUInfo {
                let prevInfoSize = MemoryLayout<integer_t>.stride * Int(numPrevCPUInfo)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevInfo), vm_size_t(prevInfoSize))
            }

            previousCPUInfo = cpuInfo
            numPrevCPUInfo = numCPUInfo

            cpuInfoLock.unlock()

            return (totalUsage, userUsage, systemUsage, perCoreUsages)
        } else {
            return (0.0, 0.0, 0.0, [Double](repeating: 0.0, count: Int(numCPUs)))
        }
    }
}
