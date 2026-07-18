import Foundation
import SystemConfiguration
import CoreWLAN
import CoreLocation

/// Connection details shown in the Network popover (interface, IPs, ping).
/// Refreshed by SystemMonitor while popovers are open.
class NetworkInfoManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkInfoManager()

    @Published var isWiFi = false
    @Published var connectionName: String = "--"   // SSID for Wi-Fi, interface name for wired
    @Published var isConnected = false
    @Published var localIP: String = "--"
    @Published var localIPv6: String = ""
    @Published var publicIP: String = "--"
    @Published var publicIPv6: String = ""
    @Published var pingString: String = "--"

    private var lastPublicIPFetch: TimeInterval = 0
    private var lastPingFetch: TimeInterval = 0
    private var isPinging = false
    private var lastSSIDFetch: TimeInterval = 0
    private var cachedSSID: String?

    // CoreWLAN only reveals the SSID when the app has Location permission
    // on modern macOS; ask for it the first time we need the network name.
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()
    private var requestedLocationPermission = false

    private func ensureLocationPermissionForSSID() {
        guard !requestedLocationPermission else { return }
        requestedLocationPermission = true
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Permission just granted (or changed): re-resolve the SSID
        DispatchQueue.main.async { [weak self] in
            self?.lastSSIDFetch = 0
            self?.refreshInterfaceInfo()
        }
    }

    /// Cheap refresh of interface/IP info + throttled public IP and ping updates
    func refresh() {
        refreshInterfaceInfo()

        let now = Date().timeIntervalSince1970
        if now - lastPublicIPFetch > 300 {
            lastPublicIPFetch = now
            fetchPublicIP()
        }
        if now - lastPingFetch > 5, !isPinging {
            lastPingFetch = now
            runPing()
        }
    }

    private func refreshInterfaceInfo() {
        guard let store = SCDynamicStoreCreate(nil, "MyStat" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primary = global["PrimaryInterface"] as? String else {
            isConnected = false
            connectionName = "--"
            localIP = "--"
            localIPv6 = ""
            return
        }

        isConnected = true
        localIP = Self.ipAddress(of: primary, family: AF_INET) ?? "--"
        localIPv6 = Self.ipAddress(of: primary, family: AF_INET6) ?? ""

        let wifiInterface = CWWiFiClient.shared().interface()
        if wifiInterface?.interfaceName == primary {
            isWiFi = true
            if let ssid = wifiInterface?.ssid(), Self.isValidSSID(ssid) {
                connectionName = ssid
                cachedSSID = ssid
            } else {
                // On modern macOS CoreWLAN needs Location permission for the
                // SSID: request it, and meanwhile try command-line fallbacks.
                ensureLocationPermissionForSSID()
                connectionName = cachedSSID ?? primary
                resolveSSIDFallback(interface: primary)
            }
        } else {
            isWiFi = false
            connectionName = primary
        }
    }

    /// Newer macOS prints "<redacted>" instead of the SSID when the caller
    /// lacks Location permission — never treat that as a network name.
    private static func isValidSSID(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.lowercased() != "<redacted>"
    }

    private func resolveSSIDFallback(interface: String) {
        let now = Date().timeIntervalSince1970
        guard now - lastSSIDFetch > 10 else { return }
        lastSSIDFetch = now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var ssid: String?

            // ipconfig getsummary prints "SSID : name" without needing Location
            let summary = Self.runCommand("/usr/sbin/ipconfig", ["getsummary", interface])
            for line in summary.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SSID : ") {
                    ssid = String(trimmed.dropFirst("SSID : ".count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            if ssid == nil {
                let out = Self.runCommand("/usr/sbin/networksetup", ["-getairportnetwork", interface])
                if let range = out.range(of: "Network: ") {
                    let value = out[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { ssid = value }
                }
            }

            if let ssid, Self.isValidSSID(ssid) {
                DispatchQueue.main.async {
                    self?.cachedSSID = ssid
                    if self?.isWiFi == true {
                        self?.connectionName = ssid
                    }
                }
            }
        }
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

    private static func ipAddress(of interfaceName: String, family: Int32) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let interface = current.pointee
            if let sa = interface.ifa_addr, sa.pointee.sa_family == UInt8(family),
               String(cString: interface.ifa_name) == interfaceName {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    var candidate = String(cString: hostname)
                    // Strip the scope suffix ("%en0") and skip link-local addresses
                    if let percent = candidate.firstIndex(of: "%") {
                        candidate = String(candidate[..<percent])
                    }
                    if family == AF_INET6 && candidate.lowercased().hasPrefix("fe80") {
                        ptr = current.pointee.ifa_next
                        continue
                    }
                    address = candidate
                    break
                }
            }
            ptr = current.pointee.ifa_next
        }
        return address
    }

    private func fetchPublicIP() {
        fetchPublicAddress(from: "https://api.ipify.org") { [weak self] ip in
            self?.publicIP = ip
        }
        fetchPublicAddress(from: "https://api6.ipify.org") { [weak self] ip in
            // Only shown when the machine actually has IPv6 connectivity
            if ip.contains(":") {
                self?.publicIPv6 = ip
            }
        }
    }

    private func fetchPublicAddress(from urlString: String, assign: @escaping (String) -> Void) {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let ip = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty, ip.count < 64 else { return }
            DispatchQueue.main.async {
                assign(ip)
            }
        }.resume()
    }

    private func runPing() {
        isPinging = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { DispatchQueue.main.async { self?.isPinging = false } }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = ["-c", "1", "-t", "2", "1.1.1.1"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            var result = "--"
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if let output = String(data: data, encoding: .utf8),
                   let range = output.range(of: "time=") {
                    let after = output[range.upperBound...]
                    if let msValue = Double(after.prefix(while: { "0123456789.".contains($0) })) {
                        result = String(format: "%.0f ms", msValue)
                    }
                }
            } catch {
                // keep "--"
            }

            DispatchQueue.main.async {
                self?.pingString = result
            }
        }
    }
}

class NetworkProvider {
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTime: TimeInterval = 0
    
    struct NetworkSpeed {
        var bytesInPerSecond: Double
        var bytesOutPerSecond: Double
    }
    
    init() {
        // Initialize baseline
        let current = getCurrentBytes()
        lastBytesIn = current.in
        lastBytesOut = current.out
        lastTime = Date().timeIntervalSince1970
    }
    
    func getNetworkSpeeds() -> NetworkSpeed {
        let current = getCurrentBytes()
        let currentTime = Date().timeIntervalSince1970
        let timeDiff = currentTime - lastTime
        
        var speedIn: Double = 0
        var speedOut: Double = 0
        
        if timeDiff > 0 {
            if current.in >= lastBytesIn {
                speedIn = Double(current.in - lastBytesIn) / timeDiff
            }
            if current.out >= lastBytesOut {
                speedOut = Double(current.out - lastBytesOut) / timeDiff
            }
        }
        
        lastBytesIn = current.in
        lastBytesOut = current.out
        lastTime = currentTime
        
        return NetworkSpeed(bytesInPerSecond: speedIn, bytesOutPerSecond: speedOut)
    }
    
    private func getCurrentBytes() -> (in: UInt64, out: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        guard let firstAddr = ifaddr else { return (0, 0) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            
            // Check for running interface
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_LINK) {
                    let data = unsafeBitCast(ptr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    totalIn += UInt64(data.pointee.ifi_ibytes)
                    totalOut += UInt64(data.pointee.ifi_obytes)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        return (totalIn, totalOut)
    }
}
