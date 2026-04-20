# OdinIDE — Foundation Layout Prompt
### Build Phase 1: Core Structure & Layout

---

## Project Identity

**Name:** `OdinIDE`
**Tagline:** *"Forged for Odin. Built in Odin."*
**Language:** Odin `dev-2026-04`
**Target:** A native, standalone desktop code editor built entirely in Odin,
designed exclusively for writing Odin code. Aesthetic and UX parity
with Zed and early VSCode — minimal, fast, and intentional.

---

## Context & Philosophy

You are building **OdinIDE**, a professional desktop source code editor written
in the Odin programming language (version `dev-2026-04`), for Odin developers.

OdinIDE is:
- **Native** — no Electron, no web tech, no embedded browser. Raw OS window,
  GPU-accelerated rendering, zero managed runtime.
- **Odin-first** — every design decision assumes the user writes Odin. No
  plugin API or language abstraction layer in Phase 1. Odin support is
  hardcoded and first-class.
- **Modern** — inspired by Zed's spatial density and VSCode's approachability.
  Dark theme by default. Clean, typographic, purposeful.
- **Fast** — the editor must feel instant. No jank on open. Target sub-5ms
  input-to-render latency on a modern machine.

This prompt covers **Phase 1: Foundation Layout**. Every piece of UI built
in this phase must be functional, not a mockup. The layout must be real,
resize correctly, and be ready to receive features in later phases.

---

## Technology Stack

| Layer            | Choice                                      |
|------------------|---------------------------------------------|
| Language         | Odin `dev-2026-04`                          |
| Windowing        | `vendor:raylib` (5.x) or `vendor:sdl3`     |
| Rendering        | Raylib's 2D draw API or SDL3 + custom       |
| Font Rendering   | Raylib `LoadFontEx` with SDF or FreeType    |
| File I/O         | `core:os`, `core:os/os2`                   |
| String handling  | `core:strings`, `core:unicode/utf8`        |
| Memory           | Odin allocators — arena for frame, general  |
| Platform layer   | Single file `platform_<os>.odin` per target |
| Build            | `odin build . -out:odinide`                |

> **Raylib is recommended** for Phase 1 because it handles windowing,
> OpenGL context, input events, and 2D drawing in a single vendor package
> already shipped with the Odin compiler. Switch to a lower-level backend
> later if needed.

---

## Directory Structure

```
odinide/
├── main.odin               # Entry point, event loop
├── app.odin                # Application state, top-level update/draw
├── layout.odin             # Panel layout system (sizes, splits, rects)
├── editor.odin             # Buffer, cursor, selection, text operations
├── renderer.odin           # All draw calls — text, cursors, UI elements
├── font.odin               # Font loading, metrics, glyph cache
├── theme.odin              # Color palette, token colors, UI colors
├── statusbar.odin          # Status bar state and draw
├── sidebar.odin            # File tree state and draw
├── tabbar.odin             # Tab state and draw
├── input.odin              # Keyboard and mouse input dispatch
├── config.odin             # Editor config (tab size, font size, etc.)
├── platform/
│   ├── platform_windows.odin
│   ├── platform_linux.odin
│   └── platform_darwin.odin
└── assets/
    ├── fonts/
    │   ├── JetBrainsMono-Regular.ttf
    │   ├── JetBrainsMono-Bold.ttf
    │   └── Inter-Regular.ttf       # UI chrome font
    └── icons/
        └── (16x16 PNG icon sprites for file tree)
```

---

## Application State (`app.odin`)

Define a top-level `App` struct that owns all subsystem state:

```odin
App :: struct {
    window_width:   i32,
    window_height:  i32,

    layout:         Layout,
    theme:          Theme,
    font:           Font_State,
    config:         Config,

    sidebar:        Sidebar,
    tabbar:         Tab_Bar,
    editors:        [dynamic]Editor_State,
    active_editor:  int,
    statusbar:      Status_Bar,

    should_quit:    bool,
}
```

Initialize all subsystems in `app_init(app: ^App)`.
Update all in `app_update(app: ^App, dt: f32)`.
Draw all in `app_draw(app: ^App)`.
Destroy all in `app_destroy(app: ^App)`.

---

## Layout System (`layout.odin`)

The layout is a **fixed-region system** — not a full tree-based layout engine
in Phase 1. It partitions the window into named rectangular regions and
recalculates them on every window resize event.

### Regions

```
┌─────────────────────────────────────────────────────────┐
│  TITLE BAR (macOS only, 28px)                           │
├──────────┬──────────────────────────────────────────────┤
│          │  TAB BAR (36px)                              │
│          ├──────────────────────────────────────────────┤
│ ACTIVITY │                                              │
│   BAR    │         EDITOR AREA                         │
│  (48px)  │         (fills remaining height)            │
│          │                                              │
│  icons   ├──────────────────────────────────────────────┤
│  only    │  STATUS BAR (24px)                           │
│          ├──────────────────────────────────────────────┤
├──────────┤                                              │
│ SIDE     │   (sidebar overlaps or pushes editor area)  │
│ BAR      │                                              │
│ (240px   │                                              │
│ default, │                                              │
│ resizable│                                              │
│ )        │                                              │
└──────────┴──────────────────────────────────────────────┘
```

### Layout Struct

```odin
Layout :: struct {
    window:       rl.Rectangle,

    activity_bar: rl.Rectangle,   // left strip, icon-only
    sidebar:      rl.Rectangle,   // resizable file tree panel
    tab_bar:      rl.Rectangle,   // horizontal tabs row
    editor_area:  rl.Rectangle,   // main text editing surface
    status_bar:   rl.Rectangle,   // bottom bar

    sidebar_visible:  bool,
    sidebar_width:    f32,        // default 240, user-resizable
    sidebar_dragging: bool,
    sidebar_drag_x:   f32,
}
```

Implement `layout_recalculate(layout: ^Layout, w, h: f32)` which is called
once per frame (or only on resize). All rectangles are derived from
`w`, `h`, and `layout.sidebar_width`. The sidebar resize handle is a 4px
wide hit zone at the right edge of the sidebar.

---

## Theme System (`theme.odin`)

One dark theme in Phase 1 — **OdinIDE Dark**. Inspired by Zed's One Dark
and VSCode's default dark. Define all colors as `rl.Color` constants inside
a `Theme` struct. No runtime loading of theme files yet.

```odin
Theme :: struct {
    // Background layers
    bg_base:         rl.Color,   // #1A1B26  deepest bg
    bg_elevated:     rl.Color,   // #1F2030  panels, sidebar
    bg_highlight:    rl.Color,   // #292B3D  hover, selection bg
    bg_active_line:  rl.Color,   // #232437  active line highlight

    // Borders & dividers
    border:          rl.Color,   // #2E3050

    // Text
    text_primary:    rl.Color,   // #C0CAF5  normal text
    text_muted:      rl.Color,   // #565F89  comments, line numbers
    text_disabled:   rl.Color,   // #3B4261  inactive tabs, etc.

    // Accent
    accent:          rl.Color,   // #7AA2F7  cursor, active tab underline
    accent_warm:     rl.Color,   // #FF9E64  warnings, bookmarks

    // Syntax token colors (used in Phase 2+ but define now)
    syn_keyword:     rl.Color,   // #BB9AF7
    syn_type:        rl.Color,   // #2AC3DE
    syn_proc:        rl.Color,   // #7AA2F7
    syn_string:      rl.Color,   // #9ECE6A
    syn_number:      rl.Color,   // #FF9E64
    syn_comment:     rl.Color,   // #565F89
    syn_operator:    rl.Color,   // #89DDFF
    syn_punctuation: rl.Color,   // #C0CAF5

    // Status bar
    sb_bg:           rl.Color,   // #7AA2F7  filled blue bar
    sb_text:         rl.Color,   // #1A1B26

    // Tabs
    tab_active_bg:   rl.Color,   // #1A1B26
    tab_inactive_bg: rl.Color,   // #16161E
    tab_active_line: rl.Color,   // #7AA2F7  underline on active tab
}
```

Provide `theme_odinide_dark() -> Theme` as a constructor that returns the
fully initialized dark theme.

---

## Font System (`font.odin`)

```odin
Font_State :: struct {
    mono:        rl.Font,    // JetBrains Mono — editor text
    ui:          rl.Font,    // Inter — tabs, status bar, sidebar labels
    font_size:   f32,        // default 15.0
    line_height: f32,        // computed: font_size * 1.5
    char_width:  f32,        // monospace cell width (advance of 'M')
    glyph_atlas: rl.Texture2D,
}
```

- Load fonts with `rl.LoadFontEx(path, size, nil, 0)` for full Unicode
  support. Request codepoints 32..127 + common box-drawing chars.
- Compute `char_width` after load by measuring `rl.MeasureTextEx(font, "M", …)`.
- `line_height` = `font_size * 1.5` — configurable via `Config`.
- Expose `font_measure_string(fs: ^Font_State, s: string) -> f32` helper.

---

## Editor Buffer (`editor.odin`)

Phase 1 uses a **gap buffer** for the text storage. This is the correct
foundational choice for a text editor and must be built now, not later.

```odin
Gap_Buffer :: struct {
    data:     []u8,
    gap_pos:  int,
    gap_len:  int,
    length:   int,   // total logical char count
}
```

Implement:
- `gap_buffer_init(gb: ^Gap_Buffer, initial_capacity: int)`
- `gap_buffer_insert(gb: ^Gap_Buffer, pos: int, text: string)`
- `gap_buffer_delete(gb: ^Gap_Buffer, pos: int, count: int)`
- `gap_buffer_to_string(gb: ^Gap_Buffer, allocator: mem.Allocator) -> string`
- `gap_buffer_char_at(gb: ^Gap_Buffer, pos: int) -> rune`
- `gap_buffer_line_count(gb: ^Gap_Buffer) -> int`
- `gap_buffer_line_start(gb: ^Gap_Buffer, line: int) -> int`

### Cursor & Selection

```odin
Cursor :: struct {
    pos:    int,    // byte offset in gap buffer
    line:   int,    // visual line (0-indexed)
    col:    int,    // visual column (0-indexed)
    // preferred column (for up/down navigation)
    sticky_col: int,
}

Selection :: struct {
    active:     bool,
    anchor:     int,
    head:       int,
}
```

### Editor State

```odin
Editor_State :: struct {
    buffer:         Gap_Buffer,
    cursor:         Cursor,
    selection:      Selection,
    file_path:      string,
    is_modified:    bool,
    scroll_offset:  rl.Vector2,   // pixel scroll
    top_line:       int,          // first visible line index
    view_lines:     int,          // visible line count (derived from layout)
}
```

Implement these editor operations (all must work in Phase 1):
- `editor_insert_char(e: ^Editor_State, r: rune)`
- `editor_delete_char_backward(e: ^Editor_State)`
- `editor_delete_char_forward(e: ^Editor_State)`
- `editor_move_cursor(e: ^Editor_State, dir: Cursor_Dir)`
  where `Cursor_Dir :: enum { Left, Right, Up, Down, Line_Start, Line_End,
  File_Start, File_End, Word_Left, Word_Right }`
- `editor_insert_newline(e: ^Editor_State)`
- `editor_handle_tab(e: ^Editor_State, config: ^Config)`
  — inserts spaces equal to `config.tab_size` (default 4)
- `editor_scroll_to_cursor(e: ^Editor_State, rect: rl.Rectangle, font: ^Font_State)`

---

## Renderer (`renderer.odin`)

All draw calls go through `renderer.odin`. No raw `rl.DrawText*` calls
outside this file in other modules.

### Gutter (line numbers)

```
gutter width = digits(line_count) * char_width + 16px padding
```

- Draw line numbers right-aligned in `theme.text_muted`
- Highlight current line number in `theme.text_primary`
- Current line background spans full width in `theme.bg_active_line`

### Cursor

Draw a solid 2px-wide vertical bar in `theme.accent`. Implement a
**blink timer** (500ms on / 500ms off) that resets to "on" on every
keystroke. The cursor must not blink while the user is typing.

### Selection

Draw selection background rectangles in `theme.bg_highlight` with 20%
alpha blend over the line background. Multi-line selections must correctly
span from anchor to head across wrapped lines.

### Text

Use `rl.DrawTextEx` with the monospace font. In Phase 1, all text is
rendered in `theme.text_primary` — syntax highlighting is Phase 2.
But leave a `render_line(…, tokens: []Token)` signature stub so Phase 2
can drop in without refactoring.

### Scrollbar

Draw a thin (6px wide) vertical scrollbar on the right edge of the editor
area. It must:
- Show the proportion of visible content to total content.
- Be draggable with the mouse.
- Fade to 30% opacity when not hovered/active.
- Use `theme.text_muted` color.

---

## Tab Bar (`tabbar.odin`)

- Each tab is 180px wide max, shrinks when many tabs are open.
- Active tab: `theme.tab_active_bg`, bottom border line in `theme.tab_active_line` (2px).
- Inactive tab: `theme.tab_inactive_bg`, no underline.
- Modified (unsaved) tab shows a filled dot (●) before the filename instead
  of a close button until hovered.
- Close button (×) appears on hover. Clicking × closes tab. If buffer is
  modified, Phase 1 may close without prompt (save-before-close dialog
  is a later phase feature).
- Clicking a tab switches `app.active_editor`.
- Tab bar has a subtle bottom border in `theme.border`.
- New Tab button (+) on the far right of the tab row creates an empty
  untitled buffer.

---

## Sidebar — File Tree (`sidebar.odin`)

The sidebar shows a file tree rooted at the **current working directory**
when OdinIDE is launched (`os.get_current_directory()`).

```odin
Tree_Node :: struct {
    name:       string,
    path:       string,
    is_dir:     bool,
    expanded:   bool,
    depth:      int,
    children:   [dynamic]Tree_Node,
}

Sidebar :: struct {
    root:         Tree_Node,
    scroll_y:     f32,
    hovered_path: string,
    selected_path: string,
}
```

- Indent each level by `16px`.
- Draw `▶` (collapsed) / `▼` (expanded) chevrons for directories.
- Clicking a directory toggles `expanded` and lazily loads children
  using `os.read_dir`.
- Clicking a file opens it in a new tab (or switches to its tab if already
  open).
- Show only files relevant to Odin projects: prioritize `.odin` files.
  Show all files but dim non-`.odin` files slightly.
- Row height = `line_height` of the UI font.
- Active file row is highlighted in `theme.bg_highlight`.

---

## Activity Bar (`layout.odin` or `activitybar.odin`)

48px wide vertical strip on the far left. Contains icon buttons for:
1. **Files** (folder icon) — toggles sidebar visibility
2. **Search** (magnifier icon) — placeholder, not implemented in Phase 1
3. **Git** (branch icon) — placeholder
4. **Settings** (gear icon) — placeholder

Use simple geometric shapes (rects, circles, lines) to approximate icons
in Phase 1 instead of loading external SVG/PNG icon assets. This avoids
asset loading complexity at this stage.

Active panel icon is highlighted with `theme.accent` color.

---

## Status Bar (`statusbar.odin`)

24px tall bar pinned to the bottom.

Left side:
```
  ● Odin   dev-2026-04   Git: main
```

Right side:
```
  Ln 42, Col 8   Spaces: 4   UTF-8   CRLF/LF
```

- Background: `theme.sb_bg` (accent blue)
- Text: `theme.sb_text` (dark, for contrast on blue)
- Use the UI font (Inter) at 11px
- Data comes from `app.active_editor` buffer state and `config`

---

## Input Dispatch (`input.odin`)

Implement a clean input layer with a focus model. Only one panel has
keyboard focus at a time (default: editor area).

### Keyboard Shortcuts (all must work in Phase 1)

| Shortcut          | Action                            |
|-------------------|-----------------------------------|
| `Ctrl+N`          | New empty tab                     |
| `Ctrl+O`          | Open file (OS dialog via raylib)  |
| `Ctrl+S`          | Save current file                 |
| `Ctrl+W`          | Close current tab                 |
| `Ctrl+Tab`        | Next tab                          |
| `Ctrl+Shift+Tab`  | Previous tab                      |
| `Ctrl+B`          | Toggle sidebar                    |
| `Ctrl+Q` / Alt+F4 | Quit                              |
| `Ctrl++` / `Ctrl+-`| Increase / Decrease font size    |
| Arrow keys        | Move cursor                       |
| `Home` / `End`    | Line start / end                  |
| `Ctrl+Home/End`   | File start / end                  |
| `Ctrl+Left/Right` | Word jump                         |
| `Shift+<move>`    | Extend selection                  |
| `Ctrl+A`          | Select all                        |
| `Ctrl+C/X/V`      | Clipboard copy / cut / paste      |
| `Ctrl+Z`          | Undo (basic — Phase 1 single-level|
| `Tab`             | Insert spaces (per config)        |
| `Backspace/Del`   | Delete character                  |
| `Enter`           | Insert newline                    |

Use `rl.GetCharPressed()` for text input (handles Unicode and IME correctly).
Use `rl.IsKeyPressed / IsKeyDown` for control keys.
Detect modifier state with `rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL)` etc.

### Mouse

- Click in editor area: move cursor to clicked position (hit-test
  `(mouse_x - gutter_width) / char_width` and
  `(mouse_y - editor_rect.y + scroll_offset_y) / line_height`).
- Click-drag: extend selection.
- Scroll wheel: scroll editor (3 lines per tick).
- Click tab: switch active editor.
- Click × on tab: close tab.
- Drag sidebar resize handle: resize sidebar.
- Click activity bar icon: switch sidebar panel / toggle sidebar.

---

## File I/O

### Open (`Ctrl+O`)

Use Raylib's `rl.OpenFileDialog` (available in Raylib 5.x):

```odin
path := rl.OpenFileDialog("Open Odin File", "", 1, "*.odin")
if path != nil {
    editor_open_file(app, string(path))
}
```

`editor_open_file` should:
1. Read file bytes with `os.read_entire_file`.
2. Decode as UTF-8 (Odin source is always UTF-8).
3. Initialize a new `Editor_State` with the file contents loaded into
   the gap buffer.
4. Append to `app.editors`, set `app.active_editor` to new index.
5. Add tab entry to `app.tabbar`.

### Save (`Ctrl+S`)

If `editor.file_path == ""`, prompt for save-as path with
`rl.SaveFileDialog`. Otherwise write gap buffer contents to the file.

```odin
content := gap_buffer_to_string(&editor.buffer, context.temp_allocator)
ok := os.write_entire_file(editor.file_path, transmute([]u8)content)
if ok do editor.is_modified = false
```

---

## Config (`config.odin`)

```odin
Config :: struct {
    font_size:         f32,       // 15.0
    tab_size:          int,       // 4
    insert_spaces:     bool,      // true
    word_wrap:         bool,      // false in Phase 1
    show_line_numbers: bool,      // true
    show_minimap:      bool,      // false in Phase 1
    line_height_mult:  f32,       // 1.5
    cursor_blink_ms:   f32,       // 500
    scroll_speed:      f32,       // 3 (lines per wheel tick)
    sidebar_width:     f32,       // 240
}

config_default :: proc() -> Config {
    return Config{
        font_size         = 15,
        tab_size          = 4,
        insert_spaces     = true,
        show_line_numbers = true,
        line_height_mult  = 1.5,
        cursor_blink_ms   = 500,
        scroll_speed      = 3,
        sidebar_width     = 240,
    }
}
```

No config file persistence in Phase 1. Load from `config_default()`.

---

## OLS Integration (Groundwork Only — Phase 1)

Do not implement OLS communication in Phase 1. However, **prepare the
structure** so it can be wired up in Phase 2 with minimal refactoring.

Create `ols.odin` with:

```odin
OLS_State :: struct {
    process:      os.Handle,     // subprocess handle
    stdin:        os.Handle,
    stdout:       os.Handle,
    stderr:       os.Handle,
    initialized:  bool,
    capabilities: OLS_Caps,
}

OLS_Caps :: struct {
    hover:           bool,
    completion:      bool,
    go_to_def:       bool,
    diagnostics:     bool,
    formatting:      bool,
}

// Stub — to be implemented in Phase 2
ols_start :: proc(state: ^OLS_State, workspace_root: string) -> bool {
    // TODO: spawn `ols` process, open stdin/stdout pipes
    // ols binary discovery: check PATH, then workspace local .bin/ols
    return false
}

ols_stop :: proc(state: ^OLS_State) {}
```

Add `ols: OLS_State` to `App`. Call `ols_start` in `app_init` (it will
silently fail in Phase 1). The field being present means Phase 2 just
needs to fill in `ols_start` with real LSP JSON-RPC code.

---

## Main Loop (`main.odin`)

```odin
package main

import rl "vendor:raylib"

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
    rl.InitWindow(1280, 800, "OdinIDE")
    rl.SetTargetFPS(120)
    defer rl.CloseWindow()

    app: App
    app_init(&app)
    defer app_destroy(&app)

    for !rl.WindowShouldClose() && !app.should_quit {
        dt := rl.GetFrameTime()

        // Handle window resize
        if rl.IsWindowResized() {
            app.window_width  = rl.GetScreenWidth()
            app.window_height = rl.GetScreenHeight()
            layout_recalculate(&app.layout,
                f32(app.window_width), f32(app.window_height))
        }

        app_update(&app, dt)

        rl.BeginDrawing()
            rl.ClearBackground(app.theme.bg_base)
            app_draw(&app)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
```

---

## Visual Quality Requirements

These are non-negotiable for Phase 1. The editor must not look like a demo:

1. **Pixel-perfect gutter alignment** — line numbers must align perfectly
   with their code lines at all font sizes.
2. **Sub-pixel-accurate cursor placement** — the cursor must sit exactly
   at the character boundary, accounting for font advance widths.
3. **Smooth scrolling** — scroll position is stored as a float, animated
   toward target with `lerp(current, target, dt * 20)`. No integer jumping.
4. **No layout flicker** — layout recalculation must not produce one frame
   of wrong sizing. Calculate before drawing.
5. **Consistent color** — use only colors from `Theme`. No hardcoded
   hex values outside `theme.odin`.
6. **Readable at all sizes** — font size range 10–24 must look clean.
   Line height must scale proportionally.

---

## Phase 1 Acceptance Criteria

The following must all work correctly before Phase 1 is considered complete:

- [ ] Window opens at 1280×800, resizes without glitching
- [ ] Sidebar shows real filesystem starting from CWD
- [ ] Clicking `.odin` file in sidebar opens it in a tab
- [ ] Text renders in the editor with correct line/column
- [ ] Cursor moves with arrow keys, Home, End, Ctrl+arrows
- [ ] Typing inserts characters; Backspace/Delete removes them
- [ ] Enter creates a new line with correct indentation carry
- [ ] Tab inserts 4 spaces
- [ ] Ctrl+S saves to disk
- [ ] Ctrl+O opens OS file picker and loads chosen file
- [ ] Ctrl+N creates new untitled tab
- [ ] Ctrl+W closes the active tab
- [ ] Multiple tabs open simultaneously, click switches between them
- [ ] Scrollbar is visible, draggable, and reflects position
- [ ] Mouse click positions cursor correctly
- [ ] Status bar shows correct line/column, file name, encoding
- [ ] Sidebar resize handle works
- [ ] Ctrl+B toggles sidebar
- [ ] Ctrl+Q quits cleanly
- [ ] Clipboard paste works from OS (Ctrl+V)
- [ ] Theme colors match the spec palette

---

## What Phase 1 Does NOT Include

Do not implement these in Phase 1. Leave stubs or TODOs:

- Syntax highlighting (Phase 2)
- OLS/LSP communication (Phase 2)
- Autocomplete / hover docs (Phase 3)
- Go-to-definition (Phase 3)
- Find / Replace (Phase 4)
- Command palette (Phase 4)
- Config file persistence (Phase 5)
- Multiple cursor / multi-selection (Phase 5)
- Git integration (Phase 6)
- Minimap (Phase 6)
- Split panes (Phase 7)
- Terminal panel (Phase 7)

---

## Build & Run

```sh
# Build
odin build . -out:odinide -opt:speed

# Run from a project directory
cd ~/my-odin-project
/path/to/odinide
```

The editor opens with the sidebar rooted at the CWD.
If a `.odin` file path is passed as an argument, open it immediately:

```odin
if len(os.args) > 1 {
    editor_open_file(&app, os.args[1])
}
```

---

*End of Phase 1 Prompt — OdinIDE Foundation Layout*
