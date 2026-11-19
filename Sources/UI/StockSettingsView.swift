import SwiftUI

struct StockSettingsView: View {
    @ObservedObject private var manager = StockQuoteManager.shared

    @AppStorage("showStock") private var showStock = false
    @AppStorage("stockShowLabel") private var showLabel = true
    @AppStorage("stockShowValue") private var showValue = true
    @AppStorage("stockShowChange") private var showChange = true
    @AppStorage("stockChangeFormat") private var changeFormat = StockChangeFormat.percent.rawValue
    @AppStorage("stockColorMode") private var colorMode = StockColorMode.redUp.rawValue
    @AppStorage("stockRefreshInterval") private var refreshInterval = 10.0

    @State private var codeInput = ""
    @State private var isResolving = false
    @State private var lookupError: LocalizedStringKey?

    /// Codes nobody would guess but most people want.
    private let quickAdds: [(LocalizedStringKey, String)] = [
        ("TAIEX", "t00"),
        ("TPEx Index", "o00")
    ]

    private let intervals: [Double] = [5, 10, 30, 60]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Toggle(isOn: $showStock) {
                        Text("Stock")
                            .font(.system(size: 28, weight: .bold))
                    }
                    .toggleStyle(.switch)
                    Spacer()
                }

                Divider()

                livePreview
                watchlistSection
                addSection
                menuBarSection
                refreshSection

                Spacer()
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { manager.refreshNow(force: true) }
    }

    // MARK: - Live preview

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Live Preview")
                .font(.headline)
                .foregroundColor(.secondary)

            let rendered = manager.menuBarText()
            HStack {
                Text(rendered.text)
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundColor(rendered.color.map { Color(nsColor: $0) } ?? .primary)
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
    }

    // MARK: - Watchlist

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Watchlist (Select the one to show in the menu bar)")
                .font(.headline)
                .foregroundColor(.secondary)

            List {
                ForEach(manager.watchlist) { symbol in
                    StockSymbolRow(
                        symbol: symbol,
                        quote: manager.quote(for: symbol),
                        isSelected: symbol.id == manager.selectedSymbol?.id,
                        onSelect: { manager.selectedID = symbol.id },
                        onDelete: {
                            if let index = manager.watchlist.firstIndex(where: { $0.id == symbol.id }) {
                                manager.remove(atOffsets: IndexSet(integer: index))
                            }
                        }
                    )
                }
                .onMove { source, destination in
                    manager.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: 160)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Adding symbols

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Stock code (e.g. 2330)", text: $codeInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onSubmit(addTypedCode)

                Button(action: addTypedCode) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .disabled(isResolving || codeInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }

            if let lookupError {
                Text(lookupError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            } else {
                Text("Listed and OTC codes are both accepted; the market is detected automatically.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(quickAdds, id: \.1) { title, code in
                    Button {
                        codeInput = code
                        addTypedCode()
                    } label: {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.gray.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private func addTypedCode() {
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isResolving else { return }

        if manager.watchlist.contains(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) {
            lookupError = "Already in the watchlist."
            return
        }

        isResolving = true
        lookupError = nil
        manager.resolve(code: code) { symbol in
            isResolving = false
            guard let symbol else {
                lookupError = "No such stock code."
                return
            }
            manager.add(symbol)
            codeInput = ""
        }
    }

    // MARK: - Menu bar content

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu Bar")
                .font(.headline)
                .foregroundColor(.secondary)

            Toggle("Show name", isOn: $showLabel)
            Toggle("Show price", isOn: $showValue)
            Toggle("Show change", isOn: $showChange)

            Picker("Change format", selection: $changeFormat) {
                ForEach(StockChangeFormat.allCases, id: \.rawValue) { format in
                    Text(LocalizedStringKey(format.rawValue)).tag(format.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
            .disabled(!showChange)

            Picker("Up / down colors", selection: $colorMode) {
                ForEach(StockColorMode.allCases, id: \.rawValue) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates")
                .font(.headline)
                .foregroundColor(.secondary)

            Picker("Refresh every", selection: $refreshInterval) {
                ForEach(intervals, id: \.self) { seconds in
                    Text(String(format: NSLocalizedString("%ds", comment: "seconds"), Int(seconds)))
                        .tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)

            Text("Quotes are only fetched during Taiwan market hours (Mon–Fri 09:00–13:30). Outside them the last close is shown.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StockSymbolRow: View {
    let symbol: StockSymbol
    let quote: StockQuote?
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
                .opacity(0.5)

            Button(action: onSelect) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            Text(quote?.name ?? symbol.name)
                .font(.system(size: 13, weight: .medium))

            Text(symbol.code.uppercased())
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)

            Spacer()

            if let quote {
                Text(StockFormat.price(quote.price))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
