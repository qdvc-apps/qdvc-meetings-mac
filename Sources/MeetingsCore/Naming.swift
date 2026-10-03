import Foundation

/// File and folder names (docs/FILE_FORMAT.md §2). Every name the app makes
/// uses only `a–z`, `0–9` and `-`, plus `/` between folders and the `.yml`
/// extension.
public enum Naming {
    public static let meetingsFolder = "meetings"
    public static let fileExtension = "yml"

    /// The longest slug made from a title.
    public static let maxSlugLength = 40

    /// Letters that do not decompose into a base letter plus accents.
    private static let specialLetters: [Character: String] = [
        "ß": "ss", "æ": "ae", "œ": "oe", "ø": "o", "ł": "l", "đ": "d", "ð": "d",
        "þ": "th", "ı": "i", "ħ": "h", "ŋ": "n", "ſ": "s",
    ]

    /// Turns arbitrary text into a slug of `a–z`, `0–9` and single `-`:
    ///
    /// 1. lower-case it, and spell out `&` as "and" and `@` as "at";
    /// 2. drop apostrophes, so "Bob's" becomes "bobs";
    /// 3. replace letters such as ß and ø, then remove accents (é → e);
    /// 4. turn every run of other characters into one `-`, and trim `-`
    ///    from both ends;
    /// 5. if longer than `maxLength`, cut it at the last `-` that keeps at
    ///    least half the length (else at `maxLength`), and trim again;
    /// 6. if nothing is left, use `fallback`.
    public static func slugify(_ text: String, maxLength: Int = maxSlugLength, fallback: String = "meeting") -> String {
        var s = text.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "@", with: " at ")
        s.removeAll { $0 == "'" || $0 == "\u{2019}" || $0 == "\u{2018}" || $0 == "`" }
        s = String(s.flatMap { specialLetters[$0] ?? String($0) })
        s = s.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var out = ""
        var pendingDash = false
        for scalar in s.unicodeScalars {
            let isAllowed = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            if isAllowed {
                if pendingDash && !out.isEmpty { out.append("-") }
                pendingDash = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }

        if out.count > maxLength {
            let cut = String(out.prefix(maxLength))
            let nextIsBreak = out.dropFirst(maxLength).first == "-"
            if !nextIsBreak, let dash = cut.lastIndex(of: "-"), cut.distance(from: cut.startIndex, to: dash) >= maxLength / 2 {
                out = String(cut[..<dash])
            } else {
                out = cut
            }
            while out.hasSuffix("-") { out.removeLast() }
        }
        return out.isEmpty ? fallback : out
    }

    /// `yyyy-mm-dd-hhmm-<title-slug>`, at most 56 characters.
    public static func stem(for meeting: Meeting) -> String {
        "\(meeting.date.iso)-\(meeting.time.compact)-\(slugify(meeting.title))"
    }

    /// `meetings/<yyyy>`.
    public static func folder(for meeting: Meeting) -> String {
        "\(meetingsFolder)/\(String(format: "%04d", meeting.date.year))"
    }

    /// Whether the file at `relativePath` already has the right name for
    /// `stem` in `folder`: the same name, or the same name with a collision
    /// suffix (`-2`, `-3`…) added.
    public static func path(_ relativePath: String, fits stem: String, in folder: String) -> Bool {
        let prefix = folder + "/"
        let suffix = "." + fileExtension
        guard relativePath.hasPrefix(prefix), relativePath.hasSuffix(suffix) else { return false }
        let name = String(relativePath.dropFirst(prefix.count).dropLast(suffix.count))
        if name == stem { return true }
        guard name.hasPrefix(stem + "-") else { return false }
        let tail = name.dropFirst(stem.count + 1)
        return !tail.isEmpty && tail.allSatisfy(\.isASCII) && tail.allSatisfy(\.isNumber) && tail.first != "0"
    }

    /// The first free path for `stem` in `folder`: `<stem>.yml`, then
    /// `<stem>-2.yml`, `<stem>-3.yml`…. `taken` holds relative paths
    /// (compared case-insensitively, as on a default macOS volume).
    public static func uniquePath(stem: String, in folder: String, taken: Set<String>) -> String {
        let lowered = Set(taken.map { $0.lowercased() })
        var n = 1
        while true {
            let name = n == 1 ? stem : "\(stem)-\(n)"
            let path = "\(folder)/\(name).\(fileExtension)"
            if !lowered.contains(path.lowercased()) { return path }
            n += 1
        }
    }

    /// The suggested name for an export: `yyyy-mm-dd-<title-slug>-notes.<ext>`.
    public static func exportFileName(for meeting: Meeting, extension ext: String) -> String {
        "\(meeting.date.iso)-\(slugify(meeting.title))-notes.\(ext)"
    }
}
