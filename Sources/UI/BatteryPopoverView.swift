import SwiftUI
import Charts
struct BatteryPopoverView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var historyManager = BatteryHistoryManager.shared
    @ObservedObject private var sleepReport = SleepReportManager.shared
    @State private var hoveredDate: Date? = nil
    
    var body: some View {
        let stats = monitor.batteryStats
        
        PopoverContainer {
            PopoverTitleBar(
                type: .battery,
                value: String(format: "%.0f%%", stats.percentage),
                systemImageOverride: stats.isCharging ? "battery.100.bolt" : "battery.100",
                accentOverride: stats.isCharging ? .green : .mint
            )

            CustomDivider()

            // Source / time remaining
            PopoverSection {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Source")
                                .font(PopoverStyle.rowLabelFont)
                                .foregroundColor(.secondary)
                            Spacer()
                            if stats.isCharging && stats.adapterWatts > 0 {
                                Text("Power Adapter (\(stats.adapterWatts)W)")
                                    .font(PopoverStyle.rowValueFont)
                            } else {
                                Text(LocalizedStringKey(stats.isCharging ? "Power Adapter" : "Battery"))
                                    .font(PopoverStyle.rowValueFont)
                            }
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

            // Power flow — where the watts are coming from and where they're going.
            let flow = monitor.powerFlow
            if flow.mode != .unavailable {
                CustomDivider()

                PopoverSection(spacing: 10) {
                    CardSectionHeader(title: "Power Flow",
                                      systemImage: "bolt.horizontal.fill",
                                      color: .green)
                    PowerFlowDiagram(flow: flow)
                        .frame(maxWidth: .infinity)
                }
            }

            // 24-hour history chart
            let history = historyManager.history
            if history.count > 1 {
                CustomDivider()

                PopoverSection {
                        HStack {
                            Label("History (Last 24 Hours)", systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.bottom, 6)

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

            // Sleep report (last completed sleep session)
            if let session = sleepReport.lastSession {
                CustomDivider()

                PopoverSection {
                        CardSectionHeader(title: "Sleep Report", systemImage: "moon.zzz.fill")

                        ForEach(session.anomalies) { anomaly in
                            anomalyLabel(anomaly)
                        }

                        StatRow(label: "Duration", value: formatDuration(session.duration))
                        if let drain = session.drainPercent, let perHour = session.drainPerHour {
                            StatRow(label: "Battery Drain", value: String(format: "%d%% (%.1f%%/h)", drain, perHour))
                        }
                        StatRow(label: "Wake-ups", value: String(format: "%d (%.1f/h)", session.darkWakeCount, session.wakesPerHour))
                }
            }

            // Sleep blockers (live)
            if !sleepReport.sleepBlockers.isEmpty {
                CustomDivider()

                PopoverSection {
                        CardSectionHeader(title: "Preventing Sleep", systemImage: "exclamationmark.triangle.fill", color: .orange)

                        ForEach(sleepReport.sleepBlockers, id: \.self) { name in
                            HStack(spacing: 6) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text(name)
                                    .font(PopoverStyle.rowLabelFont)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                            }
                        }
                }
            }

            CustomDivider()

            // Health & details
            PopoverSection {
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

            CustomDivider()

            // Energy impact
            PopoverSection {
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
        .onAppear {
            SleepReportManager.shared.refresh()
            SleepReportManager.shared.refreshBlockers()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PopoverDidOpen"))) { notification in
            if let typeRaw = notification.object as? String, typeRaw == MonitorType.battery.rawValue {
                SleepReportManager.shared.refresh()
            }
        }
    }

    @ViewBuilder
    private func anomalyLabel(_ anomaly: SleepAnomaly) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Group {
                switch anomaly {
                case .nonAppleSources(let sources):
                    Text("Non-Apple wake sources") + Text(": \(sources.joined(separator: ", "))")
                case .frequentWakes(let perHour):
                    Text("Frequent wake-ups") + Text(String(format: " (%.1f/h)", perHour))
                case .highDrain(let perHour):
                    Text("High sleep drain") + Text(String(format: " (%.1f%%/h)", perHour))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.orange)
            Spacer()
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
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

// MARK: - Power Flow Sankey

/// Fixed geometry for the Sankey diagram. The popover width is a constant
/// (`PopoverStyle.width`) and `PopoverSection` insets are 16/side, so the box can be
/// hard-coded and we skip a `GeometryReader` layout pass entirely.
private enum Sankey {
    static let boxWidth: CGFloat = 288
    static let boxHeight: CGFloat = 104
    /// Width of the icon + wattage column on each side.
    static let nodeWidth: CGFloat = 60
    static let gutter: CGFloat = 6
    /// Horizontal span the ribbons occupy.
    static var ribbonStart: CGFloat { nodeWidth + gutter }
    static var ribbonEnd: CGFloat { boxWidth - nodeWidth - gutter }

    static var midY: CGFloat { boxHeight / 2 }
    /// Vertical centres when a side carries two nodes.
    static let upperY: CGFloat = 24
    static let lowerY: CGFloat = 80
    /// Keeps two stacked ribbons from fusing into one block where they share a node.
    static let stackGap: CGFloat = 4

    /// Total vertical space the ribbon stack may occupy.
    static let budget: CGFloat = 48
    /// A 0.4 W trickle still has to be visible.
    static let minThickness: CGFloat = 3

    static var leftLabelX: CGFloat { nodeWidth / 2 }
    static var rightLabelX: CGFloat { boxWidth - nodeWidth / 2 }

    /// Ribbon thickness is proportional to watts up to a 20 W reference, and normalised
    /// beyond that. So an idle 5 W draw reads as a thin trickle while a 45 W charge fills
    /// the box, instead of every state looking identically fat.
    static func thicknesses(_ watts: [Double]) -> [CGFloat] {
        let total = watts.reduce(0, +)
        guard total > 0 else { return watts.map { _ in minThickness } }
        let scale: CGFloat = budget / CGFloat(max(total, 20))
        var result: [CGFloat] = watts.map { max(minThickness, CGFloat($0) * scale) }

        // The min-thickness floor can push the stack past the budget; give the overflow
        // back proportionally from whatever slack the thicker ribbons have.
        let overflow = result.reduce(0, +) - budget
        guard overflow > 0 else { return result }
        let slack = result.map { max(0, $0 - minThickness) }
        let slackTotal = slack.reduce(0, +)
        guard slackTotal > 0 else { return result }
        for i in result.indices { result[i] -= overflow * slack[i] / slackTotal }
        return result
    }
}

/// A Sankey ribbon: a closed band between two vertical spans, not a stroked line.
/// Stroking would tie thickness to `lineWidth`, which can't taper and won't animate.
/// `animatableData` is what lets the band morph smoothly — a `Path` built inline in a
/// view body does not interpolate.
private struct RibbonShape: Shape {
    var y0: CGFloat
    var t0: CGFloat
    var y1: CGFloat
    var t1: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(y0, t0), .init(y1, t1)) }
        set {
            y0 = newValue.first.first
            t0 = newValue.first.second
            y1 = newValue.second.first
            t1 = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let xStart = Sankey.ribbonStart
        let xEnd = Sankey.ribbonEnd
        // Horizontal tangents at both ends so the band meets each node column flat.
        let control = (xEnd - xStart) * 0.5
        let topStart = CGPoint(x: xStart, y: y0 - t0 / 2)
        let topEnd = CGPoint(x: xEnd, y: y1 - t1 / 2)
        let bottomEnd = CGPoint(x: xEnd, y: y1 + t1 / 2)
        let bottomStart = CGPoint(x: xStart, y: y0 + t0 / 2)

        var path = Path()
        path.move(to: topStart)
        path.addCurve(to: topEnd,
                      control1: CGPoint(x: xStart + control, y: topStart.y),
                      control2: CGPoint(x: xEnd - control, y: topEnd.y))
        path.addLine(to: bottomEnd)
        path.addCurve(to: bottomStart,
                      control1: CGPoint(x: xEnd - control, y: bottomEnd.y),
                      control2: CGPoint(x: xStart + control, y: bottomStart.y))
        path.closeSubpath()
        return path
    }
}

private struct RibbonGeometry: Equatable {
    var y0: CGFloat = Sankey.midY
    var t0: CGFloat = Sankey.minThickness
    var y1: CGFloat = Sankey.midY
    var t1: CGFloat = Sankey.minThickness
    var isActive = false
}

private enum PowerNodeKind { case adapter, batterySource, batterySink, mac }

private struct PowerNodeLabel: Equatable, Identifiable {
    var kind: PowerNodeKind
    var watts: Double
    var y: CGFloat
    var id: Int {
        switch kind {
        case .adapter: return 0
        case .batterySource, .batterySink: return 1
        case .mac: return 2
        }
    }
}

/// Everything the diagram draws, derived purely from `PowerFlowStats`.
private struct PowerFlowLayout: Equatable {
    var adapterToMac = RibbonGeometry()
    var adapterToBattery = RibbonGeometry()
    var batteryToMac = RibbonGeometry()
    var leftNodes: [PowerNodeLabel] = []
    var rightNodes: [PowerNodeLabel] = []

    static func make(from flow: PowerFlowStats) -> PowerFlowLayout {
        var layout = PowerFlowLayout()
        let mac = max(0, flow.systemWatts)

        switch flow.mode {
        case .unavailable:
            return layout

        case .battery:
            let t = Sankey.thicknesses([mac])[0]
            layout.batteryToMac = RibbonGeometry(y0: Sankey.midY, t0: t,
                                                 y1: Sankey.midY, t1: t, isActive: true)
            layout.leftNodes = [PowerNodeLabel(kind: .batterySource, watts: mac, y: Sankey.midY)]
            layout.rightNodes = [PowerNodeLabel(kind: .mac, watts: mac, y: Sankey.midY)]

        case .adapterOnly:
            let t = Sankey.thicknesses([mac])[0]
            layout.adapterToMac = RibbonGeometry(y0: Sankey.midY, t0: t,
                                                 y1: Sankey.midY, t1: t, isActive: true)
            layout.leftNodes = [PowerNodeLabel(kind: .adapter, watts: mac, y: Sankey.midY)]
            layout.rightNodes = [PowerNodeLabel(kind: .mac, watts: mac, y: Sankey.midY)]

        case .charging:
            // Adapter fans out. Stack at the source in sink order so the ribbons don't cross.
            let charge = flow.batteryChargeWatts
            let t = Sankey.thicknesses([mac, charge])
            var cursor = Sankey.midY - (t[0] + t[1] + Sankey.stackGap) / 2
            let macSourceY = cursor + t[0] / 2
            cursor += t[0] + Sankey.stackGap
            let batterySourceY = cursor + t[1] / 2

            layout.adapterToMac = RibbonGeometry(y0: macSourceY, t0: t[0],
                                                 y1: Sankey.upperY, t1: t[0], isActive: true)
            layout.adapterToBattery = RibbonGeometry(y0: batterySourceY, t0: t[1],
                                                     y1: Sankey.lowerY, t1: t[1], isActive: true)
            layout.leftNodes = [PowerNodeLabel(kind: .adapter, watts: mac + charge, y: Sankey.midY)]
            layout.rightNodes = [
                PowerNodeLabel(kind: .mac, watts: mac, y: Sankey.upperY),
                PowerNodeLabel(kind: .batterySink, watts: charge, y: Sankey.lowerY)
            ]

        case .supplemented:
            // Two sources merge; the sink side stacks instead.
            let fromBattery = min(mac, flow.batteryDrawWatts)
            let fromAdapter = max(0, mac - fromBattery)
            let t = Sankey.thicknesses([fromAdapter, fromBattery])
            var cursor = Sankey.midY - (t[0] + t[1] + Sankey.stackGap) / 2
            let adapterSinkY = cursor + t[0] / 2
            cursor += t[0] + Sankey.stackGap
            let batterySinkY = cursor + t[1] / 2

            layout.adapterToMac = RibbonGeometry(y0: Sankey.upperY, t0: t[0],
                                                 y1: adapterSinkY, t1: t[0], isActive: true)
            layout.batteryToMac = RibbonGeometry(y0: Sankey.lowerY, t0: t[1],
                                                 y1: batterySinkY, t1: t[1], isActive: true)
            layout.leftNodes = [
                PowerNodeLabel(kind: .adapter, watts: fromAdapter, y: Sankey.upperY),
                PowerNodeLabel(kind: .batterySource, watts: fromBattery, y: Sankey.lowerY)
            ]
            layout.rightNodes = [PowerNodeLabel(kind: .mac, watts: mac, y: Sankey.midY)]
        }

        return layout
    }
}

/// AlDente-style power flow diagram: where the watts are coming from and where they go.
struct PowerFlowDiagram: View {
    let flow: PowerFlowStats

    var body: some View {
        let layout = PowerFlowLayout.make(from: flow)

        ZStack(alignment: .topLeading) {
            // Three fixed ribbon slots, always present. Keeping view identity stable lets
            // SwiftUI interpolate between states instead of popping views in and out.
            ribbon(layout.adapterToMac,
                   colors: [.green.opacity(0.55), .green.opacity(0.28)])
            ribbon(layout.adapterToBattery,
                   colors: [.green.opacity(0.55), .mint.opacity(0.45)])
            ribbon(layout.batteryToMac,
                   colors: [.orange.opacity(0.55), .orange.opacity(0.28)])

            ForEach(layout.leftNodes) { node in
                nodeLabel(node).position(x: Sankey.leftLabelX, y: node.y)
            }
            ForEach(layout.rightNodes) { node in
                nodeLabel(node).position(x: Sankey.rightLabelX, y: node.y)
            }
        }
        .frame(width: Sankey.boxWidth, height: Sankey.boxHeight)
        .animation(.easeInOut(duration: 0.45), value: layout)
    }

    private func ribbon(_ geometry: RibbonGeometry, colors: [Color]) -> some View {
        let shape = RibbonShape(y0: geometry.y0, t0: geometry.t0, y1: geometry.y1, t1: geometry.t1)
        return shape
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            // Translucent fills wash out on light vibrancy over a bright wallpaper; the
            // hairline keeps the band readable, same reasoning as CustomDivider.
            .overlay(shape.stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
            .opacity(geometry.isActive ? 1 : 0)
    }

    private func nodeLabel(_ node: PowerNodeLabel) -> some View {
        VStack(spacing: 1) {
            Image(systemName: symbol(for: node.kind))
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(tint(for: node.kind))
            Text(Self.wattsLabel(node.watts))
                .font(PopoverStyle.rowValueFont)
                .monospacedDigit()
            Text(LocalizedStringKey(name(for: node.kind)))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: Sankey.nodeWidth)
    }

    private func symbol(for kind: PowerNodeKind) -> String {
        switch kind {
        case .adapter: return "powerplug.fill"
        case .batterySource: return "battery.50"
        case .batterySink: return "battery.100.bolt"
        case .mac: return "laptopcomputer"
        }
    }

    private func tint(for kind: PowerNodeKind) -> Color {
        switch kind {
        case .adapter: return .green
        case .batterySource: return .orange
        case .batterySink: return .mint
        case .mac: return .secondary
        }
    }

    private func name(for kind: PowerNodeKind) -> String {
        switch kind {
        case .adapter: return "Adapter"
        case .batterySource, .batterySink: return "Battery"
        case .mac: return "Mac"
        }
    }

    /// Never render "0.0 W" — below the deadband it isn't a real reading.
    static func wattsLabel(_ watts: Double) -> String {
        guard watts >= PowerFlowStats.deadband else { return "—" }
        return watts < 10 ? String(format: "%.1f W", watts) : String(format: "%.0f W", watts)
    }
}
