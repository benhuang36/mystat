import SwiftUI

struct TimeSettingsView: View {
    @ObservedObject var formatHelper = TimeFormatHelper.shared
    @State private var previewDate = Date()
    @State private var timer: Timer?
    @State private var draggedIndex: Int?
    
    // Grouping tokens for the palette
    let tokenGroups: [(String, [TimeFormatToken])] = [
        ("Time", [.hour12, .hour24, .minute, .second, .ampm]),
        ("Date", [.dayName, .dayNameShort, .dayNumber, .monthName, .monthNameShort, .monthNumber, .year, .yearShort]),
        ("Separators", [.space, .colon, .slash, .dash])
    ]
    
    
    @AppStorage("showTime") private var showTime = true
    @ObservedObject private var clockManager = WorldClockManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            HStack {
                Toggle(isOn: $showTime) {
                    Text("Time")
                        .font(.system(size: 28, weight: .bold))
                }
                .toggleStyle(.switch)
                Spacer()
            }
            
            Divider()
            
            // Live Preview
            VStack(alignment: .leading, spacing: 5) {
                Text("Live Preview")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(formatHelper.generateTimeString(date: previewDate))
                        .font(.system(size: 24, weight: .medium, design: .default))
                        .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            
            // Current Format (Active Tokens)
            VStack(alignment: .leading, spacing: 5) {
                Text("Current Format (Click to remove, drag to reorder)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    if formatHelper.formatTokens.isEmpty {
                        Text("No format specified")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(formatHelper.formatTokens.indices, id: \.self) { index in
                            let token = formatHelper.formatTokens[index]
                            Button(action: {
                                var newTokens = formatHelper.formatTokens
                                newTokens.remove(at: index)
                                formatHelper.saveTokens(newTokens)
                            }) {
                                Text(LocalizedStringKey(token.displayString))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onDrag {
                                self.draggedIndex = index
                                return NSItemProvider(object: NSString(string: "\(index)"))
                            }
                            .onDrop(of: [.text], delegate: TokenDropDelegate(itemIndex: index, tokens: $formatHelper.formatTokens, draggedIndex: $draggedIndex, saveAction: {
                                formatHelper.saveTokens(formatHelper.formatTokens)
                            }))
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .animation(.default, value: formatHelper.formatTokens.map { $0.rawValue })
                
                HStack {
                    Spacer()
                    Button("Clear All") {
                        formatHelper.saveTokens([])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Token Palette
            VStack(alignment: .leading, spacing: 15) {
                Text("Available Tokens (Click to add)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ForEach(tokenGroups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(group.0))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Using a simple wrapping layout or just ScrollView if too many
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(group.1) { token in
                                    Button(action: {
                                        var newTokens = formatHelper.formatTokens
                                        newTokens.append(token)
                                        formatHelper.saveTokens(newTokens)
                                    }) {
                                        Text(LocalizedStringKey(token.displayString))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundColor(.primary)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            // World Clocks Section
            VStack(alignment: .leading, spacing: 5) {
                Text("World Clocks (Drag to reorder)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach($clockManager.clocks) { $clock in
                        WorldClockRow(clock: $clock, onDelete: {
                            if let index = clockManager.clocks.firstIndex(where: { $0.id == clock.id }) {
                                clockManager.clocks.remove(at: index)
                            }
                        })
                    }
                    .onMove { source, destination in
                        clockManager.clocks.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .frame(height: 180)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                
                Button(action: {
                    clockManager.clocks.append(WorldClock(name: "New City", timeZoneIdentifier: "UTC"))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add World Clock")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                previewDate = Date()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct TokenDropDelegate: DropDelegate {
    let itemIndex: Int
    @Binding var tokens: [TimeFormatToken]
    @Binding var draggedIndex: Int?
    let saveAction: () -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggedIndex = nil
        saveAction()
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedIndex = self.draggedIndex,
              draggedIndex != itemIndex,
              tokens.indices.contains(draggedIndex),
              tokens.indices.contains(itemIndex) else { return }
        
        withAnimation(.default) {
            let item = tokens.remove(at: draggedIndex)
            tokens.insert(item, at: itemIndex)
            self.draggedIndex = itemIndex
        }
    }
}

struct TimeZonePicker: View {
    @Binding var selection: String
    @State private var showPopover = false
    @State private var searchText = ""
    
    var filteredTimeZones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        if searchText.isEmpty {
            return all
        } else {
            let lowerSearch = searchText.lowercased()
            return all.filter { tz in
                if tz.localizedCaseInsensitiveContains(searchText) { return true }
                
                if let countryCode = timezoneCountryMap[tz] {
                    let englishLocale = Locale(identifier: "en_US")
                    if let englishName = englishLocale.localizedString(forRegionCode: countryCode),
                       englishName.lowercased().contains(lowerSearch) {
                        return true
                    }
                    
                    let currentLocale = Locale.current
                    if let localName = currentLocale.localizedString(forRegionCode: countryCode),
                       localName.lowercased().contains(lowerSearch) {
                        return true
                    }
                }
                
                return false
            }
        }
    }
    
    var body: some View {
        Button(action: {
            showPopover.toggle()
        }) {
            HStack {
                Text(selection.isEmpty ? "Select Time Zone" : selection)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search timezone...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(12)
                
                Divider()
                
                // List
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredTimeZones, id: \.self) { tz in
                            Button(action: {
                                selection = tz
                                showPopover = false
                                searchText = ""
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tz)
                                            .font(.system(size: 13))
                                            .foregroundColor(.primary)
                                        if let code = timezoneCountryMap[tz], let countryName = Locale.current.localizedString(forRegionCode: code) {
                                            Text(countryName)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if tz == selection {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .frame(width: 250, height: 250)
            }
        }
    }
}

struct WorldClockRow: View {
    @Binding var clock: WorldClock
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
                .opacity(0.5)
            
            TextField("City Name", text: $clock.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: 150)
            
            Spacer()
            
            TimeZonePicker(selection: $clock.timeZoneIdentifier)
                .frame(width: 220)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}
