import SwiftUI
import MeetingsCore

/// New Meeting (⌘N) and Edit Meeting (⌘E): title, date, start and end,
/// location (its kind is shown as you type), people and description.
/// Notes are edited in the meeting pane, not here.
struct MeetingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: MeetingEditorRequest
    @State private var draft: MeetingDraft
    @FocusState private var titleFocused: Bool

    init(request: MeetingEditorRequest) {
        self.request = request
        _draft = State(initialValue: MeetingDraft(request.original))
    }

    var body: some View {
        let kind = LocationKind.of(draft.location)
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $draft.title, prompt: Text("Meeting title"))
                        .focused($titleFocused)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    DatePicker("Starts", selection: $draft.start, displayedComponents: .hourAndMinute)
                    LabeledContent("Ends") {
                        HStack {
                            Toggle("End time", isOn: $draft.hasEnd)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                            DatePicker("Ends", selection: $draft.end, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .disabled(!draft.hasEnd)
                            if draft.endsBeforeStart {
                                Label("Ends before it starts", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.callout)
                            }
                        }
                    }
                }
                Section {
                    LabeledContent("Location") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Location", text: $draft.location,
                                      prompt: Text("A place, or a Teams, Zoom or Google Maps link"))
                                .labelsHidden()
                            Label(kind.detectedLabel, systemImage: kind.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("People") {
                        PeopleTokenField(
                            names: draft.people,
                            placeholder: "Type names, separated by commas",
                            suggestions: { query, current in model.peopleSuggestions(query, excluding: current) },
                            onChange: { draft.people = $0 })
                    }
                }
                Section("Description") {
                    TextEditor(text: $draft.details)
                        .font(.body)
                        .frame(minHeight: 70, maxHeight: 140)
                        .scrollContentBackground(.hidden)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.meetingID == nil ? "Add Meeting" : "Save") {
                    model.commitEditor(request, draft: draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear { titleFocused = request.meetingID == nil }
        .onChange(of: draft.start) { old, new in
            // Moving the start keeps the meeting's length, as in Calendar.
            guard draft.hasEnd else { return }
            draft.end = draft.end.addingTimeInterval(new.timeIntervalSince(old))
        }
    }
}
