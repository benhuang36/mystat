import Foundation

enum MonitorType: String, CaseIterable {
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case network = "Network"
    case battery = "Battery"
    
    var sfSymbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.100"
        }
    }
}
