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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: SettingsSelection.general) {
                    Label("General", systemImage: "gearshape")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
                
                Section("Monitors") {
                    ForEach(MonitorType.allCases, id: \.self) { type in
                        NavigationLink(value: SettingsSelection.monitor(type)) {
                            Label(type.rawValue, systemImage: type.sfSymbolName)
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
                    DetailView(for: type)
                }
            } else {
                Text("Select a category from the sidebar.")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Settings")
                .font(.system(size: 28, weight: .bold))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
                Text("System")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Toggle("Launch MyStat at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                if SMAppService.mainApp.status == .notRegistered {
                                    try SMAppService.mainApp.register()
                                }
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
            
            Spacer()
            
            Divider()
            
            HStack {
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

// Extract DetailView for cleaner code
struct DetailView: View {
    let type: MonitorType
    
    // Binding to AppStorage depending on type
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showDisk") private var showDisk = false
    @AppStorage("showNetwork") private var showNetwork = false
    @AppStorage("showBattery") private var showBattery = false
    
    @AppStorage("cpuDisplayStyle") private var cpuDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("memoryDisplayStyle") private var memoryDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("diskDisplayStyle") private var diskDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("networkDisplayStyle") private var networkDisplayStyle = DisplayStyle.icon.rawValue
    @AppStorage("batteryDisplayStyle") private var batteryDisplayStyle = DisplayStyle.text.rawValue
    
    @AppStorage("cpuShowLabel") private var cpuShowLabel = false
    @AppStorage("memoryShowLabel") private var memoryShowLabel = false
    @AppStorage("diskShowLabel") private var diskShowLabel = false
    @AppStorage("networkShowLabel") private var networkShowLabel = false
    @AppStorage("batteryShowLabel") private var batteryShowLabel = false
    
    init(for type: MonitorType) {
        self.type = type
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with big toggle
            HStack {
                let isOn = binding(for: type)
                Toggle(isOn: isOn) {
                    Text(type.rawValue)
                        .font(.system(size: 28, weight: .bold))
                }
                .toggleStyle(.switch)
                Spacer()
            }
            
            Divider()
            
            // Live Preview & Settings Area
            HStack(alignment: .top, spacing: 40) {
                // Left side: Fake live preview of popover
                VStack(alignment: .leading) {
                    Text("Live Preview")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    // Render the actual popover view inside a styled container
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(radius: 5)
                        
                    switch type {
                        case .cpu: CPUPopoverView()
                        case .memory: MemoryPopoverView()
                        case .disk: DiskPopoverView()
                        case .network: NetworkPopoverView()
                        case .battery: BatteryPopoverView()
                        }
                    }
                    .frame(width: 320, height: 400) // Fixed size for preview
                    .clipped()
                }
                
                // Right side: Settings controls
                VStack(alignment: .leading, spacing: 15) {
                    Text("Menu Bar Layout")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    let displayStyleBinding = styleBinding(for: type)
                    
                    Picker("Style", selection: displayStyleBinding) {
                        Text("Label / Icon").tag(DisplayStyle.icon.rawValue)
                        Text("Percentage Text").tag(DisplayStyle.text.rawValue)
                        Text("History Graph").tag(DisplayStyle.history.rawValue)
                        Text("Pie Chart").tag(DisplayStyle.pieChart.rawValue)
                        Text("Arc Gauge").tag(DisplayStyle.gauge.rawValue)
                        Text("Bar Chart").tag(DisplayStyle.barChart.rawValue)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                    
                    let showLabelBinding = labelBinding(for: type)
                    Toggle("Show text label next to chart", isOn: showLabelBinding)
                        .padding(.top, 5)
                    
                    Text("Hold ⌘ (Command) and drag icons in the menu bar to rearrange them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func binding(for type: MonitorType) -> Binding<Bool> {
        switch type {
        case .cpu: return $showCPU
        case .memory: return $showMemory
        case .disk: return $showDisk
        case .network: return $showNetwork
        case .battery: return $showBattery
        }
    }
    
    private func styleBinding(for type: MonitorType) -> Binding<String> {
        switch type {
        case .cpu: return $cpuDisplayStyle
        case .memory: return $memoryDisplayStyle
        case .disk: return $diskDisplayStyle
        case .network: return $networkDisplayStyle
        case .battery: return $batteryDisplayStyle
        }
    }
    
    private func labelBinding(for type: MonitorType) -> Binding<Bool> {
        switch type {
        case .cpu: return $cpuShowLabel
        case .memory: return $memoryShowLabel
        case .disk: return $diskShowLabel
        case .network: return $networkShowLabel
        case .battery: return $batteryShowLabel
        }
    }
}
