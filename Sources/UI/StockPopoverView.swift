import SwiftUI

extension StockColorMode {
    func color(for direction: StockDirection) -> Color {
        guard let nsColor = nsColor(for: direction) else { return .primary }
        return Color(nsColor: nsColor)
    }
}

struct StockPopoverView: View {
    @ObservedObject private var manager = StockQuoteManager.shared

    private var symbol: StockSymbol? { manager.selectedSymbol }
    private var quote: StockQuote? { manager.selectedQuote }

    var body: some View {
        PopoverContainer {
            PopoverTitleBar(
                type: .stock,
                value: quote.map { StockFormat.price($0.price) } ?? "--"
            )

            CustomDivider()

            if let symbol {
                PopoverSection {
                    header(for: symbol, quote: quote)
                }

                if let quote {
                    CustomDivider()
                    PopoverSection {
                        CardSectionHeader(title: "Today", systemImage: "calendar", color: .secondary)
                        todayRows(quote, isIndex: symbol.isIndex)
                    }
                }
            } else {
                PopoverSection {
                    Text("No symbols in the watchlist yet. Add one in Settings.")
                        .font(PopoverStyle.rowLabelFont)
                        .foregroundColor(.secondary)
                }
            }

            if manager.watchlist.count > 1 {
                CustomDivider()
                PopoverSection {
                    CardSectionHeader(title: "Watchlist", systemImage: "list.bullet", color: .secondary)
                    watchlist
                }
            }

            CustomDivider()
            PopoverSection {
                footer
            }
        }
        .onAppear { manager.refreshNow() }
    }

    // MARK: - Selected symbol

    @ViewBuilder
    private func header(for symbol: StockSymbol, quote: StockQuote?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(quote?.name ?? symbol.name)
                .font(.system(size: 14, weight: .semibold))
            Text(symbol.code.uppercased())
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
            Spacer()
            statusBadge(for: quote)
        }

        if let quote {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(StockFormat.price(quote.price))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundColor(manager.colorMode.color(for: quote.direction))

                VStack(alignment: .leading, spacing: 1) {
                    // With no match yet the change is zero only because `price`
                    // is standing in for yesterday's close; the No Trade badge
                    // says what is actually going on.
                    if quote.hasTrade {
                        Text("\(StockFormat.arrow(quote.direction))\(StockFormat.points(quote.change))")
                        Text(StockFormat.percent(quote.changePercent))
                    } else {
                        Text(StockFormat.placeholder)
                    }
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(quote.hasTrade ? manager.colorMode.color(for: quote.direction) : .secondary)

                Spacer()
            }
        } else {
            Text("Waiting for quote…")
                .font(PopoverStyle.rowLabelFont)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func statusBadge(for quote: StockQuote?) -> some View {
        if let quote, !quote.hasTrade {
            badge("No Trade", color: .orange)
        } else if !manager.isMarketOpen {
            badge("Market Closed", color: .secondary)
        } else {
            badge("Live", color: .green)
        }
    }

    private func badge(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }

    // MARK: - Today's numbers

    @ViewBuilder
    private func todayRows(_ quote: StockQuote, isIndex: Bool) -> some View {
        StatRow(label: "Open", value: quote.open.map(StockFormat.price) ?? "--")
        StatRow(label: "High", value: quote.high.map(StockFormat.price) ?? "--")
        StatRow(label: "Low", value: quote.low.map(StockFormat.price) ?? "--")
        StatRow(label: "Previous Close", value: StockFormat.price(quote.previousClose))
        StatRow(label: "Volume (lots)", value: quote.volume.map(StockFormat.lots) ?? "--")

        // Indices have no daily price limit; only equities report u/w.
        if !isIndex, let limitUp = quote.limitUp, let limitDown = quote.limitDown {
            StatRow(label: "Limit Up", value: StockFormat.price(limitUp),
                    valueColor: manager.colorMode.color(for: .up))
            StatRow(label: "Limit Down", value: StockFormat.price(limitDown),
                    valueColor: manager.colorMode.color(for: .down))
        }

        if !quote.tradeTime.isEmpty {
            StatRow(label: "Last Match", value: quote.tradeTime)
        }
    }

    // MARK: - Watchlist

    @ViewBuilder
    private var watchlist: some View {
        VStack(spacing: 0) {
            ForEach(manager.watchlist) { entry in
                StockWatchRow(
                    symbol: entry,
                    quote: manager.quote(for: entry),
                    colorMode: manager.colorMode,
                    isSelected: entry.id == symbol?.id
                ) {
                    manager.selectedID = entry.id
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if let error = manager.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                switch error {
                case .noData:
                    Text("No quote data returned")
                case .network(let description):
                    Text(description)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else if let updated = manager.lastUpdate {
                Text("Updated \(Self.clockFormatter.string(from: updated))")
            } else {
                Text("Waiting for quote…")
            }
            Spacer()
            Text("TWSE")
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// One tappable watchlist entry. Clicking promotes it to the menu bar.
struct StockWatchRow: View {
    let symbol: StockSymbol
    let quote: StockQuote?
    let colorMode: StockColorMode
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "menubar.arrow.up.rectangle" : "circle")
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                .frame(width: 14)

            Text(quote?.name ?? symbol.name)
                .font(PopoverStyle.rowLabelFont)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let quote {
                Text(StockFormat.price(quote.price))
                    .font(PopoverStyle.rowValueFont.monospacedDigit())
                Text(quote.hasTrade ? StockFormat.percent(quote.changePercent) : StockFormat.placeholder)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(quote.hasTrade ? colorMode.color(for: quote.direction) : .secondary)
                    .frame(width: 56, alignment: .trailing)
            } else {
                Text("--")
                    .font(PopoverStyle.rowValueFont)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}
