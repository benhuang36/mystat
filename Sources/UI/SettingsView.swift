import SwiftUI
import ServiceManagement

enum DisplayStyle: String, CaseIterable {
    case icon = "Icon Only"
    case text = "Text"
    case history = "History"
    case pieChart = "Pie Chart"
    case gauge = "Gauge"
    case barChart = "Bar Chart"
    case coreBars = "Core Bars"
    case capacityBar = "Capacity Bar"

    var isGraphical: Bool {
        switch self {
        case .icon, .text: return false
        default: return true
        }
    }

    static func available(for type: MonitorType) -> [DisplayStyle] {
        switch type {
        case .cpu: return [.icon, .text, .history, .coreBars, .barChart, .pieChart, .gauge, .capacityBar]
        case .memory, .disk: return [.icon, .text, .history, .barChart, .pieChart, .gauge, .capacityBar]
        case .network: return [.icon, .text, .history, .barChart, .pieChart, .gauge]
        case .battery: return [.icon, .text, .capacityBar, .gauge, .pieChart, .barChart]
        case .display: return [.icon, .text]
        case .time: return []
        }
    }

    func localizedName(for type: MonitorType) -> LocalizedStringKey {
        switch self {
        case .icon: return "Label / Icon"
        case .text:
            switch type {
            case .display: return "Resolution Text"
            case .network: return "Speed Text"
            default: return "Percentage Text"
            }
        case .history: return "History Graph"
        case .pieChart: return "Pie Chart"
        case .gauge: return "Arc Gauge"
        case .barChart: return "Bar Chart"
        case .coreBars: return "Core Bars"
        case .capacityBar: return "Capacity Bar"
        }
    }
}

enum MenuBarColor: String, CaseIterable {
    case auto = "Auto"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case teal = "Teal"
    case blue = "Blue"
    case indigo = "Indigo"
    case purple = "Purple"
    case pink = "Pink"
    case graphite = "Graphite"

    /// nil means "Auto": each monitor keeps its own default color
    var nsColor: NSColor? {
        switch self {
        case .auto: return nil
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .graphite: return .systemGray
        }
    }

    var swatchColor: Color {
        if let nsColor { return Color(nsColor: nsColor) }
        return .clear
    }
}

enum SettingsSelection: Hashable {
    case general
    case combined
    case monitor(MonitorType)
}

class SettingsNavigationManager: ObservableObject {
    static let shared = SettingsNavigationManager()
    @Published var selection: SettingsSelection? = .general
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNavigationManager.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.selection) {
                NavigationLink(value: SettingsSelection.general) {
                    Label {
                        Text("General")
                    } icon: {
                        SettingsSidebarIcon(systemName: "gearshape.fill", color: .gray)
                    }
                }

                NavigationLink(value: SettingsSelection.combined) {
                    Label {
                        Text("Combined Mode")
                    } icon: {
                        SettingsSidebarIcon(systemName: "rectangle.split.3x1.fill", color: .teal)
                    }
                }

                Section("Monitors") {
                    ForEach(MonitorType.allCases, id: \.self) { type in
                        NavigationLink(value: SettingsSelection.monitor(type)) {
                            Label {
                                Text(LocalizedStringKey(type.rawValue))
                            } icon: {
                                SettingsSidebarIcon(systemName: type.sfSymbolName, color: colorForType(type))
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("MyStat")
            .listStyle(.sidebar)
        } detail: {
            if let selection = nav.selection {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .combined:
                    CombinedSettingsView()
                case .monitor(let type):
                    if type == .time {
                        TimeSettingsView()
                    } else {
                        DetailView(for: type)
                    }
                }
            } else {
                Text("Select a category from the sidebar.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private func colorForType(_ type: MonitorType) -> Color {
        switch type {
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

/// System Settings-style sidebar icon: white glyph on a colored rounded rectangle
struct SettingsSidebarIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 21, height: 21)
            .background(RoundedRectangle(cornerRadius: 5.5).fill(color.gradient))
    }
}

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("appLanguage") private var appLanguage = "system"
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return "v\(version)"
    }

    var body: some View {
        Form {
            Section("System") {
                Toggle("Launch MyStat at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update launch at login status: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .onAppear {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }

            Section("Language") {
                Picker("Language", selection: $appLanguage) {
                    Text("System Default").tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh-Hant")
                }
                .pickerStyle(.menu)
            }

            Section("About") {
                LabeledContent("Version", value: "MyStat \(appVersion)")

                HStack {
                    Text("Quit MyStat")
                    Spacer()
                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// Settings page for Combined Mode (one status item hosting several monitors)
struct CombinedSettingsView: View {
    @AppStorage("combinedModeEnabled") private var combinedEnabled = false
    @AppStorage("combinedSpacing") private var spacing = 8.0
    @State private var order: [MonitorType] = CombinedStatusItemController.orderedTypes

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $combinedEnabled) {
                    Text("Combine into One Item")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            } footer: {
                Label {
                    Text("Shows the enabled monitors side by side in a single menu bar item. Click a section to open its popover.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }

            Section("Layout") {
                Slider(value: $spacing, in: 0...16, step: 1) {
                    Text("Spacing")
                } minimumValueLabel: {
                    Image(systemName: "rectangle.compress.vertical")
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "rectangle.expand.vertical")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!combinedEnabled)

            Section {
                ForEach(order, id: \.self) { type in
                    CombinedItemRow(type: type)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    UserDefaults.standard.set(order.map(\.rawValue), forKey: "combinedOrder")
                }
            } header: {
                Text("Items & Order")
            } footer: {
                Text("Drag to reorder. Each monitor keeps its own menu bar style and \"Show in Menu Bar\" setting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .disabled(!combinedEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Combined Mode")
    }
}

private struct CombinedItemRow: View {
    let type: MonitorType
    @AppStorage private var isShown: Bool

    init(type: MonitorType) {
        self.type = type
        _isShown = AppStorage(wrappedValue: type == .cpu || type == .memory, "show\(type.rawValue)")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            SettingsSidebarIcon(systemName: type.sfSymbolName, color: .teal)
            Text(LocalizedStringKey(type.rawValue))
            Spacer()
            Toggle("", isOn: $isShown)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}

// Settings page for a single monitor
struct DetailView: View {
    let type: MonitorType

    @AppStorage private var isShown: Bool
    @AppStorage private var styleRaw: String
    @AppStorage private var showLabel: Bool
    @AppStorage private var showValue: Bool
    @AppStorage private var chartColor: String
    @AppStorage private var secondaryChartColor: String
    @AppStorage private var gaugeValueInside: Bool
    @AppStorage("displayUIStyle") private var displayUIStyle = "Glass"

    init(for type: MonitorType) {
        self.type = type
        let key = type.rawValue.lowercased()
        let defaultShown = (type == .cpu || type == .memory || type == .display)
        let defaultStyle = (type == .battery ? DisplayStyle.text : DisplayStyle.icon).rawValue
        _isShown = AppStorage(wrappedValue: defaultShown, "show\(type.rawValue)")
        _styleRaw = AppStorage(wrappedValue: defaultStyle, "\(key)DisplayStyle")
        _showLabel = AppStorage(wrappedValue: false, "\(key)ShowLabel")
        _showValue = AppStorage(wrappedValue: false, "\(key)ShowValue")
        _chartColor = AppStorage(wrappedValue: MenuBarColor.auto.rawValue, "\(key)ChartColor")
        _secondaryChartColor = AppStorage(wrappedValue: MenuBarColor.auto.rawValue, "\(key)SecondaryColor")
        _gaugeValueInside = AppStorage(wrappedValue: false, "\(key)GaugeValueInside")
    }

    private var currentStyle: DisplayStyle {
        DisplayStyle(rawValue: styleRaw) ?? .icon
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isShown) {
                    Text("Show in Menu Bar")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Section {
                Picker("Style", selection: $styleRaw) {
                    ForEach(DisplayStyle.available(for: type), id: \.rawValue) { style in
                        Text(style.localizedName(for: type)).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)

                if currentStyle.isGraphical {
                    switch type {
                    case .network:
                        ColorSwatchPicker(selection: $chartColor, label: "Download Color")
                        ColorSwatchPicker(selection: $secondaryChartColor, label: "Upload Color")
                        Toggle("Show speed text", isOn: $showLabel)
                    case .disk where currentStyle == .history:
                        ColorSwatchPicker(selection: $chartColor, label: "Read Color")
                        ColorSwatchPicker(selection: $secondaryChartColor, label: "Write Color")
                        Toggle("Show value", isOn: $showValue)
                        Toggle("Show vertical label", isOn: $showLabel)
                    default:
                        ColorSwatchPicker(selection: $chartColor)
                        Toggle("Show value", isOn: $showValue)
                        if currentStyle == .gauge && showValue {
                            Toggle("Show value inside gauge", isOn: $gaugeValueInside)
                        }
                        Toggle("Show vertical label", isOn: $showLabel)
                    }
                }
            } header: {
                Text("Menu Bar Style")
            } footer: {
                Label {
                    Text("Hold ⌘ (Command) and drag icons in the menu bar to rearrange them.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
            .disabled(!isShown)

            if type == .display {
                Section("Popover") {
                    Picker("Popover Style", selection: $displayUIStyle) {
                        Text("Glassmorphism UI").tag("Glass")
                        Text("Native Menu").tag("Classic")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(LocalizedStringKey(type.rawValue))
    }
}

/// A row of tappable color swatches, iStat-style
struct ColorSwatchPicker: View {
    @Binding var selection: String
    var label: LocalizedStringKey = "Color"

    var body: some View {
        LabeledContent {
            HStack(spacing: 7) {
                ForEach(MenuBarColor.allCases, id: \.rawValue) { color in
                    swatch(for: color)
                }
            }
        } label: {
            Text(label)
        }
    }

    @ViewBuilder
    private func swatch(for color: MenuBarColor) -> some View {
        let isSelected = selection == color.rawValue
        ZStack {
            if color == .auto {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .teal, .blue, .purple, .red],
                        center: .center))
                    .frame(width: 16, height: 16)
            } else {
                Circle()
                    .fill(color.swatchColor)
                    .frame(width: 16, height: 16)
            }

            if isSelected {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 21, height: 21)
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .onTapGesture { selection = color.rawValue }
        .help(Text(LocalizedStringKey(color.rawValue)))
        .accessibilityLabel(Text(LocalizedStringKey(color.rawValue)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
