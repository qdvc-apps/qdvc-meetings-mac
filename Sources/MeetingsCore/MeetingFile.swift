import Foundation
import Yams

public enum MeetingFileError: Error, Equatable, CustomStringConvertible {
    case invalidYAML(String)
    case notAMapping
    case missingDate
    case invalidDate(String)
    case missingTime
    case invalidTime(String)
    case invalidEndTime(String)

    public var description: String {
        switch self {
        case .invalidYAML(let detail): return "The file is not valid YAML (\(detail))."
        case .notAMapping: return "The file does not hold a YAML mapping."
        case .missingDate: return "The file has no date."
        case .invalidDate(let v): return "The date \u{201C}\(v)\u{201D} is not a yyyy-mm-dd date."
        case .missingTime: return "The file has no time."
        case .invalidTime(let v): return "The time \u{201C}\(v)\u{201D} is not an HH:MM time."
        case .invalidEndTime(let v): return "The end time \u{201C}\(v)\u{201D} is not an HH:MM time."
        }
    }
}

/// Reads and writes meeting files and `platforms.yml`
/// (docs/FILE_FORMAT.md §3–5).
public enum MeetingFile {
    static let meetingKeys = ["title", "date", "time", "end_time", "location", "people", "description", "notes"]
    static let noteKeys = ["text", "kind", "assignees"]

    // MARK: Reading

    public static func parse(_ text: String, relativePath: String? = nil, id: UUID = UUID()) throws -> Meeting {
        let pairs = try mappingPairs(text)
        var values: [String: Node] = [:]
        var extras: [ExtraField] = []
        for (k, v) in pairs {
            if meetingKeys.contains(k) {
                if values[k] == nil { values[k] = v }
            } else {
                extras.append(ExtraField(key: k, value: v))
            }
        }

        guard let dateText = values["date"].flatMap(string) else { throw MeetingFileError.missingDate }
        guard let date = LocalDate(dateText) else { throw MeetingFileError.invalidDate(dateText) }
        guard let timeText = values["time"].flatMap(string) else { throw MeetingFileError.missingTime }
        guard let time = LocalTime(timeText) else { throw MeetingFileError.invalidTime(timeText) }
        var endTime: LocalTime?
        if let endText = values["end_time"].flatMap(string) {
            guard let t = LocalTime(endText) else { throw MeetingFileError.invalidEndTime(endText) }
            endTime = t
        }

        var title = values["title"].flatMap(string).map(oneLine) ?? ""
        if title.isEmpty { title = "Untitled Meeting" }

        let notes = (values["notes"].map(sequence) ?? []).compactMap(parseNote)

        return Meeting(id: id, relativePath: relativePath, title: title, date: date, time: time,
                       endTime: endTime,
                       location: values["location"].flatMap(string).map(oneLine) ?? "",
                       people: People.merge(values["people"].map(strings) ?? []),
                       details: values["description"].flatMap(string) ?? "",
                       notes: notes, extras: extras)
    }

    static func parseNote(_ node: Node) -> Note? {
        if let text = string(node) {
            return Note(text: text)
        }
        guard let mapping = node.mapping else { return nil }
        var values: [String: Node] = [:]
        var extras: [ExtraField] = []
        for (kNode, v) in mapping {
            let k = kNode.string ?? ""
            if noteKeys.contains(k) {
                if values[k] == nil { values[k] = v }
            } else {
                extras.append(ExtraField(key: k, value: v))
            }
        }
        return Note(text: values["text"].flatMap(string) ?? "",
                    kind: values["kind"].flatMap(string).map(NoteKind.init(fileValue:)) ?? .note,
                    assignees: People.merge(values["assignees"].map(strings) ?? []),
                    extras: extras)
    }

    /// The top-level mapping as (key, value) pairs in file order. An empty
    /// file is an empty mapping.
    static func mappingPairs(_ text: String) throws -> [(String, Node)] {
        let node: Node?
        do {
            node = try Yams.compose(yaml: text)
        } catch {
            throw MeetingFileError.invalidYAML(String(describing: error).split(separator: "\n").first.map(String.init) ?? "")
        }
        guard let root = node else { return [] }
        if isNull(root) { return [] }
        guard let mapping = root.mapping else { throw MeetingFileError.notAMapping }
        return mapping.map { ($0.key.string ?? "", $0.value) }
    }

    /// A scalar's text, or nil for null and for non-scalars. Numbers, dates
    /// and booleans are read as written, so `14:00` and `'14:00'` are the same.
    static func string(_ node: Node) -> String? {
        guard let scalar = node.scalar else { return nil }
        if isNull(node) { return nil }
        return scalar.string
    }

    static func isNull(_ node: Node) -> Bool {
        guard let scalar = node.scalar else { return false }
        if scalar.style != .plain && scalar.style != .any { return false }
        return ["", "~", "null", "Null", "NULL"].contains(scalar.string)
    }

    /// A sequence's items; a lone scalar counts as a one-item sequence.
    static func sequence(_ node: Node) -> [Node] {
        if let seq = node.sequence { return Array(seq) }
        if isNull(node) { return [] }
        return [node]
    }

    static func strings(_ node: Node) -> [String] {
        sequence(node).compactMap(string)
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Writing

    /// The file's text: keys in the order `title`, `date`, `time`,
    /// `end_time`, `location`, `people`, `description`, `notes`, then any
    /// unknown keys as read. Empty optional keys and blank notes are left
    /// out.
    public static func render(_ m: Meeting) -> String {
        var pairs: [(Node, Node)] = []
        pairs.append((key("title"), str(oneLine(m.title))))
        pairs.append((key("date"), Node(m.date.iso, Tag(.implicit), .plain)))
        pairs.append((key("time"), Node(m.time.text, Tag(.implicit), .singleQuoted)))
        if let end = m.endTime {
            pairs.append((key("end_time"), Node(end.text, Tag(.implicit), .singleQuoted)))
        }
        let location = oneLine(m.location)
        if !location.isEmpty { pairs.append((key("location"), str(location))) }
        let people = People.merge(m.people)
        if !people.isEmpty { pairs.append((key("people"), Node(people.map(str)))) }
        let details = trimTrailingNewlines(m.details)
        if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pairs.append((key("description"), str(details)))
        }
        let notes = m.notes.filter { !$0.isBlank }.map(renderNote)
        if !notes.isEmpty { pairs.append((key("notes"), Node(notes))) }
        for extra in m.extras { pairs.append((key(extra.key), extra.value)) }
        return emit(Node(pairs))
    }

    static func renderNote(_ n: Note) -> Node {
        var pairs: [(Node, Node)] = [(key("text"), str(trimTrailingNewlines(n.text)))]
        if n.kind != .note { pairs.append((key("kind"), str(n.kind.rawValue))) }
        let assignees = People.merge(n.assignees)
        if !assignees.isEmpty { pairs.append((key("assignees"), Node(assignees.map(str)))) }
        for extra in n.extras { pairs.append((key(extra.key), extra.value)) }
        return Node(pairs)
    }

    static func key(_ k: String) -> Node { Node(k, Tag(.implicit), .plain) }

    /// A string scalar in the plainest style that reads back as the same
    /// string in YAML 1.1 and 1.2 readers: literal (`|`) for several lines,
    /// single-quoted where a plain scalar would read as something else.
    static func str(_ s: String) -> Node {
        if s.contains("\n") { return Node(s, Tag(.implicit), .literal) }
        return Node(s, Tag(.implicit), needsQuotes(s) ? .singleQuoted : .plain)
    }

    static func needsQuotes(_ s: String) -> Bool {
        if s.isEmpty || s != s.trimmingCharacters(in: .whitespaces) { return true }
        let reserved: Set<String> = ["y", "n", "yes", "no", "true", "false", "on", "off", "null", "~"]
        if reserved.contains(s.lowercased()) { return true }
        // Anything starting like a number, date, time or YAML indicator.
        if let first = s.unicodeScalars.first, "0123456789+-.:?!&*#|>'\"%@`,[]{}=".unicodeScalars.contains(first) {
            return true
        }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return true }
        return false
    }

    static func trimTrailingNewlines(_ s: String) -> String {
        var out = s
        while let last = out.last, last.isNewline || last == " " || last == "\t" { out.removeLast() }
        return out
    }

    static func emit(_ node: Node) -> String {
        do {
            return try Yams.serialize(node: node, indent: 2, width: -1, allowUnicode: true, lineBreak: .ln)
        } catch {
            // Serialising a tree built from strings cannot fail in practice.
            return ""
        }
    }

    // MARK: platforms.yml

    public static func parsePlatforms(_ text: String) throws -> PlatformInstructions {
        var result = PlatformInstructions()
        for (k, v) in try mappingPairs(text) {
            if let platform = ConferencePlatform(rawValue: k) {
                result[platform] = string(v).map(trimTrailingNewlines) ?? ""
            } else {
                result.extras.append(ExtraField(key: k, value: v))
            }
        }
        return result
    }

    public static func renderPlatforms(_ p: PlatformInstructions) -> String {
        var pairs: [(Node, Node)] = []
        for platform in ConferencePlatform.allCases {
            let text = trimTrailingNewlines(p[platform].trimmingCharacters(in: .whitespaces))
            if !text.isEmpty { pairs.append((key(platform.rawValue), str(text))) }
        }
        for extra in p.extras { pairs.append((key(extra.key), extra.value)) }
        return pairs.isEmpty ? "{}\n" : emit(Node(pairs))
    }
}
