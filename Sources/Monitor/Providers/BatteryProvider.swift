import Foundation
import IOKit.ps

// MARK: - Sleep Report

enum SleepAnomaly: Identifiable {
    case nonAppleSources([String])
    case frequentWakes(Double)   // wakes per hour
    case highDrain(Double)       // percent per hour

    var id: String {
        switch self {
        case .nonAppleSources: return "sources"
        case .frequentWakes: return "wakes"
        case .highDrain: return "drain"
        }
    }
}

struct SleepSession {
    let start: Date
    let end: Date
    let startCharge: Int?
    let endCharge: Int?
    let darkWakeCount: Int
    let nonAppleSources: [String]

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var wakesPerHour: Double {
        duration > 0 ? Double(darkWakeCount) / (duration / 3600.0) : 0
    }

    var drainPercent: Int? {
        guard let s = startCharge, let e = endCharge, s >= e else { return nil }
        return s - e
    }

    var drainPerHour: Double? {
        guard let drain = drainPercent, duration > 0 else { return nil }
        return Double(drain) / (duration / 3600.0)
    }

    /// Anomalies only evaluated for sessions longer than 30 minutes
    var anomalies: [SleepAnomaly] {
        guard duration > 1800 else { return [] }
        var result: [SleepAnomaly] = []
        if !nonAppleSources.isEmpty {
            result.append(.nonAppleSources(nonAppleSources))
        }
        if wakesPerHour > 6 {
            result.append(.frequentWakes(wakesPerHour))
        }
        if let perHour = drainPerHour, perHour > 1.5 {
            result.append(.highDrain(perHour))
        }
        return result
    }
}

/// Parses `pmset -g log` into the most recent completed sleep session and
/// `pmset -g assertions` into the processes currently preventing sleep.
final class SleepReportManager: ObservableObject {
    static let shared = SleepReportManager()

    @Published var lastSession: SleepSession?
    @Published var sleepBlockers: [String] = []

    private var lastRefresh: TimeInterval = 0
    private var isRefreshing = false

    /// System daemons whose scheduled wakes are considered normal
    private static let appleRequesters: Set<String> = [
        "powerd", "dasd", "mDNSResponder", "apsd", "sharingd", "bluetoothd",
        "calaccessd", "softwareupdated", "backupd", "biomesyncd", "searchd",
        "dataaccessd", "remindd", "timed", "locationd", "wifid"
    ]

    /// Heavy: parses the pmset log. Throttled to once per minute.
    func refresh() {
        let now = Date().timeIntervalSince1970
        guard !isRefreshing, now - lastRefresh > 60 else { return }
        isRefreshing = true
        lastRefresh = now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = Self.runCommand("/bin/sh", [
                "-c",
                "pmset -g log | grep -E 'Entering Sleep state|DarkWake from|Wake from|Wake Requests' | tail -n 4000"
            ])
            let session = Self.parseLastSession(from: output)
            DispatchQueue.main.async {
                self?.lastSession = session
                self?.isRefreshing = false
            }
        }
    }

    /// Cheap: current sleep-preventing assertions
    func refreshBlockers() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = Self.runCommand("/usr/bin/pmset", ["-g", "assertions"])
            let blockers = Self.parseBlockers(from: output)
            DispatchQueue.main.async {
                self?.sleepBlockers = blockers
            }
        }
    }

    // MARK: Parsing

    static func parseLastSession(from output: String) -> SleepSession? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let chargeRegex = try? NSRegularExpression(pattern: "Charge:(\\d+)", options: [.caseInsensitive])
        // The starred entry in a "Wake Requests" line is the request chosen to fire next
        let starRegex = try? NSRegularExpression(pattern: "\\[\\*process=([^ \\]]+) request=[^\\]]*?\\]", options: [])
        let infoRegex = try? NSRegularExpression(pattern: "\\[\\*process=[^\\]]*?info=\"([^\"]*)\"", options: [])

        func firstMatch(_ regex: NSRegularExpression?, in text: String) -> String? {
            guard let regex else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let group = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[group])
        }

        var completedSessions: [SleepSession] = []
        var sessionStart: Date?
        var sessionStartCharge: Int?
        var darkWakes = 0
        var nonApple = Set<String>()
        var pendingRequester: (process: String, info: String?)?

        for line in output.components(separatedBy: .newlines) {
            guard line.count > 26 else { continue }
            guard let date = dateFormatter.date(from: String(line.prefix(25))) else { continue }
            let charge = firstMatch(chargeRegex, in: line).flatMap { Int($0) }

            if line.contains("Wake Requests") {
                if let process = firstMatch(starRegex, in: line) {
                    pendingRequester = (process, firstMatch(infoRegex, in: line))
                }
            } else if line.contains("Entering Sleep state") {
                if sessionStart == nil {
                    sessionStart = date
                    sessionStartCharge = charge
                    darkWakes = 0
                    nonApple = []
                }
                // Re-sleeps after dark wakes stay inside the same session
            } else if line.contains("DarkWake from") {
                guard sessionStart != nil else { continue }
                darkWakes += 1
                if let requester = pendingRequester {
                    let isApple = appleRequesters.contains(requester.process)
                        || (requester.info?.contains("com.apple.") ?? false)
                    if !isApple {
                        nonApple.insert(requester.process)
                    }
                }
            } else if line.contains("Wake from") {
                // Full wake ends the session
                if let start = sessionStart {
                    completedSessions.append(SleepSession(
                        start: start,
                        end: date,
                        startCharge: sessionStartCharge,
                        endCharge: charge,
                        darkWakeCount: darkWakes,
                        nonAppleSources: nonApple.sorted()
                    ))
                }
                sessionStart = nil
                pendingRequester = nil
            }
        }

        return completedSessions.last
    }

    static func parseBlockers(from output: String) -> [String] {
        let regex = try? NSRegularExpression(
            pattern: "pid \\d+\\(([^)]+)\\): \\[[^\\]]+\\] \\S+ (PreventUserIdleSystemSleep|PreventSystemSleep|NoIdleSleepAssertion)",
            options: [])
        guard let regex else { return [] }

        var names: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line) else { continue }
            let name = String(line[nameRange])
            if name == "powerd" { continue } // internal bookkeeping, not a culprit
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private static func runCommand(_ path: String, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

struct BatteryStats {
    var isPresent: Bool
    var isCharging: Bool
    var capacity: Double
    var maxCapacity: Double
    var designCapacity: Double
    var cycleCount: Int
    var timeRemaining: Int // in minutes, -1 means calculating
    var health: String

    var percentage: Double {
        return maxCapacity > 0 ? (capacity / maxCapacity) * 100.0 : 0
    }

    /// Health as Full Charge Capacity / Design Capacity, 0 if unknown
    var healthPercentage: Double {
        return designCapacity > 0 ? (maxCapacity / designCapacity) * 100.0 : 0
    }

    static let empty = BatteryStats(isPresent: false, isCharging: false, capacity: 0, maxCapacity: 0, designCapacity: 0, cycleCount: 0, timeRemaining: 0, health: "Unknown")
}

class BatteryProvider {
    
    private var cachedBatteryEntry: io_registry_entry_t = 0
    private var batteryCacheAge: Int = 0
    
    deinit {
        if cachedBatteryEntry != 0 {
            IOObjectRelease(cachedBatteryEntry)
        }
    }
    
    func getBatteryStats() -> BatteryStats {
        var stats = BatteryStats.empty
        
        if cachedBatteryEntry == 0 || batteryCacheAge >= 10 {
            if cachedBatteryEntry != 0 {
                IOObjectRelease(cachedBatteryEntry)
                cachedBatteryEntry = 0
            }
            
            let matchingDict = IOServiceMatching("AppleSmartBattery")
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
                let regEntry = IOIteratorNext(iterator)
                if regEntry != 0 {
                    cachedBatteryEntry = regEntry
                }
                IOObjectRelease(iterator)
            }
            batteryCacheAge = 0
        }
        batteryCacheAge += 1
        
        if cachedBatteryEntry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(cachedBatteryEntry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess {
                if let properties = props?.takeRetainedValue() as? [String: Any] {
                    stats.isPresent = true
                    if let extConnected = properties["ExternalConnected"] {
                        if let boolVal = extConnected as? Bool {
                            stats.isCharging = boolVal
                        } else if let intVal = extConnected as? Int {
                            stats.isCharging = intVal != 0
                        }
                    } else {
                        stats.isCharging = false
                    }
                    stats.capacity = Double(properties["AppleRawCurrentCapacity"] as? Int ?? properties["CurrentCapacity"] as? Int ?? 0)
                    stats.maxCapacity = Double(properties["AppleRawMaxCapacity"] as? Int ?? properties["MaxCapacity"] as? Int ?? 0)
                    stats.cycleCount = properties["CycleCount"] as? Int ?? 0
                    stats.timeRemaining = properties["TimeRemaining"] as? Int ?? -1
                    
                    stats.designCapacity = Double(properties["DesignCapacity"] as? Int ?? 0)

                    // Infer health
                    if stats.maxCapacity > 0, stats.designCapacity > 0 {
                        let healthRatio = stats.maxCapacity / stats.designCapacity
                        if healthRatio > 0.8 { stats.health = "Good" }
                        else if healthRatio > 0.6 { stats.health = "Fair" }
                        else { stats.health = "Poor" }
                    } else {
                        stats.health = "Good"
                    }
                }
            }
        }
        
        return stats
    }
}

public struct BatteryDataPoint: Codable, Identifiable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let percentage: Double
    public let isCharging: Bool
}

public class BatteryHistoryManager: ObservableObject {
    public static let shared = BatteryHistoryManager()
    
    @Published public var history: [BatteryDataPoint] = []
    
    private let maxHistoryAge: TimeInterval = 24 * 60 * 60 // 24 hours
    private let recordInterval: TimeInterval = 5 * 60 // 5 minutes
    private let userDefaultsKey = "BatteryHistoryData"
    
    private init() {
        loadHistory()
    }
    
    public func record(percentage: Double, isCharging: Bool) {
        let now = Date()
        
        // Always record if empty
        if history.isEmpty {
            addPoint(percentage: percentage, isCharging: isCharging, at: now)
            return
        }
        
        let lastPoint = history.last!
        
        // Record if 5 minutes have passed, OR if charging state changed
        if lastPoint.isCharging != isCharging {
            // To prevent a 1-pixel gap between segments, we overlap them by 1 second
            addPoint(percentage: percentage, isCharging: lastPoint.isCharging, at: now)
            addPoint(percentage: percentage, isCharging: isCharging, at: now.addingTimeInterval(-1))
        } else if now.timeIntervalSince(lastPoint.timestamp) >= recordInterval {
            addPoint(percentage: percentage, isCharging: isCharging, at: now)
        }
    }
    
    private func addPoint(percentage: Double, isCharging: Bool, at timestamp: Date) {
        let newPoint = BatteryDataPoint(timestamp: timestamp, percentage: percentage, isCharging: isCharging)
        
        DispatchQueue.main.async {
            self.history.append(newPoint)
            
            // Prune old data
            let cutoff = timestamp.addingTimeInterval(-self.maxHistoryAge)
            self.history.removeAll { $0.timestamp < cutoff }
            
            self.saveHistory()
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([BatteryDataPoint].self, from: data) {
            
            // Prune on load
            let cutoff = Date().addingTimeInterval(-maxHistoryAge)
            DispatchQueue.main.async {
                self.history = decoded.filter { $0.timestamp >= cutoff }
                
                // Re-save if we pruned
                if self.history.count != decoded.count {
                    self.saveHistory()
                }
            }
        }
    }
}
