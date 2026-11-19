import Foundation
import Combine
import AppKit

// MARK: - Model

/// One entry in the watchlist. `exchange` is resolved once when the symbol is
/// added (see `StockQuoteManager.resolve`) and stored, so routine refreshes
/// never have to probe both markets.
struct StockSymbol: Codable, Identifiable, Equatable {
    var id = UUID()
    var code: String        // "2330", "t00"
    var exchange: String    // "tse" | "otc"
    var name: String        // "台積電"

    /// The `ex_ch` token the MIS endpoint expects
    var exCh: String { "\(exchange)_\(code).tw" }

    var isIndex: Bool { code.hasPrefix("t") || code.hasPrefix("o") }
}

struct StockQuote: Equatable {
    var code: String
    var name: String
    var price: Double
    var previousClose: Double
    var open: Double?
    var high: Double?
    var low: Double?
    /// Lots traded. MIS reports this as `v` for equities and `m` for indices.
    var volume: Int?
    var limitUp: Double?
    var limitDown: Double?
    var tradeTime: String   // "13:30:00"
    var dataDate: String    // "20260826"
    /// False when MIS reported no matched price yet (`z` == "-"), e.g. during
    /// the pre-open call auction or on an illiquid stock. `price` then falls
    /// back to the last seen intraday price, or to the previous close.
    var hasTrade: Bool

    var change: Double { price - previousClose }
    var changePercent: Double { previousClose == 0 ? 0 : change / previousClose * 100 }
    var direction: StockDirection {
        if change > 0 { return .up }
        if change < 0 { return .down }
        return .flat
    }
}

enum StockDirection: String {
    case up, down, flat
}

// MARK: - Settings enums

enum StockColorMode: String, CaseIterable {
    /// Taiwan/Asia convention, and the default here
    case redUp = "Red Up / Green Down"
    case greenUp = "Green Up / Red Down"
    case none = "No Color"

    func nsColor(for direction: StockDirection) -> NSColor? {
        switch self {
        case .none: return nil
        case .redUp:
            switch direction {
            case .up: return .systemRed
            case .down: return .systemGreen
            case .flat: return nil
            }
        case .greenUp:
            switch direction {
            case .up: return .systemGreen
            case .down: return .systemRed
            case .flat: return nil
            }
        }
    }
}

enum StockChangeFormat: String, CaseIterable {
    case percent = "Percent"
    case points = "Points"
    case both = "Points + Percent"
}

// MARK: - Formatting

enum StockFormat {
    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        // Brokers here round half away from zero; `%.2f` rounds half to even,
        // which would print 2415/2400 as +0.62% where every quote site says 0.63%.
        f.roundingMode = .halfUp
        return f
    }()

    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        f.roundingMode = .halfUp
        return f
    }()

    private static func fixed2(_ value: Double) -> String {
        percentFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static let lotFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    static func price(_ value: Double) -> String {
        priceFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func lots(_ value: Int) -> String {
        lotFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Signed form, for the popover where there is no arrow to carry the sign.
    static func points(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        return sign + price(abs(value))
    }

    static func percent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        return "\(sign)\(fixed2(abs(value)))%"
    }

    /// Magnitude only, for the menu bar where the arrow already shows direction.
    static func pointsMagnitude(_ value: Double) -> String { price(abs(value)) }

    static func percentMagnitude(_ value: Double) -> String {
        "\(fixed2(abs(value)))%"
    }

    /// Stands in wherever MIS has nothing to report yet.
    static let placeholder = "--"

    static func arrow(_ direction: StockDirection) -> String {
        switch direction {
        case .up: return "▲"
        case .down: return "▼"
        case .flat: return ""
        }
    }
}

/// Why the last fetch failed. Kept as a case rather than a rendered string so
/// the popover can localize it through the app's own language setting —
/// `NSLocalizedString` only ever follows the system language.
enum StockFetchError: Equatable {
    case noData
    case network(String)
}

/// What the menu bar item should draw, plus the tint the change deserves.
struct StockMenuBarText: Equatable {
    var text: String
    var color: NSColor?
}

// MARK: - Manager

/// Owns the watchlist and polls TWSE MIS for quotes.
///
/// Deliberately keeps its own timer instead of riding `SystemMonitor`'s 1 Hz
/// tick (same as `WorldClockManager` / `CalendarEventManager`): quotes are the
/// only network-backed monitor, and their cadence is measured in seconds, not
/// milliseconds. Polling is gated hard — see `shouldPoll` — because this app's
/// whole idle-cost story depends on not doing work nobody is looking at.
class StockQuoteManager: ObservableObject {
    static let shared = StockQuoteManager()

    // MARK: Published state

    @Published var watchlist: [StockSymbol] = [] {
        didSet {
            guard !isLoading else { return }
            save()
            pruneQuotes()
            refreshNow(force: true)
        }
    }
    /// Keyed by `StockSymbol.exCh`
    @Published private(set) var quotes: [String: StockQuote] = [:]
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastError: StockFetchError?
    @Published private(set) var isMarketOpen: Bool = false

    // MARK: Keys

    private let watchlistKey = "MyStat_StockWatchlist"
    private let selectionKey = "stockSelectedID"

    // MARK: Private state

    private var isLoading = false
    private var isFetching = false
    private var timer: Timer?
    private var scheduledInterval: TimeInterval = 0
    /// Taipei date (yyyyMMdd) already found to be a non-trading day, so we stop
    /// hammering MIS for the rest of it. Cleared when the date rolls over.
    private var knownHolidayDate: String?
    private var wasVisible = false
    /// Start of the most recent request, used to throttle `refreshNow`.
    private var lastFetchStart: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
        isMarketOpen = Self.isTradingWindow()

        // Style/interval/visibility all live in UserDefaults; one sink covers them.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rescheduleIfNeeded() }
            .store(in: &cancellables)

        scheduleTimer()
        // Seed once at launch even outside market hours, so the menu bar has a
        // closing price to show instead of a placeholder.
        refreshNow()
        wasVisible = isVisible
    }

    // MARK: Selection

    var selectedID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectionKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: selectionKey)
            objectWillChange.send()
        }
    }

    /// The symbol the menu bar shows. Falls back to the first entry so a stale
    /// or missing selection never blanks the item.
    var selectedSymbol: StockSymbol? {
        if let id = selectedID, let match = watchlist.first(where: { $0.id == id }) {
            return match
        }
        return watchlist.first
    }

    var selectedQuote: StockQuote? {
        guard let symbol = selectedSymbol else { return nil }
        return quotes[symbol.exCh]
    }

    func quote(for symbol: StockSymbol) -> StockQuote? { quotes[symbol.exCh] }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = UserDefaults.standard.data(forKey: watchlistKey),
           let saved = try? JSONDecoder().decode([StockSymbol].self, from: data) {
            // Names are re-derived rather than trusted: a list saved before a
            // symbol was added to `shortNames` still holds the long one.
            watchlist = saved.map {
                var symbol = $0
                symbol.name = Self.displayName(code: $0.code, raw: $0.name)
                return symbol
            }
        } else {
            watchlist = [
                StockSymbol(code: "t00", exchange: "tse", name: Self.displayName(code: "t00", raw: "發行量加權股價指數")),
                StockSymbol(code: "2330", exchange: "tse", name: "台積電")
            ]
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(watchlist) {
            UserDefaults.standard.set(data, forKey: watchlistKey)
        }
    }

    private func pruneQuotes() {
        let live = Set(watchlist.map(\.exCh))
        quotes = quotes.filter { live.contains($0.key) }
    }

    // MARK: Watchlist editing

    func add(_ symbol: StockSymbol) {
        guard !watchlist.contains(where: { $0.exCh == symbol.exCh }) else { return }
        watchlist.append(symbol)
        if selectedID == nil { selectedID = symbol.id }
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed = offsets.map { watchlist[$0].id }
        watchlist.remove(atOffsets: offsets)
        if let id = selectedID, removed.contains(id) {
            selectedID = watchlist.first?.id
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        watchlist.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Trading calendar

    static let taipeiTimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

    private static var taipeiCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = taipeiTimeZone
        return cal
    }()

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = taipeiTimeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func taipeiDateKey(_ date: Date = Date()) -> String {
        dateKeyFormatter.string(from: date)
    }

    /// Mon-Fri 08:30-13:35 Taipei. Starts at the 08:30 pre-open call auction and
    /// runs five minutes past the 13:30 close so the final match still lands.
    /// Public holidays aren't on any calendar we have, so they're detected after
    /// the fact from the quote's own date field (see `noteDataDate`).
    static func isTradingWindow(_ date: Date = Date()) -> Bool {
        let parts = taipeiCalendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday) else { return false }
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes >= (8 * 60 + 30) && minutes <= (13 * 60 + 35)
    }

    /// Minutes into the Taipei day, used to delay holiday detection until the
    /// session is unambiguously under way.
    private static func taipeiMinuteOfDay(_ date: Date = Date()) -> Int {
        let parts = taipeiCalendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// MIS keeps serving the previous session's snapshot on public holidays.
    /// Once we're well past the open (09:15) and the payload still carries an
    /// older date, treat today as closed and stand down until tomorrow.
    private func noteDataDate(_ dataDate: String) {
        let today = Self.taipeiDateKey()
        guard !dataDate.isEmpty, dataDate != today else {
            if knownHolidayDate == today { knownHolidayDate = nil }
            return
        }
        if Self.taipeiMinuteOfDay() >= (9 * 60 + 15) {
            knownHolidayDate = today
        }
    }

    private var isKnownHolidayToday: Bool {
        knownHolidayDate == Self.taipeiDateKey()
    }

    // MARK: Polling

    /// Nobody is looking → nothing is fetched. Only the Stock popover counts:
    /// another monitor's popover being open is no reason to reach TWSE while
    /// the Stock item is switched off.
    private var isVisible: Bool {
        UserDefaults.standard.bool(forKey: "showStock")
            || SystemMonitor.shared.openPopoverTypes.contains(.stock)
    }

    private var configuredInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "stockRefreshInterval")
        return stored > 0 ? stored : 10
    }

    private var shouldPoll: Bool {
        isVisible && Self.isTradingWindow() && !isKnownHolidayToday
    }

    /// Live cadence while the session runs; otherwise a cheap 60 s heartbeat
    /// whose only job is to notice the market opening.
    private var desiredInterval: TimeInterval {
        shouldPoll ? configuredInterval : 60
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = desiredInterval
        scheduledInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func rescheduleIfNeeded() {
        let open = Self.isTradingWindow()
        if open != isMarketOpen { isMarketOpen = open }

        // Switching the item on (or opening a popover) outside market hours has
        // to pull the last close once. Without this the menu bar would sit on a
        // placeholder until the next session, since `tick` never fetches while
        // the market is shut.
        let visible = isVisible
        if visible && !wasVisible { refreshNow() }
        wasVisible = visible

        if desiredInterval != scheduledInterval { scheduleTimer() }
    }

    private func tick() {
        rescheduleIfNeeded()
        guard shouldPoll else { return }
        fetch()
    }

    /// Fetches once regardless of the trading window, as long as the item is
    /// actually on screen. Used at launch and when a popover opens.
    ///
    /// `force` additionally bypasses the visibility gate, for the two moments
    /// the user is demonstrably looking at quotes even though the menu bar item
    /// may be switched off: the settings screen, and adding a symbol.
    func refreshNow(force: Bool = false) {
        guard force || isVisible, !isKnownHolidayToday else { return }

        // A popover refreshes on every appear, and appearing is cheap to
        // repeat (open, close, open again). Without a floor, flicking the
        // item on and off would fire a request per flick.
        if !force, let last = lastFetchStart,
           Date().timeIntervalSince(last) < Self.minimumRefreshSpacing {
            return
        }
        fetch()
    }

    /// Shortest gap allowed between two on-demand refreshes.
    private static let minimumRefreshSpacing: TimeInterval = 2

    // MARK: Networking

    private static let endpoint = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp"

    private static func requestURL(exChList: [String]) -> URL? {
        guard !exChList.isEmpty else { return nil }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "ex_ch", value: exChList.joined(separator: "|")),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "delay", value: "0"),
            // Cache-buster: MIS serves the same URL from edge caches otherwise.
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        return components?.url
    }

    private func fetch() {
        guard !isFetching else { return }
        let symbols = watchlist
        guard let url = Self.requestURL(exChList: symbols.map(\.exCh)) else { return }

        isFetching = true
        lastFetchStart = Date()
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            let parsed = data.flatMap { Self.parse($0, against: symbols) }

            DispatchQueue.main.async {
                self.isFetching = false

                guard let parsed, !parsed.isEmpty else {
                    self.lastError = error.map { .network($0.localizedDescription) } ?? .noData
                    return
                }

                self.lastError = nil
                self.lastUpdate = Date()
                for (key, incoming) in parsed {
                    self.quotes[key] = Self.merge(incoming, previous: self.quotes[key])
                }
                if let anyDate = parsed.values.first?.dataDate {
                    self.noteDataDate(anyDate)
                }
            }
        }.resume()
    }

    /// Keeps the last matched price alive across ticks that report no trade, so
    /// an illiquid stock doesn't visibly snap back to yesterday's close.
    private static func merge(_ incoming: StockQuote, previous: StockQuote?) -> StockQuote {
        guard !incoming.hasTrade,
              let previous,
              previous.hasTrade,
              previous.dataDate == incoming.dataDate else { return incoming }
        var merged = incoming
        merged.price = previous.price
        return merged
    }

    // MARK: Parsing

    /// Resolves a bare code to a full symbol by asking MIS for both markets at
    /// once and keeping whichever side answers with a name. Also how an index
    /// like `t00` gets validated.
    func resolve(code rawCode: String, completion: @escaping (StockSymbol?) -> Void) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              let url = Self.requestURL(exChList: ["tse_\(code).tw", "otc_\(code).tw"]) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let symbol = data.flatMap { Self.parseSymbol($0) }
            DispatchQueue.main.async { completion(symbol) }
        }.resume()
    }

    /// MIS reports a handful of indices under their full statutory name, and
    /// 發行量加權股價指數 alone is nine characters — long enough to push the
    /// menu bar item past 200 pt on its own. Everything else it returns is
    /// already short (櫃買指數, 未含金融指數, 台積電), so only the unwieldy ones
    /// are mapped. These are data values, not UI copy: MIS has no English
    /// names, so they stay untranslated like every other symbol name.
    private static let shortNames: [String: String] = [
        "t00": "加權指數"
    ]

    private static func displayName(code: String, raw: String) -> String {
        return shortNames[code.lowercased()] ?? raw
    }

    /// MIS answers a wrong-market guess with a placeholder entry that has no
    /// `n`, so "has a name" is the validity test.
    static func parseSymbol(_ data: Data) -> StockSymbol? {
        for entry in messageArray(data) {
            guard let name = string(entry, "n"), !name.isEmpty,
                  let exchange = string(entry, "ex"),
                  let entryCode = string(entry, "c") else { continue }
            return StockSymbol(code: entryCode, exchange: exchange,
                               name: displayName(code: entryCode, raw: name))
        }
        return nil
    }

    static func parse(_ data: Data, against symbols: [StockSymbol]) -> [String: StockQuote]? {
        let entries = messageArray(data)
        guard !entries.isEmpty else { return nil }

        var byCode: [String: StockSymbol] = [:]
        for symbol in symbols { byCode[symbol.exCh] = symbol }

        var result: [String: StockQuote] = [:]
        for entry in entries {
            guard let code = string(entry, "c"),
                  let exchange = string(entry, "ex") else { continue }
            let key = "\(exchange)_\(code).tw"
            guard let quote = quote(from: entry, code: code, fallbackName: byCode[key]?.name) else { continue }
            result[key] = quote
        }
        return result
    }

    private static func quote(from entry: [String: Any], code: String, fallbackName: String?) -> StockQuote? {
        guard let previousClose = number(entry, "y") else { return nil }
        let matched = number(entry, "z")
        // Indices report lots as `m`; equities as `v`.
        let volume = number(entry, "v") ?? number(entry, "m")

        return StockQuote(
            code: code,
            name: string(entry, "n").map { displayName(code: code, raw: $0) } ?? fallbackName ?? code,
            price: matched ?? previousClose,
            previousClose: previousClose,
            open: number(entry, "o"),
            high: number(entry, "h"),
            low: number(entry, "l"),
            volume: volume.map { Int($0) },
            limitUp: number(entry, "u"),
            limitDown: number(entry, "w"),
            tradeTime: string(entry, "t") ?? "",
            dataDate: string(entry, "d") ?? "",
            hasTrade: matched != nil
        )
    }

    private static func messageArray(_ data: Data) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["msgArray"] as? [[String: Any]] else { return [] }
        return array
    }

    /// MIS types everything as a string and uses "-" for "not available".
    private static func string(_ entry: [String: Any], _ key: String) -> String? {
        guard let value = entry[key] as? String, value != "-", !value.isEmpty else { return nil }
        return value
    }

    private static func number(_ entry: [String: Any], _ key: String) -> Double? {
        guard let value = string(entry, key) else { return nil }
        return Double(value)
    }

    // MARK: Menu bar text

    var colorMode: StockColorMode {
        StockColorMode(rawValue: UserDefaults.standard.string(forKey: "stockColorMode") ?? "")
            ?? .redUp
    }

    var changeFormat: StockChangeFormat {
        StockChangeFormat(rawValue: UserDefaults.standard.string(forKey: "stockChangeFormat") ?? "")
            ?? .percent
    }

    /// Assembles the menu bar string from the user's toggles. Falls back to the
    /// bare price when every part is switched off, so the item is never blank.
    func menuBarText() -> StockMenuBarText {
        guard let symbol = selectedSymbol else {
            return StockMenuBarText(text: NSLocalizedString("No Symbol", comment: ""), color: nil)
        }
        guard let quote = quotes[symbol.exCh] else {
            return StockMenuBarText(text: "\(symbol.name) --", color: nil)
        }

        let defaults = UserDefaults.standard
        return Self.menuBarText(
            for: quote,
            showLabel: defaults.bool(forKey: "stockShowLabel"),
            showValue: defaults.bool(forKey: "stockShowValue"),
            showChange: defaults.bool(forKey: "stockShowChange"),
            changeFormat: changeFormat,
            colorMode: colorMode
        )
    }

    /// The pure half of `menuBarText()`, split out so the offline harness can
    /// exercise every toggle combination without a live manager.
    static func menuBarText(
        for quote: StockQuote,
        showLabel: Bool,
        showValue: Bool,
        showChange: Bool,
        changeFormat: StockChangeFormat,
        colorMode: StockColorMode
    ) -> StockMenuBarText {
        var parts: [String] = []
        if showLabel { parts.append(quote.name) }
        if showValue || (!showLabel && !showChange) { parts.append(StockFormat.price(quote.price)) }
        if showChange {
            // Before the session's first match `price` is only standing in for
            // yesterday's close, so the change works out to exactly zero. Drawn
            // as 0.00 that reads as "flat", which is a different claim from
            // "nothing has traded yet" — say nothing instead.
            if quote.hasTrade {
                let arrow = StockFormat.arrow(quote.direction)
                let signed = arrow.isEmpty
                let points = signed ? StockFormat.points(quote.change) : StockFormat.pointsMagnitude(quote.change)
                let percent = signed ? StockFormat.percent(quote.changePercent) : StockFormat.percentMagnitude(quote.changePercent)
                let body: String
                switch changeFormat {
                case .percent: body = percent
                case .points: body = points
                case .both: body = "\(points) \(percent)"
                }
                parts.append(arrow + body)
            } else {
                parts.append(StockFormat.placeholder)
            }
        }

        return StockMenuBarText(
            text: parts.joined(separator: " "),
            color: quote.hasTrade ? colorMode.nsColor(for: quote.direction) : nil
        )
    }
}
