import Foundation
import AppKit
import UniformTypeIdentifiers

struct TopProcessInfo: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let usage: String
}

/// Resolves an app icon for a pid. Helper processes living inside an .app
/// bundle get their parent app's icon; bare binaries get the generic
/// executable icon. Results are cached by binary path.
enum ProcessIcon {
    private static var pathCache: [String: NSImage] = [:]
    private static let lock = NSLock()
    private static let generic: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .unixExecutable)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    static func icon(for pid: Int) -> NSImage {
        guard pid > 0 else { return generic }

        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return generic }
        let path = String(cString: buffer)

        lock.lock()
        if let cached = pathCache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Use the enclosing .app bundle's icon when there is one
        let iconPath: String
        if let appRange = path.range(of: ".app/") {
            iconPath = String(path[..<appRange.lowerBound]) + ".app"
        } else {
            iconPath = path
        }

        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        icon.size = NSSize(width: 16, height: 16)

        lock.lock()
        pathCache[path] = icon
        lock.unlock()
        return icon
    }
}

struct AllTopProcesses {
    let cpu: [TopProcessInfo]
    let memory: [TopProcessInfo]
    let diskRead: [TopProcessInfo]
    let diskWrite: [TopProcessInfo]
}

class ProcessProvider {
    
    // CPU tracking state
    private var previousCPUTimes: [Int32: UInt64] = [:]
    private var lastQueryTime: UInt64 = 0
    
    init() {
        lastQueryTime = mach_absolute_time()
    }
    
    func getAllTopProcesses(count: Int = 5) -> AllTopProcesses {
        let maxPids = 4096
        var pids = [Int32](repeating: 0, count: maxPids)
        let pidsSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let numPids = pidsSize / Int32(MemoryLayout<Int32>.size)
        
        let currentQueryTicks = mach_absolute_time()
        let elapsedTicks = currentQueryTicks - lastQueryTime
        lastQueryTime = currentQueryTicks
        
        var currentCPUTimes: [Int32: UInt64] = [:]
        
        struct ProcData {
            let pid: Int32
            let name: String
            let cpuUsage: Double
            let memoryBytes: UInt64
            let diskRead: UInt64
            let diskWrite: UInt64
        }
        
        var allProcs: [ProcData] = []
        allProcs.reserveCapacity(Int(numPids))
        
        for i in 0..<Int(numPids) {
            let pid = pids[i]
            if pid == 0 { continue }
            
            // Get Task Info (Memory & CPU)
            var taskInfo = proc_taskinfo()
            let taskResult = withUnsafeMutablePointer(to: &taskInfo) { ptr in
                ptr.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { optPtr in
                    proc_pidinfo(pid, Int32(PROC_PIDTASKINFO), 0, optPtr, Int32(MemoryLayout<proc_taskinfo>.size))
                }
            }
            
            // Get Rusage (Disk I/O)
            var rusage = rusage_info_v2()
            let rusageResult = withUnsafeMutablePointer(to: &rusage) { ptr in
                ptr.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { optPtr in
                    proc_pid_rusage(pid, Int32(RUSAGE_INFO_V2), optPtr)
                }
            }
            
            if taskResult > 0 {
                var pathBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
                proc_name(pid, &pathBuffer, UInt32(pathBuffer.count))
                let name = String(cString: pathBuffer)
                if name.isEmpty { continue }
                
                let cpuTimeTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
                currentCPUTimes[pid] = cpuTimeTicks
                
                var cpuUsagePercent: Double = 0.0
                if let prevTimeTicks = previousCPUTimes[pid], cpuTimeTicks > prevTimeTicks, elapsedTicks > 0 {
                    let deltaTicks = cpuTimeTicks - prevTimeTicks
                    cpuUsagePercent = (Double(deltaTicks) / Double(elapsedTicks)) * 100.0
                }
                
                let readBytes = rusageResult == 0 ? rusage.ri_diskio_bytesread : 0
                let writeBytes = rusageResult == 0 ? rusage.ri_diskio_byteswritten : 0
                
                allProcs.append(ProcData(
                    pid: pid,
                    name: name,
                    cpuUsage: cpuUsagePercent,
                    memoryBytes: taskInfo.pti_resident_size,
                    diskRead: readBytes,
                    diskWrite: writeBytes
                ))
            }
        }
        
        // Update previous times
        previousCPUTimes = currentCPUTimes
        
        let formatSize = { (bytes: UInt64) -> String in
            let mb = Double(bytes) / 1024.0 / 1024.0
            if mb >= 1024 {
                return String(format: "%.1f GB", mb / 1024.0)
            } else if mb >= 1 {
                return String(format: "%.0f MB", mb)
            } else {
                let kb = Double(bytes) / 1024.0
                return String(format: "%.0f KB", kb)
            }
        }
        
        // Top CPU
        let topCpu = Array(allProcs.filter { $0.cpuUsage > 0.1 }.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(count)).map {
            TopProcessInfo(pid: Int($0.pid), name: $0.name, usage: String(format: "%.1f", $0.cpuUsage))
        }
        
        // Top Memory
        let topMem = Array(allProcs.filter { $0.memoryBytes > 0 }.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(count)).map {
            TopProcessInfo(pid: Int($0.pid), name: $0.name, usage: formatSize($0.memoryBytes))
        }
        
        // Top Disk Read
        let topRead = Array(allProcs.filter { $0.diskRead > 0 }.sorted { $0.diskRead > $1.diskRead }.prefix(count)).map {
            TopProcessInfo(pid: Int($0.pid), name: $0.name, usage: formatSize($0.diskRead))
        }
        
        // Top Disk Write
        let topWrite = Array(allProcs.filter { $0.diskWrite > 0 }.sorted { $0.diskWrite > $1.diskWrite }.prefix(count)).map {
            TopProcessInfo(pid: Int($0.pid), name: $0.name, usage: formatSize($0.diskWrite))
        }
        
        return AllTopProcesses(cpu: topCpu, memory: topMem, diskRead: topRead, diskWrite: topWrite)
    }
    
    func getTopPowerProcesses(count: Int = 5) -> [TopProcessInfo] {
        let task = Process()
        task.launchPath = "/usr/bin/top"
        // Run 2 samples to get valid power data, sort by power
        task.arguments = ["-l", "2", "-n", "\(count)", "-stats", "pid,command,power", "-o", "power"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            // The output has two samples. We want the second one.
            // Samples are separated by "Processes: "
            let components = output.components(separatedBy: "Processes:")
            guard components.count >= 3 else { return [] }
            let lastSample = components[2] // The second sample
            
            var processes: [TopProcessInfo] = []
            let lines = lastSample.split(separator: "\n")
            
            var isProcessSection = false
            for line in lines {
                if line.contains("PID") && line.contains("COMMAND") {
                    isProcessSection = true
                    continue
                }
                if isProcessSection {
                    // line format: "PID  COMMAND  POWER"
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 3 {
                        let pidStr = String(parts[0])
                        guard let pid = Int(pidStr) else { continue } // skip header or invalid
                        let powerStr = String(parts[parts.count - 1])
                        // top truncates COMMAND to a fixed width; resolve the full name from the pid
                        let truncatedName = parts[1..<parts.count-1].joined(separator: " ")
                        let nameStr = Self.fullProcessName(pid: Int32(pid)) ?? truncatedName

                        processes.append(TopProcessInfo(pid: pid, name: nameStr, usage: powerStr))
                    }
                }
            }
            return processes
        } catch {
            return []
        }
    }

    /// Resolves the full binary name for a pid (top/nettop truncate names)
    static func fullProcessName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
