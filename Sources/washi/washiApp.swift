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

struct ContentView: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .frame(minWidth: 1000, minHeight: 700)
    }
}
