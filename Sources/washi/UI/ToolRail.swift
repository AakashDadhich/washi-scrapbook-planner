import SwiftUI

/// Floating left toolbar (spec §5.2): one tool active at a time, except
/// `.addPage` which fires immediately rather than becoming "active".
struct ToolRail: View {
    @EnvironmentObject var store: ProjectStore
    @Binding var activeTool: Tool
    var onAddSinglePage: () -> Void
    var onAddSpread: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tool.allCases) { tool in
                if tool == .addPage {
                    addPageButton
                } else {
                    toolButton(tool)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private var addPageButton: some View {
        Menu {
            Button("Add Single Page", action: onAddSinglePage)
            Button("Add Spread", action: onAddSpread)
        } label: {
            Image(systemName: Tool.addPage.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Tool.addPage.label)
        .keyboardShortcut(Tool.addPage.shortcutKey, modifiers: [])
        // A disabled control's keyboard shortcut isn't intercepted at all
        // (the key event falls through to whatever's focused instead), so
        // typing digits 1-7 into a text element being edited doesn't get
        // eaten as a tool-switch shortcut — see the identical guard on
        // ProjectStore.editingTextElementID in washiApp.swift/PageFilmstripView.
        .disabled(store.editingTextElementID != nil)
    }

    private func toolButton(_ tool: Tool) -> some View {
        let isActive = activeTool == tool
        return Button {
            activeTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .help(tool.label)
        .keyboardShortcut(tool.shortcutKey, modifiers: [])
        .disabled(store.editingTextElementID != nil)
        .modifier(ClipartPopoverIfSticker(tool: tool, activeTool: $activeTool))
    }
}

/// Attaches the Clipart panel as a popover only to the Add Sticker button
/// (spec §7: "opened from the Add Sticker toolbar icon"), open exactly
/// while that tool is active.
private struct ClipartPopoverIfSticker: ViewModifier {
    @EnvironmentObject var store: ProjectStore
    var tool: Tool
    @Binding var activeTool: Tool

    func body(content: Content) -> some View {
        if tool == .addSticker {
            content.popover(isPresented: Binding(
                get: { activeTool == .addSticker },
                set: { if !$0 && activeTool == .addSticker { activeTool = .select } }
            )) {
                ClipartPanel { item in
                    guard let pageID = store.selectedPageID, let center = store.pageCenterCm(onPageID: pageID) else { return }
                    store.placeClipart(item, onPageID: pageID, atCm: center)
                    activeTool = .select
                }
            }
        } else {
            content
        }
    }
}
