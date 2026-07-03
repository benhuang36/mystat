import Foundation

struct TopProcessInfo: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let usage: String
}

class ProcessProvider {
    
    func getTopCPUProcesses(count: Int = 5) -> [TopProcessInfo] {
        let processes = runPSCommand(args: ["-arcxo", "pid,%cpu,comm"])
        return Array(processes.prefix(count))
    }
    
    func getTopMemoryProcesses(count: Int = 5) -> [TopProcessInfo] {
        let processes = runPSCommand(args: ["-amcxo", "pid,%mem,comm"])
        return Array(processes.prefix(count))
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
                        if Int(pidStr) == nil { continue } // skip header or invalid
                        let powerStr = String(parts[parts.count - 1])
                        let nameStr = parts[1..<parts.count-1].joined(separator: " ")
                        
                        processes.append(TopProcessInfo(pid: Int(pidStr) ?? 0, name: nameStr, usage: powerStr))
                    }
                }
            }
            return processes
        } catch {
            return []
        }
    }
    
    private func runPSCommand(args: [String]) -> [TopProcessInfo] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = args
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // ignore error
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            var processes: [TopProcessInfo] = []
            let lines = output.split(separator: "\n")
            // Skip the first line (header)
            for line in lines.dropFirst() {
                // Split by whitespace
                let components = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                if components.count >= 3 {
                    let pid = Int(components[0]) ?? 0
                    let usage = String(components[1])
                    let name = String(components[2])
                    processes.append(TopProcessInfo(pid: pid, name: name, usage: usage))
                }
            }
            return processes
        } catch {
            print("Failed to run ps command: \(error)")
            return []
        }
    }
}
