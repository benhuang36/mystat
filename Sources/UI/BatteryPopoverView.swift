import SwiftUI
import Charts
struct BatteryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var historyManager = BatteryHistoryManager.shared
    @State private var hoveredDate: Date? = nil
    
    var body: some View {
        let stats = monitor.batteryStats
        
        VStack(spacing: 12) {
            // Header & Info Card
            GlassCard {
                VStack(spacing: 12) {
                    PopoverHeader(
                        type: .battery,
                        value: String(format: "%.0f%%", stats.percentage),
                        systemImageOverride: stats.isCharging ? "battery.100.bolt" : "battery.100",
                        accentOverride: stats.isCharging ? .green : .mint
                    )

                    VStack(spacing: 8) {
                        HStack {
                            Text("Source")
                                .font(PopoverStyle.rowLabelFont)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(LocalizedStringKey(stats.isCharging ? "Power Adapter" : "Battery"))
                                .font(PopoverStyle.rowValueFont)
                        }

                        if !stats.isCharging {
                            HStack {
                                Text("Time Remaining")
                                    .font(PopoverStyle.rowLabelFont)
                                    .foregroundColor(.secondary)
                                Spacer()
                                // Filter out max values like 65535 minutes which mean calculating
                                if stats.timeRemaining > 0 && stats.timeRemaining < 10000 {
                                    Text("\(stats.timeRemaining / 60)h \(stats.timeRemaining % 60)m")
                                        .font(PopoverStyle.rowValueFont)
                                        .monospacedDigit()
                                } else {
                                    Text("Calculating...")
                                        .font(PopoverStyle.rowValueFont)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            // 24-Hour History Chart
            let history = historyManager.history
            if history.count > 1 {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("History (Last 24 Hours)", systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        let segmentedHistory: [(point: BatteryDataPoint, segmentID: Int)] = {
                            var result: [(BatteryDataPoint, Int)] = []
                            var currentSegmentID = 0
                            var previousState: Bool? = nil
                            var previousDate: Date? = nil
                            for point in history {
                                if let prevDate = previousDate, point.timestamp.timeIntervalSince(prevDate) > 15 * 60 {
                                    currentSegmentID += 1
                                } else if let prev = previousState, prev != point.isCharging {
                                    currentSegmentID += 1
                                }
                                result.append((point, currentSegmentID))
                                previousState = point.isCharging
                                previousDate = point.timestamp
                            }
                            return result
                        }()
                        
                        Chart {
                            ForEach(segmentedHistory, id: \.point.id) { item in
                                LineMark(
                                    x: .value("Time", item.point.timestamp),
                                    y: .value("Battery", item.point.percentage),
                                    series: .value("Segment", item.segmentID)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(item.point.isCharging ? Color.green : Color.orange)
                                
                                AreaMark(
                                    x: .value("Time", item.point.timestamp),
                                    y: .value("Battery", item.point.percentage),
                                    series: .value("Segment", item.segmentID)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            item.point.isCharging ? Color.green.opacity(0.5) : Color.orange.opacity(0.5),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                            
                            if let hoveredDate {
                                if let point = historyManager.history.min(by: { abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate)) }) {
                                    RuleMark(x: .value("Time", point.timestamp))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                                        .foregroundStyle(.gray.opacity(0.5))
                                        .annotation(position: .top) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(point.timestamp, format: .dateTime.hour().minute())
                                                    .font(.system(size: 10, weight: .bold))
                                                Text("\(Int(point.percentage))% (\(point.isCharging ? "Charging" : "Battery"))")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(6)
                                            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                                            .cornerRadius(6)
                                            .shadow(radius: 2)
                                        }
                                }
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .onContinuousHover { phase in
                                        switch phase {
                                        case .active(let location):
                                            let x = location.x - geometry[proxy.plotAreaFrame].origin.x
                                            if let date: Date = proxy.value(atX: x) {
                                                hoveredDate = date
                                            }
                                        case .ended:
                                            hoveredDate = nil
                                        }
                                    }
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis {
                            AxisMarks { value in
                                if let date = value.as(Date.self) {
                                    AxisValueLabel {
                                        Text(date, format: .dateTime.hour().minute())
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let doubleValue = value.as(Double.self) {
                                        Text("\(Int(doubleValue))%")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        .frame(height: 100)
                        .padding(.top, 5)
                        
                        // Custom Legend
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Charging").font(.caption2).foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 8, height: 8)
                                Text("Battery").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            // Health & Details Card
            GlassCard {
                VStack(spacing: 8) {
                    HStack {
                        Text("Health")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            if stats.healthPercentage > 0 {
                                Text(String(format: "%.0f%%", stats.healthPercentage))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                            }
                            Text(LocalizedStringKey(stats.health))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(healthColor(for: stats))
                        }
                    }

                    HStack {
                        Text("Cycle Count")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(stats.cycleCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }

                    Divider()

                    HStack {
                        Text("Battery Charge")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(stats.capacity)) mAh")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Full Charge Capacity")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(stats.maxCapacity)) mAh")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }

                    if stats.designCapacity > 0 {
                        HStack {
                            Text("Design Capacity")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(stats.designCapacity)) mAh")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
            
            // Energy Impact Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Energy Impact", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if monitor.topPowerProcesses.isEmpty {
                        Text("Calculating...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        ProcessListView(
                            rows: monitor.topPowerProcesses.map {
                                ProcessRowItem(name: $0.name, value: $0.usage, pid: $0.pid)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .frame(width: PopoverStyle.width)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func healthColor(for stats: BatteryStats) -> Color {
        switch stats.health {
        case "Good": return .green
        case "Fair": return .orange
        case "Poor": return .red
        default: return .secondary
        }
    }
}
