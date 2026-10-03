import Foundation

/// The content every export shares (docs/DESIGN.md §7): a header, the notes
/// in their order with decisions and action items labelled, and a recap of
/// the action items.
public struct ExportContent {
    public struct Item {
        public let kind: NoteKind
        public let text: String
        public let assignees: [String]
    }

    public let title: String
    public let when: String
    public let location: String
    public let locationURL: String?
    public let people: [String]
    public let details: String
    public let items: [Item]

    public var actionItems: [Item] { items.filter { $0.kind == .action } }

    public init(_ m: Meeting, formatter: MeetingFormatter, plain: Bool = false) {
        title = m.title
        let rangeDash = plain ? "-" : "\u{2013}"
        when = ExportContent.tidySpaces(formatter.when(m, dash: rangeDash))
        location = formatter.locationLine(m)
        locationURL = m.locationKind.isLink ? m.location.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        people = People.merge(m.people)
        details = m.details.trimmingCharacters(in: .whitespacesAndNewlines)
        items = m.writtenNotes.map {
            Item(kind: $0.kind, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                 assignees: People.merge($0.activeAssignees))
        }
    }

    /// Date formatters use no-break and narrow no-break spaces (as in
    /// "2:00 PM"), which some mail clients show oddly; use plain spaces.
    static func tidySpaces(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

public enum NotesExport {
    /// Plain text for pasting into an email.
    public static func plainText(_ m: Meeting, formatter: MeetingFormatter = MeetingFormatter()) -> String {
        let c = ExportContent(m, formatter: formatter, plain: true)
        var lines: [String] = [c.title, c.when]
        if !c.location.isEmpty { lines.append("Location: \(c.location)") }
        if !c.people.isEmpty { lines.append("People: \(c.people.joined(separator: ", "))") }
        if !c.details.isEmpty {
            lines.append("")
            lines.append(c.details)
        }
        lines.append("")
        lines.append("Notes")
        if c.items.isEmpty {
            lines.append("No notes.")
        } else {
            for item in c.items {
                lines.append(bullet(label(item, plain: true) + item.text))
            }
        }
        let actions = c.actionItems
        if !actions.isEmpty {
            lines.append("")
            lines.append("Action items")
            for item in actions {
                lines.append(bullet(owner(item) + ": " + item.text))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Markdown, with the title as a level-1 heading.
    public static func markdown(_ m: Meeting, formatter: MeetingFormatter = MeetingFormatter()) -> String {
        let c = ExportContent(m, formatter: formatter)
        var lines: [String] = ["# \(oneLine(c.title))", ""]
        lines.append("- **When:** \(c.when)")
        if !c.location.isEmpty {
            if let url = c.locationURL {
                let service = m.locationKind.serviceName ?? url
                lines.append("- **Location:** [\(escapeLinkText(service))](\(url))")
            } else {
                lines.append("- **Location:** \(c.location)")
            }
        }
        if !c.people.isEmpty { lines.append("- **People:** \(c.people.joined(separator: ", "))") }
        if !c.details.isEmpty {
            lines.append("")
            lines.append(c.details)
        }
        lines.append("")
        lines.append("## Notes")
        lines.append("")
        if c.items.isEmpty {
            lines.append("No notes.")
        } else {
            for item in c.items {
                let l = label(item, plain: false)
                lines.append(bullet((l.isEmpty ? "" : "**\(l.dropLast())** ") + item.text))
            }
        }
        let actions = c.actionItems
        if !actions.isEmpty {
            lines.append("")
            lines.append("## Action items")
            lines.append("")
            for item in actions {
                lines.append(bullet("**\(owner(item)):** " + item.text))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "DECISION: ", "ACTION (Alice Smith): " in plain text; "Decision: ",
    /// "Action (Alice Smith): " otherwise; "" for a plain note.
    static func label(_ item: ExportContent.Item, plain: Bool) -> String {
        switch item.kind {
        case .note:
            return ""
        case .decision:
            return plain ? "DECISION: " : "Decision: "
        case .action:
            let base = plain ? "ACTION" : "Action"
            return item.assignees.isEmpty ? "\(base): " : "\(base) (\(item.assignees.joined(separator: ", "))): "
        }
    }

    static func owner(_ item: ExportContent.Item) -> String {
        item.assignees.isEmpty ? "Unassigned" : item.assignees.joined(separator: ", ")
    }

    /// "- " and the text, with any further lines indented to line up.
    static func bullet(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return "- " + lines.map(String.init).joined(separator: "\n  ")
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    static func escapeLinkText(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
