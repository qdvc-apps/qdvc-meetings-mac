import Foundation

/// App preferences, in the standard defaults domain
/// (`defaults read org.qdvc.meetings.mac`). The platform instructions belong
/// to the workspace instead (`platforms.yml`), so they travel with it.
enum Prefs {
    enum Key {
        static let recentWorkspaces = "recentWorkspaces"
        static let lastWorkspace = "lastWorkspace"
        static let reopenLast = "reopenLastWorkspace"
        static let viewMode = "viewMode"
        static let defaultDuration = "defaultDurationMinutes"
    }

    private static var defaults: UserDefaults { .standard }

    static var recentWorkspaces: [String] {
        get { defaults.stringArray(forKey: Key.recentWorkspaces) ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: Key.recentWorkspaces) }
    }

    static var lastWorkspace: String? {
        get { defaults.string(forKey: Key.lastWorkspace) }
        set { defaults.set(newValue, forKey: Key.lastWorkspace) }
    }

    static var reopenLast: Bool {
        get { defaults.object(forKey: Key.reopenLast) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reopenLast) }
    }

    static var viewMode: ViewMode {
        get { ViewMode(rawValue: defaults.string(forKey: Key.viewMode) ?? "") ?? .list }
        set { defaults.set(newValue.rawValue, forKey: Key.viewMode) }
    }

    /// The length a new meeting is given (0 = no end time).
    static var defaultDuration: Int {
        get { defaults.object(forKey: Key.defaultDuration) as? Int ?? 60 }
        set { defaults.set(newValue, forKey: Key.defaultDuration) }
    }
}
