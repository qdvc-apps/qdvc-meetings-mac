import Foundation
import Yams

/// A key this version does not know about, kept so that it survives a save.
public struct ExtraField: Equatable {
    public let key: String
    public let value: Node

    public init(key: String, value: Node) {
        self.key = key
        self.value = value
    }
}

public enum NoteKind: String, CaseIterable, Identifiable {
    case note
    case action
    case decision

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .note: return "Note"
        case .action: return "Action Item"
        case .decision: return "Decision"
        }
    }

    /// Reads the `kind` value, accepting a few spellings people type by hand.
    public init(fileValue: String) {
        let v = fileValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        switch v {
        case "action", "action item", "todo", "to do", "task": self = .action
        case "decision", "decided": self = .decision
        default: self = .note
        }
    }
}

/// One entry in a meeting's notes.
public struct Note: Identifiable, Equatable {
    /// Identifies the note while the app runs; not stored.
    public var id: UUID
    public var text: String
    public var kind: NoteKind
    /// Kept when the note is not an action item, so switching kinds back and
    /// forth loses nothing, but only shown and exported for action items.
    public var assignees: [String]
    public var extras: [ExtraField]

    public init(id: UUID = UUID(), text: String = "", kind: NoteKind = .note,
                assignees: [String] = [], extras: [ExtraField] = []) {
        self.id = id
        self.text = text
        self.kind = kind
        self.assignees = assignees
        self.extras = extras
    }

    public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The assignees that apply: those of an action item, none otherwise.
    public var activeAssignees: [String] { kind == .action ? assignees : [] }
}

/// What a meeting's location text is.
public enum LocationKind: Equatable {
    case none
    case text
    /// A link that is not one of the recognised services.
    case link
    case googleMaps
    case teams
    case zoom

    public var conferencePlatform: ConferencePlatform? {
        switch self {
        case .teams: return .teams
        case .zoom: return .zoom
        default: return nil
        }
    }

    public var isLink: Bool {
        switch self {
        case .link, .googleMaps, .teams, .zoom: return true
        case .none, .text: return false
        }
    }

    /// A short label for lists ("Microsoft Teams"), or nil to show the text.
    public var serviceName: String? {
        switch self {
        case .googleMaps: return "Google Maps"
        case .teams: return "Microsoft Teams"
        case .zoom: return "Zoom"
        case .none, .text, .link: return nil
        }
    }

    /// Classifies a location (docs/FILE_FORMAT.md §3). Matching is
    /// case-insensitive, on the URL's scheme and host.
    public static func of(_ location: String) -> LocationKind {
        let text = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .none }
        guard !text.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }),
              let url = URLComponents(string: text),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else { return .text }
        if scheme == "https" {
            if let teams = host.range(of: "teams"), host[teams.upperBound...].contains("microsoft") {
                return .teams
            }
            if host.contains("zoom") { return .zoom }
            let path = url.path.lowercased()
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if bare.hasPrefix("maps.google.") || bare == "maps.app.goo.gl"
                || (bare.hasPrefix("google.") && path.hasPrefix("/maps"))
                || (bare == "goo.gl" && path.hasPrefix("/maps")) {
                return .googleMaps
            }
        }
        if scheme == "https" || scheme == "http" { return .link }
        return .text
    }
}

/// The teleconference platforms that can carry instructions.
public enum ConferencePlatform: String, CaseIterable, Identifiable {
    case teams
    case zoom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .teams: return "Microsoft Teams"
        case .zoom: return "Zoom"
        }
    }
}

/// One meeting, as stored in `meetings/<yyyy>/<stem>.yml`.
public struct Meeting: Identifiable, Equatable {
    /// Identifies the meeting while the app runs (it survives renames); not
    /// stored.
    public var id: UUID
    /// The file's path relative to the workspace root, or nil before the
    /// meeting is first saved.
    public var relativePath: String?
    public var title: String
    public var date: LocalDate
    public var time: LocalTime
    public var endTime: LocalTime?
    public var location: String
    public var people: [String]
    /// The `description` key.
    public var details: String
    public var notes: [Note]
    public var extras: [ExtraField]

    public init(id: UUID = UUID(), relativePath: String? = nil, title: String, date: LocalDate,
                time: LocalTime, endTime: LocalTime? = nil, location: String = "",
                people: [String] = [], details: String = "", notes: [Note] = [],
                extras: [ExtraField] = []) {
        self.id = id
        self.relativePath = relativePath
        self.title = title
        self.date = date
        self.time = time
        self.endTime = endTime
        self.location = location
        self.people = people
        self.details = details
        self.notes = notes
        self.extras = extras
    }

    public var locationKind: LocationKind { LocationKind.of(location) }

    /// Minutes since 1970-01-01 00:00, for sorting.
    public var sortKey: Int { date.ordinal * 1440 + time.minutesSinceMidnight }

    /// Notes with some text in them.
    public var writtenNotes: [Note] { notes.filter { !$0.isBlank } }

    public var hasNotes: Bool { notes.contains { !$0.isBlank } }

    public var noteCount: Int { writtenNotes.count }
    public var actionItemCount: Int { writtenNotes.filter { $0.kind == .action }.count }
    public var decisionCount: Int { writtenNotes.filter { $0.kind == .decision }.count }

    /// Everyone named in the meeting: its people, then any other assignees.
    public var everyone: [String] {
        People.merge(people + notes.flatMap(\.activeAssignees))
    }

    /// Whether the meeting mentions a person (by `People.key`), as one of its
    /// people or an action item's assignee.
    public func involves(personKey key: String) -> Bool {
        everyone.contains { People.key($0) == key }
    }

    /// Case- and diacritic-insensitive search over every text field.
    public func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.isEmpty { return true }
        var haystack = [title, location, details] + people
        for note in notes {
            haystack.append(note.text)
            haystack.append(contentsOf: note.activeAssignees)
        }
        let joined = haystack.joined(separator: "\n")
        return terms.allSatisfy { joined.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// A copy for Duplicate Meeting: same title, time, location, people and
    /// description a week later, with no notes and a new identity.
    public func duplicated(weeksLater: Int = 1) -> Meeting {
        Meeting(title: title, date: date.adding(days: 7 * weeksLater), time: time, endTime: endTime,
                location: location, people: people, details: details, notes: [], extras: extras)
    }
}

/// The short instructions shown as a callout for each platform
/// (`platforms.yml`).
public struct PlatformInstructions: Equatable {
    public var teams: String
    public var zoom: String
    public var extras: [ExtraField]

    public init(teams: String = "", zoom: String = "", extras: [ExtraField] = []) {
        self.teams = teams
        self.zoom = zoom
        self.extras = extras
    }

    public subscript(platform: ConferencePlatform) -> String {
        get {
            switch platform {
            case .teams: return teams
            case .zoom: return zoom
            }
        }
        set {
            switch platform {
            case .teams: teams = newValue
            case .zoom: zoom = newValue
            }
        }
    }

    /// The suggested maximum, about two sentences.
    public static let suggestedLength = 200
}
