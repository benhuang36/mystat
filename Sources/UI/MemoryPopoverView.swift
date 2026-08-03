import SwiftUI
import Charts

struct MemoryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        PopoverContainer {
            PopoverTitleBar(type: .memory, value: monitor.memoryUsageString)

            CustomDivider()

            // Circular charts
            PopoverSection {
                HStack(spacing: 30) {
                    let pressureVal = monitor.memoryPressureRatio * 100
                    StatRing(value: pressureVal, displayValue: "\(Int(pressureVal))%", title: "PRESSURE", color: .purple, lineWidth: 6, valueFont: .system(size: 16, weight: .bold), titleFont: .system(size: 9))
                        .frame(width: 80, height: 80)

                    let memVal = monitor.memoryUsageRatio * 100
                    StatRing(value: memVal, displayValue: "\(Int(memVal))%", title: "MEMORY", color: .cyan, lineWidth: 6, valueFont: .system(size: 16, weight: .bold), titleFont: .system(size: 9))
                        .frame(width: 80, height: 80)
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
            }

            CustomDivider()

            // Breakdown
            PopoverSection {
                StatRow(label: "App Memory", value: monitor.appMemoryString, dotColor: .purple)
                StatRow(label: "Wired Memory", value: monitor.wiredMemoryString, dotColor: .cyan)
                StatRow(label: "Compressed", value: monitor.compressedMemoryString, dotColor: .indigo)
                StatRow(label: "Cached Files", value: monitor.cachedFilesString, dotColor: .green)
                StatRow(label: "Swap Used", value: monitor.swapUsageString, dotColor: .orange)
            }

            CustomDivider()

            // Top processes
            PopoverSection {
                CardSectionHeader(title: "Top Processes")

                ProcessListView(
                    rows: monitor.topMemoryProcesses.map {
                        ProcessRowItem(name: $0.name, value: $0.usage, pid: $0.pid)
                    },
                    minRows: 5
                )
            }
        }
    }
}
