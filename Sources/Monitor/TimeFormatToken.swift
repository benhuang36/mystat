import Foundation

enum TimeFormatToken: String, Codable, CaseIterable, Identifiable {
    case hour12 = "12 Hour"
    case hour24 = "24 Hour"
    case minute = "Minute"
    case second = "Second"
    case ampm = "AM/PM"
    case dayName = "Day Name"
    case dayNameShort = "Day Name (Short)"
    case dayNumber = "Day Number"
    case monthName = "Month Name"
    case monthNameShort = "Month Name (Short)"
    case monthNumber = "Month Number"
    case year = "Year"
    case yearShort = "Year (Short)"
    case space = "Space"
    case colon = ":"
    case slash = "/"
    case dash = "-"
    
    var id: String { self.rawValue }
    
    var isSeparator: Bool {
        switch self {
        case .space, .colon, .slash, .dash: return true
        default: return false
        }
    }
    
    var displayString: String {
        switch self {
        case .space: return "␣"
        default: return self.rawValue
        }
    }
    
    func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        
        switch self {
        case .hour12:
            formatter.dateFormat = "h"
        case .hour24:
            formatter.dateFormat = "H"
        case .minute:
            formatter.dateFormat = "mm"
        case .second:
            formatter.dateFormat = "ss"
        case .ampm:
            formatter.dateFormat = "a"
        case .dayName:
            formatter.dateFormat = "EEEE"
        case .dayNameShort:
            formatter.dateFormat = "EEE"
        case .dayNumber:
            formatter.dateFormat = "d"
        case .monthName:
            formatter.dateFormat = "MMMM"
        case .monthNameShort:
            formatter.dateFormat = "MMM"
        case .monthNumber:
            formatter.dateFormat = "M"
        case .year:
            formatter.dateFormat = "yyyy"
        case .yearShort:
            formatter.dateFormat = "yy"
        case .space:
            return " "
        case .colon:
            return ":"
        case .slash:
            return "/"
        case .dash:
            return "-"
        }
        
        return formatter.string(from: date)
    }
}

class TimeFormatHelper: ObservableObject {
    static let shared = TimeFormatHelper()
    
    @Published var formatTokens: [TimeFormatToken] = []
    
    private let defaultTokens: [TimeFormatToken] = [.dayNameShort, .space, .hour12, .colon, .minute, .space, .ampm]
    
    init() {
        loadTokens()
    }
    
    func loadTokens() {
        if let data = UserDefaults.standard.data(forKey: "timeFormatTokens"),
           let tokens = try? JSONDecoder().decode([TimeFormatToken].self, from: data) {
            self.formatTokens = tokens.isEmpty ? defaultTokens : tokens
        } else {
            self.formatTokens = defaultTokens
        }
    }
    
    func saveTokens(_ tokens: [TimeFormatToken]) {
        self.formatTokens = tokens
        if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: "timeFormatTokens")
        }
        // Force refresh
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }
    
    func generateTimeString(date: Date = Date()) -> String {
        return formatTokens.map { $0.format(date: date) }.joined()
    }
}
