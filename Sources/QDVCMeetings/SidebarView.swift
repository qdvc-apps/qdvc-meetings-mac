import SwiftUI
import MeetingsCore

/// The source list: date filters (dimmed in Calendar view, where the calendar
/// is the date filter; choosing one shows the list), and everyone who has
/// been in a meeting.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var peopleExpanded = true

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section("Meetings") {
                ForEach(DateFilter.allCases) { f in
                    Label(f.title, systemImage: f.symbol)
                        .badge(model.count(f))
                        .foregroundStyle(model.viewMode == .calendar ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                        .help(model.viewMode == .calendar ? "Show \(f.title.lowercased()) in the list" : "")
                        .tag(SidebarItem.dates(f))
                }
            }
            if !model.people.isEmpty {
                Section("People", isExpanded: $peopleExpanded) {
                    ForEach(model.people.all) { p in
                        Label(p.name, systemImage: "person")
                            .badge(p.meetingCount)
                            .tag(SidebarItem.person(p.id))
                            .contextMenu {
                                Button("Rename Person\u{2026}") { model.beginRenamePerson(p.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// Rename Person… : fixes a misspelt name in every meeting.
struct RenamePersonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let person: PersonSummary
    @State private var name = ""

    var body: some View {
        let trimmed = People.normalize(name)
        let merging = model.people.person(forKey: People.key(trimmed)).map { $0.id != person.id } ?? false
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \u{201C}\(person.name)\u{201D}").font(.headline)
            Text("The new name replaces the old one in all \(person.meetingCount) meeting\(person.meetingCount == 1 ? "" : "s"), including action item assignees.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save(trimmed) }
            if merging {
                Label("\(trimmed) is already in the list; the two will be merged.", systemImage: "arrow.triangle.merge")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { save(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || trimmed == person.name)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = person.name }
    }

    private func save(_ trimmed: String) {
        guard !trimmed.isEmpty, trimmed != person.name else { return }
        model.renamePerson(person.id, to: trimmed)
        dismiss()
    }
}
