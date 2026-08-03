import SwiftUI

struct CalendarDay {
    let date: Date
    let isCurrentMonth: Bool
}

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    @State private var displayMonth: Date
    @State private var showMonthPicker = false
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
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) { showMonthPicker.toggle() }
                }) {
                    HStack(spacing: 5) {
                        Text(monthYearString(from: displayMonth))
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(showMonthPicker ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

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
            
            // Weekdays + Days Grid (with month/year picker overlay)
            ZStack {
                VStack(spacing: 16) {
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
                }
                .opacity(showMonthPicker ? 0 : 1)

                if showMonthPicker {
                    MonthYearPicker(
                        displayMonth: $displayMonth,
                        onSelectMonth: {
                            withAnimation(.easeInOut(duration: 0.18)) { showMonthPicker = false }
                        }
                    )
                    .transition(.opacity)
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
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(formatEventTime(event.startDate)) - \(formatEventTime(event.endDate))")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        if eventManager.eventsForSelectedDate.count > 4 {
                            (Text("+\(eventManager.eventsForSelectedDate.count - 4)") + Text(" more events"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
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
            showMonthPicker = false
            eventManager.fetchMonthIndicators(for: displayMonth)
            eventManager.fetchEvents(for: selectedDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PopoverDidOpen"))) { _ in
            // Panel is reused across opens, so onAppear won't fire again — reset here.
            showMonthPicker = false
        }
        .onChange(of: displayMonth) { newMonth in
            eventManager.fetchMonthIndicators(for: newMonth)
        }
        .onChange(of: selectedDate) { newDate in
            eventManager.fetchEvents(for: newDate)
            if !calendar.isDate(displayMonth, equalTo: newDate, toGranularity: .month) {
                displayMonth = newDate
            }
        }
    }
    
    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) {
            displayMonth = newMonth
        }
    }
    
    private func generateDays() -> [CalendarDay] {
        var days: [CalendarDay] = []
        
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        // Always render a fixed 6-week grid so the calendar height never changes
        // between months/years (5-week vs 6-week months).
        var currentDate = monthFirstWeek.start
        for _ in 0..<42 {
            let isCurrentMonth = calendar.isDate(currentDate, equalTo: displayMonth, toGranularity: .month)
            days.append(CalendarDay(date: currentDate, isCurrentMonth: isCurrentMonth))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return days
    }
}

struct MonthYearPicker: View {
    @Binding var displayMonth: Date
    let onSelectMonth: () -> Void

    private enum Mode { case month, year }
    @State private var mode: Mode = .month
    @State private var yearPageStart: Int = 0   // first year shown in the 12-year grid

    private struct PickerItem: Identifiable {
        let id: String
        let label: String
        let isSelected: Bool
        let isCurrent: Bool
        let action: () -> Void
    }

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var displayedYear: Int { calendar.component(.year, from: displayMonth) }
    private var displayedMonth: Int { calendar.component(.month, from: displayMonth) }
    private var currentYear: Int { calendar.component(.year, from: Date()) }
    private var currentMonth: Int { calendar.component(.month, from: Date()) }

    var body: some View {
        VStack(spacing: 14) {
            // Header: ‹ [title] › — title toggles month/year mode, arrows page.
            HStack {
                stepperButton(systemName: "chevron.left") { page(-1) }
                Spacer()
                Button(action: toggleMode) {
                    Text(mode == .month ? String(displayedYear) : yearRangeLabel)
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                Spacer()
                stepperButton(systemName: "chevron.right") { page(1) }
            }
            .padding(.horizontal, 4)

            // Grid: months or years, both 3×4 so height stays constant.
            // Single ForEach over uniquely-id'd items to avoid SwiftUI reusing
            // month cells as year cells (id collision) when the mode toggles.
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(gridItems) { item in
                    cell(item)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { yearPageStart = displayedYear - 4 }  // center current year in the grid
    }

    private var gridItems: [PickerItem] {
        if mode == .month {
            return (1...12).map { month in
                PickerItem(
                    id: "m\(month)",
                    label: calendar.shortMonthSymbols[month - 1],
                    isSelected: month == displayedMonth,
                    isCurrent: month == currentMonth && displayedYear == currentYear,
                    action: { select(month: month) }
                )
            }
        } else {
            return (0..<12).map { i in
                let year = yearPageStart + i
                return PickerItem(
                    id: "y\(year)",
                    label: String(year),
                    isSelected: year == displayedYear,
                    isCurrent: year == currentYear,
                    action: { select(year: year) }
                )
            }
        }
    }

    private var yearRangeLabel: String { "\(yearPageStart)–\(yearPageStart + 11)" }

    private func cell(_ item: PickerItem) -> some View {
        Button(action: item.action) {
            Text(item.label)
                .font(.system(size: 13, weight: item.isSelected ? .bold : .medium))
                .monospacedDigit()
                .foregroundColor(item.isSelected ? .white : (item.isCurrent ? .blue : .primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.isSelected ? Color.blue : Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func stepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func toggleMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if mode == .month {
                yearPageStart = displayedYear - 4
                mode = .year
            } else {
                mode = .month
            }
        }
    }

    private func page(_ direction: Int) {
        if mode == .month {
            // Month view: arrows jump a year at a time.
            if let newDate = calendar.date(byAdding: .year, value: direction, to: displayMonth) {
                displayMonth = newDate
            }
        } else {
            // Year view: arrows page 12 years at once.
            yearPageStart += direction * 12
        }
    }

    private func select(month: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: displayMonth)
        components.month = month
        if let newDate = calendar.date(from: components) {
            displayMonth = newDate
        }
        onSelectMonth()
    }

    private func select(year: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: displayMonth)
        components.year = year
        if let newDate = calendar.date(from: components) {
            displayMonth = newDate
        }
        // Return to month grid so the user can confirm the month.
        withAnimation(.easeInOut(duration: 0.15)) { mode = .month }
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
