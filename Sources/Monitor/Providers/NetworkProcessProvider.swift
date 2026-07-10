import Foundation

class NetworkProcessProvider {
    private var previousBytesIn: [String: UInt64] = [:]
    private var previousBytesOut: [String: UInt64] = [:]
    private var lastUpdateTimes: [String: TimeInterval] = [:]
    
    // We don't need start() and stop() anymore as we fetch synchronously.
    func start() {}
    func stop() {
        previousBytesIn.removeAll()
        previousBytesOut.removeAll()
        lastUpdateTimes.removeAll()
    }
    
    func getTopNetworkProcesses(count: Int) -> (download: [TopProcessInfo], upload: [TopProcessInfo]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -l 1: 1 sample
        // -n: disable DNS resolution (crucial for speed)
        // -L 1: CSV format
        // -J bytes_in,bytes_out: only these columns
        task.arguments = ["-l", "1", "-n", "-L", "1", "-J", "bytes_in,bytes_out"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            if let output = String(data: data, encoding: .utf8) {
                return parseOutput(output, count: count)
            }
        } catch {
            print("Failed to run nettop: \(error)")
        }
        
        return ([], [])
    }
    
    private func parseOutput(_ output: String, count: Int) -> (download: [TopProcessInfo], upload: [TopProcessInfo]) {
        let lines = output.components(separatedBy: .newlines)
        
        var currentDownloadSpeeds: [String: Double] = [:]
        var currentUploadSpeeds: [String: Double] = [:]
        
        let now = Date().timeIntervalSince1970
        
        for line in lines {
            if line.isEmpty || line.hasPrefix(",bytes_in") || line.hasPrefix("time,") { continue }
            
            let columns = line.components(separatedBy: ",")
            var processIndex = 0
            if columns.count > 3 && columns[0].contains(":") {
                processIndex = 1
            }
            guard columns.count > processIndex + 2 else { continue }
            
            let processNameAndPid = columns[processIndex]
            guard processNameAndPid.contains(".") && !processNameAndPid.contains(" ") else { continue }
            
            let bytesInStr = columns[processIndex + 1]
            let bytesOutStr = columns[processIndex + 2]
            
            guard let bytesIn = UInt64(bytesInStr), let bytesOut = UInt64(bytesOutStr) else { continue }
            
            let parts = processNameAndPid.components(separatedBy: ".")
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            let pidString = parts.last! // The last part is usually the PID
            
            if let previousIn = previousBytesIn[pidString], let lastTime = lastUpdateTimes[pidString] {
                let timeDiff = now - lastTime
                if timeDiff > 0 {
                    let deltaIn = max(0, Int64(bytesIn) - Int64(previousIn))
                    let speedIn = Double(deltaIn) / timeDiff
                    currentDownloadSpeeds[name] = (currentDownloadSpeeds[name] ?? 0) + speedIn
                    
                    if let previousOut = previousBytesOut[pidString] {
                        let deltaOut = max(0, Int64(bytesOut) - Int64(previousOut))
                        let speedOut = Double(deltaOut) / timeDiff
                        currentUploadSpeeds[name] = (currentUploadSpeeds[name] ?? 0) + speedOut
                    }
                }
            }
            
            previousBytesIn[pidString] = bytesIn
            previousBytesOut[pidString] = bytesOut
            lastUpdateTimes[pidString] = now
        }
        
        // Clean up old processes
        for pid in previousBytesIn.keys {
            if let lastTime = lastUpdateTimes[pid], now - lastTime > 5.0 {
                previousBytesIn.removeValue(forKey: pid)
                previousBytesOut.removeValue(forKey: pid)
                lastUpdateTimes.removeValue(forKey: pid)
            }
        }
        
        let downloadProcesses = currentDownloadSpeeds
            .filter { $0.value > 1024 }
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { (name, speed) in
                TopProcessInfo(pid: 0, name: name, usage: formatBytes(speed) + "/s")
            }
        
        let uploadProcesses = currentUploadSpeeds
            .filter { $0.value > 1024 }
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { (name, speed) in
                TopProcessInfo(pid: 0, name: name, usage: formatBytes(speed) + "/s")
            }
        
        return (Array(downloadProcesses), Array(uploadProcesses))
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        let kb = bytes / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}
