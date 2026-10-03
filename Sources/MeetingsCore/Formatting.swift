import Foundation

/// A date heading in the meeting list.
public struct DateBucket: Hashable, Identifiable {
    public let id: String
    public let title: String

    /// Whether every meeting under the heading is on the same day (Today,
    /// Tomorrow, Yesterday, a weekday), so rows need only show the time.
    public var isSingleDay: Bool {
        id == "today" || id == "tomorrow" || id == "yesterday" || id.hasPrefix("day-")
    }
}

/// Puts days under the list's headings: Today, Tomorrow, the rest of this
/// week by weekday, Next Week, Later This Month, then month names; and
/// Yesterday, earlier this week by weekday, Last Week, Earlier This Month,
/// then month names, for the past. Months outside the current year carry
/// the year.
public struct DateBucketer {
    public let today: LocalDate
    public let calendar: Calendar

    public init(today: LocalDate, calendar: Calendar = .current) {
        self.today = today
        self.calendar = calendar
    }

    public func bucket(for day: LocalDate) -> DateBucket {
        let weekStart = today.startOfWeek(firstWeekday: calendar.firstWeekday)
        let weekEnd = weekStart.adding(days: 6)
        if day == today { return DateBucket(id: "today", title: "Today") }
        if day == today.adding(days: 1) { return DateBucket(id: "tomorrow", title: "Tomorrow") }
        if day == today.adding(days: -1) { return DateBucket(id: "yesterday", title: "Yesterday") }
        if day > today {
            if day <= weekEnd { return weekdayBucket(day) }
            if day <= weekEnd.adding(days: 7) { return DateBucket(id: "next-week", title: "Next Week") }
            if day.isSameMonth(as: today) { return DateBucket(id: "later-this-month", title: "Later This Month") }
        } else {
            if day >= weekStart { return weekdayBucket(day) }
            if day >= weekStart.adding(days: -7) { return DateBucket(id: "last-week", title: "Last Week") }
            if day.isSameMonth(as: today) { return DateBucket(id: "earlier-this-month", title: "Earlier This Month") }
        }
        return monthBucket(day)
    }

    private func weekdayBucket(_ day: LocalDate) -> DateBucket {
        let symbols = calendar.weekdaySymbols
        let name = symbols.indices.contains(day.weekday - 1) ? symbols[day.weekday - 1] : day.iso
        return DateBucket(id: "day-\(day.iso)", title: name)
    }

    private func monthBucket(_ day: LocalDate) -> DateBucket {
        let symbols = calendar.monthSymbols
        let name = symbols.indices.contains(day.month - 1) ? symbols[day.month - 1] : String(day.month)
        let title = day.year == today.year ? name : "\(name) \(day.year)"
        return DateBucket(id: String(format: "month-%04d-%02d", day.year, day.month), title: title)
    }
}

/// How dates and times are written in the app and in exports. Times use the
/// locale's short time style (14:00, or 2:00 PM).
public struct MeetingFormatter {
    public let locale: Locale
    private let cache = FormatterCache()

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        c.locale = locale
        return c
    }

    private func formatter(template: String) -> DateFormatter {
        if let f = cache.formatters[template] { return f }
        let f = makeFormatter(template: template)
        cache.formatters[template] = f
        return f
    }

    private func makeFormatter(template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = utcCalendar
        f.timeZone = utc
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// "Monday 5 October 2026" (or the locale's equivalent).
    public func longDate(_ d: LocalDate) -> String {
        formatter(template: "EEEEdMMMMyyyy").string(from: d.date(calendar: utcCalendar))
    }

    /// "Mon 5 Oct 2026".
    public func mediumDate(_ d: LocalDate) -> String {
        formatter(template: "EEEdMMMyyyy").string(from: d.date(calendar: utcCalendar))
    }

    /// "Mon 5 Oct".
    public func shortDate(_ d: LocalDate) -> String {
        formatter(template: "EEEdMMM").string(from: d.date(calendar: utcCalendar))
    }

    /// "October 2026".
    public func monthTitle(_ d: LocalDate) -> String {
        formatter(template: "MMMMyyyy").string(from: d.date(calendar: utcCalendar))
    }

    public func time(_ t: LocalTime) -> String {
        let f: DateFormatter
        if let cached = cache.formatters["time"] {
            f = cached
        } else {
            f = DateFormatter()
            f.locale = locale
            f.calendar = utcCalendar
            f.timeZone = utc
            f.dateStyle = .none
            f.timeStyle = .short
            cache.formatters["time"] = f
        }
        let day = LocalDate(year: 2000, month: 1, day: 1)!
        return f.string(from: day.date(at: t, calendar: utcCalendar))
    }

    /// "14:00–15:00", or "14:00" with no end time.
    public func timeRange(_ m: Meeting, dash: String = "\u{2013}") -> String {
        guard let end = m.endTime else { return time(m.time) }
        return time(m.time) + dash + time(end)
    }

    /// "Monday 5 October 2026, 14:00–15:00".
    public func when(_ m: Meeting, separator: String = ", ", dash: String = "\u{2013}") -> String {
        longDate(m.date) + separator + timeRange(m, dash: dash)
    }

    /// The location as one line for exports: "Microsoft Teams (https://…)",
    /// or the text itself.
    public func locationLine(_ m: Meeting) -> String {
        let loc = m.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let service = m.locationKind.serviceName { return "\(service) (\(loc))" }
        return loc
    }
}

/// Formatters are slow to make, so each MeetingFormatter keeps the ones it
/// has made. Used from one thread at a time (the main thread, in the app).
final class FormatterCache {
    var formatters: [String: DateFormatter] = [:]
}
