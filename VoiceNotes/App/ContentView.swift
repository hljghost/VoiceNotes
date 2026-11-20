import SwiftUI

enum AppTab: Hashable {
    case record
    case notes
    case settings
}

struct ContentView: View {
    @State private var tab: AppTab = Self.initialTab()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                RecordView()
            }
            .tabItem {
                Label("录音", systemImage: "mic.circle.fill")
            }
            .tag(AppTab.record)

            NavigationStack {
                NotesListView()
            }
            .tabItem {
                Label("笔记", systemImage: "list.bullet.rectangle")
            }
            .tag(AppTab.notes)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
    }

    private static func initialTab() -> AppTab {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-OpenTab"), args.indices.contains(idx + 1) {
            switch args[idx + 1].lowercased() {
            case "notes": return .notes
            case "settings": return .settings
            default: return .record
            }
        }
        return .record
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
