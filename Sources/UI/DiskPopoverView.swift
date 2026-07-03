import SwiftUI
import Charts

struct DiskPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Disk")
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
                
                Text(monitor.diskFreeString)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
            }
            
            // Macintosh HD
            HStack(spacing: 12) {
                let diskVal = monitor.diskUsageRatio * 100
                StatRing(value: diskVal, displayValue: "\(Int(diskVal))%", title: "", color: .cyan, lineWidth: 5, valueFont: .system(size: 10, weight: .bold))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    Text("Macintosh HD")
                        .font(.subheadline)
                    Text(monitor.diskFreeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 5)
            
            Divider()
            
            // Speeds
            HStack {
                VStack(alignment: .leading) {
                    Text("377 KB/s")
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                    HStack {
                        Circle().fill(Color.cyan).frame(width: 6, height: 6)
                        Text("Read").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("108 KB/s")
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                    HStack {
                        Circle().fill(Color.indigo).frame(width: 6, height: 6)
                        Text("Write").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            
            // Mock Activity Chart
            Chart {
                ForEach(0..<30, id: \.self) { index in
                    BarMark(
                        x: .value("Time", index),
                        y: .value("Read", Double.random(in: 10...100))
                    )
                    .foregroundStyle(Color.cyan)
                    
                    BarMark(
                        x: .value("Time", index),
                        y: .value("Write", Double.random(in: -100...(-10)))
                    )
                    .foregroundStyle(Color.indigo)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 80)
            
            Divider()
            
            Text("PROCESSES")
                .font(.caption)
                .foregroundColor(.cyan)
            
            VStack(spacing: 4) {
                // Mock disk processes
                HStack {
                    Text("kernel_task").font(.system(size: 11))
                    Spacer()
                    Text("8.8M")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                HStack {
                    Text("mds_stores").font(.system(size: 11))
                    Spacer()
                    Text("2.1M")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
