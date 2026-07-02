# Quill

A tiny personal drawing app for **iPad (Apple Pencil) + Mac**. Draw on one, see
it live on the other, each with a ghost cursor showing the other's pointer.
Sketches are saved like Notes and sync between the two devices when they're near
each other — **peer-to-peer, no account, no server, no cost.**

The UI follows the **Studio** design (`design_handoff_quill_redesign/`): a
sidebar + thumbnail-grid home, a single-row drawing bar with a five-tool
switcher (Text is a tool), hairline borders on a warm off-white palette, and
the blue quill app icon.

## How it works

- **One codebase** — SwiftUI + PencilKit, shipped to iPad (iOS) and to Mac via
  **Mac Catalyst**. Apple's `PKCanvasView` + built-in tool palette on both.
- **Live sync** — MultipeerConnectivity streams strokes + cursor position while
  both devices are nearby on the same Wi-Fi and viewing the same sketch.
- **Catch-up + conflict sync** — each pad carries a per-device **version
  vector**. On connect (and on changes) devices swap a manifest and reconcile:
  one side newer → fast-forward; both edited independently → **fork** into
  `Sketch` + `Sketch (conflict)` (no work lost); deletes travel as **tombstones**
  so they don't resurrect, but a peer edit newer than the delete brings it back.
- **Local storage** — each device keeps sketches on disk (Application Support),
  one small metadata file + one drawing file per sketch. No Core Data, no iCloud.
- **Home** — sidebar (search, All pads / Unsorted / folders, connection
  status) beside a grid of live pad thumbnails rendered from each pad's ink
  over its paper style. Conflict forks nest under their originals with a FORK
  badge; search results highlight the matched title or text snippet.
- **Folders** — create/rename/delete from the sidebar (deleting moves pads to
  Unsorted). Folders sync too; concurrent renames resolve deterministically
  (newest wins), never fork.
- **Paper styles** — blank / lines / grid / dots per pad via the paper chip;
  the style syncs with the pad (live, if both are viewing it).
- **Tools** — the Mac bar has a five-tool switcher: pen / marker / pencil /
  eraser / **Text**, plus six ink colors and a width slider (Catalyst's
  PKToolPicker is unreliable, so the Mac doesn't use it; the iPad keeps
  Apple's full palette and gets Text as a nav-bar tool button).
- **Text blocks** — pick the Text tool, tap anywhere: the selected block shows
  corner handles and a floating strip (drag ✥, resize A−/A+, delete). Esc
  deselects, then exits the tool. Pen input pauses while Text is active.
  Blocks sync with the pad, live when co-viewing.
- **Zoom** — pinch on both platforms (up to 4×); the Mac also has − / % / +
  buttons. Zoom is per-device; paper, text, and the peer cursor stay aligned.
- **Presence** — grid cards show an eye pill when the other device has that
  pad open; inside a shared pad you see a green chip and the peer's cursor
  (accent triangle + name pill).
- **Sync-on-close cadence** — while you draw, the other device doesn't
  re-download the pad; it catches up the moment you close it (or streams live
  if it's viewing the same pad). Radios also go quiet once connected. Keeps
  CPU/battery calm.

## Prerequisites

- **Xcode** (full app, not just Command Line Tools):
  ```sh
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  xcodebuild -runFirstLaunch
  ```
- **XcodeGen** (generates the `.xcodeproj` from `project.yml`):
  ```sh
  brew install xcodegen
  ```
- A **free Apple ID** added in Xcode → Settings → Accounts. No paid Developer
  Program needed (there's no CloudKit).

## Build & run

```sh
cd quill
xcodegen generate          # creates Quill.xcodeproj
open Quill.xcodeproj
```

In Xcode:

1. Select the **Quill** target → **Signing & Capabilities** → set **Team** to
   your Apple ID and pick a unique **Bundle Identifier** (e.g.
   `com.<you>.quill`). Do it for the Mac Catalyst destination too.
2. **Run on iPad:** pick your iPad as the destination and hit Run. First run
   needs the iPad in **Developer Mode** (Settings → Privacy & Security →
   Developer Mode) and trusted via cable.
3. **Run on Mac:** switch the destination to **My Mac (Mac Catalyst)** and Run.

Regenerate the project after adding/removing files: `xcodegen generate`.

## Testing the live experience (needs 2 real devices)

1. iPad + Mac on the **same Wi-Fi**.
2. Run Quill on both. The list shows a green "connected" badge once they find
   each other.
3. Create a sketch on one device → it appears on the other (catch-up sync).
4. Open the same sketch on both → draw on one, strokes + a ghost cursor appear
   live on the other. Both directions work.

> The MultipeerConnectivity live/cursor features need two physical devices — the
> simulator's peer-to-peer support is unreliable.

## Running the unit tests

```sh
xcodebuild test -project Quill.xcodeproj -scheme Quill \
  -destination 'platform=macOS,variant=Mac Catalyst'
```
Or just press **Cmd-U** in Xcode. Covers the sync message format and the local
store (CRUD + last-writer-wins).

## Project layout

```
Quill/
  QuillApp.swift                     app entry; wires stores + connectivity
  Theme/QuillTheme.swift             Studio design tokens (colors/radii/type)
  Model/
    SketchMetadata.swift             on-disk metadata + list/manifest digest
    SketchStore.swift                local file-based sketch library
    ThumbnailStore.swift             cached PKDrawing previews for the grid
    HomeModels.swift                 search matches, conflict pairing, labels
  Connectivity/
    SyncMessage.swift                Codable wire format (live + catch-up)
    MultipeerSession.swift           MPC transport (advertise/browse/send)
    ConnectivityManager.swift        live channel, presence, cadence
    ConnectivityManager+Library.swift  catch-up reconcile (pads + sections)
    SyncReconciler.swift             pure pad-sync decisions (pull/fork/tombstone)
    SectionSync.swift                pure section merge (LWW, deterministic)
  Views/
    SketchListView.swift             home composer (sidebar | grid/search/empty)
    Home/                            sidebar, grid, cards, search, empty state
    SketchDetailView.swift           drawing screen: bars, canvas, overlays
    MacToolStrip.swift               Mac 5-tool switcher (incl. Text tool)
    CanvasView.swift                 PKCanvasView bridge; strokes/cursor/zoom
    TextBlockLayer.swift             text blocks + floating control strip
    RemoteCursorOverlay.swift        the peer's ghost cursor
    PaperBackgroundView.swift        lines/grid/dots paper rendering
  Resources/                         Info.plist, entitlements, assets + icon
QuillTests/                          unit tests
design_handoff_quill_redesign/       Studio design spec, mocks, icon source
project.yml                          XcodeGen spec (source of truth)
```

## Known limitations (v1, by design)

- **Nearby only.** No internet sync — devices must be on the same local network
  to go live or reconcile. (That's the trade for being free + serverless.)
- **Concurrent offline edits fork.** Editing the same pad on both devices while
  apart yields a `… (conflict)` copy after they reconnect; you merge/delete by
  hand. Safe (never silently loses work), but you do the cleanup.
- **Live undo/erase isn't streamed.** Strokes append live; an undo or erase
  shows up on the peer on the next full sync, not instantly.
- **Different screen sizes:** the cursor maps to the shared drawing coordinate,
  so a point past the edge of the smaller screen is simply clipped.
- **Editing a pad at the exact moment a conflict for it resolves** is an
  unhandled edge (rare) — the on-screen canvas may lag the resolved copy until
  you reopen it.
