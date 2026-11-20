import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                RecordView()
            }
            .tabItem {
                Label("录音", systemImage: "mic.circle.fill")
            }

            NavigationStack {
                NotesListView()
            }
            .tabItem {
                Label("笔记", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
