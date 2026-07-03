import SwiftUI

struct BatteryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        let stats = monitor.batteryStats
        
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("BATTERY")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                
                Button(action: {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                Text(String(format: "%.0f%%", stats.percentage))
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Source")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(stats.isCharging ? "Power Adapter" : "Battery")
                }
                
                if !stats.isCharging {
                    HStack {
                        Text("Time Remaining")
                            .foregroundColor(.secondary)
                        Spacer()
                        // Filter out max values like 65535 minutes which mean calculating
                        if stats.timeRemaining > 0 && stats.timeRemaining < 10000 {
                            Text("\(stats.timeRemaining / 60)h \(stats.timeRemaining % 60)m")
                                .monospacedDigit()
                        } else {
                            Text("Calculating...")
                                .monospacedDigit()
                        }
                    }
                }
                
                HStack {
                    Text("Health")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(stats.health)
                        .foregroundColor(stats.health == "Good" ? .green : .orange)
                }
                
                HStack {
                    Text("Cycle Count")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(stats.cycleCount)")
                        .monospacedDigit()
                }
                
                HStack {
                    Text("Capacity")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(stats.capacity)) / \(Int(stats.maxCapacity)) mAh")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12))
            
            Divider()
            
            // Power Processes
            Text("ENERGY IMPACT")
                .font(.caption)
                .foregroundColor(.mint)
                .padding(.top, 5)
            
            VStack(spacing: 4) {
                if monitor.topPowerProcesses.isEmpty {
                    Text("Calculating...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(monitor.topPowerProcesses) { process in
                        HStack {
                            Text(process.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(process.usage)
                                .font(.system(size: 11))
                                .monospacedDigit()
                        }
                    }
                }
            }
            
        }
        .padding()
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
