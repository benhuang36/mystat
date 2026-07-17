import Foundation
import Darwin

/// One aggregated process row with both directions, iStat-style
struct NetworkProcessEntry: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let downloadSpeed: Double
    let uploadSpeed: Double
}

class NetworkProcessProvider {
    private var previousBytesIn: [String: UInt64] = [:]
    private var previousBytesOut: [String: UInt64] = [:]
    private var lastUpdateTimes: [String: TimeInterval] = [:]
    private var nameCache: [String: String] = [:]

    // Sticky rows: once a process shows real traffic it stays listed
    // (at 0 K) for a while, so the list doesn't jump around or go empty.
    private struct StickyEntry {
        var pid: Int
        var down: Double
        var up: Double
        var lastActive: TimeInterval
    }
    private var stickyEntries: [String: StickyEntry] = [:]
    private let stickyLifetime: TimeInterval = 60

    // Samples taken too close together produce meaningless ~0 deltas,
    // so remember the last computed result and serve it instead.
    private var cachedResult: [NetworkProcessEntry] = []
    private var lastSampleTime: TimeInterval = 0
    private var lastParseTime: TimeInterval = 0

    // We don't need start() and stop() anymore as we fetch synchronously.
    func start() {}
    func stop() {
        previousBytesIn.removeAll()
        previousBytesOut.removeAll()
        lastUpdateTimes.removeAll()
        nameCache.removeAll()
        stickyEntries.removeAll()
    }

    func getTopNetworkProcesses(count: Int) -> [NetworkProcessEntry] {
        let now = Date().timeIntervalSince1970
        if now - lastSampleTime < 0.5 {
            return cachedResult
        }
        lastSampleTime = now

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P: per-process rows only (no connection rows)
        // -l 1: 1 sample
        // -n: disable DNS resolution (crucial for speed)
        // -L 1: CSV format
        // -J bytes_in,bytes_out: only these columns
        task.arguments = ["-P", "-l", "1", "-n", "-L", "1", "-J", "bytes_in,bytes_out"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                cachedResult = parseOutput(output, count: count)
                return cachedResult
            }
        } catch {
            print("Failed to run nettop: \(error)")
        }

        return cachedResult
    }

    private func parseOutput(_ output: String, count: Int) -> [NetworkProcessEntry] {
        let lines = output.components(separatedBy: .newlines)

        var currentDownloadSpeeds: [String: Double] = [:]
        var currentUploadSpeeds: [String: Double] = [:]
        // Representative pid per aggregated name, used to resolve app icons
        var namePids: [String: Int] = [:]

        let now = Date().timeIntervalSince1970

        // Sampling paused (popover was closed): the stored baselines span the
        // whole gap and would produce bogus ~0 speeds that wipe the list.
        // Rebuild baselines only, renew the sticky rows, and keep the
        // previous list on screen — real speeds resume next sample.
        let resumingAfterGap = lastParseTime > 0 && (now - lastParseTime) > 5.0
        lastParseTime = now

        for line in lines {
            if line.isEmpty || line.hasPrefix(",bytes_in") || line.hasPrefix("time,") { continue }

            let columns = line.components(separatedBy: ",")
            var processIndex = 0
            if columns.count > 3 && columns[0].contains(":") {
                processIndex = 1
            }
            guard columns.count > processIndex + 2 else { continue }

            let processNameAndPid = columns[processIndex]
            guard processNameAndPid.contains(".") else { continue }
            // Filter out connection rows just in case (-P should exclude them already)
            guard !processNameAndPid.contains("<->") else { continue }

            let bytesInStr = columns[processIndex + 1]
            let bytesOutStr = columns[processIndex + 2]

            guard let bytesIn = UInt64(bytesInStr), let bytesOut = UInt64(bytesOutStr) else { continue }

            var parts = processNameAndPid.components(separatedBy: ".")
            guard parts.count >= 2 else { continue }
            let pidString = parts.removeLast()
            let truncatedName = parts.joined(separator: ".")
            let name = resolveName(pid: pidString, fallback: truncatedName)
            if namePids[name] == nil, let pidValue = Int(pidString) {
                namePids[name] = pidValue
            }

            if !resumingAfterGap, let previousIn = previousBytesIn[pidString], let lastTime = lastUpdateTimes[pidString] {
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
                nameCache.removeValue(forKey: pid)
            }
        }

        if resumingAfterGap {
            // Fresh lease on every remembered row so the cached list survives
            for key in stickyEntries.keys {
                stickyEntries[key]?.lastActive = now
            }
            return cachedResult
        }

        // Merge this sample into the sticky registry
        let allNames = Set(currentDownloadSpeeds.keys).union(currentUploadSpeeds.keys)
        for name in allNames {
            let down = currentDownloadSpeeds[name] ?? 0
            let up = currentUploadSpeeds[name] ?? 0
            var entry = stickyEntries[name] ?? StickyEntry(pid: 0, down: 0, up: 0, lastActive: 0)
            if let pid = namePids[name] { entry.pid = pid }
            // Light smoothing keeps values and sort order from twitching
            entry.down = down * 0.7 + entry.down * 0.3
            entry.up = up * 0.7 + entry.up * 0.3
            if down > 1024 || up > 1024 {
                entry.lastActive = now
            }
            stickyEntries[name] = entry
        }

        // Processes absent from this sample idle toward zero
        for (name, entry) in stickyEntries where !allNames.contains(name) {
            var idle = entry
            idle.down = 0
            idle.up = 0
            stickyEntries[name] = idle
        }

        // Drop rows that have been idle for a while
        stickyEntries = stickyEntries.filter { now - $0.value.lastActive < stickyLifetime }

        return stickyEntries
            .filter { $0.value.lastActive > 0 }
            .sorted { max($0.value.down, $0.value.up) > max($1.value.down, $1.value.up) }
            .prefix(count)
            .map { (name, entry) in
                NetworkProcessEntry(pid: entry.pid, name: name, downloadSpeed: entry.down, uploadSpeed: entry.up)
            }
    }

    /// nettop truncates process names to 15 characters ("Brave Browser H").
    /// Resolve the real binary name from the pid, and group helper processes
    /// under their app name ("Brave Browser Helper (Renderer)" -> "Brave Browser").
    private func resolveName(pid pidString: String, fallback: String) -> String {
        if let cached = nameCache[pidString] { return cached }

        var name = fallback
        if let pid = Int32(pidString) {
            var buffer = [CChar](repeating: 0, count: 4096)
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            if length > 0 {
                let binaryName = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
                if !binaryName.isEmpty {
                    name = binaryName
                }
            }
        }

        if let helperRange = name.range(of: " Helper") {
            let appName = String(name[..<helperRange.lowerBound])
            if !appName.isEmpty {
                name = appName
            }
        }

        nameCache[pidString] = name
        return name
    }
}
