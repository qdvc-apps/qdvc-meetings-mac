import Foundation

/// A meeting file that could not be read.
public struct LoadFailure: Equatable, Identifiable {
    public var id: String { relativePath }
    public let relativePath: String
    public let message: String
}

/// The result of reading the workspace.
public struct LoadResult {
    public let meetings: [Meeting]
    public let failures: [LoadFailure]
}

/// A workspace folder (docs/FILE_FORMAT.md §1). Every write is atomic and
/// immediate. Reads are cached by modification date and size, so a refresh
/// re-parses only files that changed on disk.
public final class Workspace {
    public let root: URL
    public static let platformsFile = "platforms.yml"

    private struct Stamp: Equatable {
        let modified: Date?
        let size: Int?
    }

    private var cache: [String: (stamp: Stamp, meeting: Meeting)] = [:]
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Whether the folder already holds a `meetings` folder.
    public static func looksLikeWorkspace(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let path = url.appendingPathComponent(Naming.meetingsFolder).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Creates `meetings/` if it is missing.
    public func ensureLayout() throws {
        try fm.createDirectory(at: root.appendingPathComponent(Naming.meetingsFolder), withIntermediateDirectories: true)
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    // MARK: Reading

    /// Every `*.yml` (or `*.yaml`) file under `meetings/`, as sorted relative
    /// paths. Hidden files and folders are skipped.
    public func meetingPaths() -> [String] {
        let base = root.appendingPathComponent(Naming.meetingsFolder)
        guard let e = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey],
                                    options: [.skipsHiddenFiles]) else { return [] }
        let prefix = base.standardizedFileURL.resolvingSymlinksInPath().path
        var out: [String] = []
        for case let url as URL in e {
            let ext = url.pathExtension.lowercased()
            guard ext == "yml" || ext == "yaml" else { continue }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile == true else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(prefix + "/") else { continue }
            out.append(Naming.meetingsFolder + "/" + String(full.dropFirst(prefix.count + 1)))
        }
        return out.sorted()
    }

    private func stamp(_ relativePath: String) -> Stamp {
        let attrs = try? fm.attributesOfItem(atPath: url(for: relativePath).path)
        return Stamp(modified: attrs?[.modificationDate] as? Date,
                     size: (attrs?[.size] as? NSNumber)?.intValue)
    }

    /// Reads every meeting, re-parsing only files that changed since the last
    /// load. A meeting keeps its `id` across loads while its path is the same.
    public func load() -> LoadResult {
        var meetings: [Meeting] = []
        var failures: [LoadFailure] = []
        var seen = Set<String>()
        for path in meetingPaths() {
            seen.insert(path)
            let s = stamp(path)
            if let cached = cache[path], cached.stamp == s {
                meetings.append(cached.meeting)
                continue
            }
            do {
                let data = try Data(contentsOf: url(for: path))
                guard let text = String(data: data, encoding: .utf8) else {
                    throw MeetingFileError.invalidYAML("not UTF-8 text")
                }
                let id = cache[path]?.meeting.id ?? UUID()
                let meeting = try MeetingFile.parse(text, relativePath: path, id: id)
                cache[path] = (s, meeting)
                meetings.append(meeting)
            } catch {
                cache[path] = nil
                failures.append(LoadFailure(relativePath: path, message: String(describing: error)))
            }
        }
        for key in cache.keys where !seen.contains(key) { cache[key] = nil }
        return LoadResult(meetings: meetings, failures: failures)
    }

    // MARK: Writing

    /// Writes the meeting, choosing or updating its file name: a new meeting
    /// gets the first free name for its date, time and title, and an existing
    /// one is renamed (and moved between year folders) when those change.
    /// Returns the meeting with its `relativePath` set.
    @discardableResult
    public func save(_ meeting: Meeting) throws -> Meeting {
        var m = meeting
        let stem = Naming.stem(for: m)
        let folder = Naming.folder(for: m)
        let oldPath = m.relativePath
        let newPath: String
        if let old = oldPath, Naming.path(old, fits: stem, in: folder) {
            newPath = old
        } else {
            var taken = Set(meetingPaths())
            if let old = oldPath { taken.remove(old) }
            newPath = Naming.uniquePath(stem: stem, in: folder, taken: taken)
        }
        m.relativePath = newPath

        let target = url(for: newPath)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(MeetingFile.render(m).utf8).write(to: target, options: .atomic)
        if let old = oldPath, old != newPath {
            try? fm.removeItem(at: url(for: old))
            cache[old] = nil
            removeFolderIfEmpty(url(for: old).deletingLastPathComponent())
        }
        cache[newPath] = (stamp(newPath), m)
        return m
    }

    /// Forgets a meeting whose file has been moved away (to the Trash), and
    /// removes its year folder if that is now empty.
    public func forget(_ relativePath: String) {
        cache[relativePath] = nil
        removeFolderIfEmpty(url(for: relativePath).deletingLastPathComponent())
    }

    private func removeFolderIfEmpty(_ folder: URL) {
        let meetings = root.appendingPathComponent(Naming.meetingsFolder).standardizedFileURL
        guard folder.standardizedFileURL != meetings,
              folder.standardizedFileURL.path.hasPrefix(meetings.path + "/"),
              let items = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        // A folder holding only Finder's .DS_Store counts as empty.
        guard items.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? fm.removeItem(at: folder)
    }

    // MARK: Platform instructions

    public var platformsURL: URL { root.appendingPathComponent(Workspace.platformsFile) }

    /// The instructions, or empty ones if the file is missing.
    public func loadPlatformInstructions() throws -> PlatformInstructions {
        guard fm.fileExists(atPath: platformsURL.path) else { return PlatformInstructions() }
        let data = try Data(contentsOf: platformsURL)
        return try MeetingFile.parsePlatforms(String(decoding: data, as: UTF8.self))
    }

    public func savePlatformInstructions(_ p: PlatformInstructions) throws {
        try Data(MeetingFile.renderPlatforms(p).utf8).write(to: platformsURL, options: .atomic)
    }
}
