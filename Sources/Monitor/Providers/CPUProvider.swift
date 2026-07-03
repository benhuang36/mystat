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
    
    func getCPUUsage() -> Double {
        var numCPUInfo: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        
        var numCPUsU: natural_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCPUInfo)
        
        if err == KERN_SUCCESS {
            cpuInfoLock.lock()
            
            var totalUsage = 0.0
            
            if let prevInfo = previousCPUInfo, let curInfo = cpuInfo {
                var inUse: Int32 = 0
                var total: Int32 = 0
                
                for i in 0 ..< Int32(numCPUs) {
                    let inUseTick = curInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)]
                        - prevInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)]
                        + curInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)]
                        - prevInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)]
                        + curInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)]
                        - prevInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)]
                    
                    let totalTick = inUseTick + curInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)]
                        - prevInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)]
                    
                    inUse += inUseTick
                    total += totalTick
                }
                
                if total > 0 {
                    totalUsage = Double(inUse) / Double(total)
                }
            }
            
            if let prevInfo = previousCPUInfo {
                let prevInfoSize = MemoryLayout<integer_t>.stride * Int(numPrevCPUInfo)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevInfo), vm_size_t(prevInfoSize))
            }
            
            previousCPUInfo = cpuInfo
            numPrevCPUInfo = numCPUInfo
            
            cpuInfoLock.unlock()
            
            return totalUsage * 100.0
        } else {
            return 0.0
        }
    }
}
