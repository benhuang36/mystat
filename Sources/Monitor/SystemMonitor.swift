import Foundation

class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    
    @Published var cpuUsage: Double = 0.0
    @Published var cpuUsageHistory: [Double] = Array(repeating: 0.0, count: 60)
    
    @Published var memoryUsageString: String = "-- GB"
    @Published var swapUsageString: String = ""
    @Published var memoryUsageRatio: Double = 0.0
    @Published var memoryUsageHistory: [Double] = Array(repeating: 0.0, count: 60)
    
    @Published var diskFreeString: String = ""
    @Published var diskUsageRatio: Double = 0.0
    
    @Published var networkUploadSpeed: Double = 0.0
    @Published var networkDownloadSpeed: Double = 0.0
    @Published var networkUploadHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published var networkDownloadHistory: [Double] = Array(repeating: 0.0, count: 60)
    
    @Published var topCPUProcesses: [TopProcessInfo] = []
    @Published var topMemoryProcesses: [TopProcessInfo] = []
    @Published var topPowerProcesses: [TopProcessInfo] = []
    
    // New Advanced Modules
    @Published var gpuUsage: Double = 0.0
    @Published var batteryStats: BatteryStats = .empty
    @Published var sensorStats: SensorStats = SensorStats(cpuTemperature: 0, fanSpeed: 0)
    
    private var timer: Timer?
    private var isFetchingPower = false
    private let cpuProvider = CPUProvider()
    private let memoryProvider = MemoryProvider()
    private let diskProvider = DiskProvider()
    private let networkProvider = NetworkProvider()
    private let processProvider = ProcessProvider()
    private let gpuProvider = GPUProvider()
    private let batteryProvider = BatteryProvider()
    private let sensorProvider = SensorProvider()
    
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
        cpuUsage = cpuProvider.getCPUUsage()
        cpuUsageHistory.append(cpuUsage)
        if cpuUsageHistory.count > 60 { cpuUsageHistory.removeFirst() }
        
        let memStats = memoryProvider.getMemoryStats()
        let usedMemGB = Double(memStats.wired + memStats.active + memStats.compressed) / (1024 * 1024 * 1024)
        let totalMemGB = Double(memStats.total) / (1024 * 1024 * 1024)
        memoryUsageString = String(format: "%.1f GB / %.1f GB", usedMemGB, totalMemGB)
        
        let swapUsedGB = Double(memStats.swapUsed) / (1024 * 1024 * 1024)
        swapUsageString = String(format: "%.1f GB", swapUsedGB)
        
        memoryUsageRatio = usedMemGB / totalMemGB
        memoryUsageHistory.append(memoryUsageRatio * 100.0)
        if memoryUsageHistory.count > 60 { memoryUsageHistory.removeFirst() }
        
        if let diskStats = diskProvider.getDiskStats() {
            let freeGB = Double(diskStats.free) / (1024 * 1024 * 1024)
            let totalGB = Double(diskStats.total) / (1024 * 1024 * 1024)
            diskFreeString = String(format: "%.1f GB Free", freeGB)
            diskUsageRatio = (totalGB - freeGB) / totalGB
        }
        
        let netStats = networkProvider.getNetworkSpeeds()
        networkUploadSpeed = netStats.bytesOutPerSecond
        networkDownloadSpeed = netStats.bytesInPerSecond
        
        networkUploadHistory.removeFirst()
        networkUploadHistory.append(networkUploadSpeed)
        
        networkDownloadHistory.removeFirst()
        networkDownloadHistory.append(networkDownloadSpeed)
        
        // Advanced Modules
        gpuUsage = gpuProvider.getGPUUsage()
        batteryStats = batteryProvider.getBatteryStats()
        sensorStats = sensorProvider.getSensorStats(cpuUsage: cpuUsage)
        
        // Update processes (dispatch to background queue so it doesn't block main thread)
        DispatchQueue.global(qos: .background).async {
            let topCPU = self.processProvider.getTopCPUProcesses()
            let topMem = self.processProvider.getTopMemoryProcesses()
            DispatchQueue.main.async {
                self.topCPUProcesses = topCPU
                self.topMemoryProcesses = topMem
            }
        }
        
        if !isFetchingPower {
            isFetchingPower = true
            DispatchQueue.global(qos: .background).async {
                let topPower = self.processProvider.getTopPowerProcesses()
                DispatchQueue.main.async {
                    self.topPowerProcesses = topPower
                    self.isFetchingPower = false
                }
            }
        }
    }
}
