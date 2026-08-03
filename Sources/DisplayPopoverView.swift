import SwiftUI

struct DisplayPopoverView: View {
    @ObservedObject var displayManager = DisplayManager.shared

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(type: .display)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if displayManager.displays.isEmpty {
                Text("No Displays Found")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ForEach(Array(displayManager.displays.enumerated()), id: \.element.id) { index, display in
                    CustomDivider()
                    DisplaySection(display: display)
                }
            }
        }
        .frame(width: PopoverStyle.width)
        .background(VisualEffectView(cornerRadius: 12).ignoresSafeArea())
    }
}

/// One display's controls: name + Main badge, then Resolution and Refresh Rate
/// as native menu pickers. No expand/collapse — the section is fixed height.
struct DisplaySection: View {
    @ObservedObject var display: DisplayInfo

    /// Unique resolutions (deduped across refresh rate / duplicate modes).
    private var uniqueResolutions: [DisplayModeInfo] {
        var res = [DisplayModeInfo]()
        var seen = Set<String>()
        for mode in display.availableModes {
            let key = resolutionKey(width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI)
            if !seen.contains(key) {
                seen.insert(key)
                res.append(mode)
            }
        }
        return res
    }

    /// Refresh rates available for the currently selected resolution.
    private var availableRefreshRates: [Double] {
        guard let current = display.currentMode else { return [] }
        let rates = display.availableModes
            .filter { $0.width == current.width && $0.height == current.height && $0.isHiDPI == current.isHiDPI }
            .map { round($0.refreshRate) }
        return Array(Set(rates)).sorted(by: >)
    }

    private func resolutionKey(width: Int, height: Int, isHiDPI: Bool) -> String {
        "\(width)x\(height)-\(isHiDPI)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name row
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MonitorType.display.accentColor)
                Text(display.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if display.isMain {
                    Text("Main")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(MonitorType.display.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(MonitorType.display.accentColor.opacity(0.18))
                        )
                }
                Spacer(minLength: 0)
            }

            if let currentMode = display.currentMode {
                // Resolution
                controlRow(label: "Resolution") {
                    Picker("", selection: Binding(
                        get: { resolutionKey(width: currentMode.width, height: currentMode.height, isHiDPI: currentMode.isHiDPI) },
                        set: { key in
                            if let mode = uniqueResolutions.first(where: {
                                resolutionKey(width: $0.width, height: $0.height, isHiDPI: $0.isHiDPI) == key
                            }) {
                                DisplayManager.shared.setResolution(for: display, width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI)
                            }
                        }
                    )) {
                        ForEach(uniqueResolutions) { mode in
                            resolutionLabel(mode)
                                .tag(resolutionKey(width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                // Refresh rate
                controlRow(label: "Refresh Rate") {
                    Picker("", selection: Binding(
                        get: { round(currentMode.refreshRate) },
                        set: { DisplayManager.shared.setRefreshRate(for: display, refreshRate: $0) }
                    )) {
                        ForEach(availableRefreshRates, id: \.self) { rate in
                            Text(String(format: "%.0f Hz", rate)).tag(rate)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A "label ............ control" row shared by both pickers.
    private func controlRow<Control: View>(label: LocalizedStringKey, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            control()
        }
    }

    /// Resolution menu entry: "2560 x 1440" plus a bolt for HiDPI modes.
    private func resolutionLabel(_ mode: DisplayModeInfo) -> Text {
        if mode.isHiDPI {
            return Text(mode.resolutionString + "  ") + Text(Image(systemName: "bolt.fill"))
        }
        return Text(mode.resolutionString)
    }
}
