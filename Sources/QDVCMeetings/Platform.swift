import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MeetingsCore

/// Thin wrappers over AppKit services.
@MainActor
enum Platform {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Moves a file to the Trash, so it can be put back from Finder.
    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Asks where to save, suggesting `name`. Nil if cancelled.
    static func saveLocation(suggesting name: String, type: UTType, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Whether a text field or text view is being edited in the key window,
    /// so that a menu shortcut that is also a text-editing key (⌘⌫) can be
    /// passed on to the text instead.
    static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    /// Puts keyboard focus in the window's toolbar search field (the one
    /// `.searchable` adds). Returns false when the window has none. (From
    /// QDVC Nice Mail.)
    @discardableResult
    static func focusSearchField(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        if let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return true
        }
        // Fall back to any search field in the window's frame, which holds the
        // toolbar as well as the content.
        guard let field = searchField(in: window.contentView?.superview ?? window.contentView) else {
            return false
        }
        window.makeFirstResponder(field)
        return true
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField, !field.isHidden { return field }
        for subview in view.subviews {
            if let found = searchField(in: subview) { return found }
        }
        return nil
    }

    /// Apple Maps, searching for a free-text place.
    static func mapsSearchURL(_ query: String) -> URL? {
        var c = URLComponents(string: "http://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: query)]
        return c?.url
    }
}

extension UTType {
    static let docx = UTType(filenameExtension: "docx") ?? .data
    static let markdownText = UTType(filenameExtension: "md") ?? .plainText
}

extension LocationKind {
    /// SF Symbol for the location, in lists, chips and the meeting pane.
    var symbol: String {
        switch self {
        case .none: return "mappin.slash"
        case .text: return "mappin.and.ellipse"
        case .link: return "link"
        case .googleMaps: return "map"
        case .teams, .zoom: return "video"
        }
    }

    /// The action button's title in the meeting pane.
    var actionTitle: String? {
        switch self {
        case .teams, .zoom: return "Join"
        case .googleMaps: return "Open Map"
        case .text: return "Show in Maps"
        case .link: return "Open Link"
        case .none: return nil
        }
    }

    /// The kind as a phrase, under the location field in the editor.
    var detectedLabel: String {
        switch self {
        case .none: return "No location"
        case .text: return "Place"
        case .link: return "Web link"
        case .googleMaps: return "Google Maps link"
        case .teams: return "Microsoft Teams link"
        case .zoom: return "Zoom link"
        }
    }
}

extension NoteKind {
    var symbol: String {
        switch self {
        case .note: return "circle.fill"
        case .action: return "checklist"
        case .decision: return "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .note: return .secondary
        case .action: return .accentColor
        case .decision: return .purple
        }
    }

    /// ⌥⌘0 / ⌥⌘A / ⌥⌘D.
    var shortcutKey: KeyEquivalent {
        switch self {
        case .note: return "0"
        case .action: return "a"
        case .decision: return "d"
        }
    }
}
