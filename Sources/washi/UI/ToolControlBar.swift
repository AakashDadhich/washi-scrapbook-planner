import SwiftUI

/// Bottom-center contextual bar (spec §5.5): contents change based on
/// whichever left-toolbar tool is active, or — once something is selected
/// on canvas — based on what's selected instead.
struct ToolControlBar: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                content
                    .frame(minWidth: geo.size.width, alignment: .center)
            }
        }
        .frame(height: 76)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        switch store.activeTool {
        case .select:
            selectStateContent
        case .addText:
            TextToolControls(text: $store.pendingTextStyle, isEnabled: true, isBackgroundDark: store.currentPageBackgroundIsDark)
        case .addImage:
            ImageToolControls(
                border: $store.pendingImageBorder,
                isTransparent: $store.pendingImageTransparent,
                shadow: .constant(nil),
                cropRect: .constant(CGRect(x: 0, y: 0, width: 1, height: 1)),
                isEnabled: true
            )
        case .addSticker:
            StickerToolControls(tint: $store.pendingStickerTint, isEnabled: true)
        case .addBorderFrame:
            FrameToolControls(border: $store.pendingFrameBorder, fill: $store.pendingFrameFill, isEnabled: true)
        case .background:
            backgroundContent
        case .addPage:
            selectStateContent
        }
    }

    @ViewBuilder
    private var backgroundContent: some View {
        if let pageID = store.selectedPageID, let idx = store.pageIndex(for: pageID) {
            BackgroundToolControls(
                background: Binding(
                    get: { store.project.album.pages[idx].background },
                    set: { store.setCurrentPageBackground($0) }
                ),
                pageSize: store.project.album.pages[idx].size,
                onPageSizeChange: { store.setCurrentPageSize($0) }
            )
        } else {
            BackgroundToolControls(background: .constant(.solidColor(.white)))
        }
    }

    @ViewBuilder
    private var selectStateContent: some View {
        if let (_, element) = store.singleSelectedElement {
            switch element.content {
            case .text(let text):
                TextToolControls(
                    text: Binding(get: { text }, set: { newValue in store.updateSelectedText { $0 = newValue } }),
                    isEnabled: true,
                    isBackgroundDark: store.currentPageBackgroundIsDark
                )
            case .image(let image):
                ImageToolControls(
                    border: Binding(get: { image.border }, set: { newValue in store.updateSelectedImage { $0.border = newValue } }),
                    isTransparent: Binding(get: { image.backgroundIsTransparent }, set: { newValue in store.updateSelectedImage { $0.backgroundIsTransparent = newValue } }),
                    shadow: Binding(get: { image.shadow }, set: { newValue in store.updateSelectedImage { $0.shadow = newValue } }),
                    cropRect: Binding(get: { image.cropRect }, set: { newValue in store.updateSelectedImage { $0.cropRect = newValue } }),
                    isEnabled: true
                )
            case .sticker(let sticker):
                StickerToolControls(
                    tint: Binding(get: { sticker.tint }, set: { newValue in store.updateSelectedSticker { $0.tint = newValue } }),
                    isEnabled: true
                )
            case .frame(let frame):
                FrameToolControls(
                    border: Binding(get: { frame.border }, set: { newValue in store.updateSelectedFrame { $0.border = newValue } }),
                    fill: Binding(get: { frame.fill }, set: { newValue in store.updateSelectedFrame { $0.fill = newValue } }),
                    isEnabled: true
                )
            }
        } else {
            TextToolControls(
                text: .constant(TextToolControls.zeroedTemplate(isBackgroundDark: store.currentPageBackgroundIsDark)),
                isEnabled: false,
                isBackgroundDark: store.currentPageBackgroundIsDark
            )
        }
    }
}
