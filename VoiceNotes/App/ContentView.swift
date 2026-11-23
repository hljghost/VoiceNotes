import SwiftUI

enum AppTab: Hashable {
    case record
    case notes
    case settings
}

struct ContentView: View {
    @State private var tab: AppTab = Self.initialTab()
    @State private var openedNoteID: UUID? = Self.initialNoteID()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                RecordView()
            }
            .tabItem {
                Label("录音", systemImage: "mic.fill")
            }
            .tag(AppTab.record)

            NavigationStack {
                NotesListView()
                    .navigationDestination(item: $openedNoteID) { id in
                        NoteDetailView(noteID: id)
                    }
            }
            .tabItem {
                Label("笔记", systemImage: "square.and.pencil")
            }
            .tag(AppTab.notes)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(VNTheme.pine)
    }

    private static func initialTab() -> AppTab {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-OpenNote") { return .notes }
        if args.contains("-OpenManageModels") { return .settings }
        if let idx = args.firstIndex(of: "-OpenTab"), args.indices.contains(idx + 1) {
            switch args[idx + 1].lowercased() {
            case "notes": return .notes
            case "settings": return .settings
            default: return .record
            }
        }
        return .record
    }

    private static func initialNoteID() -> UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-OpenNote"),
              args.indices.contains(idx + 1)
        else { return nil }
        return UUID(uuidString: args[idx + 1])
    }
}

#if DEBUG
enum NoteDeleteDebugHook {
    static var pendingDeleteID: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-PerformDeleteNote"),
              args.indices.contains(idx + 1)
        else { return nil }
        return UUID(uuidString: args[idx + 1])
    }
}
#endif

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
