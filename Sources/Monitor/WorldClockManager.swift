import Foundation
import Combine
import SwiftUI

struct WorldClock: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var timeZoneIdentifier: String
    
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

class WorldClockManager: ObservableObject {
    static let shared = WorldClockManager()
    
    @Published var clocks: [WorldClock] = [] {
        didSet {
            save()
        }
    }
    
    private let defaultsKey = "MyStat_WorldClocks"
    
    init() {
        load()
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([WorldClock].self, from: data) {
            self.clocks = saved
        } else {
            // Default initial state
            self.clocks = [
                WorldClock(name: "Current Location", timeZoneIdentifier: TimeZone.current.identifier),
                WorldClock(name: "New York City", timeZoneIdentifier: "America/New_York"),
                WorldClock(name: "Tokyo", timeZoneIdentifier: "Asia/Tokyo")
            ]
        }
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(clocks) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
