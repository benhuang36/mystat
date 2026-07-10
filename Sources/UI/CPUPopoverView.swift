import SwiftUI
import Charts

struct CPUPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    @StateObject private var hoverManager = HoverManager()
    @StateObject private var tempHoverManager = HoverManager()
    
    var body: some View {
        VStack(spacing: 12) {
            // Header & Chart Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("CPU", systemImage: "cpu")
                            .font(.headline)
                            .foregroundColor(.indigo)
                            .symbolRenderingMode(.hierarchical)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f%%", monitor.cpuUsage))
                            .font(.title3)
                            .bold()
                            .monospacedDigit()
                        
                        Button(action: {
                            AppDelegate.shared.openSettings(for: .cpu)
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                    
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
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 60)
                    
                    HStack {
                        Circle().fill(Color.indigo).frame(width: 8, height: 8)
                        (Text("User ") + Text(String(format: "%.0f%%", monitor.cpuUsage * 0.7)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Circle().fill(Color.cyan).frame(width: 8, height: 8)
                        (Text("System ") + Text(String(format: "%.0f%%", monitor.cpuUsage * 0.3)))
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
                    Label("Top Processes", systemImage: "list.dash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    CustomDivider().padding(.vertical, 4)
                    
                    VStack(spacing: 6) {
                        ForEach(Array(monitor.topCPUProcesses.enumerated()), id: \.element.id) { index, process in
                            VStack(spacing: 6) {
                                HStack {
                                    Text(process.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text("\(process.usage)%")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor((Double(process.usage) ?? 0) > 20 ? .orange : .primary)
                                }
                                if index < monitor.topCPUProcesses.count - 1 {
                                    CustomDivider()
                                }
                            }
                        }
                    }
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
        .frame(width: 320)
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
