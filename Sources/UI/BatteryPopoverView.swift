import SwiftUI
import Charts
struct BatteryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var historyManager = BatteryHistoryManager.shared
    
    var body: some View {
        let stats = monitor.batteryStats
        
        VStack(spacing: 12) {
            // Header & Info Card
            GlassCard {
                VStack(spacing: 12) {
                    HStack {
                        Label("Battery", systemImage: stats.isCharging ? "battery.100.bolt" : "battery.100")
                            .font(.headline)
                            .foregroundColor(stats.isCharging ? .green : .mint)
                            .symbolRenderingMode(.hierarchical)
                        
                        Spacer()
                        
                        Button(action: {
                            AppDelegate.shared.openSettings(for: .battery)
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        
                        Text(String(format: "%.0f%%", stats.percentage))
                            .font(.title3)
                            .bold()
                            .monospacedDigit()
                    }
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("Source")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(LocalizedStringKey(stats.isCharging ? "Power Adapter" : "Battery"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        
                        if !stats.isCharging {
                            HStack {
                                Text("Time Remaining")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                // Filter out max values like 65535 minutes which mean calculating
                                if stats.timeRemaining > 0 && stats.timeRemaining < 10000 {
                                    Text("\(stats.timeRemaining / 60)h \(stats.timeRemaining % 60)m")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                } else {
                                    Text("Calculating...")
                                        .font(.system(size: 12, weight: .semibold))
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
                            for point in history {
                                if let prev = previousState, prev != point.isCharging {
                                    currentSegmentID += 1
                                }
                                result.append((point, currentSegmentID))
                                previousState = point.isCharging
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
                        Text(LocalizedStringKey(stats.health))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(stats.health == "Good" ? .green : .orange)
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
                    
                    HStack {
                        Text("Capacity")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(stats.capacity)) / \(Int(stats.maxCapacity)) mAh")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            
            // Energy Impact Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Energy Impact", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 6) {
                        if monitor.topPowerProcesses.isEmpty {
                            Text("Calculating...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(monitor.topPowerProcesses) { process in
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
        }
        .padding()
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
