import AppKit
import SwiftUI
import MeetingsCore

/// A Mail-style token field for people's names (`NSTokenField`). Typing
/// completes from `suggestions`; a comma, semicolon or Return turns the text
/// into a token, and anything typed that is not suggested becomes a new
/// name. `isOutsider` names are drawn as square tokens (used for assignees
/// who are not among the meeting's people).
struct PeopleTokenField: NSViewRepresentable {
    var names: [String]
    var placeholder: String
    var bordered: Bool = true
    var suggestions: (_ query: String, _ current: [String]) -> [String]
    var isOutsider: (String) -> Bool = { _ in false }
    var onChange: ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.tokenStyle = .rounded
        field.completionDelay = 0
        field.tokenizingCharacterSet = CharacterSet(charactersIn: ",;")
        field.placeholderString = placeholder
        field.objectValue = names
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.isBordered = bordered
        field.isBezeled = bordered
        field.bezelStyle = .roundedBezel
        field.drawsBackground = bordered
        field.focusRingType = bordered ? .default : .none
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        // Leave the field alone while it is being edited.
        guard field.currentEditor() == nil else { return }
        if context.coordinator.tokens(field) != names {
            field.objectValue = names
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTokenField, context: Context) -> CGSize? {
        let width = max(80, proposal.width ?? 260)
        guard let cell = nsView.cell else { return nil }
        let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000))
        return CGSize(width: width, height: max(22, ceil(size.height)))
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: PeopleTokenField

        init(parent: PeopleTokenField) {
            self.parent = parent
        }

        /// The tokens, normalised.
        func tokens(_ field: NSTokenField) -> [String] {
            let values = field.objectValue as? [Any] ?? []
            return People.merge(values.compactMap { $0 as? String })
        }

        func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String,
                        indexOfToken tokenIndex: Int,
                        indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
            let typedKey = People.key(substring)
            let current = tokens(tokenField).filter { People.key($0) != typedKey }
            return parent.suggestions(substring, current)
        }

        func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
            var seen = Set<String>()
            var out: [Any] = []
            for case let name as String in tokens {
                let n = People.normalize(name)
                guard !n.isEmpty else { continue }
                // Duplicates of existing tokens are merged away on commit.
                guard seen.insert(People.key(n)).inserted else { continue }
                out.append(n)
            }
            Task { @MainActor [weak self] in self?.commit(tokenField) }
            return out
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            guard let name = representedObject as? String else { return .rounded }
            return parent.isOutsider(name) ? .squared : .rounded
        }

        func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
            false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTokenField else { return }
            commit(field)
        }

        func commit(_ field: NSTokenField) {
            let names = tokens(field)
            if names != People.merge(parent.names) {
                parent.onChange(names)
            }
        }
    }
}
