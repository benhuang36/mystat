import SwiftUI
import Charts

struct DiskPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Header & Disk Card
            GlassCard {
                VStack(spacing: 12) {
                    PopoverHeader(type: .disk, value: monitor.diskFreeString)

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
                            Text(ByteFormat.speed(monitor.diskReadSpeed))
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 6, height: 6)
                                Text("Read").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(ByteFormat.speed(monitor.diskWriteSpeed))
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
                    CardSectionHeader(title: "Top Read", systemImage: "arrow.down.circle.fill", color: .cyan)

                    ProcessListView(
                        rows: monitor.topDiskReadProcesses.map {
                            ProcessRowItem(name: $0.name, value: $0.usage, pid: $0.pid)
                        }
                    )

                    CustomDivider().padding(.vertical, 4)

                    CardSectionHeader(title: "Top Write", systemImage: "arrow.up.circle.fill", color: .indigo)

                    ProcessListView(
                        rows: monitor.topDiskWriteProcesses.map {
                            ProcessRowItem(name: $0.name, value: $0.usage, pid: $0.pid)
                        }
                    )
                }
            }
        }
        .padding()
        .frame(width: PopoverStyle.width)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
