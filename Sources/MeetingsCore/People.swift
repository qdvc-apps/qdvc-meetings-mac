import Foundation

/// Helpers for people's names, which are plain strings.
public enum People {
    /// Trims and collapses runs of whitespace to single spaces.
    public static func normalize(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The comparison key: normalised and lower-cased, so "alice  SMITH" and
    /// "Alice Smith" are the same person.
    public static func key(_ name: String) -> String {
        normalize(name).lowercased()
    }

    /// Normalises, drops empty names and removes later duplicates, keeping
    /// the order.
    public static func merge(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let n = normalize(name)
            guard !n.isEmpty, seen.insert(key(n)).inserted else { continue }
            out.append(n)
        }
        return out
    }

    /// Whether `query` matches the start of the name or of any word in it,
    /// ignoring case and accents ("smi" and "ali" both match "Alice Smith").
    public static func name(_ name: String, matches query: String) -> Bool {
        let q = fold(normalize(query))
        if q.isEmpty { return true }
        let n = fold(name)
        if n.hasPrefix(q) { return true }
        return n.split(whereSeparator: { $0 == " " || $0 == "-" }).contains { $0.hasPrefix(q) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The meeting with every mention of the person `oldKey` (in its people
    /// and in every note's assignees) replaced by `newName`, merging with any
    /// existing mention of `newName`. Nil if the meeting does not mention them.
    public static func renaming(_ meeting: Meeting, from oldKey: String, to newName: String) -> Meeting? {
        let replacement = normalize(newName)
        guard !replacement.isEmpty else { return nil }
        func swap(_ names: [String]) -> [String] {
            merge(names.map { key($0) == oldKey ? replacement : $0 })
        }
        var m = meeting
        m.people = swap(m.people)
        for i in m.notes.indices {
            m.notes[i].assignees = swap(m.notes[i].assignees)
        }
        return m == meeting ? nil : m
    }
}

/// One person in the index.
public struct PersonSummary: Identifiable, Hashable {
    /// `People.key` of the name.
    public let id: String
    /// The most common spelling.
    public let name: String
    /// How many meetings mention the person.
    public let meetingCount: Int
    /// The latest meeting that mentions them.
    public let lastDate: LocalDate
}

/// Everyone who appears in any meeting, as people or as assignees, built
/// from the meetings each time they load.
public struct PeopleIndex {
    public private(set) var all: [PersonSummary] = []
    private var byKey: [String: PersonSummary] = [:]

    public init(meetings: [Meeting]) {
        var spellings: [String: [String: Int]] = [:]
        var counts: [String: Int] = [:]
        var last: [String: LocalDate] = [:]
        for meeting in meetings {
            var seen = Set<String>()
            for name in meeting.people + meeting.notes.flatMap(\.activeAssignees) {
                let n = People.normalize(name)
                guard !n.isEmpty else { continue }
                let k = People.key(n)
                spellings[k, default: [:]][n, default: 0] += 1
                if seen.insert(k).inserted {
                    counts[k, default: 0] += 1
                    if let d = last[k] { last[k] = max(d, meeting.date) } else { last[k] = meeting.date }
                }
            }
        }
        for (k, variants) in spellings {
            // Most common spelling; ties go to the one with more capitals
            // ("Alice Smith" over "alice smith"), then alphabetically.
            let name = variants.max { a, b in
                if a.value != b.value { return a.value < b.value }
                let ca = a.key.filter(\.isUppercase).count, cb = b.key.filter(\.isUppercase).count
                if ca != cb { return ca < cb }
                return a.key > b.key
            }!.key
            byKey[k] = PersonSummary(id: k, name: name, meetingCount: counts[k] ?? 0, lastDate: last[k]!)
        }
        all = byKey.values.sorted {
            $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending
        }
    }

    public var isEmpty: Bool { all.isEmpty }

    public func person(forKey key: String) -> PersonSummary? { byKey[key] }

    /// The index's spelling of a typed name, or the typed name normalised if
    /// the person is new.
    public func canonicalName(_ typed: String) -> String {
        byKey[People.key(typed)]?.name ?? People.normalize(typed)
    }

    /// People whose name matches `query`, most frequent first, then most
    /// recent, then alphabetical; `excluding` holds keys to leave out.
    public func suggestions(matching query: String, excluding: Set<String> = [], limit: Int = 12) -> [PersonSummary] {
        let hits = all.filter { !excluding.contains($0.id) && People.name($0.name, matches: query) }
        let sorted = hits.sorted { a, b in
            if a.meetingCount != b.meetingCount { return a.meetingCount > b.meetingCount }
            if a.lastDate != b.lastDate { return a.lastDate > b.lastDate }
            return a.name.compare(b.name, options: .caseInsensitive) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    /// Suggestions for an action item's assignees: the meeting's own people
    /// first (in the meeting's order), then everyone else.
    public func assigneeSuggestions(matching query: String, meetingPeople: [String],
                                    excluding: Set<String> = [], limit: Int = 12) -> [String] {
        var out: [String] = []
        var used = excluding
        for name in meetingPeople where People.name(name, matches: query) {
            let k = People.key(name)
            if used.insert(k).inserted { out.append(canonicalName(name)) }
        }
        for p in suggestions(matching: query, excluding: used, limit: limit) {
            out.append(p.name)
        }
        return Array(out.prefix(limit))
    }

    /// Short labels for the list: first names where no one else in the index
    /// shares that first name, full names otherwise.
    public func shortName(_ name: String) -> String {
        let n = People.normalize(name)
        guard let first = n.split(separator: " ").first.map(String.init), first.count < n.count else { return n }
        let fk = first.lowercased()
        let clash = all.contains { p in
            p.id != People.key(n) && p.name.split(separator: " ").first.map { $0.lowercased() } == fk
        }
        return clash ? n : first
    }
}
