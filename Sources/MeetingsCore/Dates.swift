import Foundation

/// A calendar day with no time zone (a `yyyy-mm-dd` in a diary), as stored
/// in a meeting file.
public struct LocalDate: Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              day >= 1, day <= LocalDate.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-mm-dd` (surrounding whitespace allowed).
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    public static func today(calendar: Calendar = .current) -> LocalDate {
        LocalDate(Date(), calendar: calendar)
    }

    /// `yyyy-mm-dd`.
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var daysInMonth: Int { LocalDate.daysIn(month: month, year: year) }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The inverse of `ordinal` (`civil_from_days`).
    public init(ordinal: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.month = m
        self.day = d
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(ordinal: ordinal + days)
    }

    /// The same day of the month `months` later (clamped to the month's
    /// length, so 31 January + 1 month is 28 or 29 February).
    public func adding(months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        let y = index / 12
        let m = index % 12 + 1
        return LocalDate(year: y, month: m, day: min(day, LocalDate.daysIn(month: m, year: y)))!
    }

    public var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    /// 1 = Sunday … 7 = Saturday, as Foundation's `Calendar` numbers weekdays.
    public var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        let r = (ordinal + 4) % 7
        return (r < 0 ? r + 7 : r) + 1
    }

    /// The first day of the week containing this day, for a calendar whose
    /// weeks start on `firstWeekday` (1 = Sunday … 7 = Saturday).
    public func startOfWeek(firstWeekday: Int) -> LocalDate {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }

    /// This day at `time` in `calendar`'s time zone.
    public func date(at time: LocalTime = LocalTime(hour: 0, minute: 0)!, calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = time.hour
        c.minute = time.minute
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: TimeInterval(ordinal) * 86400)
    }

    public func isSameMonth(as other: LocalDate) -> Bool {
        year == other.year && month == other.month
    }
}

/// A wall-clock time of day with no time zone, as stored in a meeting file.
public struct LocalTime: Hashable, Comparable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses `H:MM`, `HH:MM` or `HH:MM:SS` (seconds are ignored).
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              (1...2).contains(parts[0].count), parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        if parts.count == 3 {
            guard parts[2].count == 2, let s = Int(parts[2]), (0...59).contains(s) else { return nil }
        }
        self.init(hour: h, minute: m)
    }

    /// The time `date` shows in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.hour = c.hour ?? 0
        self.minute = c.minute ?? 0
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// `HH:MM`, as stored.
    public var text: String { String(format: "%02d:%02d", hour, minute) }

    /// `HHMM`, as used in file names.
    public var compact: String { String(format: "%02d%02d", hour, minute) }

    public var description: String { text }

    public static func < (a: LocalTime, b: LocalTime) -> Bool {
        a.minutesSinceMidnight < b.minutesSinceMidnight
    }

    public func adding(minutes: Int) -> LocalTime {
        let total = ((minutesSinceMidnight + minutes) % 1440 + 1440) % 1440
        return LocalTime(hour: total / 60, minute: total % 60)!
    }
}
