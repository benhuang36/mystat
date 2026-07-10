import Foundation

class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    
    @Published var cpuUsage: Double = 0.0
    @Published var cpuUsageHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published var cpuCoreUsages: [Double] = []
    
    @Published var memoryUsageString: String = "-- GB"
    @Published var swapUsageString: String = ""
    @Published var memoryUsageRatio: Double = 0.0
    @Published var memoryUsageHistory: [Double] = Array(repeating: 0.0, count: 60)
    
    @Published var diskFreeString: String = ""
    @Published var diskUsageRatio: Double = 0.0
    
    @Published var diskReadSpeed: Double = 0.0
    @Published var diskWriteSpeed: Double = 0.0
    @Published var diskReadHistory: [Double] = Array(repeating: 0.0, count: 30)
    @Published var diskWriteHistory: [Double] = Array(repeating: 0.0, count: 30)
    
    @Published var networkUploadSpeed: Double = 0.0
    @Published var networkDownloadSpeed: Double = 0.0
    @Published var networkUploadHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published var networkDownloadHistory: [Double] = Array(repeating: 0.0, count: 60)
    
    @Published var topCPUProcesses: [TopProcessInfo] = []
    @Published var topMemoryProcesses: [TopProcessInfo] = []
    @Published var topPowerProcesses: [TopProcessInfo] = []
    @Published var topDiskReadProcesses: [TopProcessInfo] = []
    @Published var topDiskWriteProcesses: [TopProcessInfo] = []
    @Published var topNetworkDownloadProcesses: [TopProcessInfo] = []
    @Published var topNetworkUploadProcesses: [TopProcessInfo] = []
    
    // New Advanced Modules
    @Published var gpuUsage: Double = 0.0
    @Published var batteryStats: BatteryStats = .empty
    @Published var sensorStats: SensorStats = SensorStats(cpuTemperature: 0, gpuTemperature: 0, batteryTemperature: 0, nandTemperature: 0, aneTemperature: 0, fanSpeed: 0)
    
    @Published var currentTime: Date = Date()
    
    private var tickCounter: Int = 0
    private var timer: Timer?
    private var isFetchingPower = false
    private var lastPowerFetchTime: TimeInterval = 0.0
    private let cpuProvider = CPUProvider()
    private let memoryProvider = MemoryProvider()
    private let diskProvider = DiskProvider()
    private let networkProvider = NetworkProvider()
    private let processProvider = ProcessProvider()
    private let gpuProvider = GPUProvider()
    private let batteryProvider = BatteryProvider()
    private let sensorProvider = SensorProvider()
    private let networkProcessProvider = NetworkProcessProvider()
    
    // Track if any popover is visible to optimize background tasks
    var activePopoversCount = 0 {
        didSet {
            if activePopoversCount > 0 {
                networkProcessProvider.start()
            } else {
                networkProcessProvider.stop()
            }
        }
    }
    
    private init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        updateStats() // Initial fetch
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateStats() {
        currentTime = Date()
        tickCounter += 1
        
        let hasActivePopovers = activePopoversCount > 0
        let showCPU = UserDefaults.standard.bool(forKey: "showCPU")
        let showMemory = UserDefaults.standard.bool(forKey: "showMemory")
        let showDisk = UserDefaults.standard.bool(forKey: "showDisk")
        let showNetwork = UserDefaults.standard.bool(forKey: "showNetwork")
        
        if hasActivePopovers || showCPU {
            let cpuData = cpuProvider.getCPUUsage()
            cpuUsage = cpuData.total
            cpuCoreUsages = cpuData.perCore
            
            cpuUsageHistory.append(cpuUsage)
            if cpuUsageHistory.count > 60 { cpuUsageHistory.removeFirst() }
        }
        
        if hasActivePopovers || showMemory {
            let memStats = memoryProvider.getMemoryStats()
            let usedMemGB = Double(memStats.wired + memStats.active + memStats.compressed) / (1024 * 1024 * 1024)
            let totalMemGB = Double(memStats.total) / (1024 * 1024 * 1024)
            memoryUsageString = String(format: "%.1f GB / %.1f GB", usedMemGB, totalMemGB)
            
            let swapUsedGB = Double(memStats.swapUsed) / (1024 * 1024 * 1024)
            swapUsageString = String(format: "%.1f GB", swapUsedGB)
            
            memoryUsageRatio = usedMemGB / totalMemGB
            memoryUsageHistory.append(memoryUsageRatio * 100.0)
            if memoryUsageHistory.count > 60 { memoryUsageHistory.removeFirst() }
        }
        
        if hasActivePopovers || showDisk {
            if tickCounter % 5 == 0 || diskFreeString.isEmpty {
                if let diskStats = diskProvider.getDiskStats() {
                    let freeGB = Double(diskStats.free) / (1024 * 1024 * 1024)
                    let totalGB = Double(diskStats.total) / (1024 * 1024 * 1024)
                    diskFreeString = String(format: "%.1f GB Free", freeGB)
                    diskUsageRatio = (totalGB - freeGB) / totalGB
                }
            }
            
            let diskIO = diskProvider.getDiskIO()
            diskReadSpeed = diskIO.readBytesPerSec
            diskWriteSpeed = diskIO.writeBytesPerSec
            
            diskReadHistory.removeFirst()
            diskReadHistory.append(diskReadSpeed)
            
            diskWriteHistory.removeFirst()
            diskWriteHistory.append(diskWriteSpeed)
        }
        
        if hasActivePopovers || showNetwork {
            let netStats = networkProvider.getNetworkSpeeds()
            networkUploadSpeed = netStats.bytesOutPerSecond
            networkDownloadSpeed = netStats.bytesInPerSecond
            
            networkUploadHistory.removeFirst()
            networkUploadHistory.append(networkUploadSpeed)
            
            networkDownloadHistory.removeFirst()
            networkDownloadHistory.append(networkDownloadSpeed)
        }
        
        // Advanced Modules
        // Only fetch GPU and Sensors if popovers are visible, because the Menu Bar icons NEVER display GPU or Fan/Temp sensors!
        if activePopoversCount > 0 {
            gpuUsage = gpuProvider.getGPUUsage()
            sensorStats = sensorProvider.getSensorStats(cpuUsage: cpuUsage)
        }
        
        // Battery is only needed if the battery menu bar item is visible or popovers are open
        // Wait, for Battery History, we ALWAYS need to track it in the background so the history chart works!
        if tickCounter % 3 == 0 || !batteryStats.isPresent {
            batteryStats = batteryProvider.getBatteryStats()
            BatteryHistoryManager.shared.record(percentage: batteryStats.percentage, isCharging: batteryStats.isCharging)
        }
        
        // If no UI popovers are active, we can skip fetching processes entirely to save massive CPU!
        if activePopoversCount > 0 {
            // Update processes (dispatch to background queue so it doesn't block main thread)
            DispatchQueue.global(qos: .background).async {
                let allTops = self.processProvider.getAllTopProcesses()
                let netTops = self.networkProcessProvider.getTopNetworkProcesses(count: 5)
                DispatchQueue.main.async {
                    self.topCPUProcesses = allTops.cpu
                    self.topMemoryProcesses = allTops.memory
                    self.topDiskReadProcesses = allTops.diskRead
                    self.topDiskWriteProcesses = allTops.diskWrite
                    self.topNetworkDownloadProcesses = netTops.download
                    self.topNetworkUploadProcesses = netTops.upload
                }
            }
            
            // Throttle power fetching to every 5 seconds since it uses the expensive `top` command
            let now = Date().timeIntervalSince1970
            if !isFetchingPower && (now - lastPowerFetchTime > 5.0) {
                isFetchingPower = true
                lastPowerFetchTime = now
                DispatchQueue.global(qos: .background).async {
                    let topPower = self.processProvider.getTopPowerProcesses()
                    DispatchQueue.main.async {
                        if !topPower.isEmpty {
                            self.topPowerProcesses = topPower
                        }
                        self.isFetchingPower = false
                    }
                }
            }
        }
    }
}
