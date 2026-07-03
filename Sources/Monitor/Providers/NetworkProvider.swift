import Foundation
import SystemConfiguration

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
