import SwiftUI

struct DisplayPopoverView: View {
    @ObservedObject var displayManager = DisplayManager.shared
    @State private var expandedDisplayId: CGDirectDisplayID?
    
    var body: some View {
        VStack(spacing: 12) {
            // Header Card
            GlassCard {
                HStack {
                    Label("Displays", systemImage: "display")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .symbolRenderingMode(.hierarchical)
                    
                    Spacer()
                    
                    Button(action: {
                        AppDelegate.shared.openSettings(for: .display)
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
            
            if displayManager.displays.isEmpty {
                Text("No Displays Found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(displayManager.displays) { display in
                    DisplayCard(display: display, isExpanded: Binding(
                        get: { self.expandedDisplayId == display.id },
                        set: { if $0 { self.expandedDisplayId = display.id } else if self.expandedDisplayId == display.id { self.expandedDisplayId = nil } }
                    ))
                }
            }
        }
        .padding()
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct DisplayCard: View {
    @ObservedObject var display: DisplayInfo
    @Binding var isExpanded: Bool
    
    var uniqueResolutions: [DisplayModeInfo] {
        var res = [DisplayModeInfo]()
        var seen = Set<String>()
        for mode in display.availableModes {
            let key = "\(mode.width)x\(mode.height)-\(mode.isHiDPI)"
            if !seen.contains(key) {
                seen.insert(key)
                res.append(mode)
            }
        }
        return res
    }
    
    var availableRefreshRates: [Double] {
        guard let current = display.currentMode else { return [] }
        let rates = display.availableModes
            .filter { $0.width == current.width && $0.height == current.height && $0.isHiDPI == current.isHiDPI }
            .map { round($0.refreshRate) }
        return Array(Set(rates)).sorted(by: >)
    }
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "display")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.name)
                                .font(.system(size: 15, weight: .bold))
                            if let current = display.currentMode {
                                Text("\(current.resolutionString) @ \(String(format: "%.0f Hz", current.refreshRate))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    if let currentMode = display.currentMode {
                        // Refresh Rate Selector
                        HStack {
                            Text("Refresh Rate")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { round(currentMode.refreshRate) },
                                set: { DisplayManager.shared.setRefreshRate(for: display, refreshRate: $0) }
                            )) {
                                ForEach(availableRefreshRates, id: \.self) { rate in
                                    Text(String(format: "%.0f Hz", rate)).tag(rate)
                                }
                            }
                            .frame(width: 100)
                            .labelsHidden()
                        }
                        
                        Text("Resolutions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        // Resolution List
                        let rowHeight: CGFloat = 34
                        let listHeight = min(CGFloat(uniqueResolutions.count) * rowHeight, 250)
                        
                        ScrollView(showsIndicators: true) {
                            VStack(spacing: 0) {
                                ForEach(uniqueResolutions) { mode in
                                    let isSelected = mode.width == currentMode.width && mode.height == currentMode.height && mode.isHiDPI == currentMode.isHiDPI
                                    
                                    Button(action: {
                                        DisplayManager.shared.setResolution(for: display, width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI)
                                    }) {
                                        HStack {
                                            Text(mode.resolutionString)
                                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(isSelected ? .white : .secondary)
                                            
                                            if mode.isHiDPI {
                                                Image(systemName: "bolt.fill")
                                                    .foregroundColor(isSelected ? .yellow : .yellow.opacity(0.6))
                                                    .font(.system(size: 10))
                                            }
                                            
                                            Spacer()
                                            
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                                    .font(.system(size: 12, weight: .bold))
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 10)
                                        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: listHeight)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(12)
        }
    }
}
