# Washi - Build Plan

**For:** an AI coding agent building this app end-to-end
**Source of truth:** `washi-spec.md` (read it in full before starting - this document sequences the work, it does not repeat the design decisions, rationale, or data model details already written there)

---

## How to use this plan

1. Read `washi-spec.md` completely first. Every section reference below (§X) points into that document - look it up rather than guessing at field names, enum cases, or behavior.
2. Work through the milestones **in order**. Each one lists what it depends on; don't start a milestone before its dependencies are done.
3. After each milestone: run `./build.sh`, launch `washi.app`, and manually verify the "Definition of done" items for that milestone before moving on. Don't batch multiple milestones into one untested commit.
4. Commit (or otherwise checkpoint) at the end of each milestone with a message naming it, e.g. `M4: New Project wizard`. If something in the spec is ambiguous once you're actually implementing it, make the most reasonable call, note the assumption in the commit message, and keep moving - don't stall the build on it.
5. §15 in the spec ("Acceptance criteria") is the definitive checklist for the whole app. This plan distributes those items across the milestones where they first become testable, but do a full pass over the entire §15 list at Milestone 16, since some items only make sense once everything is wired together.
6. Treat §14 ("Edge cases") as required behavior, not stretch goals - each one is called out in the milestone where it applies.

---

## M1 - Project scaffolding & empty app shell

**Builds:** §2 (Technology & build) in full.

- `Package.swift` targeting `.macOS(.v14)`, single executable target `washi`, zero third-party dependencies.
- `build.sh` per §2.4: `swift build -c release`, assemble `washi.app/Contents/{MacOS,Resources}`, copy `Info.plist` + compiled binary in, ad-hoc codesign, print the `open` hint.
- `Resources/Info.plist` and `Resources/washi.entitlements` per §2.4-2.5, including the `.washi` document type registration.
- `Sources/washi/washiApp.swift`: a minimal `@main App` that opens a blank window. Call `NSApplication.shared.setActivationPolicy(.regular)` on launch if focus doesn't take when launched from Terminal (§2.4 note).
- Create the full empty directory skeleton from §2.2 (`Models/`, `Store/`, `Rendering/`, `UI/`, `UI/ToolControlBar/`, `Util/`) so later milestones just add files to an already-correct structure.

**Depends on:** nothing.

**Definition of done:** `./build.sh` produces a launchable `washi.app` with no `.xcodeproj` in the repo, and it opens to a blank window. (First bullet of §15.)

---

## M2 - Data model

**Builds:** §3 (Data model) in full - every struct/enum in 3.1 through 3.9.

- `Models/Project.swift`, `Album.swift`, `Page.swift`, `PageElement.swift`, `TextElement.swift`, `ImageElement.swift`, `StickerElement.swift`, `FrameElement.swift`, `BorderStyle.swift`, `PageBackground.swift`, `PageSize.swift`, `Transform2D.swift`, `ElementGroup.swift` - one file per major type as listed in §2.2's tree.
- Everything `Codable`, matching the exact shapes in §3 (don't invent extra fields; don't drop any).
- `PageSize`'s built-in presets (§3.9) as static values somewhere sensible (e.g. `PageSize.presets`).
- `PageBackground`'s built-in starter palette (§3.9: White `#FFFFFF`, Kraft brown `#C8A97E`, Black `#0A0A0A`) as static values, stored as data (not a hardcoded enum) so more can be added later without a migration, per the spec's comment.

**Depends on:** M1.

**Definition of done:** the package builds with these models and no UI. Write a throwaway `main`-level sanity check (or just confirm at the call site during M3) that a fully-populated `Project` round-trips through `JSONEncoder`/`JSONDecoder` without data loss - this is the property the rest of the app depends on.

---

## M3 - Project store & persistence

**Builds:** §10 (Save / load - project file format) in full, plus the `AssetRecord`/`assetManifest` embedding behavior described in §3.1.

- `Store/ProjectStore.swift` - `ObservableObject`, single source of truth for the currently-open `Project`.
- `Store/ProjectFile.swift` - reads/writes the `.washi` package format from §10.1 exactly: `manifest.json`, `Assets/<uuid>.<ext>`, `Thumbnails/<page-uuid>.png`.
- Asset embedding: importing a photo copies its bytes into `Assets/`, computes a content hash, and dedupes against `assetManifest` (§3.1, §10.1) - re-importing the same file (even from a different path) must not create a second copy.
- Autosave: a timer-driven recovery snapshot every ~2 minutes and on quit/background, kept separate from the user's last explicit save (§10.2). On next launch, if a newer autosave exists than the last save, offer to recover or discard it (§14 edge case: "Autosave recovery offered, user declines" - discard means discard, don't silently keep it around).
- `Cmd+S` / `Cmd+Shift+S` save behavior, unsaved-changes indicator in the title bar (§10.2) - the actual menu/shortcut wiring can happen in M15, but the underlying save/save-as functions belong here.

**Depends on:** M2.

**Definition of done:**
- Build a `Project` in memory, save it, quit, reopen it, and confirm every field matches (§15: "Saving, quitting, and reopening a project restores every page, every element's exact position/size/rotation/style, and every embedded photo...").
- Move or delete the original imported photo file outside the app after saving, then reopen the project - it must still work, since the photo is embedded, not referenced (§15, §14 edge case 1).
- Force-quit with unsaved changes present, relaunch, and confirm autosave recovery is offered (§15).

---

## M4 - New Project wizard & page creation logic

**Builds:** §4 (New Project wizard) in full.

- `UI/NewProjectSheet.swift`: page size (28×28cm default among the §3.9 presets, plus custom entry with a unit toggle), starting background color, starting page count (numeric stepper, default 5, with the "you can add or remove pages at any time" note), album name.
- Wire confirmation to `ProjectStore`: build one `.cover` page, one `.singlePage` ("first page"), and enough `.spreadLeft`/`.spreadRight` pairs to reach the requested content-page count, all using the chosen size/background (§4). This is the first place `PageRole` assignment logic actually gets exercised - get it right here since M6-M9 all depend on it.

**Depends on:** M2, M3.

**Definition of done:** the two related §15 bullets - the sheet offers all four fields with the note visible, and confirming produces the correct cover + first page + N spreads.

---

## M5 - App chrome (static layout)

**Builds:** the structural layout from §5.1-§5.4, without wiring functionality yet - this is "build the window's skeleton correctly" before "make it do things."

- `UI/TitleBarControls.swift`: `New` and `Info` buttons top-left; `Save` and `Export` buttons top-right (§5.1). `New` opens the M4 sheet. `Info` and `Save`/`Export` can be stubbed (no-op or disabled) here - they get wired in M14/M15.
- `UI/ToolRail.swift`: the floating left toolbar with all 7 icons in order (§5.2) - Select/Move, Add Page, Add Text, Add Image, Add Sticker/Washi Tape, Add Border/Frame, Background color. Radio-button single-active-tool behavior. The tools don't need to *do* anything yet beyond visibly becoming active.
- `UI/PageFilmstripView.swift`: left arrow, horizontal thumbnail strip, right arrow below the canvas (§5.4). Thumbnails can render as placeholder rectangles for now; wire them to real page content in M6.
- A canvas placeholder area (§5.3) sized correctly relative to the current `PageSize`, with no elements rendered yet.
- `UI/ToolControlBar.swift`: an empty/placeholder bottom bar sized and positioned correctly, subviews wired in M10.
- No `PropertiesPanel` yet - it only appears once selection exists (M8/M11).

**Depends on:** M2, M3, M4 (so New Project can populate something for the chrome to display).

**Definition of done:** §15's chrome-position bullet - New/Info top-left, Save/Export top-right, tool rail at the canvas's left edge, filmstrip+arrows directly below canvas, tool control bar below that.

---

## M6 - Page navigation, add/delete/merge/split

**Builds:** §5.3-§5.4 fully wired, plus §9 (Adding/removing pages), plus the merge/split behavior from §3.2 and §14 edge cases 6-9.

- `Rendering/PageCanvasView.swift` (cover/single page) and `Rendering/SpreadView.swift` (two facing pages, grouping consecutive `.spreadLeft`/`.spreadRight` by matching `spreadID`) - rendering the page background only for now; elements come in M7.
- Real filmstrip thumbnails: live low-res renders of each page/spread, click-to-jump with a crossfade (not a flip).
- `Rendering/PageFlipTransition.swift`: the ≈400ms `CATransform3D` page-curl animation for prev/next arrow navigation, with a reduce-motion crossfade fallback (§5.4).
- Add Page tool (toolbar icon and filmstrip's trailing `+`) - add single page or spread, inserted after the current page (§9).
- Delete page: confirmation dialog naming the page/spread (§9); deleting a spread removes both pages together, never orphaning one side (§14 edge case 6). No special protection on cover/first page - same flow applies to them (§9, §14 edge case 9).
- Merge/split: shift-click two adjacent single-page thumbnails → "Merge into spread"; right-click a spread thumbnail → "Split into two pages." Both re-tag `PageRole`/`spreadID` only, never touching element positions (§3.2, §14 edge case 7). Merge is only offered for exactly two *adjacent* single pages (§14 edge case 8).

**Depends on:** M5.

**Definition of done:** the §15 bullets covering flip/crossfade navigation, page deletion with confirmation, cover/first-page deletion, and merge/split.

---

## M7 - Element placement & rendering

**Builds:** §3.3-§3.7 rendering, and the placement half of §5.2 (Add Text/Image/Sticker/Border-Frame tools).

- `Rendering/ElementView.swift`: renders `PageElement` by switching on `ElementContent` - text, image (crop-filled, respecting `backgroundIsTransparent`), sticker, frame. Borders/shadows can render as flat/placeholder styling here; the real procedural border system comes in M9.
- Add Text: click/drag on canvas places a `TextElement` with default styling.
- Add Image: file picker or drag-and-drop from Finder, imports through the M3 asset-embedding pipeline, places an `ImageElement`.
- Add Sticker: for now, wire it to place a placeholder colored square `StickerElement` referencing a dummy asset - the real Clipart panel arrives in M12, don't block this milestone on it.
- Add Border/Frame: places a standalone `FrameElement` (§3.7) with default border style.
- After any placement, the active tool returns to Select/Move with the new element selected (§5.2) - selection itself is built in M8, so this hook can be a no-op until then.
- `zIndex` assignment on placement (new elements go on top).

**Depends on:** M6.

**Definition of done:** §15's bullet that photo/text/sticker/frame placement all work via the same interaction model, and the transparency bullet (a photo with `backgroundIsTransparent` shows the page background through it on all three starter colors).

---

## M8 - Selection & transform

**Builds:** §6 (Selection & transform) in full.

- `Rendering/SelectionHandlesView.swift`: corner + edge-midpoint resize handles and a rotation handle, all respecting the element's current rotation (§6.1). Proportional resize by default, modifier-key for free resize; Shift-drag rotation snaps to 15°.
- Single selection (click), marquee selection (drag on empty canvas), Shift-click add/remove (§6.2).
- Multi-select group transform: one bounding-box handle set, move/resize/rotate applied proportionally across the selection's `Transform2D`s (§6.2).
- Persistent groups: `Cmd+G`/`Cmd+Shift+G`, stored in `Page.groups`, surviving selection changes and reopening the project (§6.3).
- Locking: per-element/group lock, blocking move/resize/rotate/delete but not selection (§6.4). Edge case: a locked element inside a group still moves with group-level transforms, but double-clicking into the group to edit that one element respects its lock (§14 edge case 10).
- Alignment/snap guides on drag, suspendable with a modifier key (§6.5).
- Layer order: Bring to Front/Send to Back/Bring Forward/Send Backward via right-click and an Arrange menu, operating on `zIndex` (§6.6).
- Edge case: elements resized to near-zero or dragged off-page are allowed mid-gesture, no clamping, but flagged if fully off-canvas at rest (§14 edge case 4). Resize handles operate in the element's own rotated coordinate space (§14 edge case 5).

**Depends on:** M7.

**Definition of done:** the §15 bullets on proportional multi-select resize, `Cmd+G` group persistence, and lock behavior.

---

## M9 - Border style system

**Builds:** §3.8 (BorderStyle) fully, replacing the placeholder borders from M7.

- `Rendering/BorderPathBuilder.swift`: generates a `CGPath` by walking an element's rounded-rect perimeter and substituting the parametric wave/scallop/zigzag function per edge for each `BorderShape` case - straight, squiggly (amplitude/wavelength), scalloped (radius), zigzag (amplitude/wavelength), dashed (dash/gap length), double line (gap).
- Apply identically to `ImageElement`, `TextElement`, and `FrameElement` borders - same builder, same parameters, three call sites.
- Live-adjustable thickness and amplitude/wavelength (these will be wired to actual UI sliders in M10, but the rendering needs to respond to parameter changes now).

**Depends on:** M8 (elements need to exist and be selectable to test border editing end-to-end, even though the builder itself only depends on M7's rendering).

**Definition of done:** §15's border bullet - every `BorderShape` case renders correctly around both a photo and a text box, with thickness/amplitude changes visibly reflected.

---

## M10 - Tool control bar

**Builds:** §5.5 in full - this is where all the per-tool/per-selection editing controls actually live.

- `UI/ToolControlBar/BorderStylePicker.swift`: the shared component (shape gallery, thickness/amplitude sliders, color swatch + RGB hex fields) used by every border-bearing control panel below.
- `UI/ToolControlBar/TextToolControls.swift`, `ImageToolControls.swift`, `StickerToolControls.swift`, `FrameToolControls.swift`, `BackgroundToolControls.swift` - one per row of the table in §5.5.
- Wire the "shows the tool's controls the moment the tool is activated, before placement" behavior (§5.2, §5.5) - selecting "Add Text" in the toolbar immediately populates the bar with text controls pre-setting what the next placed text box will use.
- Wire the "Select/Move, nothing selected" state to render the *same* text-control layout, disabled and zeroed, rather than hiding the bar (§5.5) - this is a specific, deliberate requirement, don't collapse it back to empty/hidden.
- Wire Background color tool to the page background swatch grid + RGB hex fields.

**Depends on:** M9 (needs the real border system to make the border picker meaningful).

**Definition of done:** the §15 bullet confirming the bar shows the same layout selected vs. unselected (disabled/zeroed vs. live values), and that each of the 7 toolbar tools updates the bar's contents immediately on activation.

---

## M11 - Properties panel

**Builds:** §5.6 in full.

- `UI/PropertiesPanel.swift`, appearing on the right only when ≥1 element is selected (never always-on chrome, unlike the tool control bar).
- **Transform** section: numeric x/y, w/h, rotation fields, applying as a group transform when multi-selected; includes the lock toggle from §6.4.
- **Layers** section: top-to-bottom element list for the current page/spread, name/visibility/lock state, drag-to-reorder wired to `zIndex` (§6.6), click-to-select synced with canvas selection. Visible whenever the panel is open, independent of selection count.

**Depends on:** M8, M10.

**Definition of done:** the two §15 bullets - panel appears/disappears correctly with selection, and the Layers section is always present when the panel is open.

---

## M12 - Clipart / sticker library

**Builds:** §7 in full, replacing the M7 placeholder sticker.

- Source or generate a small starter clipart set (~40-60 assets per §7's target) as simple SVG doodles, washi-tape strip patterns, and basic decorative shapes (stars, hearts, arrows, banners). These are original, simple vector shapes the agent should generate directly (e.g. programmatically or by hand-authoring SVG) - not sourced from copyrighted third-party clipart. Ship them in `Resources/Assets/StarterClipart/`.
- `UI/ClipartPanel.swift`: searchable grid split into "Starter Set" / "My Imports," opened from the Add Sticker toolbar icon. Drag onto canvas or click to insert at canvas center.
- Import-your-own: accepts PNG/JPEG/SVG/PDF, routes through the M3 asset-embedding pipeline exactly like a photo import.
- `StickerElement.tint` recoloring for SVG assets.

**Depends on:** M3, M10 (the sticker tool's control-bar entry point).

**Definition of done:** §15's clipart bullet - both the starter set and a freshly-imported custom sticker are visible and placeable.

---

## M13 - Undo / redo

**Builds:** §8 in full, wired retroactively across every mutation introduced in M4-M12.

- `Store/UndoStack.swift`: value-level diffs pushed for every `Project` mutation - element add/remove/transform, property edits, page add/remove/reorder/merge/split, background/size changes, grouping.
- Gesture coalescing: an in-progress drag/resize/rotate collapses to a single undo step on gesture end, not one step per frame.
- `Cmd+Z`/`Cmd+Shift+Z` (or `Cmd+Y`).

This milestone touches a lot of existing code - go through each mutation point built in M4-M12 and confirm it's routed through `UndoStack` rather than mutating `ProjectStore` directly.

**Depends on:** M4 through M12 (everything that can mutate state).

**Definition of done:** §15's undo bullet - element add/delete, transform change, property change, page add/delete, and group/ungroup each undo as one step.

---

## M14 - Export to PDF

**Builds:** §11 in full.

- `Rendering/PDFExporter.swift` using PDFKit: renders every page/spread in album order to a multi-page PDF at true physical size (points derived from `PageSize`'s cm dimensions) and full embedded-image resolution, not preview resolution.
- Wire the `Export` title-bar button (stubbed since M5) to this, defaulting to "entire album" with a per-page/per-spread option.
- Parameterize the renderer by target size/DPI even though only PDF ships in v1 (§11's explicit note - this keeps a later JPG/PNG export cheap).
- Locked elements render normally on export; guides never render (§11).

**Depends on:** M9 (borders must render correctly to export correctly), M13 (not a hard dependency, but export should happen after state mutations are stable).

**Definition of done:** §15's export bullet - a multi-page PDF at correct physical page size matching the on-canvas layout.

---

## M15 - Keyboard shortcuts & Info sheet

**Builds:** §12 in full, plus the `Info` button stub from M5.

- Wire every shortcut in §12's table to its corresponding action from earlier milestones.
- `UI/KeyboardShortcutsSheet.swift`, opened from the title bar's `Info` button and from `Cmd+/`, listing the full shortcut table.

**Depends on:** M4 through M14 (needs every action it's binding a shortcut to).

**Definition of done:** every shortcut in the §12 table works; Info button opens a sheet listing them all.

---

## M16 - Edge-case hardening & full acceptance pass

This is not new feature work - it's verification. Go through **every item in §14 (Edge cases)** one at a time and confirm the built app actually handles it as specified; fix anything that doesn't. Then go through **every item in §15 (Acceptance criteria)** top to bottom as a literal checklist, testing each one manually in the running app. Don't mark this milestone done until every box in §15 is genuinely checked, not assumed.

Pay particular attention to the edge cases that cut across multiple milestones and are easy to miss in isolated testing:
- Font fallback when a project's custom font isn't installed on the current Mac (§14 edge case 12), preserving the original `fontName` in saved data.
- Page size changed after elements already exist - no auto-scaling, elements may extend past new bounds (§14 edge case 11).
- Same photo imported twice, or into multiple pages - deduped by content hash, not stored twice (§14 edge case 3).
- Very large source photos - downsampled proxy for preview, full resolution at export (§14 edge case 2).

**Depends on:** M1 through M15.

**Definition of done:** every checkbox in spec §15 is checked, and every numbered item in spec §14 has been individually verified.
