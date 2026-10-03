import SwiftUI
import MeetingsCore

/// The selected meeting, laid out like Calendar's event inspector, then its
/// notes (docs/DESIGN.md §2.5).
struct MeetingPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let m = model.selectedMeeting {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MeetingHeader(meeting: m)
                    if m.locationKind != .none {
                        LocationRow(meeting: m)
                    }
                    if let callout = model.instructions(for: m) {
                        PlatformCallout(platform: callout.0, text: callout.1)
                    }
                    if !m.people.isEmpty {
                        PeopleChips(names: m.people)
                    }
                    if !m.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(m.details)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().padding(.vertical, 2)
                    NotesList(meetingID: m.id)
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(m.id)
        } else {
            ContentUnavailableView {
                Label("No Meeting Selected", systemImage: "calendar")
            } description: {
                Text("Choose a meeting to see its details and notes.")
            }
        }
    }
}

private struct MeetingHeader: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        let m = meeting
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.formatter.longDate(m.date) + " \u{00B7} " + model.formatter.timeRange(m))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Edit") { model.editMeeting(m.id) }
                .help("Edit the meeting\u{2019}s title, time, location, people and description (\u{2318}E)")
            Menu {
                Button("Duplicate Meeting") { model.duplicateMeeting(m.id) }
                Divider()
                ExportMenuItems(meetingID: m.id)
                Divider()
                Button("Reveal in Finder") { model.revealMeetingFile(m.id) }
                Divider()
                Button("Delete Meeting\u{2026}") { model.requestDelete(m.id) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions for this meeting")
        }
    }
}

/// The location's symbol and text, with Join, Open Map or Show in Maps.
private struct LocationRow: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        let m = meeting
        let kind = m.locationKind
        let text = m.location.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                if let service = kind.serviceName {
                    Text(kind == .googleMaps ? service : "\(service) meeting")
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(text).textSelection(.enabled).lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            if let title = kind.actionTitle {
                if kind.conferencePlatform != nil {
                    Button(title) { model.openLocation(m.id) }
                        .buttonStyle(.borderedProminent)
                        .help("Open the meeting link (\u{2318}J)")
                } else {
                    Button(title) { model.openLocation(m.id) }
                        .help(kind == .text ? "Search for this place in Maps (\u{2318}J)" : "Open the link (\u{2318}J)")
                }
            }
        }
        .contextMenu {
            Button(kind.isLink ? "Copy Link" : "Copy Location") { model.copyLocation(m.id) }
        }
    }
}

/// The short instructions for the meeting's platform, from Settings.
struct PlatformCallout: View {
    let platform: ConferencePlatform
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            (Text("\(platform.title): ").fontWeight(.semibold) + Text(text))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }
}

/// The meeting's people as tokens; clicking one shows their meetings.
private struct PeopleChips: View {
    @Environment(AppModel.self) private var model
    let names: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            FlowLayout(spacing: 5) {
                ForEach(names, id: \.self) { name in
                    Button {
                        model.selectPerson(name)
                    } label: {
                        Text(name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Show meetings with \(name)")
                }
            }
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
