import SwiftUI
import Charts

struct CPUPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    @StateObject private var hoverManager = HoverManager()
    @StateObject private var tempHoverManager = HoverManager()
    @State private var hoveredIndex: Int? = nil

    var body: some View {
        VStack(spacing: 12) {
            // Header & Chart Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    PopoverHeader(type: .cpu, value: String(format: "%.0f%%", monitor.cpuUsage))

                    Chart {
                        ForEach(Array(monitor.cpuUsageHistory.enumerated()), id: \.offset) { index, value in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Usage", value)
                            )
                            .foregroundStyle(Color.indigo)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Time", index),
                                y: .value("Usage", value)
                            )
                            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.indigo.opacity(0.8), .clear]), startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        }

                        if let index = hoveredIndex, monitor.cpuUsageHistory.indices.contains(index) {
                            RuleMark(x: .value("Time", index))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                                .annotation(position: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(PopoverStyle.secondsAgoLabel(max(0, monitor.cpuUsageHistory.count - 1 - index)))
                                            .font(.system(size: 10, weight: .bold))
                                        Text(String(format: "%.0f%%", monitor.cpuUsageHistory[index]))
                                            .font(.system(size: 10))
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(6)
                                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                                    .cornerRadius(6)
                                    .shadow(radius: 2)
                                }
                            PointMark(
                                x: .value("Time", index),
                                y: .value("Usage", monitor.cpuUsageHistory[index])
                            )
                            .foregroundStyle(Color.white)
                            .symbolSize(30)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: PopoverStyle.chartHeight)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        let x = location.x - geometry[proxy.plotAreaFrame].origin.x
                                        if let raw: Double = proxy.value(atX: x) {
                                            let count = monitor.cpuUsageHistory.count
                                            hoveredIndex = min(max(0, Int(raw.rounded())), max(0, count - 1))
                                        }
                                    case .ended:
                                        hoveredIndex = nil
                                    }
                                }
                        }
                    }

                    HStack {
                        Circle().fill(Color.indigo).frame(width: 8, height: 8)
                        (Text("User ") + Text(String(format: "%.0f%%", monitor.cpuUserUsage)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Circle().fill(Color.cyan).frame(width: 8, height: 8)
                        (Text("System ") + Text(String(format: "%.0f%%", monitor.cpuSystemUsage)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoverManager.show()
                } else {
                    hoverManager.hide()
                }
            }
            .popover(isPresented: $hoverManager.isHovering, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                CPUCorePopoverView(coreUsages: monitor.cpuCoreUsages)
                    .onHover { hovering in
                        if hovering {
                            hoverManager.show()
                        } else {
                            hoverManager.hide()
                        }
                    }
            }
            
            // Processes Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    CardSectionHeader(title: "Top Processes")

                    CustomDivider().padding(.vertical, 4)

                    ProcessListView(
                        rows: monitor.topCPUProcesses.map { process in
                            ProcessRowItem(
                                name: process.name,
                                value: "\(process.usage)%",
                                valueColor: (Double(process.usage) ?? 0) > 20 ? .orange : .primary,
                                pid: process.pid
                            )
                        },
                        minRows: 5
                    )
                }
            }
            
            // Sensors Card
            GlassCard {
                HStack(spacing: 20) {
                    StatRing(value: monitor.gpuUsage, displayValue: "\(Int(monitor.gpuUsage))%", title: "GPU", color: .indigo)
                        .frame(width: 50, height: 50)
                    
                    // Display Fan speed RPM
                    let rpm = Int(monitor.sensorStats.fanSpeed)
                    if rpm > 0 {
                        StatRing(value: min(100, (monitor.sensorStats.fanSpeed / 5000.0) * 100.0), displayValue: "\(rpm)", title: "FAN", color: .cyan)
                            .frame(width: 50, height: 50)
                    }
                    
                    // Temp display
                    let temp = Int(monitor.sensorStats.cpuTemperature)
                    StatRing(value: min(100, monitor.sensorStats.cpuTemperature), displayValue: "\(temp)°", title: "TMP", color: .orange)
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                tempHoverManager.show()
                            } else {
                                tempHoverManager.hide()
                            }
                        }
                        .popover(isPresented: $tempHoverManager.isHovering, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                            TempSensorsPopoverView(stats: monitor.sensorStats)
                                .onHover { hovering in
                                    if hovering {
                                        tempHoverManager.show()
                                    } else {
                                        tempHoverManager.hide()
                                    }
                                }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(width: PopoverStyle.width)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct StatRing: View {
    let value: Double
    let displayValue: String
    let title: String
    let color: Color
    var lineWidth: CGFloat = 5
    var valueFont: Font = .system(size: 12, weight: .bold)
    var titleFont: Font = .system(size: 8)
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(value / 100.0))
                .stroke(
                    LinearGradient(gradient: Gradient(colors: [color.opacity(0.5), color]), startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 0) {
                Text(displayValue)
                    .font(valueFont)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                
                if !title.isEmpty {
                    Text(title)
                        .font(titleFont)
                        .foregroundColor(.secondary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .padding(lineWidth + 2) // keep text away from edges
        }
    }
}

struct CPUCorePopoverView: View {
    let coreUsages: [Double]
    
    private var columnCount: Int {
        let count = coreUsages.count
        if count <= 4 { return max(1, count) }
        
        switch count {
        case 8: return 4 // 4x2
        case 10: return 5 // 5x2
        case 12: return 6 // 6x2
        case 14: return 7 // 7x2
        case 16: return 8 // 8x2
        case 24: return 8 // 8x3
        default:
            if count % 8 == 0 { return 8 }
            if count % 6 == 0 { return 6 }
            if count % 5 == 0 { return 5 }
            if count % 4 == 0 { return 4 }
            if count % 3 == 0 { return count / 3 }
            return Int(ceil(sqrt(Double(count))))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CPU Cores")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: columnCount), spacing: 8) {
                ForEach(0..<coreUsages.count, id: \.self) { index in
                    VStack(spacing: 2) {
                        (Text("Core ") + Text("\(index)"))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.1))
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.blue, .cyan]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(height: geometry.size.height * CGFloat(coreUsages[index] / 100.0))
                            }
                        }
                        .frame(height: 30)
                        
                        Text("\(Int(coreUsages[index]))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                    .frame(width: 40)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .fixedSize()
    }
}

class HoverManager: ObservableObject {
    @Published var isHovering = false
    private var hideTask: DispatchWorkItem?
    
    func show() {
        hideTask?.cancel()
        hideTask = nil
        if !isHovering {
            isHovering = true
        }
    }
    
    func hide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.isHovering = false
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
    }
}

struct TempSensorsPopoverView: View {
    let stats: SensorStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temperatures")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                if stats.cpuTemperature > 0 {
                    TempRow(title: "CPU", value: stats.cpuTemperature)
                }
                if stats.gpuTemperature > 0 {
                    TempRow(title: "GPU", value: stats.gpuTemperature)
                }
                if stats.batteryTemperature > 0 {
                    TempRow(title: "Battery", value: stats.batteryTemperature)
                }
                if stats.nandTemperature > 0 {
                    TempRow(title: "NAND", value: stats.nandTemperature)
                }
                if stats.aneTemperature > 0 {
                    TempRow(title: "ANE", value: stats.aneTemperature)
                }
                if stats.cpuTemperature <= 0 && stats.gpuTemperature <= 0 && stats.batteryTemperature <= 0 && stats.nandTemperature <= 0 && stats.aneTemperature <= 0 {
                    Text("No sensor data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .fixedSize()
    }
}

struct TempRow: View {
    let title: String
    let value: Double
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .red]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(min(1.0, value / 100.0)))
                }
            }
            .frame(height: 10)
            
            Text("\(Int(value))°C")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
                .frame(width: 35, alignment: .trailing)
        }
        .frame(width: 160)
    }
}
