import SwiftUI
import Charts

struct NetworkPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var info = NetworkInfoManager.shared

    // Match the menu bar chart defaults: download = cyan, upload = red
    private let downloadColor = Color.cyan
    private let uploadColor = Color.red

    var body: some View {
        VStack(spacing: 12) {
            // Header Card
            GlassCard {
                PopoverHeader(type: .network)
            }

            // Combined Traffic Card
            GlassCard {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ByteFormat.speed(monitor.networkDownloadSpeed))
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Circle().fill(downloadColor).frame(width: 6, height: 6)
                                Text("Download").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(ByteFormat.speed(monitor.networkUploadSpeed))
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Circle().fill(uploadColor).frame(width: 6, height: 6)
                                Text("Upload").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    // Mirrored chart: download grows up, upload grows down.
                    // Each direction is normalized to its own peak so the
                    // quieter direction stays readable.
                    mirroredChart
                }
            }

            // Connection Info Card
            GlassCard {
                VStack(spacing: 8) {
                    StatRow(
                        label: info.isWiFi ? "Wi-Fi" : "Ethernet",
                        value: info.isConnected ? info.connectionName : NSLocalizedString("Not Connected", comment: ""),
                        dotColor: info.isConnected ? .green : .red
                    )

                    StatRow(label: "IP Address", value: info.localIP)
                    if !info.localIPv6.isEmpty {
                        ipv6Row(info.localIPv6)
                    }

                    StatRow(label: "Public IP", value: info.publicIP)
                    if !info.publicIPv6.isEmpty {
                        ipv6Row(info.publicIPv6)
                    }

                    StatRow(label: "Ping", value: info.pingString)
                }
            }

            // Combined Processes Card (iStat-style: one list, two columns)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        CardSectionHeader(title: "Processes")
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(downloadColor)
                            .frame(width: 48, alignment: .trailing)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(uploadColor)
                            .frame(width: 48, alignment: .trailing)
                    }

                    CustomDivider()

                    VStack(spacing: 6) {
                        ForEach(monitor.topNetworkProcesses) { process in
                            HStack(spacing: 6) {
                                Image(nsImage: ProcessIcon.icon(for: process.pid))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                Text(process.name)
                                    .font(PopoverStyle.rowLabelFont)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(ByteFormat.compact(process.downloadSpeed))
                                    .font(PopoverStyle.rowValueFont)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                                Text(ByteFormat.compact(process.uploadSpeed))
                                    .font(PopoverStyle.rowValueFont)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                            .frame(height: 17)
                        }
                        ForEach(0..<max(0, 5 - monitor.topNetworkProcesses.count), id: \.self) { _ in
                            HStack { Spacer() }.frame(height: 17)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: PopoverStyle.width)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    /// Long IPv6 address shown right-aligned under its IPv4 row
    private func ipv6Row(_ address: String) -> some View {
        HStack {
            Spacer()
            Text(address)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var mirroredChart: some View {
        let downMax = max(1.0, monitor.networkDownloadHistory.max() ?? 1.0)
        let upMax = max(1.0, monitor.networkUploadHistory.max() ?? 1.0)

        return Chart {
            ForEach(Array(monitor.networkDownloadHistory.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Time", index),
                    y: .value("Download", value / downMax)
                )
                .foregroundStyle(downloadColor.opacity(0.85))
            }
            ForEach(Array(monitor.networkUploadHistory.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Time", index),
                    y: .value("Upload", -(value / upMax))
                )
                .foregroundStyle(uploadColor.opacity(0.85))
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: -1.05...1.05)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 84)
    }
}
