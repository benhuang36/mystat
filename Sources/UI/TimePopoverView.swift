import SwiftUI
import Combine

struct TimePopoverView: View {
    @State private var date = Date()
    @State private var calendarSelectedDate = Date()
    @State private var timer: AnyCancellable?
    @ObservedObject private var clockManager = WorldClockManager.shared
    @State private var contentHeight: CGFloat
    
    init() {
        let baseHeight: CGFloat = 420
        let clocksCount = WorldClockManager.shared.clocks.count
        let initialH = baseHeight + CGFloat(clocksCount * 55)
        _contentHeight = State(initialValue: min(initialH, 850))
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let date = timeline.date
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Header Card
                    GlassCard {
                        PopoverHeader(type: .time, value: formatTime(date: date, timeZone: .current))
                    }
                    
                    // Calendar
                    GlassCard {
                        CustomCalendarView(date: $calendarSelectedDate)
                    }
                    
                    // World Clocks
                    GlassCard {
                        VStack(spacing: 8) {
                            ForEach(clockManager.clocks.indices, id: \.self) { index in
                                let clock = clockManager.clocks[index]
                                let tz = clock.timeZone
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(clock.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(formatTime(date: date, timeZone: tz))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    Spacer()
                                    
                                    // Time difference indicator
                                    if !timeDifferenceString(to: tz).isEmpty {
                                        Text(timeDifferenceString(to: tz))
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.blue.opacity(0.7)))
                                    }
                                }
                                
                                if index < clockManager.clocks.count - 1 {
                                    CustomDivider()
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(
                    GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            contentHeight = geo.size.height
                        }
                        return Color.clear
                    }
                )
            }
            .frame(width: PopoverStyle.width)
            .frame(height: min(contentHeight, 850))
            .background(VisualEffectView().ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear {
                calendarSelectedDate = Date()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PopoverDidOpen"))) { notification in
                if let typeRaw = notification.object as? String, typeRaw == MonitorType.time.rawValue {
                    self.calendarSelectedDate = Date()
                }
            }
        }
    }
    
    private func formatTime(date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
    
    private func timeDifferenceString(to timeZone: TimeZone) -> String {
        if timeZone == TimeZone.current { return "" }
        let diffSeconds = timeZone.secondsFromGMT() - TimeZone.current.secondsFromGMT()
        let hours = diffSeconds / 3600
        if hours > 0 {
            return "+\(hours)h"
        } else if hours < 0 {
            return "\(hours)h"
        }
        return ""
    }
}
