import SwiftUI

struct CalendarDay {
    let date: Date
    let isCurrentMonth: Bool
}

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    @State private var displayMonth: Date
    @ObservedObject private var eventManager = CalendarEventManager.shared
    
    init(date: Binding<Date>) {
        self._selectedDate = date
        self._displayMonth = State(initialValue: date.wrappedValue)
    }
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 4) {
                Menu {
                    ForEach(1...12, id: \.self) { month in
                        Button(action: { setMonth(month) }) {
                            Text(calendar.monthSymbols[month - 1])
                        }
                    }
                } label: {
                    Text(monthString(from: displayMonth))
                        .font(.system(size: 16, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                
                Menu {
                    let currentYear = calendar.component(.year, from: Date())
                    ForEach((currentYear - 20)...(currentYear + 20), id: \.self) { year in
                        Button(action: { setYear(year) }) {
                            Text(String(year))
                        }
                    }
                } label: {
                    Text(yearString(from: displayMonth))
                        .font(.system(size: 16, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                
                Spacer(minLength: 4)
                
                Button(action: {
                    displayMonth = Date()
                    selectedDate = Date()
                }) {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .layoutPriority(1)
                
                HStack(spacing: 0) {
                    Button(action: { changeMonth(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    
                    Button(action: { changeMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
            }
            .padding(.horizontal, 2)
            
            // Weekdays
            HStack(spacing: 0) {
                ForEach(daysOfWeek.indices, id: \.self) { index in
                    Text(daysOfWeek[index])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days Grid
            let days = generateDays()
            VStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if index < days.count {
                                let day = days[index]
                                let startOfDay = calendar.startOfDay(for: day.date)
                                let hasEvent = eventManager.eventsForDisplayMonth[startOfDay] == true
                                
                                DayCell(
                                    day: day,
                                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate),
                                    isToday: calendar.isDateInToday(day.date),
                                    hasEvent: hasEvent
                                )
                                .onTapGesture {
                                    selectedDate = day.date
                                }
                            } else {
                                Spacer().frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            
            // Events List
            if eventManager.isAuthorized {
                if !eventManager.eventsForSelectedDate.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CustomDivider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(eventManager.eventsForSelectedDate.prefix(4), id: \.eventIdentifier) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: event.calendar.color))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    
                                    if event.isAllDay {
                                        Text("All Day")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    } else {
                                        Text("\(formatEventTime(event.startDate)) - \(formatEventTime(event.endDate))")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                            }
                        }
                        
                        if eventManager.eventsForSelectedDate.count > 4 {
                            (Text("+\(eventManager.eventsForSelectedDate.count - 4)") + Text(" more events"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.leading, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(spacing: 12) {
                    CustomDivider()
                    
                    Button("Enable Calendar Events") {
                        print("Enable Calendar Events Button Tapped!")
                        
                        // Directly open settings just in case TCC is silently failing
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                        
                        eventManager.requestAccess { granted in
                            if granted {
                                eventManager.fetchMonthIndicators(for: displayMonth)
                                eventManager.fetchEvents(for: selectedDate)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            eventManager.fetchMonthIndicators(for: displayMonth)
            eventManager.fetchEvents(for: selectedDate)
        }
        .onChange(of: displayMonth) { newMonth in
            eventManager.fetchMonthIndicators(for: newMonth)
        }
        .onChange(of: selectedDate) { newDate in
            eventManager.fetchEvents(for: newDate)
        }
    }
    
    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func monthString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }
    
    private func yearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }
    
    private func setMonth(_ month: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: displayMonth)
        components.month = month
        if let newDate = calendar.date(from: components) {
            displayMonth = newDate
        }
    }
    
    private func setYear(_ year: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: displayMonth)
        components.year = year
        if let newDate = calendar.date(from: components) {
            displayMonth = newDate
        }
    }
    
    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) {
            displayMonth = newMonth
        }
    }
    
    private func generateDays() -> [CalendarDay] {
        var days: [CalendarDay] = []
        
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1) else {
            return []
        }
        
        var currentDate = monthFirstWeek.start
        let endDate = monthLastWeek.end
        
        while currentDate < endDate {
            let isCurrentMonth = calendar.isDate(currentDate, equalTo: displayMonth, toGranularity: .month)
            days.append(CalendarDay(date: currentDate, isCurrentMonth: isCurrentMonth))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
}

struct DayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isToday: Bool
    let hasEvent: Bool
    
    var body: some View {
        let calendar = Calendar.current
        let dayNumber = calendar.component(.day, from: day.date)
        
        VStack(spacing: 4) {
            Text("\(dayNumber)")
                .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium))
                .foregroundColor(textColor)
                .frame(width: 26, height: 26)
                .background(
                    Group {
                        if isSelected {
                            Circle().fill(Color.blue)
                        } else if isToday {
                            Circle().stroke(Color.blue, lineWidth: 1.5)
                        }
                    }
                )
            
            Circle()
                .fill(hasEvent ? Color.gray.opacity(0.8) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // Cursor for macOS
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if !day.isCurrentMonth {
            return .secondary.opacity(0.3)
        } else if isToday {
            return .blue
        } else {
            return .primary
        }
    }
}
