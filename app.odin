package main

import "core:strings"
import rl "vendor:raylib"

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

    ols:            OLS_State,
    should_quit:    bool,

    active_panel:       Active_Panel,
    cursor_blink_timer: f32,

    scrollbar_dragging:   bool,
    scrollbar_drag_start: f32,
    mouse_selecting:      bool,

    toast_message: string,
    toast_timer:   f32,
}

app_init :: proc(app: ^App) {
    app.config = config_default()
    app.theme  = theme_odinide_dark()

    font_init(&app.font, &app.config)

    app.layout.sidebar_width   = app.config.sidebar_width
    app.layout.sidebar_visible = true

    sidebar_init(&app.sidebar)

    app.editors       = make([dynamic]Editor_State)
    app.active_editor = -1
    app.active_panel  = .Files

    ols_start(&app.ols, ".")
}

app_update :: proc(app: ^App, dt: f32) {
    input_update(app, dt)

    if app.toast_timer > 0 {
        app.toast_timer -= dt
        if app.toast_timer <= 0 {
            app.toast_message = ""
            app.toast_timer   = 0
        }
    }

    if app.active_editor >= 0 && app.active_editor < len(app.editors) {
        e := &app.editors[app.active_editor]
        e.scroll_offset.y = rl.Lerp(e.scroll_offset.y, e.target_scroll_y, dt * 18.0)
    }
}

app_draw :: proc(app: ^App) {
    // ── Activity Bar ──────────────────────────────────────────────────────────
    _draw_activity_bar(app)

    // ── Sidebar ───────────────────────────────────────────────────────────────
    if app.layout.sidebar_visible {
        sidebar_draw(app)
    }

    // ── Editor / Welcome ──────────────────────────────────────────────────────
    if len(app.editors) > 0 && app.active_editor >= 0 && app.active_editor < len(app.editors) {
        tabbar_draw(app)

        // Tab actions can change editor count/index in the same frame.
        if len(app.editors) > 0 && app.active_editor >= 0 && app.active_editor < len(app.editors) {
            renderer_draw_editor(app, &app.editors[app.active_editor])
        } else {
            _draw_welcome(app)
        }
    } else {
        _draw_welcome(app)
    }

    // ── Status Bar ────────────────────────────────────────────────────────────
    statusbar_draw(app)

    // ── Action Toast ──────────────────────────────────────────────────────────
    if app.toast_timer > 0 && app.toast_message != "" {
        _draw_toast(app)
    }
}

app_destroy :: proc(app: ^App) {
    for &e in app.editors {
        delete(e.buffer.data)
        if e.has_undo { delete(e.undo_entry.content) }
    }
    delete(app.editors)
    rl.UnloadFont(app.font.mono)
    rl.UnloadFont(app.font.ui)
    ols_stop(&app.ols)
}

// ─── Activity Bar ─────────────────────────────────────────────────────────────

_draw_activity_bar :: proc(app: ^App) {
    ab := app.layout.activity_bar
    rl.DrawRectangleRec(ab, app.theme.bg_elevated)

    // Right border
    rl.DrawLineEx(
        {ab.x + ab.width, ab.y},
        {ab.x + ab.width, ab.y + ab.height},
        1, app.theme.border)

    icon_sz   : f32 = 36
    icon_gap  : f32 = 4
    top_start : f32 = 12

    mouse_pos := rl.GetMousePosition()

    for icon_i in 0..<4 {
        ix  := ab.x + (ab.width - icon_sz) * 0.5
        iy  := ab.y + top_start + f32(icon_i) * (icon_sz + icon_gap)
        ir  := rl.Rectangle{ix, iy, icon_sz, icon_sz}

        is_active := app.active_panel == Active_Panel(icon_i) && app.layout.sidebar_visible
        hov       := rl.CheckCollisionPointRec(mouse_pos, ir)

        // Active left accent bar
        if is_active {
            rl.DrawRectangleRec({ab.x, iy + 4, 2, icon_sz - 8}, app.theme.accent)
        }

        // Hover / active background pill
        if is_active || hov {
            pill_col := is_active ? rl.Color{122, 162, 247, 30} : rl.Color{255, 255, 255, 12}
            rl.DrawRectangleRounded(
                {ix + 3, iy + 3, icon_sz - 6, icon_sz - 6},
                0.35, 6, pill_col)
        }

        col := is_active ? app.theme.accent : (hov ? app.theme.text_primary : app.theme.text_muted)
        cx  := ix + icon_sz * 0.5
        cy  := iy + icon_sz * 0.5

        switch icon_i {
        case 0: _draw_icon_files(cx, cy, col)
        case 1: _draw_icon_search(cx, cy, col)
        case 2: _draw_icon_git(cx, cy, col)
        case 3: _draw_icon_settings(cx, cy, col)
        }
    }
}

// ── Icon: Files (folder) ──────────────────────────────────────────────────────
_draw_icon_files :: proc(cx, cy: f32, col: rl.Color) {
    // Tab portion (top-left)
    rl.DrawRectangleRounded({cx - 9, cy - 7, 8, 4}, 0.4, 4, col)
    // Folder body
    rl.DrawRectangleRounded({cx - 9, cy - 5, 18, 12}, 0.25, 4, col)
}

// ── Icon: Search (magnifier) ──────────────────────────────────────────────────
_draw_icon_search :: proc(cx, cy: f32, col: rl.Color) {
    // Outer ring
    rl.DrawRing({cx - 2, cy - 2}, 5, 7.5, 0, 360, 20, col)
    // Handle
    rl.DrawLineEx({cx + 3.5, cy + 3.5}, {cx + 9, cy + 9}, 2.5, col)
}

// ── Icon: Git (branch) ────────────────────────────────────────────────────────
_draw_icon_git :: proc(cx, cy: f32, col: rl.Color) {
    // Main commit (top)
    rl.DrawCircle(i32(cx - 4), i32(cy - 6), 3, col)
    // Branch commit (right)
    rl.DrawCircle(i32(cx + 5), i32(cy),     3, col)
    // Trunk commit (bottom)
    rl.DrawCircle(i32(cx - 4), i32(cy + 7), 3, col)
    // Trunk line
    rl.DrawLineEx({cx - 4, cy - 3}, {cx - 4, cy + 4}, 2, col)
    // Branch curve (approximate with two lines)
    rl.DrawLineEx({cx - 4, cy - 4}, {cx + 5, cy - 2}, 2, col)
    rl.DrawLineEx({cx + 5, cy - 2}, {cx + 5, cy - 1}, 2, col)
}

// ── Icon: Settings (gear) ────────────────────────────────────────────────────
_draw_icon_settings :: proc(cx, cy: f32, col: rl.Color) {
    // Outer ring
    rl.DrawRing({cx, cy}, 5, 8.5, 0, 360, 24, col)
    // Inner fill circle
    rl.DrawCircle(i32(cx), i32(cy), 3.5, col)
    // 8 teeth: 4 axis-aligned rects + 4 diagonal lines
    // Top / Bottom / Left / Right
    rl.DrawRectangle(i32(cx - 1.5), i32(cy - 12), 3, 4, col)
    rl.DrawRectangle(i32(cx - 1.5), i32(cy + 8),  3, 4, col)
    rl.DrawRectangle(i32(cx - 12),  i32(cy - 1.5), 4, 3, col)
    rl.DrawRectangle(i32(cx + 8),   i32(cy - 1.5), 4, 3, col)
    // Diagonal (NE, NW, SE, SW) as thick lines from ring to beyond
    d : f32 = 7.5
    rl.DrawLineEx({cx + d, cy - d}, {cx + d + 2.5, cy - d - 2.5}, 2.5, col)
    rl.DrawLineEx({cx - d, cy - d}, {cx - d - 2.5, cy - d - 2.5}, 2.5, col)
    rl.DrawLineEx({cx + d, cy + d}, {cx + d + 2.5, cy + d + 2.5}, 2.5, col)
    rl.DrawLineEx({cx - d, cy + d}, {cx - d - 2.5, cy + d + 2.5}, 2.5, col)
}

// ─── Welcome / Empty State ────────────────────────────────────────────────────

_draw_welcome :: proc(app: ^App) {
    ea := app.layout.editor_area
    rl.DrawRectangleRec(ea, app.theme.bg_base)

    // Centered content
    cx := ea.x + ea.width  * 0.5
    cy := ea.y + ea.height * 0.5

    // Large Odin logo text
    logo      := strings.clone_to_cstring("OdinIDE", context.temp_allocator)
    tagline   := strings.clone_to_cstring("Forged for Odin.  Built in Odin.", context.temp_allocator)
    hint1     := strings.clone_to_cstring("Ctrl+N   New file", context.temp_allocator)
    hint2     := strings.clone_to_cstring("Ctrl+O   Open file (or drag & drop)", context.temp_allocator)
    hint3     := strings.clone_to_cstring("Ctrl+B   Toggle sidebar", context.temp_allocator)

    logo_sz   : f32 = 36
    tag_sz    : f32 = 13
    hint_sz   : f32 = 12

    lw := rl.MeasureTextEx(app.font.ui, logo,    logo_sz, 0).x
    tw := rl.MeasureTextEx(app.font.ui, tagline, tag_sz,  0).x

    rl.DrawTextEx(app.font.ui, logo,
        {cx - lw * 0.5, cy - 65}, logo_sz, 0, app.theme.accent)
    rl.DrawTextEx(app.font.ui, tagline,
        {cx - tw * 0.5, cy - 22}, tag_sz, 0, app.theme.text_muted)

    // Divider
    rl.DrawLineEx({cx - 100, cy + 5}, {cx + 100, cy + 5}, 1, app.theme.border)

    // Keyboard hints
    hints := [3]cstring{hint1, hint2, hint3}
    for h, i in hints {
        hw := rl.MeasureTextEx(app.font.ui, h, hint_sz, 0).x
        rl.DrawTextEx(app.font.ui, h,
            {cx - hw * 0.5, cy + 20 + f32(i) * 22},
            hint_sz, 0, app.theme.text_disabled)
    }
}

app_push_toast :: proc(app: ^App, message: string, duration: f32 = 1.6) {
    app.toast_message = message
    app.toast_timer   = max(duration, f32(0.6))
}

_draw_toast :: proc(app: ^App) {
    msg := strings.clone_to_cstring(app.toast_message, context.temp_allocator)
    sz  : f32 = 12
    tw  := rl.MeasureTextEx(app.font.ui, msg, sz, 0).x
    pad_x : f32 = 12
    pad_y : f32 = 7

    width  := tw + pad_x * 2
    height : f32 = sz + pad_y * 2
    x := f32(app.window_width) - width - 12
    y := f32(app.window_height) - app.layout.status_bar.height - height - 10

    rl.DrawRectangleRounded(
        {x, y, width, height},
        0.35, 8,
        {app.theme.bg_highlight.r, app.theme.bg_highlight.g, app.theme.bg_highlight.b, 220},
    )
    rl.DrawRectangleRoundedLinesEx(
        {x, y, width, height},
        0.35, 8, 1,
        app.theme.border,
    )
    rl.DrawTextEx(app.font.ui, msg, {x + pad_x, y + pad_y}, sz, 0, app.theme.text_primary)
}