import SwiftUI
import Charts

struct NetworkPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label("Network", systemImage: "network")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Spacer()
                
                Button(action: {
                    AppDelegate.shared.openSettings(for: .network)
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
            
            // Download Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.pink)
                            .symbolRenderingMode(.hierarchical)
                        Spacer()
                        Text(formatBytes(monitor.networkDownloadSpeed) + "/s")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
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
                    .padding(.top, 5)
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
                    
                    CustomDivider().padding(.vertical, 4)
                    VStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { index in
                            if index < monitor.topNetworkDownloadProcesses.count {
                                let proc = monitor.topNetworkDownloadProcesses[index]
                                HStack {
                                    Text(proc.name)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(proc.usage)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            } else {
                                HStack {
                                    Text(" ")
                                        .font(.system(size: 11))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            
            // Upload Card
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Upload", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
                            .symbolRenderingMode(.hierarchical)
                        Spacer()
                        Text(formatBytes(monitor.networkUploadSpeed) + "/s")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
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
                    .padding(.top, 5)
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
                    
                    CustomDivider().padding(.vertical, 4)
                    VStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { index in
                            if index < monitor.topNetworkUploadProcesses.count {
                                let proc = monitor.topNetworkUploadProcesses[index]
                                HStack {
                                    Text(proc.name)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(proc.usage)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            } else {
                                HStack {
                                    Text(" ")
                                        .font(.system(size: 11))
                                    Spacer()
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
        return String(format: "%.1f MB", mb)
    }
}
