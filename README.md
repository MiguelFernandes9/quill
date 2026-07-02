# Quill

A tiny personal drawing app for **iPad (Apple Pencil) + Mac**. Draw on one, see
it live on the other, each with a ghost cursor showing the other's pointer.
Sketches are saved like Notes and sync between the two devices when they're near
each other — **peer-to-peer, no account, no server, no cost.**

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
- **Sections** — pads group into folders (create/rename/delete; deleting a
  section moves its pads to Unfiled). Folders sync too; concurrent renames
  resolve deterministically (newest wins), never fork.
- **Paper styles** — blank / lines / grid / dots per pad, switchable from the
  pad's toolbar; the style syncs with the pad (live, if both are viewing it).
- **Mac tool strip** — the Mac has its own pen/marker/pencil/eraser, six
  colors, and a width slider (Catalyst's PKToolPicker palette is unreliable, so
  it isn't used there; the iPad keeps Apple's full palette).
- **Text blocks** — toggle text mode (T button) to add text anywhere: tap a
  block for its control strip (drag ✥, resize A−/A+, delete); Esc deselects,
  tap empty space deselects then creates. Pen input pauses in text mode.
  Blocks sync with the pad, live when co-viewing.
- **Zoom** — pinch on both platforms (up to 4×); the Mac also has − / % / +
  buttons. Zoom is per-device; paper, text, and the peer cursor stay aligned.
- **Search** — the main page's search field matches pad titles and text-block
  content.
- **Presence** — the pad list shows an eye badge on whichever pad the other
  device has open; inside a shared pad you see the peer's name and cursor.
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
  QuillApp.swift                     app entry; wires store + connectivity
  Model/
    SketchMetadata.swift             on-disk metadata + list/manifest digest
    SketchStore.swift                local file-based sketch library
  Connectivity/
    SyncMessage.swift                Codable wire format (live + catch-up)
    MultipeerSession.swift           MPC transport (advertise/browse/send)
    ConnectivityManager.swift        live channel, presence, cadence
    ConnectivityManager+Library.swift  catch-up reconcile (pads + sections)
    SyncReconciler.swift             pure pad-sync decisions (pull/fork/tombstone)
    SectionSync.swift                pure section merge (LWW, deterministic)
  Views/
    SketchListView.swift             Notes-like list (new/rename/delete)
    SketchDetailView.swift           canvas screen + cursor overlay wiring
    CanvasView.swift                 PKCanvasView bridge; strokes + cursor
    RemoteCursorOverlay.swift        the peer's ghost cursor
  Resources/                         Info.plist, entitlements, assets
QuillTests/                          unit tests
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
