import SwiftUI
import Charts

struct MemoryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Header & Charts Card
            GlassCard {
                VStack(spacing: 15) {
                    PopoverHeader(type: .memory, value: monitor.memoryUsageString)

                    // Circular Charts
                    HStack(spacing: 30) {
                        let pressureVal = monitor.memoryPressureRatio * 100
                        StatRing(value: pressureVal, displayValue: "\(Int(pressureVal))%", title: "PRESSURE", color: .purple, lineWidth: 6, valueFont: .system(size: 16, weight: .bold), titleFont: .system(size: 9))
                            .frame(width: 80, height: 80)

                        let memVal = monitor.memoryUsageRatio * 100
                        StatRing(value: memVal, displayValue: "\(Int(memVal))%", title: "MEMORY", color: .cyan, lineWidth: 6, valueFont: .system(size: 16, weight: .bold), titleFont: .system(size: 9))
                            .frame(width: 80, height: 80)
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                }
            }

            // Breakdown Card
            GlassCard {
                VStack(spacing: 8) {
                    StatRow(label: "App Memory", value: monitor.appMemoryString, dotColor: .purple)
                    StatRow(label: "Wired Memory", value: monitor.wiredMemoryString, dotColor: .cyan)
                    StatRow(label: "Compressed", value: monitor.compressedMemoryString, dotColor: .indigo)
                    StatRow(label: "Swap Used", value: monitor.swapUsageString, dotColor: .orange)
                }
            }

            // Processes Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    CardSectionHeader(title: "Top Processes")

                    CustomDivider().padding(.vertical, 4)

                    ProcessListView(
                        rows: monitor.topMemoryProcesses.map {
                            ProcessRowItem(name: $0.name, value: $0.usage, pid: $0.pid)
                        },
                        minRows: 5
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
