import SwiftUI
import Charts

struct DiskPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Header & Disk Card
            GlassCard {
                VStack(spacing: 12) {
                    HStack {
                        Label("Disk", systemImage: "internaldrive")
                            .font(.headline)
                            .foregroundColor(.cyan)
                            .symbolRenderingMode(.hierarchical)
                        
                        Spacer()
                        
                        Button(action: {
                            AppDelegate.shared.openSettings(for: .disk)
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        
                        Text(monitor.diskFreeString)
                            .font(.title3)
                            .bold()
                            .monospacedDigit()
                    }
                    
                    HStack(spacing: 15) {
                        let diskVal = monitor.diskUsageRatio * 100
                        StatRing(value: diskVal, displayValue: "\(Int(diskVal))%", title: "", color: .cyan, lineWidth: 6, valueFont: .system(size: 14, weight: .bold))
                            .frame(width: 50, height: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Macintosh HD")
                                .font(.system(size: 14, weight: .semibold))
                            Text(monitor.diskFreeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                }
            }
            
            // Speeds & Chart Card
            GlassCard {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(formatBytes(monitor.diskReadSpeed) + "/s")
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 6, height: 6)
                                Text("Read").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(formatBytes(monitor.diskWriteSpeed) + "/s")
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Circle().fill(Color.indigo).frame(width: 6, height: 6)
                                Text("Write").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Chart {
                        ForEach(Array(zip(monitor.diskReadHistory.indices, monitor.diskReadHistory)), id: \.0) { index, value in
                            BarMark(
                                x: .value("Time", index),
                                y: .value("Read", value)
                            )
                            .foregroundStyle(Color.cyan.opacity(0.8))
                        }
                        ForEach(Array(zip(monitor.diskWriteHistory.indices, monitor.diskWriteHistory)), id: \.0) { index, value in
                            BarMark(
                                x: .value("Time", index),
                                y: .value("Write", -value)
                            )
                            .foregroundStyle(Color.indigo.opacity(0.8))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 60)
                }
            }
            
            // Processes Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Top Processes", systemImage: "list.dash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Read
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Top Read")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)
                            
                            ForEach(monitor.topDiskReadProcesses) { process in
                                HStack {
                                    Text(process.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(process.usage)
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                        
                        CustomDivider()
                        
                        // Write
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Top Write")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.indigo)
                            
                            ForEach(monitor.topDiskWriteProcesses) { process in
                                HStack {
                                    Text(process.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(process.usage)
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                }
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
    
    private func formatBytes(_ bytes: Double) -> String {
        let kb = bytes / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}
