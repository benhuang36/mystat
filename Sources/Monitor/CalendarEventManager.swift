import Foundation
import EventKit
import Combine
import AppKit

class CalendarEventManager: ObservableObject {
    static let shared = CalendarEventManager()
    private let eventStore = EKEventStore()
    
    @Published var isAuthorized: Bool = false
    @Published var eventsForSelectedDate: [EKEvent] = []
    @Published var eventsForDisplayMonth: [Date: Bool] = [:] // Just tracking if a day has events
    
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("CalendarEventManager init status: \(status.rawValue)")
        DispatchQueue.main.async {
            if #available(macOS 14.0, *) {
                self.isAuthorized = (status == .authorized || status == .fullAccess)
            } else {
                self.isAuthorized = (status == .authorized)
            }
            print("CalendarEventManager isAuthorized set to: \(self.isAuthorized)")
            if self.isAuthorized {
                self.fetchMonthIndicators(for: Date())
                self.fetchEvents(for: Date())
            }
        }
    }
    
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("CalendarEventManager: requestAccess clicked. Current status: \(status.rawValue)")
        
        if status == .denied || status == .restricted {
            print("CalendarEventManager: Status is denied/restricted, opening System Settings...")
            // Open System Settings -> Privacy -> Calendars
            DispatchQueue.main.async {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
                completion(false)
            }
            return
        }
        
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                if let error = error {
                    print("Error requesting calendar access: \(error)")
                }
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    completion(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                if let error = error {
                    print("Error requesting calendar access: \(error)")
                }
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    completion(granted)
                }
            }
        }
    }
    
    func fetchEvents(for date: Date) {
        guard isAuthorized else {
            eventsForSelectedDate = []
            return
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let fetchedEvents = self.eventStore.events(matching: predicate)
            
            DispatchQueue.main.async {
                self.eventsForSelectedDate = fetchedEvents.sorted { $0.startDate < $1.startDate }
            }
        }
    }
    
    func fetchMonthIndicators(for month: Date) {
        guard isAuthorized else {
            eventsForDisplayMonth = [:]
            return
        }
        
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1) else {
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let predicate = self.eventStore.predicateForEvents(withStart: monthFirstWeek.start, end: monthLastWeek.end, calendars: nil)
            let fetchedEvents = self.eventStore.events(matching: predicate)
            
            var indicators: [Date: Bool] = [:]
            for event in fetchedEvents {
                let startOfDay = calendar.startOfDay(for: event.startDate)
                indicators[startOfDay] = true
            }
            
            DispatchQueue.main.async {
                self.eventsForDisplayMonth = indicators
            }
        }
    }
}
