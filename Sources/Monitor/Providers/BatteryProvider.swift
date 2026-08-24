import Foundation
import IOKit
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
    var adapterWatts: Int = 0 // rated wattage of the connected power adapter, 0 = unknown/none
    /// IORegistry power-routing snapshot, refreshed on the same cadence as the rest of
    /// these stats. `BatteryProvider.refreshedPowerFlow` overlays the live SMC reading.
    var powerFlow = PowerFlowStats()

    var percentage: Double {
        return maxCapacity > 0 ? (capacity / maxCapacity) * 100.0 : 0
    }

    /// Health as Full Charge Capacity / Design Capacity, 0 if unknown
    var healthPercentage: Double {
        return designCapacity > 0 ? (maxCapacity / designCapacity) * 100.0 : 0
    }

    static let empty = BatteryStats(isPresent: false, isCharging: false, capacity: 0, maxCapacity: 0, designCapacity: 0, cycleCount: 0, timeRemaining: 0, health: "Unknown")
}

// MARK: - Power Flow

/// Which of the four power-routing situations the machine is in.
/// Mirrors AlDente's Power Flow examples 1-4.
enum PowerFlowMode {
    case unavailable    // no usable telemetry
    case battery        // unplugged: battery -> Mac
    case adapterOnly    // plugged in, battery idle: adapter -> Mac
    case charging       // plugged in: adapter -> Mac + battery
    case supplemented   // adapter can't keep up: adapter + battery -> Mac
}

/// Instantaneous power routing, in watts.
struct PowerFlowStats: Equatable {
    var isValid = false
    var adapterWatts: Double = 0   // what the adapter is actually delivering
    var batteryWatts: Double = 0   // signed: positive = charging, negative = discharging
    var systemWatts: Double = 0    // what the Mac itself is drawing
    var adapterRatedWatts: Int = 0 // nameplate rating of the connected adapter, 0 = unknown
    var externalConnected = false

    /// Wattages below this are treated as zero, so a Mac sitting at 0.02 W of trickle
    /// doesn't make the diagram flip modes every second.
    static let deadband: Double = 0.15

    var batteryChargeWatts: Double { max(0, batteryWatts) }
    var batteryDrawWatts: Double { max(0, -batteryWatts) }

    var mode: PowerFlowMode {
        guard isValid else { return .unavailable }
        guard externalConnected else { return .battery }
        if adapterWatts > Self.deadband && batteryDrawWatts > Self.deadband { return .supplemented }
        if batteryChargeWatts > Self.deadband { return .charging }
        return .adapterOnly
    }
}

// MARK: - SMC

/// Minimal read-only AppleSMC client. Reads need no privileges (only writes do), so this
/// stays entirely inside the app. Used for power telemetry, which SMC refreshes about once
/// a second versus AppleSmartBattery's ~15 seconds.
private final class SMCPowerReader {

    private struct KeyData {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo: (dataSize: UInt32, dataType: UInt32, dataAttributes: UInt8) = (0, 0, 0)
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let kGetKeyInfo: UInt8 = 9
    private static let kReadKey: UInt8 = 5
    private static let typeFloat: UInt32 = 0x666C7420 // 'flt '

    private var connection: io_connect_t = 0
    private var openFailed = false
    /// Cached dataType/dataSize per key; SMC key metadata never changes at runtime.
    private var keyInfoCache: [UInt32: (type: UInt32, size: UInt32)] = [:]

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private func connect() -> Bool {
        if connection != 0 { return true }
        if openFailed { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { openFailed = true; return false }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        if result != kIOReturnSuccess {
            connection = 0
            openFailed = true
            return false
        }
        return true
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<KeyData>.stride,
                                              &output, &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func fourCC(_ key: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in key.utf8 { value = (value << 8) | UInt32(byte) }
        return value
    }

    /// Reads a `flt ` key. Returns nil if the key is absent or isn't a float.
    func readFloat(_ key: String) -> Double? {
        guard connect() else { return nil }
        let code = Self.fourCC(key)

        let info: (type: UInt32, size: UInt32)
        if let cached = keyInfoCache[code] {
            info = cached
        } else {
            var request = KeyData()
            request.key = code
            request.data8 = Self.kGetKeyInfo
            guard let response = call(&request) else { return nil }
            info = (response.keyInfo.dataType, response.keyInfo.dataSize)
            keyInfoCache[code] = info
        }
        guard info.type == Self.typeFloat, info.size == 4 else { return nil }

        var request = KeyData()
        request.key = code
        request.keyInfo.dataSize = info.size
        request.data8 = Self.kReadKey
        guard let response = call(&request) else { return nil }

        // SMC returns `flt ` little-endian.
        let bits = withUnsafeBytes(of: response.bytes) { raw in
            UInt32(raw[0]) | (UInt32(raw[1]) << 8) | (UInt32(raw[2]) << 16) | (UInt32(raw[3]) << 24)
        }
        let value = Double(Float(bitPattern: bits))
        return value.isFinite ? value : nil
    }
}

class BatteryProvider {
    
    private var cachedBatteryEntry: io_registry_entry_t = 0
    private var batteryCacheAge: Int = 0
    private let smc = SMCPowerReader()
    
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

                    if stats.isCharging, let adapter = properties["AdapterDetails"] as? [String: Any] {
                        stats.adapterWatts = adapter["Watts"] as? Int ?? 0
                    }

                    stats.powerFlow = Self.powerFlow(from: properties,
                                                     externalConnected: stats.isCharging,
                                                     adapterRatedWatts: stats.adapterWatts)

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

    // MARK: - Power Flow

    /// Overlays SMC's ~1 Hz system-load reading onto the IORegistry snapshot captured by
    /// `getBatteryStats()`.
    ///
    /// Each leg comes from whichever source is actually good at it:
    ///
    /// - **System load** from SMC `PSTR`. AppleSmartBattery only republishes every ~15 s, so
    ///   the one number that visibly moves gets the fast source.
    /// - **Battery power** from `PowerTelemetryData`. It is exact and, unlike SMC, it
    ///   conserves; battery charge rate genuinely changes slowly, so 15 s is no loss.
    /// - **Adapter** is derived, so `adapter == system + battery` holds by construction and
    ///   the ribbons always meet.
    ///
    /// Deliberately *not* derived from SMC `PDTR - PSTR`: measured on M1, `PDTR` and `PSTR`
    /// update one generation apart, so with a full battery (true battery power 0) their
    /// difference swings +-0.5 W typically and up to +-5.5 W on a load transient. That is
    /// enough to flip the diagram between "charging" and "adapter underpowered" while
    /// nothing is actually flowing.
    func refreshedPowerFlow(_ snapshot: PowerFlowStats) -> PowerFlowStats {
        var flow = snapshot
        guard flow.isValid else { return flow }

        // A running Mac never draws zero, so a non-positive reading is a bad sample rather
        // than a measurement; keep the IORegistry value in that case.
        if let systemLoad = smc.readFloat("PSTR"), systemLoad > PowerFlowStats.deadband {
            flow.systemWatts = systemLoad
        }

        if flow.externalConnected {
            flow.adapterWatts = max(0, flow.systemWatts + flow.batteryWatts)
        } else {
            // On battery there is no adapter leg, whatever the telemetry says.
            flow.adapterWatts = 0
            flow.batteryWatts = -flow.systemWatts
        }
        return flow
    }

    /// Reads PowerTelemetryData out of the property dictionary `getBatteryStats()` already
    /// fetched, so this costs no extra IOKit round-trip.
    private static func powerFlow(from properties: [String: Any],
                                  externalConnected: Bool,
                                  adapterRatedWatts: Int) -> PowerFlowStats {
        var flow = PowerFlowStats()
        flow.externalConnected = externalConnected
        flow.adapterRatedWatts = adapterRatedWatts

        guard let telemetry = properties["PowerTelemetryData"] as? [String: Any] else { return flow }
        let adapterIn = signedMilliwatts(telemetry["SystemPowerIn"])
        let systemLoad = signedMilliwatts(telemetry["SystemLoad"])
        let batteryPower = signedMilliwatts(telemetry["BatteryPower"])
        guard systemLoad != nil || batteryPower != nil else { return flow }

        flow.adapterWatts = max(0, (adapterIn ?? 0) / 1000)
        flow.systemWatts = max(0, (systemLoad ?? 0) / 1000)
        flow.batteryWatts = (batteryPower ?? 0) / 1000

        // No laptop moves 250 W across these rails; a garbage republish would otherwise blow
        // the ribbon scale wide open.
        guard flow.adapterWatts < 250, flow.systemWatts < 250, abs(flow.batteryWatts) < 250 else {
            return PowerFlowStats()
        }

        if flow.systemWatts <= 0 {
            flow.systemWatts = max(0, flow.adapterWatts - flow.batteryWatts)
        }
        flow.isValid = flow.systemWatts > 0
        return flow
    }

    /// PowerTelemetryData wattages are signed but come back through CFNumber as unsigned,
    /// either 32- or 64-bit wide depending on the macOS build. Real wattages never approach
    /// 200 W, so unwrapping both widths is unambiguous.
    private static func signedMilliwatts(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let unsigned = number.uint64Value
        var signed = unsigned > UInt64(Int64.max) ? Int64(bitPattern: unsigned) : Int64(unsigned)
        if signed > 0x7FFF_FFFF { signed -= 0x1_0000_0000 }
        return Double(signed)
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
