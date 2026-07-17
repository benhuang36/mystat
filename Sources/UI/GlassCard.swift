import SwiftUI

// MARK: - Design tokens

extension MonitorType {
    /// Single source of truth for each monitor's accent color,
    /// shared by the settings sidebar and every popover.
    var accentColor: Color {
        switch self {
        case .cpu: return .indigo
        case .memory: return .purple
        case .disk: return .cyan
        case .network: return .blue
        case .battery: return .mint
        case .time: return .orange
        case .display: return .blue
        }
    }
}

enum PopoverStyle {
    /// Popover content width (excluding outer padding)
    static let width: CGFloat = 320
    /// Standard history chart height
    static let chartHeight: CGFloat = 60

    static let rowLabelFont: Font = .system(size: 12, weight: .medium)
    static let rowValueFont: Font = .system(size: 12, weight: .semibold)
}

/// Shared byte-rate formatting (KB/s -> MB/s -> GB/s)
enum ByteFormat {
    static func speed(_ bytesPerSecond: Double) -> String {
        return size(bytesPerSecond) + "/s"
    }

    /// Compact form for narrow columns: "0 K", "34 K", "1.2 M"
    static func compact(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1 { return "0 K" }
        if kb < 1000 { return String(format: "%.0f K", kb) }
        let mb = kb / 1024
        if mb < 1000 { return String(format: "%.1f M", mb) }
        return String(format: "%.1f G", mb / 1024)
    }

    static func size(_ bytes: Double) -> String {
        let kb = bytes / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}

// MARK: - Containers

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

struct CustomDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }
}

// MARK: - Shared popover components

/// Standard popover header row: accent icon + title on the left,
/// prominent value in the middle, settings gear on the right.
struct PopoverHeader: View {
    let type: MonitorType
    var value: String? = nil
    var systemImageOverride: String? = nil
    var accentOverride: Color? = nil

    var body: some View {
        HStack {
            Label(LocalizedStringKey(type.rawValue), systemImage: systemImageOverride ?? type.sfSymbolName)
                .font(.headline)
                .foregroundColor(accentOverride ?? type.accentColor)
                .symbolRenderingMode(.hierarchical)

            Spacer()

            if let value {
                Text(value)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
            }

            Button(action: {
                AppDelegate.shared.openSettings(for: type)
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
    }
}

/// Standard caption-style section title inside a card
struct CardSectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String = "list.dash"
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundColor(color)
    }
}

/// Standard "label ... value" row, with an optional legend dot
struct StatRow: View {
    let label: LocalizedStringKey
    let value: String
    var dotColor: Color? = nil
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 8, height: 8)
            }
            Text(label)
                .font(PopoverStyle.rowLabelFont)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(PopoverStyle.rowValueFont)
                .monospacedDigit()
                .foregroundColor(valueColor)
        }
    }
}

/// One display row of a process list
struct ProcessRowItem: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    var valueColor: Color = .primary
    var pid: Int = 0
}

/// Unified top-process list with app icons. `minRows` pads with blank
/// rows so the popover height stays stable while entries come and go.
struct ProcessListView: View {
    let rows: [ProcessRowItem]
    var minRows: Int = 0

    private static let rowHeight: CGFloat = 17

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Image(nsImage: ProcessIcon.icon(for: row.pid))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text(row.name)
                        .font(PopoverStyle.rowLabelFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(row.value)
                        .font(PopoverStyle.rowValueFont)
                        .monospacedDigit()
                        .foregroundColor(row.valueColor)
                }
                .frame(height: Self.rowHeight)
            }
            ForEach(0..<max(0, minRows - rows.count), id: \.self) { _ in
                HStack {
                    Spacer()
                }
                .frame(height: Self.rowHeight)
            }
        }
    }
}
