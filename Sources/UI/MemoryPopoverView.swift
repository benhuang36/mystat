import SwiftUI
import Charts

struct MemoryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Memory")
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
                
                Text(monitor.memoryUsageString)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
            }
            
            // Circular Charts
            HStack(spacing: 30) {
                StatRing(value: 44, displayValue: "44%", title: "PRESSURE", color: .purple, lineWidth: 6, valueFont: .system(size: 16, weight: .bold), titleFont: .system(size: 9))
                    .frame(width: 80, height: 80)
                
                let memVal = monitor.memoryUsageRatio * 100
                StatRing(value: memVal, displayValue: "\(Int(memVal))%", title: "MEMORY", color: .cyan, lineWidth: 6, valueFont: .system(size: 16, weight: .bold), titleFont: .system(size: 9))
                    .frame(width: 80, height: 80)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            
            // Bars
            HStack {
                Circle().fill(Color.purple).frame(width: 8, height: 8)
                Text("App")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("3.7 GB")
                    .font(.caption)
                    .monospacedDigit()
            }
            HStack {
                Circle().fill(Color.cyan).frame(width: 8, height: 8)
                Text("Wired")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("2.4 GB")
                    .font(.caption)
                    .monospacedDigit()
            }
            HStack {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Swap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(monitor.swapUsageString)
                    .font(.caption)
                    .monospacedDigit()
            }
            
            Divider()
            
            // Processes
            Text("PROCESSES")
                .font(.caption)
                .foregroundColor(.purple)
                .padding(.top, 5)
            
            VStack(spacing: 4) {
                ForEach(monitor.topMemoryProcesses) { process in
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
        .padding()
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
