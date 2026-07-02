# Handoff: Quill "Studio" Redesign

## Overview
A visual + UX redesign of **Quill**, a personal drawing app for iPad (Apple Pencil) + Mac (Mac Catalyst), built in SwiftUI + PencilKit. Repo: `MiguelFernandes9/quill`. The redesign ("Studio" direction) restyles the pad list and drawing screen, and makes one UX change: **text mode becomes a fifth Text tool in the tool switcher** (no separate mode toggle on Mac). It also ships a new app icon.

The target codebase is the existing SwiftUI app — keep all current behavior (sections, search, MultipeerConnectivity sync, presence, paper styles, zoom, conflict forks) and re-skin it.

## About the Design Files
`Quill Redesign.dc.html` is a **design reference created in HTML** — a mockup canvas showing intended look and behavior, not production code. The task is to **recreate these designs in the existing SwiftUI/Catalyst codebase** using its established patterns (SwiftUI views, `#if targetEnvironment(macCatalyst)` splits, AppStorage persistence). The relevant approved options in the HTML file are: **1b** (Mac home), **2a** (iPad home), **2b** (iPad drawing screen), **2c** (Mac states), **4a** (Mac drawing screen — final toolbar), **4b** (iPad text tool). Options 1a, 1c, 3a, 3b are rejected explorations — ignore them.

## Fidelity
**High-fidelity.** Colors, spacing, radii, and copy are final. Typography: mocks use the "Archivo" webfont purely as a stand-in — in SwiftUI use the **system font (SF Pro)** with matching sizes/weights. Match everything else as closely as SwiftUI allows.

## Design Tokens
Colors:
- Background: `#FBFBFA`
- Surface / cards: `#FFFFFF`
- Hairline border: `#E7E7E2` (lighter inner dividers `#F1F1EC`)
- Ink (primary text): `#16161A`
- Secondary text: `#44443E`
- Muted text / placeholders: `#9C9C94`
- Accent: `#2547F4` (hover/pressed `#1D39C9`; soft accent bg `#EDF0FE`; text-match highlight `#DCE4FD`)
- Connected green: `#1FA84D` (chip bg `#EBF7EE`, chip border `#BBE3C6`, chip text `#177A38`)
- Conflict amber: text `#B07818`, border `#EDD9AE`, row bg `#FFF9EE`
- Destructive red: `#D63030`
- Drawing ink palette (6 swatches): `#16161A`, `#2547F4`, `#D63030`, `#1FA84D`, `#E8850C`, `#8B3FD1`
- Dark strip/tooltip bg: `#16161A`, white text

Radii: cards/buttons 8–12px (Mac 8–10, iPad 10–12), segmented controls 8 outer / 6 inner, chips 8–9, floating strips 9 (Mac) / 12 (iPad).
Spacing: 12–16px paddings inside bars; 14–16px grid gaps; hairline 1px dividers everywhere (no shadows except floating strips/tooltips).
Type scale (Mac): 17/600 wordless header, 15/600 section title, 13.5/600 row title, 12–12.5 chips, 11.5 metadata, 10.5/700 letterspaced section labels (e.g. `FOLDERS`, `2 RESULTS`). iPad: bump ~+1.5px; all touch targets ≥ 44px.

## Screens / Views

### 1. Mac home — pad list (`SketchListView.swift`, Catalyst) — mock 1b
Replaces the Notes-like collapsing section cards with a **left sidebar + thumbnail grid**:
- **Sidebar** (208pt, right hairline): search field (white, hairline, radius 8); nav list — "All pads" (selected state: `#EDF0FE` bg, accent text, radius 8), "Unsorted"; `FOLDERS` label; one row per section with right-aligned count; "+ New folder" muted row. Pinned bottom (top hairline): green dot + "Miguel's iPad · connected" (gray dot + "not connected" otherwise). No app wordmark.
- **Main**: header row — view title left, primary button right ("＋ New pad", accent bg, white text, radius 8, 8×14 padding).
- **Grid**: 3 columns, 14pt gap. Each pad card: white, hairline border, radius 10; thumbnail area (~110pt tall) rendering the pad's `PKDrawing` preview over its paper style (lines/grid/dots/blank); footer (top hairline, 10×12 padding): title 13.5/600, second line 11.5 muted "2h ago · Home projects" (relative date · section). Hover: border becomes accent. Presence: dark pill top-right of thumbnail with eye icon + device name ("iPad") when peer has the pad open. Last grid cell: dashed "＋ New pad" placeholder card (hover → accent).
- Context menu (right-click) keeps Rename / Move… / Delete.

### 2. iPad home (`SketchListView.swift`, iOS) — mock 2a
Same sidebar + grid adapted for touch: sidebar 236pt, rows 44pt tall, search field 44pt; "New pad" button 44pt; grid cards identical with slightly larger type (15/600 titles). Presence pill reads "Mac".

### 3. Mac drawing screen (`SketchDetailView.swift` + `MacToolStrip.swift`) — mock 4a (final)
Single top bar (canvas below it, unchanged architecture):
- Back chevron · title 13.5/600 · muted section name · hairline divider.
- **Tool switcher**: segmented control (`#F1F1EC` bg, radius 8, 2pt padding) of **5 icon-only buttons** (36×28, radius 6): Pen, Marker, Pencil, Eraser, **Text**. Selected = accent bg + white icon for Text; for ink tools selected = white bg + shadow (as today's segmented style). Hover = `#E4E4DE`. **Every button shows a tooltip on hover** (dark `#16161A` pill, white 11px text, radius 6, small arrow) — use `.help()` in Catalyst or a custom hover popover.
- **Colors**: six 17pt rounded squares (radius 5); selected gets a 1.5pt accent ring offset by 2pt white. Picking a color while Eraser/Text is active switches back to Pen (existing behavior).
- **Width slider**: 110pt, ink-colored fill + 12pt round thumb.
- Right side: zoom group (− / 125% / +, white bg, hairline, radius 8, tabular numerals), green "iPad" presence chip (only when peer is in this pad), paper style chip (icon + current style name, e.g. "Dots") opening the paper menu.
- When **Text tool** is active: colors + slider + paper chip dim to 35% opacity and are disabled; canvas pen input pauses (existing `editingTexts` freeze).

### 4. Text tool behavior (Mac 4a + iPad 4b) — replaces "text mode"
- Selecting the Text tool = old `editingTexts = true`. No separate T toggle button on Mac anymore.
- Click/tap empty paper → new text block with caret. Existing blocks render normally; non-selected blocks show a 1px dashed `#C9C9C1` border, white 70% bg, radius 6.
- **Selected block**: 1.5pt accent border, radius 6, white 85% bg, 4 corner handles (7pt white circles with accent border).
- **Control strip** floats centered **under** the block (dark `#16161A`, radius 9, shadow): move (✥ arrows icon) · A− · A+ · trash (soft red `#FF7A6E` icon). Buttons 34×32 on Mac, **48×44 on iPad**. Esc deselects first, then exits the tool (existing behavior).
- **iPad**: the nav-bar T button becomes this same tool: active = accent bg, white T icon, `#EDF0FE` glow ring. While active, the system PencilKit palette dims to 35% (pen paused). No hover on iPad — no tooltips needed.

### 5. iPad drawing screen (`SketchDetailView.swift`, iOS) — mock 2b
- Nav bar (50pt, hairline bottom): "‹ Pads" back in accent, centered title 15/600, right: green "Mac is here" chip, T (Text tool) button 44×38, paper chip.
- Canvas: keep Apple's PKToolPicker palette exactly as is.
- **Remote ghost cursor** (both platforms): small accent-filled cursor triangle + accent pill label with peer name ("Miguel's Mac"), white 10.5–11px/600 text, radius 6.

### 6. Mac states — mock 2c
- **Search**: focused field gets 1.5pt accent border + 3pt `#EDF0FE` glow. Results: `N RESULTS` label; rows with 52×38 thumbnail, title with matched substring highlighted (`#DCE4FD` bg), second line muted — "Title match · Home projects" or `Text match: "…check garage fuse box…"` (matched substring highlighted). Hovered/first row bg `#F1F1EC`, radius 8.
- **Empty state**: centered muted squiggle glyph, "No pads yet" 15/600, subline muted 13 "Everything you draw here syncs to your iPad when it's nearby.", accent "＋ New pad" button.
- **Conflict fork**: label `EDITED ON BOTH DEVICES WHILE APART`; the `… (conflict)` copy renders in the same card as the original: original row on top; fork row below with `#FFF9EE` bg, amber subline "Forked from your iPad's edits · keep, merge by hand, or delete", and an outlined `FORK` badge (amber).

## Interactions & Behavior
- Hover states as listed (cards → accent border; sidebar rows → `#F1F1EC`; segmented buttons → `#E4E4DE`; tooltips after ~0.5s).
- Selection/mode transitions: quick fades ~150ms; tool-strip dim to 35% animated.
- All existing behaviors are unchanged: live stroke + cursor streaming, catch-up sync, tombstones, section CRUD, collapsed-state persistence (now "selected sidebar item" persistence), zoom stepping (1×–4×, step 0.5 from last requested), Esc chain, swipe actions on iPad list (if list still reachable — grid uses context menu / long-press instead).

## State Management
Reuse existing stores. Changes:
- `MacToolStrip` gains a 5th tool value `"text"` persisted in `@AppStorage("macTool")`; `editingTexts` derives from `tool == .text` instead of a separate toggle.
- Sidebar selection (All pads / Unsorted / section id) replaces `collapsedSections` as the persisted list state.
- Pad thumbnails: render `PKDrawing` to an image (e.g. `drawing.image(from:scale:)`) cached per pad, invalidated on drawing change/sync.

## Assets
- `icon/quill-app-icon.svg` — master app icon (Studio blue `#2547F4`, dot-grid paper texture, hand-drawn white Q whose tail is a pen stroke). Full-bleed square; the OS applies the squircle mask.
- `icon/quill-app-icon-1024.png` — 1024×1024 render for `Assets.xcassets/AppIcon.appiconset` (use as the single-size iOS icon; generate the macOS/Catalyst size set from it).
- `icon/preview-rounded.png` — masked preview only, not a shipping asset.
- Sketch thumbnails in the mocks are placeholders — real thumbnails come from each pad's `PKDrawing`.

## Files
- `Quill Redesign.dc.html` — the full design canvas. Newest work at top: turn 4 (final toolbar + iPad text tool), turn 3 (text-mode explorations; 3c chosen), turn 2 (iPad screens + Mac states), turn 1 (direction exploration; 1b chosen). Option ids (1b, 2a, 2b, 2c, 4a, 4b) are labeled badges in the file.
- `icon/` — app icon assets (above).
