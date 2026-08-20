# Washi - Product & Engineering Specification

**Version:** 0.1 (draft for build agent)
**Platform:** macOS 14.0+
**Language / toolchain:** Swift 5.9+, SwiftUI + AppKit interop, Swift Package Manager only (no `.xcodeproj`)
**Deliverable:** a runnable `washi.app` bundle produced by a shell script

---

## 1. Overview

Washi is a macOS app for planning physical scrapbook pages before you commit scissors to paper. You lay out photos, text, decorative borders and stickers on a digital canvas that matches the real dimensions of your physical scrapbook, arrange everything exactly the way you want it, save your progress as a project, and come back to it over multiple sessions. When a spread is finished, you export a high-resolution PDF you can use as a visual reference while assembling the real page (or send to a print shop for full-page prints/overlays).

It is a **planning and layout tool**, not a print-on-demand or photo-editing app. Photos are placed, cropped to a border shape, and arranged; Washi does not do color-correction, filters, or retouching.

### 1.1 Design principles
1. **True-to-scale canvas.** The canvas always represents the physical page at true relative proportions, so what you plan is what you can replicate on paper.
2. **Direct manipulation.** Every element - text, photo, border, sticker - is selectable, movable, rotatable and resizable with on-canvas handles, individually or as a group.
3. **Never lose work.** Projects are files you explicitly save and reopen, with every element's exact position, size, rotation and style preserved byte-for-byte between sessions.
4. **Self-contained projects.** A saved project does not depend on the original photo files staying in place - images are stored inside the project so it opens correctly weeks or years later, even if the source photos have moved, been renamed, or deleted.
5. **Physical-book metaphor, held loosely.** The app models a cover, a first page, and then facing two-page spreads by default, because that's how a bound scrapbook is actually built and viewed - but the cover and first page can be deleted if you don't want them, and any two adjacent pages can be merged into a spread or split back apart, since not every real album follows the same structure.

### 1.2 Non-goals (v1)
- Photo editing: filters, color correction, red-eye removal, retouching
- Direct print-shop ordering / fulfillment integration
- Cloud sync, multi-user collaboration, accounts
- Video, Live Photos, GIF, audio
- iOS/iPadOS builds
- Automatic/AI-suggested layouts

---

## 2. Technology & build

### 2.1 Constraints
Swift via Swift Package Manager, matching the reference project's approach: no `.xcodeproj` or `.xcworkspace` committed. Xcode command line tools must be installed on the build machine.

### 2.2 Structure
```
Washi/
├── Package.swift
├── build.sh                          # compiles + assembles washi.app
├── Resources/
│   ├── Info.plist
│   ├── washi.entitlements
│   └── Assets/
│       └── StarterClipart/           # bundled starter sticker/clipart set (SVG + PNG)
└── Sources/
    └── washi/
        ├── washiApp.swift         # @main App entry point
        ├── Models/
        │   ├── Project.swift
        │   ├── Album.swift
        │   ├── Page.swift
        │   ├── PageElement.swift
        │   ├── TextElement.swift
        │   ├── ImageElement.swift
        │   ├── StickerElement.swift
        │   ├── FrameElement.swift
        │   ├── BorderStyle.swift
        │   ├── PageBackground.swift
        │   ├── PageSize.swift
        │   ├── Transform2D.swift
        │   └── ElementGroup.swift
        ├── Store/
        │   ├── ProjectStore.swift        # ObservableObject, single source of truth
        │   ├── ProjectFile.swift         # package read/write, migrations
        │   ├── UndoStack.swift
        │   └── ClipartLibrary.swift      # built-in + user-imported assets
        ├── Rendering/
        │   ├── SpreadView.swift          # two-page facing view
        │   ├── PageCanvasView.swift      # single-page canvas (cover / first page)
        │   ├── ElementView.swift
        │   ├── SelectionHandlesView.swift
        │   ├── BorderPathBuilder.swift   # generates squiggly/scallop/zigzag vector paths
        │   ├── PageFlipTransition.swift  # page-turn animation
        │   └── PDFExporter.swift
        ├── UI/
        │   ├── TitleBarControls.swift     # New, Info, Save, Export buttons
        │   ├── NewProjectSheet.swift
        │   ├── KeyboardShortcutsSheet.swift   # opened from the Info button
        │   ├── ToolRail.swift              # floating left toolbar, §5.2
        │   ├── PageFilmstripView.swift     # thumbnail strip + prev/next, below canvas, §5.4
        │   ├── ToolControlBar.swift        # bottom-center contextual bar, §5.5, one subview per tool/selection state
        │   ├── ToolControlBar/
        │   │   ├── TextToolControls.swift
        │   │   ├── ImageToolControls.swift
        │   │   ├── StickerToolControls.swift
        │   │   ├── FrameToolControls.swift
        │   │   ├── BackgroundToolControls.swift
        │   │   └── BorderStylePicker.swift     # shared by text/image/frame controls
        │   ├── PropertiesPanel.swift       # right-side, appears only when a canvas element is selected, §5.6
        │   ├── ClipartPanel.swift          # opened from the sticker tool's bottom-bar controls
        │   └── Components/
        └── Util/
            ├── ImageLoader.swift
            ├── ColorHex.swift
            └── UnitConversion.swift      # cm <-> pt <-> px at export DPI
```

### 2.3 Package.swift
- `platforms: [.macOS(.v14)]`
- Single executable target `washi`
- Zero third-party dependencies. SwiftUI, AppKit, CoreGraphics, PDFKit, ImageIO, UniformTypeIdentifiers only.

### 2.4 build.sh
1. `swift build -c release`
2. Create `washi.app/Contents/{MacOS,Resources}`
3. Copy `Info.plist`, `StarterClipart/`, and the compiled binary in
4. Ad-hoc codesign: `codesign --force --deep --sign - washi.app`
5. Print the path and an `open washi.app` hint

`Info.plist`: `CFBundleName`, `CFBundleIdentifier` (`com.washi.app`), `CFBundleExecutable`, `CFBundlePackageType=APPL`, `LSMinimumSystemVersion=14.0`, `NSHighResolutionCapable=true`. Register the `.washi` project extension as a `CFBundleDocumentTypes` entry so double-clicking a project file opens it in the app.

### 2.5 Sandboxing / file access
Sandbox optional for v1 (no App Store target). If enabled: `com.apple.security.files.user-selected.read-write` for opening photos and saving projects/PDFs via `NSOpenPanel`/`NSSavePanel`.

---

## 3. Data model

### 3.1 Project → Album → Page hierarchy

```swift
struct Project: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var album: Album
    var assetManifest: [UUID: AssetRecord]   // every embedded image/sticker, deduplicated by content hash
}

struct Album: Codable {
    var pages: [Page]                        // ordered; see §3.2 for page roles
    var defaultPageSize: PageSize
}

struct AssetRecord: Codable {
    var id: UUID
    var relativePath: String                 // path inside the project package, see §10
    var contentHash: String                  // SHA-256, used to dedupe re-imports of the same file
    var originalFilename: String
    var pixelSize: CGSize
}
```

### 3.2 Page

```swift
enum PageRole: Codable {
    case cover
    case singlePage                          // e.g. the first page, not part of a spread
    case spreadLeft(spreadID: UUID)
    case spreadRight(spreadID: UUID)
}

struct Page: Codable, Identifiable {
    var id: UUID
    var role: PageRole
    var size: PageSize
    var background: PageBackground
    var elements: [PageElement]
    var groups: [ElementGroup]               // persistent named groups, see §6.3
    var pageNumber: Int?                     // nil for cover; auto-assigned, user-editable
}
```

Pages are stored as a **flat ordered array**, with `PageRole` carrying the spread relationship rather than nesting spreads as their own container. This keeps "insert a page," "delete a page," and "reorder pages" as simple array operations, while `SpreadView` groups consecutive `.spreadLeft`/`.spreadRight` pairs at render time by matching `spreadID`. A `.singlePage` can appear anywhere in the sequence (e.g., inserted between two spreads).

Converting between single pages and a spread is always an **explicit, symmetric** user action (§5.4), never inferred automatically: "merge into spread" re-tags two adjacent `.singlePage`s to `.spreadLeft`/`.spreadRight` sharing a new `spreadID`, and "split into two pages" does the reverse. Either direction preserves each page's own elements exactly as they were - merging or splitting never re-lays-out content, it only changes how the pair is presented and navigated.

Both `.cover` and the first `.singlePage` can be deleted like any other page if you don't want them (§9) - the roles describe a default starting structure (§4), not a permanent constraint. Deleting the cover simply removes it from the array; the album no longer opens on a cover screen, it opens on whatever page is now first.

### 3.3 PageElement (the core abstraction)

Every placeable thing on a page - text, photo, or sticker - shares a common transform and a common set of manipulation behaviors, and carries its type-specific data in an associated payload.

```swift
struct PageElement: Codable, Identifiable {
    var id: UUID
    var transform: Transform2D
    var zIndex: Int
    var isLocked: Bool
    var content: ElementContent
}

enum ElementContent: Codable {
    case text(TextElement)
    case image(ImageElement)
    case sticker(StickerElement)
    case frame(FrameElement)
}

struct Transform2D: Codable {
    var position: CGPoint      // center of the element, in page-space cm
    var size: CGSize           // width/height in page-space cm, pre-rotation
    var rotationDegrees: Double
}
```

`Transform2D` is intentionally the *only* place geometry lives. Resize, move, and rotate are three independent operations on the same struct, which is what makes multi-select transforms (§6.2) and undo/redo (§8) tractable as simple value diffs.

### 3.4 ImageElement

```swift
struct ImageElement: Codable {
    var assetID: UUID                        // key into Project.assetManifest
    var cropRect: CGRect                     // normalized 0-1 rect into the source image
    var border: BorderStyle?
    var cornerStyle: CornerStyle             // .sharp, .rounded(radius), .circle
    var backgroundIsTransparent: Bool        // honor source alpha (PNG) instead of filling behind it
    var shadow: ShadowStyle?
}
```

Images are cropped (not distorted) to fill the element's bounding box, following the same "always fill, pan to reframe" model reviewed in competitor products. When `backgroundIsTransparent` is true and the source has an alpha channel, the page background shows through instead of the crop being matted onto a solid rectangle - this is what makes a die-cut/transparent PNG sticker-photo sit naturally on a colored or black page.

### 3.5 TextElement

```swift
struct TextElement: Codable {
    var string: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: ColorValue
    var alignment: TextAlignment             // .leading, .center, .trailing
    var border: BorderStyle?                 // a box/outline drawn around the text block
    var backgroundFill: ColorValue?          // optional fill behind the text block, independent of border
    var shadow: ShadowStyle?
    var outline: TextOutlineStyle?           // stroke around the glyphs themselves (distinct from the box border)
}
```

### 3.6 StickerElement

```swift
struct StickerElement: Codable {
    var assetID: UUID                        // key into Project.assetManifest, same storage as photos
    var tint: ColorValue?                    // optional recolor for monochrome/silhouette clipart
}
```

Stickers reuse `AssetRecord`/embedding exactly like photos (§3.1, §10) - a sticker is just an image element without cropping and without the shadow/border options that assume a rectangular photo.

### 3.7 FrameElement - standalone decorative borders

```swift
enum FrameBaseShape: Codable {
    case rectangle
    case circle
}

struct FrameElement: Codable {
    var shape: FrameBaseShape
    var border: BorderStyle
    var fill: ColorValue?        // nil = transparent interior, so it frames whatever is behind it
}
```

A frame is a placeable decoration in its own right - a squiggly-bordered rectangle or circle you drop onto the page as an accent, independent of any photo or text underneath. It reuses the exact same `BorderStyle`/`BorderPathBuilder` machinery as photo and text borders (§3.8), just without an image or text payload attached. This is what the dedicated "Add Border/Frame" toolbar icon places (§5.2) - a photo's or text box's own border is instead a property you turn on for that element from the tool control bar (§5.5), not a separately-added element.

### 3.8 BorderStyle - procedural/vector borders

```swift
enum BorderShape: Codable {
    case straight
    case squiggly(amplitude: CGFloat, wavelength: CGFloat)
    case scalloped(radius: CGFloat)
    case zigzag(amplitude: CGFloat, wavelength: CGFloat)
    case dashed(dashLength: CGFloat, gapLength: CGFloat)
    case doubleLine(gap: CGFloat)
}

struct BorderStyle: Codable {
    var shape: BorderShape
    var thickness: CGFloat
    var color: ColorValue
    var cornerStyle: CornerStyle
}
```

`BorderPathBuilder` (Rendering/) generates a `CGPath` by walking the element's rounded rect perimeter and substituting a parametric wave/scallop/zigzag function for each edge, so amplitude and wavelength are live-adjustable sliders rather than baked raster art. This applies identically to a photo border and a text-box border, since both are just a `BorderStyle` attached to a rectangular element bounds.

### 3.9 PageBackground & PageSize

```swift
enum PageBackground: Codable {
    case solidColor(ColorValue)
    case custom(assetID: UUID)               // a user-imported background/patterned-paper image, v2 candidate (see §13)
}

// Starter palette, v1: extensible - stored as data, not a hardcoded enum, so more can be added
// without a migration. Ships with:
//   "White"  #FFFFFF
//   "Kraft brown (parchment)"  #C8A97E
//   "Black"  #0A0A0A

struct PageSize: Codable, Equatable {
    var name: String
    var widthCm: Double
    var heightCm: Double
}

// Built-in presets (from competitor/market research, §13):
//   28 x 28 cm            <- user's own scrapbook, ships as the default preset
//   30.5 x 30.5 cm (12x12 in)   <- most common scrapbook size worldwide
//   20 x 20 cm (8x8 in)
//   15 x 15 cm (6x6 in)
//   21 x 29.7 cm (A4)
//   21.6 x 27.9 cm (US Letter, 8.5x11 in)
//   Custom...  (free-entry width/height in cm or inches, with a unit toggle)
```

---

## 4. New Project wizard

Creating a project (`File > New Project`, `Cmd+N`) opens a sheet, per your requirements:

1. **Page size** - defaults to the 28 x 28 cm preset, with the other presets and a "Custom size" entry available.
2. **Starting background color** - one of the built-in palette (white / kraft brown / black) or a custom color, applied to every starting page. Can be changed per-page later.
3. **Number of starting pages** - numeric stepper, default **5**, with inline text noting "You can add or remove pages at any time." This count is the number of *content* pages (spreads + singles combined, not counting the cover, which always exists).
4. **Album name.**

On confirmation, Washi creates: one `.cover` page, one `.singlePage` (the "first page"), and enough `.spreadLeft`/`.spreadRight` pairs to reach the requested content-page count, all using the chosen size and background.

---

## 5. App layout & chrome

This section describes the window's fixed chrome, matching the wireframe you provided. From top to bottom: title bar, then a floating tool rail overlapping the left edge of the canvas, the canvas itself, a page filmstrip with prev/next arrows below it, a contextual tool control bar below that, and a contextual properties panel that appears on the right only when something on the canvas is selected.

### 5.1 Title bar
- **Top-left**: `New` button (opens the New Project sheet, §4) and an `Info` button (circled "i") that opens a **Keyboard Shortcuts sheet** (`KeyboardShortcutsSheet.swift`) listing every shortcut in §12.
- **Top-right**: `Save` (writes the `.washi` project package, §10) and `Export` (writes the PDF, §11).

### 5.2 Floating left toolbar (`ToolRail.swift`)
A vertical floating rail, top to bottom, one tool active at a time (radio-button behavior, not multi-toggle):

1. **Select/Move** - default tool; click and drag elements directly on canvas, marquee-select on empty space (§6.1-6.2)
2. **Add Text** - places a new `TextElement` where you next click/drag on the canvas
3. **Add Image** - opens a file picker (or accepts a drag-and-drop) and places a new `ImageElement`
4. **Add Sticker/Washi Tape** - opens the Clipart panel (§7) to pick an asset, then places a new `StickerElement`
5. **Add Border/Frame** - places a new standalone `FrameElement` (§3.7)
6. **Background color** - not a placement tool; opens the current page's background color picker directly in the tool control bar (§5.5)

Selecting any placement tool (2-5) immediately populates the tool control bar (§5.5) with that tool's relevant controls **before** you've placed anything - e.g. clicking "Add Text" shows font/size/color/border pickers right away, so you set them up once and then drop text boxes with those settings already applied, rather than placing first and styling after. After placing an element, the tool automatically returns to Select/Move with the new element selected, so you can immediately transform it.

### 5.3 Canvas
Shows one navigable unit at a time: the cover alone, the first page alone, or a spread as two facing pages side by side, per §3.2's `PageRole`. Always rendered at true relative proportions to the page's physical size (§1.1).

### 5.4 Page filmstrip & navigation (`PageFilmstripView.swift`)
Directly below the canvas: a **left arrow**, a **horizontal filmstrip of page/spread thumbnails** in album order, and a **right arrow**. This is the only page-navigation UI - there is no separate sidebar.

- **Thumbnails**: each shows a live-updating low-res render of that page/spread (cover, single page, or spread rendered as one wide thumbnail). Clicking a thumbnail jumps the canvas directly to it with a crossfade (not a flip - flipping through every intervening page when jumping from page 2 to page 12 would be tedious rather than useful). Drag-to-reorder within the filmstrip reorders pages in the album.
- **Left/right arrows** (or `←`/`→`) step exactly one unit at a time - cover → first page → spread 1 → spread 2 → ... - and trigger `PageFlipTransition`: a short (≈400ms) 3D page-curl/turn animation via `CATransform3D`, matching the physical-book metaphor (§1.1). Flip direction matches navigation direction. A "reduce motion" accessibility check falls back to a plain crossfade.
- A `+` beside the filmstrip - outside the scrolling thumbnail strip, alongside the left/right arrows - offers the "add page or spread" action (§9). It sits outside the scroll area so it stays visible however many pages the album has and wherever the strip is scrolled to; it is the app's only add-page control, apart from the empty-album prompt (§14 edge case 9).
- **Merge / split**: shift-click two *adjacent* single-page thumbnails to select them together and reveal a "Merge into spread" action (right-click menu or a button that appears above the selected pair); right-click a spread thumbnail for "Split into two pages." Both are the explicit, symmetric conversion described in §3.2 - content on each page is preserved exactly, only the `PageRole` tagging and how the pair is navigated/displayed changes.
- **Deleting the cover or first page**: no special-cased protection - right-click (or select + Delete) works on the cover and first-page thumbnails exactly like any other, with the same confirmation dialog (§9). If deleted, the album simply opens on whatever page is now first.

### 5.5 Tool control bar (`ToolControlBar.swift`)
A bottom-center bar, full width, whose contents change based on **whichever left-toolbar tool is active**, and once something is selected on canvas, based on **what's selected** instead. One subview per state (`UI/ToolControlBar/`):

| Active tool / selection | Bar shows |
|---|---|
| Select/Move, nothing selected | The same layout as "text element selected" below (font, size, color, alignment, border style picker, shadow/outline toggles), but every control is disabled/greyed and numeric fields read `0` or blank rather than being hidden. This keeps the bar's shape and height constant rather than popping in and out as selection changes. |
| Select/Move, a text element selected | Font, size, color, alignment, border style picker (shape/thickness/color), shadow/outline toggles - all enabled and reflecting the selected element's actual values |
| Select/Move, an image or sticker selected | Crop controls, border style picker, transparency toggle, shadow toggle |
| Select/Move, a frame element selected | Border style picker (shape/thickness/amplitude/color), fill color or "transparent" toggle |
| Add Text (before placing) | Same controls as "text selected" above, pre-set for the next text box you place |
| Add Image / Add Sticker (before placing) | Border style picker, transparency toggle, pre-set for the next element you place |
| Add Border/Frame (before placing) | Border style picker, fill color, pre-set for the next frame you place |
| Background color tool | Page background color swatch grid (white/kraft brown/black + custom) with live RGB hex fields, matching your wireframe's color-picker segment |

The **border style picker** (`BorderStylePicker.swift`) is a single shared component used everywhere a `BorderStyle` is editable: a gallery of shape thumbnails (straight, squiggly, scalloped, zigzag, dashed, double line - §3.8) with the current selection highlighted, plus thickness and amplitude/wavelength sliders and a color swatch with RGB hex fields, mirroring your wireframe's bottom-bar sketch.

### 5.6 Properties panel (`PropertiesPanel.swift`)
A right-side panel that only appears when one or more elements are selected on the canvas (it is not always-on chrome, unlike the tool control bar). It has two parts, both scoped to the current page/spread:

- **Transform** - numeric position (x/y), size (w/h), and rotation fields for the current selection, for precise entry alongside on-canvas dragging. With a multi-selection, these apply as a group transform (§6.2). Includes the lock toggle (§6.4).
- **Layers** - a top-to-bottom list of every element on the currently visible page/spread, showing name, visibility, and lock state, with drag-to-reorder controlling `zIndex` (§6.6) and click-to-select syncing with canvas selection. This section is visible whenever the panel is open, regardless of how many elements are selected, so you can always see and reorder the full stack.

---

## 6. Selection & transform

### 6.1 Single-element selection
Clicking an element selects it (auto-switching the active tool to Select/Move) and shows resize handles at the four corners and four edge midpoints, plus a rotation handle offset above the top edge. Handles respect the element's current rotation (they rotate with it, standard direct-manipulation behavior). Dragging a corner handle resizes proportionally by default; holding a modifier key allows free (non-proportional) resize. Dragging the rotation handle rotates freely; holding Shift snaps to 15° increments.

### 6.2 Multi-select and group transform
- **Marquee select**: drag on empty canvas to select every element whose bounds intersect the marquee.
- **Shift-click**: add/remove individual elements from the current selection.
- With 2+ elements selected, a single bounding-box handle set appears around the combined selection. Move, resize, and rotate apply proportionally to every selected element's `Transform2D`, preserving relative position/scale/rotation between them. The tool control bar (§5.5) hides styling controls in this state, since they'd apply inconsistently across mixed element types; the Properties panel's Transform section (§5.6) remains available.

### 6.3 Persistent groups
Beyond an ad-hoc multi-select, `Cmd+G` on a multi-selection creates a named `ElementGroup` (stored in `Page.groups`) that stays grouped across selection changes and reopening the project, until explicitly ungrouped (`Cmd+Shift+G`). This matches the group/ungroup behavior found across competitor apps in §13 and is distinct from a one-off marquee selection.

### 6.4 Locking
Any element (or group) can be locked from the Properties panel's Transform section (§5.6) or the right-click menu. A locked element cannot be moved, resized, rotated, or deleted until unlocked; it can still be selected (to inspect/unlock it) but shows no drag/resize/rotate handles.

### 6.5 Alignment & guides
Dragging an element shows dynamic alignment guides (snap lines) when its edges or center align with another element's edges/center, or with the page's center/margins. Snapping can be temporarily suspended by holding a modifier key while dragging.

### 6.6 Layer order
`Bring to Front` / `Send to Back` / `Bring Forward` / `Send Backward` in the right-click menu and Arrange menu, operating on `zIndex`. The Properties panel's Layers list (§5.6) shows every element on the current page/spread top-to-bottom and supports drag-to-reorder as an alternative to the menu commands.

---

## 7. Clipart / sticker library

Per your requirement, both a built-in starter set and user-imported assets are supported through the same panel, opened from the **Add Sticker/Washi Tape** toolbar icon (§5.2).

- **Built-in starter set**: a small curated collection (target: ~40-60 assets for v1) of simple vector-friendly doodles, washi-tape strip patterns, and basic decorative shapes (stars, hearts, arrows, banners), shipped in `Resources/Assets/StarterClipart/` as SVG where practical (recolorable via `StickerElement.tint`) and PNG where not.
- **Import your own**: `Add to Library...` accepts PNG/JPEG/SVG/PDF and copies the file into the project's asset store (§10) the same way an imported photo is - so custom clipart also survives project reopen without depending on the original file's location.
- The **Clipart panel** (`ClipartPanel.swift`) shows a searchable/scrollable grid, split into "Starter Set" and "My Imports" sections; drag from the panel onto the canvas, or click to insert at the canvas center. Selecting an asset here is what places the `StickerElement` - the toolbar icon opens the panel, the panel click/drag does the placing.
- Imported clipart is scoped **per-project** in v1 (stored in that project's asset manifest); a cross-project personal library is a natural v2 extension (§13) once usage patterns are clearer.

---

## 8. Undo / redo

Every mutation to `Project` (element add/remove/transform, property edits, page add/remove/reorder, background/size changes, grouping) is captured as a value-level diff and pushed onto `UndoStack`. Continuous gestures (an in-progress drag, resize, or rotate) coalesce into a single undo step on gesture end, matching the "a divider drag undoes as one step" pattern from the reference spec's competitor findings. `Cmd+Z` / `Cmd+Shift+Z` (or `Cmd+Y`) standard.

---

## 9. Adding / removing pages

- The filmstrip's `+` (§5.4), offering: add a single page, or add a spread (two pages), inserted after the currently selected page, with the current default background/size pre-filled and editable.
- Deleting a page (right-click a filmstrip thumbnail, or Delete key with a thumbnail selected) always shows a confirmation dialog naming the page ("Delete Spread 3? This removes 2 pages and everything on them. This cannot be undone after closing the project.") before removing it. Deletion *within* the current session is still undoable via `Cmd+Z` like any other action; the dialog's warning is about the boundary once the project is saved and closed.
- The cover and first page use the same deletion flow as any other page - there is no special protection on them (§1.1, §3.2). Deleting the cover shows a confirmation naming it ("Delete Cover? ..."); the album then simply opens on whatever page is now first.

---

## 10. Save / load - project file format

### 10.1 Package format
A project is a **package directory** (macOS bundle, extension `.washi`) rather than a single flat file:

```
MyAlbum.washi/
├── manifest.json          # Codable Project struct (§3), minus embedded binary data
├── Assets/
│   ├── <asset-uuid-1>.jpg     # embedded copies of every imported photo, full resolution
│   ├── <asset-uuid-2>.png
│   └── ...
└── Thumbnails/
    └── <page-uuid>.png        # cached low-res page renders, for fast navigator/Finder previews
```

This mirrors the reference spec's principle of keeping the project `Codable`, but goes further than "store a JSON project plus security-scoped bookmarks to sources" (the reference's deferred v2 approach): Washi **copies photo bytes into the package on import**, deduplicated by content hash in `assetManifest`. This is a deliberate divergence, justified by §1.1's "never lose work" principle - a scrapbook plan may be reopened months later, by which point a bookmarked source photo is very plausibly moved, renamed, edited elsewhere, or deleted, none of which should be able to break a saved layout. The cost is disk space (a project embeds full-resolution copies of every photo used) and slightly slower import (a copy, not just a reference); both are judged acceptable for a keepsake-planning tool where correctness of the saved state matters more than package size.

### 10.2 Behavior
- `Cmd+S` saves in place; `Cmd+Shift+S` / `File > Save As...` for a new location or copy.
- Autosave to a recovery snapshot every ~2 minutes and on app-quit/background, separate from the user's last explicit save, so a crash doesn't lose more than a couple of minutes of work; on next launch, if a newer autosave exists than the last save, the user is offered a choice to recover it or discard it.
- Opening a `.washi` package (double-click in Finder, or `File > Open...`) reconstructs `Project` from `manifest.json` and lazily loads asset bytes from `Assets/` as pages become visible.
- Title bar shows unsaved-changes state (dot in the close button, standard macOS document convention); quitting or closing with unsaved changes prompts to save.

---

## 11. Export

- `File > Export PDF...` renders every page/spread in album order to a single multi-page PDF via `PDFExporter` (PDFKit), at true physical size (page geometry in points derived from `PageSize`'s cm dimensions, so the PDF opens/prints at 1:1 scale) and at high resolution for embedded raster images (photos/stickers rendered at their full embedded resolution, not the on-screen preview resolution).
- Export is available per-page/per-spread or for the whole album; the dialog defaults to "entire album."
- Locked elements and hidden guides do not affect export (guides never render; locked elements render normally - lock is an editing-only constraint, §6.4).
- Export renderer is parameterized by target size/DPI rather than hardcoded, so a future per-page JPG/PNG export (declined in v1 per your answer to the clarifying question, but cheap to add) doesn't require re-architecting rendering.

---

## 12. Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+N` | New project |
| `Cmd+O` | Open project |
| `Cmd+S` / `Cmd+Shift+S` | Save / Save As |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo |
| `Cmd+G` / `Cmd+Shift+G` | Group / Ungroup |
| `Cmd+D` | Duplicate selection |
| `Delete` | Delete selected element(s) (no confirmation - undoable) |
| `→` / `←` | Next / previous page (with flip animation) |
| `Shift+drag` (rotate handle) | Snap rotation to 15° |
| `Cmd+A` | Select all elements on current page/spread |
| `Cmd+Shift+I` | Import photo |
| `Cmd+E` | Export PDF |
| `1`-`6` | Switch left-toolbar tool (Select, Add Text, Add Image, Add Sticker, Add Border/Frame, Background) |
| `Cmd+/` | Open Keyboard Shortcuts sheet (same as the Info button) |

---

## 13. Findings from competitor research

Reviewed against MyMemories Suite, Scrapbook Crafter, iScrapbook, MemoryMixer, PhotoGrid-adjacent collage tools, and MyScrapBook Studio (browser-based). Features that are near-universal in that set:

**Confirmed in scope for v1** (folded into the sections above, listed here for provenance):
1. **Clipart/sticker library** with both a starter set and personal imports - §7
2. **Group/ungroup as a persistent operation**, not just multi-select - §6.3
3. **Lock/unlock individual elements** - §6.4
4. **Undo/redo** with gesture coalescing - §8
5. **Layer/z-order management with a visible list**, not just front/back commands - §5.6
6. **Drag-and-drop import** from Finder, plus copy/paste - implied by §10/§11, both routed through the same asset-embedding path
7. **Text effects**: shadow, outline/stroke, background fill, independent of border - §3.5
8. **Alignment/snap guides** - §6.5
9. **Multi-page album/project organization** with reorderable pages - §4, §9

**Deferred to v2** (do not build unless explicitly asked):
10. **Patterned/custom background images** (`PageBackground.custom` case already modeled in §3.9, so this is additive - v1 ships solid colors only per your brief's three starter colors, extensible list)
11. **Cross-project personal clipart library** (v1 scopes imported clipart per-project, §7)
12. **Per-page/per-spread JPG/PNG export** (PDF-only in v1 per your answer in §11; renderer already parameterized to support this later)
13. **Image filters/color adjustment** (explicitly a non-goal, §1.2, but noted since several competitors bundle basic filters)
14. **Calendar/date-stamp objects** (a MyMemories Suite feature; out of scope, this is a layout planner, not a calendar tool)
15. **Copy layout to clipboard** for pasting elsewhere (`Cmd+C` at canvas level)
16. **Template/starter-kit pages** (pre-made themed layouts to start from, rather than a blank page)

**Deliberately rejected** (contradicts the brief or design principles): automatic/AI layout suggestions, social sharing integrations, in-app print-shop ordering, filters/retouching, video/Live Photo support.

---

## 14. Edge cases the agent must handle

1. **Photo deleted from disk after import**: no effect - the project embeds a copy at import time (§10.1), so the original file's fate is irrelevant to the project.
2. **Very large source photo** (e.g., 24MP+): decode a downsampled proxy for on-canvas preview/thumbnails; embed and export at full resolution.
3. **Same photo imported twice, including into different pages**: deduplicated by content hash in `assetManifest` - only one copy stored, referenced by multiple `ImageElement`s.
4. **Element resized to near-zero or dragged fully off-page**: allowed during the drag (no clamping mid-gesture, to keep manipulation predictable), but flagged in the layer list with a small warning glyph if fully off-canvas at rest, so it isn't silently lost.
5. **Rotation + resize combined**: resize handles always operate in the element's own rotated coordinate space, not the page's, so a 45°-rotated photo resizes along its own edges as expected.
6. **Deleting a spread**: both pages of the pair are removed together (confirmation names both), never leaving an orphaned `.spreadLeft` without its `.spreadRight`.
7. **Merging two single pages into a spread, or splitting a spread back apart**: explicit, symmetric user action (§3.2, §5.4); re-tags `PageRole` and sets/clears the shared `spreadID`; element positions are preserved per-page in both directions (no re-layout).
8. **Merge requested on two non-adjacent single pages, or on a single page and a spread**: the merge action is simply not offered (not a disabled button with an error) unless exactly two *adjacent* `.singlePage`s are selected together.
9. **Deleting the cover, or the first page**: no special-cased protection - same confirmation flow as any other page (§9). If the cover is deleted, the album opens on whatever page is now first; if all pages are eventually deleted, the canvas shows an empty-album state prompting "Add Page."
10. **Group containing a locked element**: the group can be moved/rotated/resized as a whole (group-level operations override individual lock for group-initiated transforms), but double-clicking into the group to edit that one element still respects its lock. This rule is stated explicitly because it's the one place group and lock semantics could conflict.
11. **Custom page size smaller than any element already placed** (e.g., switching page size after adding elements): elements are not auto-scaled; they simply may extend past the new page bounds, visible on canvas so the user can manually adjust. Auto-fit-to-new-size is a possible v2 convenience, not v1 behavior.
12. **Project opened on a Mac where a custom font used in a `TextElement` isn't installed**: fall back to system default font for display, with the original `fontName` preserved in the saved data (not overwritten) so it renders correctly again on a Mac that has it.
13. **Autosave recovery offered, user declines**: the autosave snapshot is discarded, not silently kept around to reappear later.
14. **Transparent-background image element on a black page vs. a white page**: no special-casing needed - `backgroundIsTransparent` (§3.4) always lets the page background show through per-pixel; behavior is identical regardless of which background color is active.

---

## 15. Acceptance criteria

The build is done when all of the following are demonstrable:

- [ ] `./build.sh` produces a launchable `washi.app` with no `.xcodeproj` in the repo
- [ ] New Project sheet offers page size (28x28cm default among presets), background color, and starting page count (default 5, editable) with the "more can be added later" note visible
- [ ] Confirming New Project produces a cover, a first single page, and enough spreads to reach the requested count
- [ ] `New` and `Info` appear top-left; `Save` and `Export` appear top-right; the floating tool rail appears at the canvas's left edge; the filmstrip with prev/next arrows sits directly below the canvas; the tool control bar sits below the filmstrip
- [ ] Next/previous arrows animate a page-turn between units; clicking a filmstrip thumbnail crossfades directly to it instead
- [ ] Clicking each of the 7 left-toolbar tools switches the active tool and updates the tool control bar's contents immediately, before anything is placed
- [ ] Adding a photo, text box, sticker, and frame to a page all work via the same drag-select-transform interaction model
- [ ] The Properties panel appears on the right only when at least one canvas element is selected, and disappears when selection is cleared
- [ ] The Properties panel's Layers section is visible whenever the panel is open, listing every element on the current page/spread
- [ ] A photo with `backgroundIsTransparent` true shows the page's background color through its transparent areas, on all three starter colors
- [ ] Every border shape in `BorderShape` (straight, squiggly, scalloped, zigzag, dashed, double line) renders correctly around both a photo and a text box, with thickness/amplitude live-adjustable
- [ ] Selecting 3 elements and dragging one resize handle scales all three proportionally, preserving relative layout
- [ ] `Cmd+G` on a multi-selection creates a group that survives closing and reopening the project
- [ ] Locking an element prevents move/resize/rotate/delete until unlocked, but still allows selection
- [ ] Deleting a page prompts a confirmation naming the page/spread; deleting a spread removes both pages together
- [ ] The cover and first page can be deleted through the same flow as any other page, with the same confirmation dialog
- [ ] Selecting two adjacent single-page thumbnails offers "Merge into spread"; selecting a spread thumbnail offers "Split into two pages"; both preserve each page's elements exactly and are reversible via the other action
- [ ] The tool control bar shows the same layout whether or not something is selected: with nothing selected, it displays the text-element controls disabled and zeroed; selecting a text element enables those same controls with its real values
- [ ] Clipart panel shows both the bundled starter set and a successfully imported custom sticker, both insertable onto the canvas
- [ ] Undo reverses each of: element add, element delete, transform change, property change, page add, page delete, group/ungroup, each as a single step
- [ ] Saving, quitting, and reopening a project restores every page, every element's exact position/size/rotation/style, and every embedded photo, with no dependency on the original photo files still existing on disk
- [ ] Moving or deleting the original imported photo file (outside the app) after saving a project has no effect on reopening that project
- [ ] Autosave recovery is offered after a simulated crash (force-quit) if unsaved changes existed
- [ ] Exporting PDF produces a multi-page document at correct physical page size (verified by measuring a page in the PDF against `PageSize`), matching the on-canvas layout
- [ ] Alignment guides appear when dragging an element into alignment with another element or the page center

---

## 16. Open questions

All three from the previous draft are now resolved and folded into the decisions above - recorded here only for provenance:

- **Clipart library scope**: confirmed per-project for v1 (§7, D5).
- **Patterned/textured backgrounds**: confirmed out of scope for now; `PageBackground.custom(assetID:)` stays modeled (§3.9) as a clean v2 extension point if that changes later.
- **Export formats beyond PDF**: confirmed PDF-only for v1 (§11, D7).

No open questions outstanding.

---

## 17. Decision log

| # | Decision | Rationale |
|---|---|---|
| D1 | Pages stored as a flat ordered array with `PageRole` (cover / single / spread-left / spread-right) rather than a nested spread container | Keeps add/remove/reorder as plain array operations; lets a single page sit between two spreads without a special container type |
| D2 | `Transform2D` (position, size, rotation) is the single source of geometry truth for every element type | Makes multi-select group transforms and undo/redo simple value diffs regardless of element type |
| D3 | Photos and stickers are copied into the project package on import, not referenced via security-scoped bookmarks | A scrapbook plan may be reopened long after the source photo has moved or been deleted; correctness of reopened state outweighs package size cost |
| D4 | Borders are procedural/vector (`BorderPathBuilder` generates paths from parametric functions), not a pre-made image library | Matches your stated preference; keeps thickness/amplitude live-adjustable and border style reusable identically on photos and text boxes |
| D5 | Clipart library ships a small built-in starter set plus per-project user imports, both stored through the same `AssetRecord` mechanism as photos | Matches your stated preference; reuses the existing embed/dedupe pipeline instead of a parallel asset system |
| D6 | Persistent named groups (`ElementGroup`, `Cmd+G`) are distinct from ad-hoc marquee multi-select | Marquee selection is transient; competitor research and your own "group select" requirement both point to groups that survive across selection changes and reopening the project |
| D7 | v1 export is PDF only, at true physical page size, with the renderer parameterized for size/DPI | Matches your confirmed requirement; keeps a later JPG/PNG or per-spread export cheap to add without re-architecting |
| D8 | Page-flip animation only plays for sequential Next/Previous navigation; filmstrip thumbnail jumps crossfade | A flip through every intervening page when jumping from page 2 to page 40 would be tedious rather than delightful; matches how physical browsing vs. jumping to a bookmark differ |
| D9 | Autosave writes to a separate recovery snapshot, distinct from the user's last explicit save | Protects against crash/power-loss without silently overwriting the user's intentionally-saved state |
| D10 | One toolbar icon per element type (Select, Add Text, Add Image, Add Sticker, Add Border/Frame, Background), not a single generic "+" menu | Matches your explicit preference after weighing both; keeps the most-reached-for actions one click away instead of one click plus a menu selection. Adding a page is not an element placement, so it lives on the filmstrip (§5.4) rather than the rail |
| D11 | No right-side Inspector; contextual styling controls live in a bottom-center Tool Control Bar, with position/size/rotation and the layer list in a separate right-side Properties panel that only appears when something is selected | Matches your wireframe's bottom-bar layout and your follow-up preference for keeping transform/layers separate; a square canvas also loses less width to a bottom bar than a side panel |
| D12 | Tool control bar shows a tool's controls the moment that tool is selected, before anything is placed on canvas | Matches your explicit preference - lets you set font/border/color once and place multiple elements with those settings already applied |
| D13 | Page navigation is a single filmstrip + prev/next below the canvas; the earlier left-sidebar navigator concept is dropped | Matches your wireframe and your explicit confirmation; avoids two competing places to find the same pages |
| D14 | A standalone `FrameElement` exists alongside the border-as-property on photos/text | Your toolbar sketch included a dedicated border/frame add-icon distinct from photo/text borders, implying a decoration you can place on its own, independent of any photo or text underneath |
| D15 | Cover and first page can be deleted through the same flow as any other page; no page role is permanently protected | You explicitly asked for this; the physical-book metaphor (§1.1) is a helpful default structure, not a hard constraint some real albums won't want |
| D16 | Merging two adjacent single pages into a spread is offered as the explicit inverse of splitting a spread, both preserving each page's elements untouched | You asked for this symmetric behavior; reusing the existing `PageRole`/`spreadID` mechanism from the split direction already in the data model (§3.2) keeps this a re-tagging operation rather than new machinery |
| D17 | The tool control bar always renders the "text element selected" layout, disabled/zeroed when nothing is selected, rather than hiding itself | You asked for this explicitly; keeps the bar's height and position constant so the rest of the chrome doesn't shift as selection changes |
