import SwiftUI
import MeetingsCore

/// Settings (⌘,): General, and the platform instructions of the open
/// workspace.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PlatformSettings()
                .tabItem { Label("Platforms", systemImage: "video") }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Reopen the last workspace at launch", isOn: $model.reopenLast)
            Picker("New meetings last", selection: $model.defaultDuration) {
                Text("No end time").tag(0)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("45 minutes").tag(45)
                Text("1 hour").tag(60)
                Text("90 minutes").tag(90)
                Text("2 hours").tag(120)
            }
            LabeledContent("Week starts on") {
                Text(Calendar.current.weekdaySymbols[Calendar.current.firstWeekday - 1])
                    .foregroundStyle(.secondary)
            }
            Text("The first day of the week follows System Settings \u{2192} General \u{2192} Language & Region, as in Calendar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 260)
    }
}

/// One short text per platform, shown as a callout on its meetings. Stored
/// in the workspace's platforms.yml, so it travels with the meetings.
private struct PlatformSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if let ws = model.workspace {
                Section {
                    ForEach(ConferencePlatform.allCases) { platform in
                        PlatformField(platform: platform)
                    }
                } footer: {
                    Text("Shown as a callout on every \(ConferencePlatform.allCases.map(\.title).joined(separator: " or ")) meeting. Saved in platforms.yml in \u{201C}\(ws.root.lastPathComponent)\u{201D}, so the instructions travel with your meetings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Open a workspace to edit its platform instructions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }
}

private struct PlatformField: View {
    @Environment(AppModel.self) private var model
    let platform: ConferencePlatform
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let limit = PlatformInstructions.suggestedLength
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(platform.title, systemImage: "video")
                    .font(.headline)
                Spacer()
                Text("\(text.count) / \(limit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(text.count > limit ? Color.orange : Color.secondary)
                    .help("About two sentences fit in the callout. Longer text is allowed.")
            }
            TextField(platform.title, text: $text,
                      prompt: Text("For example: Use the desktop app and sign in with your work account."),
                      axis: .vertical)
                .lineLimit(2...4)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit { save() }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PlatformCallout(platform: platform, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        .padding(.vertical, 4)
        .onAppear { text = model.instructions[platform] }
        .onChange(of: model.instructions[platform]) { _, new in
            if !isFocused { text = new }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { save() }
        }
        .onDisappear { save() }
    }

    private func save() {
        model.setInstructions(text.trimmingCharacters(in: .whitespacesAndNewlines), for: platform)
    }
}
