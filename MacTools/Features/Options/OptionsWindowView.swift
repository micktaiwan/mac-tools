import SwiftUI

struct OptionsWindowView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var shortcutStore: ShortcutStore
    @ObservedObject var snapService: SnapService
    @StateObject private var shortcutsService = ShortcutsService()

    enum Tab: String, CaseIterable, Identifiable {
        case general
        case calendarMail
        case shortcuts
        case snap

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .calendarMail: return "Calendrier et emails"
            case .shortcuts: return "Raccourcis et scripts"
            case .snap: return "Fenetres"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .calendarMail: return "calendar"
            case .shortcuts: return "keyboard"
            case .snap: return "macwindow.on.rectangle"
            }
        }
    }

    @State private var selection: Tab

    init(
        calendarService: CalendarService,
        shortcutStore: ShortcutStore,
        snapService: SnapService,
        initialTab: Tab = .general
    ) {
        self.calendarService = calendarService
        self.shortcutStore = shortcutStore
        self.snapService = snapService
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            switch selection {
            case .general:
                GeneralOptionsView()
            case .calendarMail:
                CalendarMailOptionsView(calendarService: calendarService)
            case .shortcuts:
                ShortcutsOptionsView(shortcutsService: shortcutsService, store: shortcutStore)
            case .snap:
                SnapOptionsView(snapService: snapService)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 420)
    }
}

/// Shared layout for an options page: a title, then the page content.
struct OptionsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)

            content

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}
