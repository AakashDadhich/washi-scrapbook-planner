import SwiftUI
import AppKit

@main
struct WashiApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}

// Temporary M4 verification harness — replaced by the real chrome in M5.
struct ContentView: View {
    @State private var showNewProjectSheet = false
    @State private var createdProject: Project?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 16) {
                Button("New Project...") { showNewProjectSheet = true }
                if let project = createdProject {
                    ScrollView {
                        Text(summary(for: project))
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    }
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet { project in
                createdProject = project
            }
        }
    }

    private func summary(for project: Project) -> String {
        var lines = ["Album: \(project.name)"]
        for page in project.album.pages {
            lines.append("  \(page.role) size=\(page.size.name) pageNumber=\(page.pageNumber.map(String.init) ?? "nil")")
        }
        return lines.joined(separator: "\n")
    }
}
