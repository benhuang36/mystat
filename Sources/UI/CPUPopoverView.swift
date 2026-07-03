import SwiftUI
import Charts

struct CPUPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("CPU")
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
                
                Text(String(format: "%.0f%%", monitor.cpuUsage))
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
            }
            
            // Chart
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
            
            // Stats
            HStack {
                Circle().fill(Color.indigo).frame(width: 8, height: 8)
                Text("User \(String(format: "%.0f%%", monitor.cpuUsage * 0.7))")
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                Circle().fill(Color.cyan).frame(width: 8, height: 8)
                Text("System \(String(format: "%.0f%%", monitor.cpuUsage * 0.3))")
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.bottom, 5)
            
            Divider()
            
            // Processes
            Text("PROCESSES")
                .font(.caption)
                .foregroundColor(.indigo)
                .padding(.top, 5)
            
            VStack(spacing: 4) {
                ForEach(monitor.topCPUProcesses) { process in
                    HStack {
                        Text(process.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text("\(process.usage)%")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                }
            }
            
            Divider()
            
            // Advanced Sensors (GPU, Fans, Temp)
            HStack(spacing: 20) {
                StatRing(value: monitor.gpuUsage, displayValue: "\(Int(monitor.gpuUsage))%", title: "GPU", color: .indigo)
                    .frame(width: 50, height: 50)
                
                // Display Fan speed RPM
                let rpm = Int(monitor.sensorStats.fanSpeed)
                StatRing(value: min(100, (monitor.sensorStats.fanSpeed / 5000.0) * 100.0), displayValue: "\(rpm)", title: "FAN", color: .cyan)
                    .frame(width: 50, height: 50)
                
                // Temp display
                let temp = Int(monitor.sensorStats.cpuTemperature)
                StatRing(value: min(100, monitor.sensorStats.cpuTemperature), displayValue: "\(temp)°", title: "TMP", color: .orange)
                    .frame(width: 50, height: 50)
            }
            .padding(.top, 10)
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
                .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(value / 100.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
