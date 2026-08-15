import SwiftUI
import AppKit

/// Positions `TextEditingOverlay` in page space exactly like
/// `PlacedElementView` positions a normal element, so entering/exiting edit
/// mode doesn't shift the box.
struct PlacedTextEditorView: View {
    @EnvironmentObject var store: ProjectStore
    var element: PageElement
    var text: TextElement
    var pageID: UUID
    var pageSizePt: CGSize
    var pageSizeCm: CGSize

    var body: some View {
        let scale = pageSizeCm.width > 0 ? pageSizePt.width / pageSizeCm.width : 1
        let w = max(element.transform.size.width * scale, 1)
        let h = max(element.transform.size.height * scale, 1)
        let x = element.transform.position.x * scale
        let y = element.transform.position.y * scale

        TextEditingOverlay(
            text: text,
            onChange: { store.updateEditingText($0) },
            onCommit: { store.commitTextEditing() }
        )
        .frame(width: w, height: h)
        .rotationEffect(.degrees(element.transform.rotationDegrees))
        .position(x: x, y: y)
    }
}

/// Replaces `TextElementContentView` for whichever element is currently
/// `ProjectStore.editingTextElementID` — mirrors the same background/
/// padding/border chrome so entering/exiting edit mode doesn't visibly
/// shift the box, but backs the text itself with a real `NSTextView` so
/// typing, cursor placement, and selection work.
struct TextEditingOverlay: View {
    var text: TextElement
    var onChange: (String) -> Void
    var onCommit: () -> Void

    var body: some View {
        ZStack {
            if let bg = text.backgroundFill {
                Rectangle().fill(bg.color)
            }
            TextEditorRepresentable(
                string: text.string,
                fontName: text.fontName,
                fontSize: text.fontSize,
                textColor: text.textColor.color,
                alignment: text.alignment,
                onChange: onChange,
                onCommit: onCommit
            )
            .padding(4)
        }
        .clipped()
        .overlay(borderOverlay)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = text.border {
            BorderOverlay(border: border)
        }
    }
}

/// Thin `NSTextView` wrapper — the first `NSViewRepresentable` in this
/// codebase (no scroll view, since the element's fixed on-page frame
/// shouldn't scroll). Font/color/alignment are re-applied to the whole
/// string on every update rather than tracked as attributed-string ranges,
/// since `TextElement` only stores one style for its entire string (no
/// per-run styling in the model).
private struct TextEditorRepresentable: NSViewRepresentable {
    var string: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: Color
    var alignment: TextAlignment
    var onChange: (String) -> Void
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = false
        textView.string = string
        applyStyle(to: textView)
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
        }
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != string {
            nsView.string = string
        }
        applyStyle(to: nsView)
    }

    private func applyStyle(to textView: NSTextView) {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let nsColor = NSColor(textColor)
        let paragraphStyle = NSMutableParagraphStyle()
        switch alignment {
        case .leading: paragraphStyle.alignment = .left
        case .center: paragraphStyle.alignment = .center
        case .trailing: paragraphStyle.alignment = .right
        }
        textView.font = font
        textView.textColor = nsColor
        textView.alignment = paragraphStyle.alignment
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: nsColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.textStorage?.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: textView.string.count))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onCommit: onCommit)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var onCommit: () -> Void

        init(onChange: @escaping (String) -> Void, onCommit: @escaping () -> Void) {
            self.onChange = onChange
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            onCommit()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCommit()
                return true
            }
            return false
        }
    }
}
