import SwiftUI

/// Floating left toolbar (spec §5.2): one tool active at a time, except
/// `.addPage` which fires immediately rather than becoming "active".
struct ToolRail: View {
    @Binding var activeTool: Tool
    var onAddPage: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tool.allCases) { tool in
                toolButton(tool)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func toolButton(_ tool: Tool) -> some View {
        let isActive = (tool != .addPage) && activeTool == tool
        return Button {
            select(tool)
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .help(tool.label)
        .keyboardShortcut(tool.shortcutKey, modifiers: [])
    }

    private func select(_ tool: Tool) {
        if tool == .addPage {
            onAddPage()
        } else {
            activeTool = tool
        }
    }
}
