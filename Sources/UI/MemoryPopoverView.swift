import SwiftUI
import Charts

struct MemoryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Header & Charts Card
            GlassCard {
                VStack(spacing: 15) {
                    HStack {
                        Label("Memory", systemImage: "memorychip")
                            .font(.headline)
                            .foregroundColor(.purple)
                            .symbolRenderingMode(.hierarchical)
                        
                        Spacer()
                        
                        Button(action: {
                            AppDelegate.shared.openSettings()
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
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
                    .padding(.vertical, 5)
                }
            }
            
            // Breakdown Card
            GlassCard {
                VStack(spacing: 8) {
                    HStack {
                        Circle().fill(Color.purple).frame(width: 8, height: 8)
                        Text("App Memory")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("3.7 GB")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                    HStack {
                        Circle().fill(Color.cyan).frame(width: 8, height: 8)
                        Text("Wired Memory")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("2.4 GB")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                    HStack {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Swap Used")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(monitor.swapUsageString)
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            
            // Processes Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Top Processes", systemImage: "list.dash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 6) {
                        ForEach(monitor.topMemoryProcesses) { process in
                            HStack {
                                Text(process.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(process.usage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                            }
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
