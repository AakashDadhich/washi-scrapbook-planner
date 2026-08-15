# Washi

A native macOS scrapbook-planning app: lay out photos, text, stickers, and
decorative borders across pages and spreads, then export the album to PDF.

Built to `washi-spec.md` (behaviour) and `washi-build-plan.md` (order).

## Build and run

Requires macOS 14+ and the Swift toolchain from Xcode's command line tools. There
is no `.xcodeproj`: everything is Swift Package Manager.

```sh
./build.sh          # release build, assembles and ad-hoc signs washi.app
open washi.app
```

## Layout of the source

```
Sources/washi/
├── washiApp.swift     @main App entry point, window, menu commands
├── Models/             value types: Project → Album → Page → PageElement, Transform2D, BorderStyle, PageSize
├── Store/               ProjectStore (single source of truth), package read/write, undo, clipart library
├── Rendering/           PageCanvasView/SpreadView, selection handles, border paths, page-flip animation, PDFExporter
├── UI/                  tool rail, filmstrip, per-tool control bars, properties panel, sheets
└── Util/                image decoding/downsampling, transform maths, colour/unit conversion
```

Two rules hold the design together:

1. **One store, checkpoint-wrapped.** Every mutating `ProjectStore` method wraps
   its change in `withUndoCheckpoint { … }`, or brackets a continuous drag/
   resize/rotate gesture with `beginGestureSnapshot()`/`commitGestureCheckpoint()`.
   That's what turns every edit into exactly one undo step; no view writes to
   `Project` directly.
2. **Shared content views.** `PDFExporter` reuses the same text/frame/border
   content views that draw the live canvas — just swapping in full-resolution
   images in place of the downsampled on-screen preview — so the exported PDF
   can't visually drift from what's on screen.

There is no test target in this repo.

## Keyboard shortcuts

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
| `1`-`7` | Switch left-toolbar tool (Select, Add Page, Add Text, Add Image, Add Sticker, Add Border/Frame, Background) |
| `Cmd+/` | Open Keyboard Shortcuts sheet (same as the Info button) |
