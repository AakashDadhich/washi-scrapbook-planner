# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Washi is a native macOS scrapbook-planning app: a canvas-based editor for laying out photos, text, stickers, and decorative borders across pages/spreads, with PDF export. Swift Package Manager project, zero third-party dependencies — SwiftUI, AppKit, CoreGraphics, PDFKit, ImageIO, UniformTypeIdentifiers only. No `.xcodeproj`/`.xcworkspace` is committed; Xcode command line tools must be installed to build.

**`washi-spec.md`** is the authoritative product spec (data model, UI layout, interaction rules, edge cases, acceptance criteria) — consult it directly rather than re-deriving behavior from code when the intent isn't obvious. **`washi-build-plan.md`** breaks the spec into milestones (M1–M16); each milestone is one git commit (`git log --oneline` shows the `M<N>: <name>` pattern). Both docs are the source of truth for "is this a bug or intended."

## Commands

Build and assemble the app bundle:
```
./build.sh
```
This runs `swift build -c release`, assembles `washi.app/Contents/{MacOS,Resources}`, copies in `Info.plist` and `Resources/Assets/StarterClipart/`, and ad-hoc codesigns (`codesign --force --deep --sign -`). Run the result with `open washi.app`.

For faster iteration without reassembling the bundle:
```
swift build -c release   # or drop -c release for a debug build
```

There is no test target and no lint config in this repo.

## Architecture

### Layers

- **`Sources/washi/Models/`** — plain `Codable`/`Equatable` value types: `Project` → `Album` → `Page` → `PageElement` (one of `TextElement`/`ImageElement`/`StickerElement`/`FrameElement`), plus `Transform2D` (position/size/rotation — the single geometry source of truth for every element type), `BorderStyle`, `PageBackground`, `PageSize`, `ElementGroup`. `PageRole` (cover/single/spreadLeft/spreadRight) tags a flat, ordered `pages` array rather than nesting spreads in a container type — this keeps add/remove/reorder plain array operations.
- **`Sources/washi/Store/`** — `ProjectStore` is a `@MainActor` `ObservableObject` and the single source of truth for the currently-open project; its surface area is split across `ProjectStore+{Elements,Pages,Properties,Selection,Styling,Clipart}.swift` extensions rather than one file. `ProjectFile` handles reading/writing the `.washi` package format and asset import (dedup by content hash). `UndoStack` and `ClipartLibrary` are the other two store-level pieces.
- **`Sources/washi/Rendering/`** — `PageCanvasView` renders one page (elements, selection handles, marquee, alignment guides) and owns **all** interaction via a single unified `DragGesture` that does its own hit-testing against handle positions and element geometry — this is deliberate (see the doc comment in that file): per-element gesture recognizers didn't reliably respect visual z-order on macOS. `PageUnitView` dispatches to `PageCanvasView` (single page) or `SpreadView` (two facing pages); both the live canvas and the filmstrip thumbnails reuse this same view tree, distinguished by an `isInteractive` flag that suppresses handles/gestures/context-menus for thumbnails. `PDFExporter` reuses the text/frame/border content views for pixel-identical export, but always loads full-resolution images rather than the downsampled on-canvas proxy.
- **`Sources/washi/UI/`** — app chrome: `ToolRail` (floating left toolbar), `PageFilmstripView` (thumbnails + prev/next), `ToolControlBar` (bottom-center, contents driven by active tool or current selection, with per-tool controls in `ToolControlBar/`), `PropertiesPanel` (right side, visible only when something's selected), plus sheets (`NewProjectSheet`, `ClipartPanel`, `ExportSheet`, `KeyboardShortcutsSheet`).
- **`Sources/washi/Util/`** — `ImageLoader` (see below), `TransformMath` (resize/rotate math, all in an element's own rotated local coordinate space), `ColorHex`, `UnitConversion`.

### Persistence and undo

- Projects are `.washi` package directories: `manifest.json` + `Assets/` (imported photo/sticker bytes, deduped by SHA-256 content hash) + `Thumbnails/`. Photos/stickers are copied into the package at import time, not referenced by path — the source file's fate after import is irrelevant.
- Undo/redo is whole-`Project` value snapshots (cheap since `Project` is `Codable`/`Equatable` and holds no embedded binary data). Every mutating `ProjectStore` method should wrap its mutation in `withUndoCheckpoint { … }`, or bracket a continuous gesture (drag/resize/rotate) with `beginGestureSnapshot()`/`commitGestureCheckpoint()` so the whole gesture collapses into one undo step rather than one per frame.
- Autosave snapshots live alongside the package; `ProjectStore.pendingAutosaveRecovery(packageURL:)` is checked on open and offers recovery — this is the mechanism spec §14 edge case 13 and the corresponding acceptance-criteria bullet require, so don't reintroduce a path that opens a project without going through it.

### Images

`ImageLoader` has two decode paths because `CGImageSourceCreateWithURL` returns an empty source for SVG/PDF on this platform despite `NSImage` handling them fine: every entry point tries the fast `CGImageSource` path first (the common JPEG/PNG case) and falls back to rasterizing via `NSImage`. The canvas and thumbnails always use `downsampledImage(at:maxDimension:)`; only `PDFExporter` uses `fullResolutionImage(at:)`.
