import SwiftUI
import ServiceManagement

enum DisplayStyle: String, CaseIterable {
    case icon = "Icon Only"
    case text = "Text"
    case history = "History"
    case pieChart = "Pie Chart"
    case gauge = "Gauge"
    case barChart = "Bar Chart"
}

enum SettingsSelection: Hashable {
    case general
    case monitor(MonitorType)
}

struct SettingsView: View {
    @State private var selection: SettingsSelection? = .general
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: SettingsSelection.general) {
                    Label {
                        Text("General")
                    } icon: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.gray)
                    }
                    .font(.headline)
                    .padding(.vertical, 4)
                }
                
                Section("Monitors") {
                    ForEach(MonitorType.allCases, id: \.self) { type in
                        NavigationLink(value: SettingsSelection.monitor(type)) {
                            Label {
                                Text(LocalizedStringKey(type.rawValue))
                            } icon: {
                                Image(systemName: type.sfSymbolName)
                                    .foregroundStyle(colorForType(type))
                            }
                            .font(.headline)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("MyStat")
            .listStyle(.sidebar)
        } detail: {
            if let selection = selection {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .monitor(let type):
                    if type == .time {
                        TimeSettingsView()
                    } else {
                        DetailView(for: type)
                    }
                }
            } else {
                Text("Select a category from the sidebar.")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
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

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("appLanguage") private var appLanguage = "system"
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return "v\(version)"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("General Settings")
                    .font(.system(size: 28, weight: .bold))
                
                Divider()
                
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("System")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        GroupBox {
                            VStack(alignment: .leading, spacing: 15) {
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
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .frame(minWidth: 200, maxWidth: 300)
                    }
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Language")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        GroupBox {
                            Picker("Language", selection: $appLanguage) {
                                Text("System Default").tag("system")
                                Text("English").tag("en")
                                Text("中文").tag("zh-Hant")
                            }
                            .pickerStyle(.menu)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .frame(minWidth: 200, maxWidth: 300)
                    }
                }
                
                Spacer()
                
                Divider()
                
                HStack {
                    Text("MyStat \(appVersion)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Text("Quit MyStat")
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// Extract DetailView for cleaner code
struct DetailView: View {
    let type: MonitorType
    
    // Binding to AppStorage depending on type
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showDisk") private var showDisk = false
    @AppStorage("showNetwork") private var showNetwork = false
    @AppStorage("showBattery") private var showBattery = false
    @AppStorage("showDisplay") private var showDisplay = true
    
    @AppStorage("cpuDisplayStyle") private var cpuDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("memoryDisplayStyle") private var memoryDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("diskDisplayStyle") private var diskDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("networkDisplayStyle") private var networkDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("batteryDisplayStyle") private var batteryDisplayStyle = DisplayStyle.text.rawValue
    @AppStorage("displayDisplayStyle") private var displayDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("displayUIStyle") private var displayUIStyle = "Glass"
    
    @AppStorage("cpuShowLabel") private var cpuShowLabel = false
    @AppStorage("memoryShowLabel") private var memoryShowLabel = false
    @AppStorage("diskShowLabel") private var diskShowLabel = false
    @AppStorage("networkShowLabel") private var networkShowLabel = false
    @AppStorage("batteryShowLabel") private var batteryShowLabel = false
    @AppStorage("displayShowLabel") private var displayShowLabel = false
    
    init(for type: MonitorType) {
        self.type = type
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with big toggle
                HStack {
                    let isOn = binding(for: type)
                    Toggle(isOn: isOn) {
                        Text(LocalizedStringKey(type.rawValue))
                            .font(.system(size: 28, weight: .bold))
                    }
                    .toggleStyle(.switch)
                    Spacer()
                }
                
                Divider()
                
                // Live Preview & Settings Area
                HStack(alignment: .top, spacing: 20) {
                    // Left side: Fake live preview of popover
                    VStack(alignment: .leading) {
                        Text("Live Preview")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        // Render the actual popover view inside a styled container
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.clear)
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                                
                            Group {
                                switch type {
                                case .cpu: CPUPopoverView()
                                case .memory: MemoryPopoverView()
                                case .disk: DiskPopoverView()
                                case .network: NetworkPopoverView()
                                case .battery: BatteryPopoverView()
                                case .display: DisplayPopoverView()
                                case .time: EmptyView() // Should not be reached
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .frame(width: 320)
                        .fixedSize(horizontal: true, vertical: true)
                    }
                    
                    // Right side: Settings controls
                VStack(alignment: .leading, spacing: 15) {
                    Text("Menu Bar Layout")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 15) {
                            if type == .display {
                                Picker("Popover Style", selection: $displayUIStyle) {
                                    Text("Glassmorphism UI").tag("Glass")
                                    Text("Native Menu").tag("Classic")
                                }
                                .pickerStyle(.menu)
                                
                                Divider()
                            }
                            
                            let displayStyleBinding = styleBinding(for: type)
                            
                            Picker("Menu Bar Style", selection: displayStyleBinding) {
                                Text("Label / Icon").tag(DisplayStyle.icon.rawValue)
                                if type == .display {
                                    Text("Resolution Text").tag(DisplayStyle.text.rawValue)
                                } else {
                                    Text("Percentage Text").tag(DisplayStyle.text.rawValue)
                                }
                                
                                if type != .display && type != .battery {
                                    Text("History Graph").tag(DisplayStyle.history.rawValue)
                                    Text("Pie Chart").tag(DisplayStyle.pieChart.rawValue)
                                    Text("Arc Gauge").tag(DisplayStyle.gauge.rawValue)
                                    Text("Bar Chart").tag(DisplayStyle.barChart.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            if type != .display {
                                Divider()
                                
                                let showLabelBinding = labelBinding(for: type)
                                Toggle("Show text label next to chart", isOn: showLabelBinding)
                            }
                        }
                        .padding(8)
                    }
                    .frame(minWidth: 200, maxWidth: 300)
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Hold ⌘ (Command) and drag icons in the menu bar to rearrange them.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                    .frame(minWidth: 200, maxWidth: 300, alignment: .leading)
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func binding(for type: MonitorType) -> Binding<Bool> {
        switch type {
        case .cpu: return $showCPU
        case .memory: return $showMemory
        case .disk: return $showDisk
        case .network: return $showNetwork
        case .battery: return $showBattery
        case .display: return $showDisplay
        case .time: return .constant(false) // Should not be reached
        }
    }
    
    private func styleBinding(for type: MonitorType) -> Binding<String> {
        switch type {
        case .cpu: return $cpuDisplayStyle
        case .memory: return $memoryDisplayStyle
        case .disk: return $diskDisplayStyle
        case .network: return $networkDisplayStyle
        case .battery: return $batteryDisplayStyle
        case .display: return $displayDisplayStyle
        case .time: return .constant("") // Should not be reached
        }
    }
    
    private func labelBinding(for type: MonitorType) -> Binding<Bool> {
        switch type {
        case .cpu: return $cpuShowLabel
        case .memory: return $memoryShowLabel
        case .disk: return $diskShowLabel
        case .network: return $networkShowLabel
        case .battery: return $batteryShowLabel
        case .display: return $displayShowLabel
        case .time: return .constant(false) // Should not be reached
        }
    }
}
