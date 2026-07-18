import SwiftUI
import Charts

struct NetworkPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var info = NetworkInfoManager.shared
    @State private var hoveredIndex: Int? = nil

    // Match the menu bar chart defaults: download = cyan, upload = red
    private let downloadColor = Color.cyan
    private let uploadColor = Color.red

    private func hoveredValue(in history: [Double]) -> Double? {
        guard let index = hoveredIndex, history.indices.contains(index) else { return nil }
        return history[index]
    }

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

                    CopyableValueRow(label: "IP Address", value: info.localIP)
                    if !info.localIPv6.isEmpty {
                        CopyableValueRow(value: info.localIPv6, valueFont: NetworkPopoverView.ipv6Font)
                    }

                    CopyableValueRow(label: "Public IP", value: info.publicIP)
                    if !info.publicIPv6.isEmpty {
                        CopyableValueRow(value: info.publicIPv6, valueFont: NetworkPopoverView.ipv6Font)
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

    /// Readable monospaced font for full-width IPv6 rows
    static let ipv6Font = Font.system(size: 11, weight: .medium, design: .monospaced)

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

            if let index = hoveredIndex {
                RuleMark(x: .value("Time", index))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    .annotation(position: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PopoverStyle.secondsAgoLabel(max(0, monitor.networkDownloadHistory.count - 1 - index)))
                                .font(.system(size: 10, weight: .bold))
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(downloadColor)
                                Text(ByteFormat.speed(hoveredValue(in: monitor.networkDownloadHistory) ?? 0))
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(uploadColor)
                                Text(ByteFormat.speed(hoveredValue(in: monitor.networkUploadHistory) ?? 0))
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                            }
                        }
                        .padding(6)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        .cornerRadius(6)
                        .shadow(radius: 2)
                    }
            }
        }
        .chartYScale(domain: -1.05...1.05)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 84)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let x = location.x - geometry[proxy.plotAreaFrame].origin.x
                            if let raw: Double = proxy.value(atX: x) {
                                let count = monitor.networkDownloadHistory.count
                                hoveredIndex = min(max(0, Int(raw.rounded())), max(0, count - 1))
                            }
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
            }
        }
    }
}
