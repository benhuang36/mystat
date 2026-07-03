import SwiftUI
import Charts

struct NetworkPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Network")
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
            }
            
            Divider()
            
            // Upload Section
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Upload")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatBytes(monitor.networkUploadSpeed) + "/s")
                        .font(.headline)
                        .foregroundColor(.cyan)
                        .monospacedDigit()
                }
                
                Chart {
                    ForEach(Array(monitor.networkUploadHistory.enumerated()), id: \.offset) { index, value in
                        AreaMark(
                            x: .value("Time", index),
                            y: .value("Upload", value)
                        )
                        .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.cyan.opacity(0.8), Color.cyan.opacity(0.1)]), startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .padding(.top, 10)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatBytes(doubleValue))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .frame(height: 70)
            }
            .padding(.bottom, 5)
            
            Divider()
            
            // Download Section
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatBytes(monitor.networkDownloadSpeed) + "/s")
                        .font(.headline)
                        .foregroundColor(.pink)
                        .monospacedDigit()
                }
                
                Chart {
                    ForEach(Array(monitor.networkDownloadHistory.enumerated()), id: \.offset) { index, value in
                        AreaMark(
                            x: .value("Time", index),
                            y: .value("Download", value)
                        )
                        .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.pink.opacity(0.8), Color.pink.opacity(0.1)]), startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .padding(.top, 10)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatBytes(doubleValue))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .frame(height: 70)
            }
        }
        .padding()
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        let kb = bytes / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
