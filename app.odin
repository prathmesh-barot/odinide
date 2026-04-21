package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "core:path/filepath"
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
    highlighter:    Highlighter,

    ols:            OLS_State,
    should_quit:    bool,

    active_panel:       Active_Panel,
    cursor_blink_timer: f32,

    scrollbar_dragging:   bool,
    scrollbar_drag_start: f32,
    mouse_selecting:      bool,

    toast_message: string,
    toast_timer:   f32,

    settings_modal_open: bool,
    settings_tab:        int,
    code_font_smooth:    bool,
    ui_font_soft:        bool,

    completion: Completion_UI,
    ctrl_k_armed: bool,
    ctrl_k_time:  f64,

    diagnostics: Diagnostics,
    find:        Find_State,
    palette:     Command_Palette,
}

app_init :: proc(app: ^App) {
    app.config = config_default()
    config_load(&app.config)
    app.theme  = theme_odinide_dark()

    font_init(&app.font, &app.config)

    app.layout.sidebar_width   = app.config.sidebar_width
    app.layout.sidebar_visible = true

    sidebar_init(&app.sidebar)

    app.editors       = make([dynamic]Editor_State)
    app.active_editor = -1
    app.active_panel  = .Files
    app.code_font_smooth = false
    app.ui_font_soft     = true
    app.highlighter.full_dirty = true

    ols_start(&app.ols, ".")

    app.completion = Completion_UI{}
    diagnostics_init(&app.diagnostics)
    find_init(&app.find)
    command_palette_init(&app.palette)
}

app_update :: proc(app: ^App, dt: f32) {
    input_update(app, dt)

    // Debounced didChange to OLS (avoid sending on every keystroke).
    if app.ols.initialized {
        now := rl.GetTime()
        for &e in app.editors {
            if e.file_path == "" do continue
            if e.lsp_dirty && (now - e.last_edit_time) > 0.30 {
                _ = ols_did_change(&app.ols, &e)
            }
        }
    }

    // Poll OLS (LSP) once per frame (non-blocking).
    ols_poll(&app.ols, app)

    if app.toast_timer > 0 {
        app.toast_timer -= dt
        if app.toast_timer <= 0 {
            app.toast_message = ""
            app.toast_timer   = 0
        }
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
            _draw_breadcrumb(app, &app.editors[app.active_editor])
            renderer_draw_editor(app, &app.editors[app.active_editor])
            find_draw(app)
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

    if app.settings_modal_open {
        _draw_settings_modal(app)
    }

    command_palette_draw(app)
}

app_destroy :: proc(app: ^App) {
    for &e in app.editors {
        delete(e.buffer.data)
        undo_clear(&e.undo_stack)
    }
    delete(app.editors)
    for lt in app.highlighter.lines {
        if lt.tokens != nil do delete(lt.tokens)
    }
    delete(app.highlighter.lines)
    diagnostics_destroy(&app.diagnostics)
    find_destroy(&app.find)
    command_palette_destroy(&app.palette)
    config_save(&app.config)
    rl.UnloadFont(app.font.mono)
    if app.font.ui.texture.id != app.font.mono.texture.id {
        rl.UnloadFont(app.font.ui)
    }
    if app.font.icons.texture.id != app.font.ui.texture.id &&
       app.font.icons.texture.id != app.font.mono.texture.id {
        rl.UnloadFont(app.font.icons)
    }
    ols_stop(&app.ols)
}

// ─── Breadcrumb ───────────────────────────────────────────────────────────────

Completion_Item :: struct {
    kind:    string,
    label:   string,
    detail:  string,
    insert:  string,
}

Completion_UI :: struct {
    open:        bool,
    selected:    int,
    anchor_line: int,
    anchor_col:  int,
    trigger_pos: int,   // byte position in buffer where replacement starts
    uri:         string,
    title:       string,
    items:       [dynamic]Completion_Item,
}

_draw_breadcrumb :: proc(app: ^App, e: ^Editor_State) {
    bc := app.layout.breadcrumb_bar
    rl.DrawRectangleRec(bc, app.theme.bg_base)
    // subtle bottom divider (slightly darker)
    rl.DrawLineEx({bc.x, bc.y + bc.height - 1}, {bc.x + bc.width, bc.y + bc.height - 1}, 1,
        {app.theme.border.r, app.theme.border.g, app.theme.border.b, 120})

    // Workspace name from sidebar root
    ws := app.sidebar.root.name
    file := e.file_path != "" ? filepath.base(e.file_path) : "Untitled"
    sym  := _breadcrumb_symbol_from_cursor(app, e)

    x := bc.x + 12
    y := bc.y + (bc.height - 11) * 0.5

    sep := "›"
    draw_text_ui(&app.font, strings.clone_to_cstring(ws, context.temp_allocator), {x, y}, app.theme.text_muted, 11)
    x += rl.MeasureTextEx(app.font.ui, strings.clone_to_cstring(ws, context.temp_allocator), 11, 0).x + 8
    draw_text_ui(&app.font, strings.clone_to_cstring(sep, context.temp_allocator), {x, y}, app.theme.border, 11)
    x += 10
    draw_text_ui(&app.font, strings.clone_to_cstring(file, context.temp_allocator), {x, y}, app.theme.text_muted, 11)
    x += rl.MeasureTextEx(app.font.ui, strings.clone_to_cstring(file, context.temp_allocator), 11, 0).x + 8

    if sym != "" {
        draw_text_ui(&app.font, strings.clone_to_cstring(sep, context.temp_allocator), {x, y}, app.theme.border, 11)
        x += 10
        draw_text_ui(&app.font, strings.clone_to_cstring(sym, context.temp_allocator), {x, y}, app.theme.accent, 11)
    }
}

_breadcrumb_symbol_from_cursor :: proc(app: ^App, e: ^Editor_State) -> string {
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines   := strings.split_lines(content, context.temp_allocator)
    if e.cursor.line < 0 || e.cursor.line >= len(lines) do return ""

    // Scan upwards for `name :: proc` or `name :: struct` etc. Keep it simple and stable.
    for i := e.cursor.line; i >= 0; i -= 1 {
        s := strings.trim_space(lines[i])
        if s == "" || strings.has_prefix(s, "//") do continue

        // Find token before `::`
        idx := strings.index(s, "::")
        if idx < 0 do continue
        left := strings.trim_space(s[:idx])
        if left == "" do continue
        // Only keep the identifier chunk (no spaces)
        sp := strings.index(left, " ")
        if sp >= 0 do left = left[:sp]
        return left
    }
    return ""
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

    icon_sz   : f32 = 34
    icon_gap  : f32 = 6
    top_start : f32 = 10

    mouse_pos := rl.GetMousePosition()

    // Codicon glyphs from mapping.json:
    // files 60144, search 60013, source-control 60008, extensions 60134, gear 60152
    icons := [4]rune{rune(60144), rune(60013), rune(60008), rune(60134)}

    for icon_i in 0..<4 {
        ix  := ab.x + (ab.width - icon_sz) * 0.5
        iy  := ab.y + top_start + f32(icon_i) * (icon_sz + icon_gap)
        ir  := rl.Rectangle{ix, iy, icon_sz, icon_sz}

        is_active := app.active_panel == Active_Panel(icon_i) && app.layout.sidebar_visible
        hov       := rl.CheckCollisionPointRec(mouse_pos, ir)

        if is_active {
            rl.DrawRectangleRec({ab.x, iy + 4, 2, icon_sz - 8}, app.theme.accent)
        }

        if is_active || hov {
            pill_col := is_active ? app.theme.activity_pill_active : app.theme.activity_pill_hover
            rl.DrawRectangleRounded(
                {ix + 3, iy + 3, icon_sz - 6, icon_sz - 6},
                0.35, 6, pill_col)
        }

        col := is_active ? app.theme.accent : (hov ? app.theme.text_primary : app.theme.text_muted)
        icon_txt := _icon_cstring(icons[icon_i])
        draw_text_icon(&app.font, icon_txt, {ix + 8, iy + 7}, col, 17)
    }

    // Bottom settings button (mock-style)
    bx := ab.x + (ab.width - icon_sz) * 0.5
    by := ab.y + ab.height - icon_sz - 10
    br := rl.Rectangle{bx, by, icon_sz, icon_sz}
    bh := rl.CheckCollisionPointRec(mouse_pos, br)
    if bh {
        rl.DrawRectangleRounded({bx + 3, by + 3, icon_sz - 6, icon_sz - 6}, 0.35, 6, app.theme.activity_pill_hover)
    }
    settings_icon := _icon_cstring(rune(60152))
    draw_text_icon(&app.font, settings_icon, {bx + 8, by + 7}, bh ? app.theme.text_primary : app.theme.text_muted, 17)
    if bh && rl.IsMouseButtonPressed(.LEFT) {
        app.settings_modal_open = true
        app.settings_tab = 0
    }
}

_icon_cstring :: proc(r: rune) -> cstring {
    buf, n := utf8.encode_rune(r)
    return strings.clone_to_cstring(string(buf[:n]), context.temp_allocator)
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

    draw_text_ui(&app.font, logo,
        {cx - lw * 0.5, cy - 65}, app.theme.accent, logo_sz)
    draw_text_ui(&app.font, tagline,
        {cx - tw * 0.5, cy - 22}, app.theme.text_muted, tag_sz)

    // Divider
    rl.DrawLineEx({cx - 100, cy + 5}, {cx + 100, cy + 5}, 1, app.theme.border)

    // Keyboard hints
    hints := [3]cstring{hint1, hint2, hint3}
    for h, i in hints {
        hw := rl.MeasureTextEx(app.font.ui, h, hint_sz, 0).x
        draw_text_ui(&app.font, h,
            {cx - hw * 0.5, cy + 20 + f32(i) * 22},
            app.theme.text_disabled, hint_sz)
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
    draw_text_ui(&app.font, msg, {x + pad_x, y + pad_y}, app.theme.text_primary, sz)
}

_draw_settings_modal :: proc(app: ^App) {
    ww := f32(app.window_width)
    wh := f32(app.window_height)
    mouse := rl.GetMousePosition()

    // Backdrop
    rl.DrawRectangleRec({0, 0, ww, wh}, {8, 10, 18, 170})

    modal := rl.Rectangle{ww * 0.18, wh * 0.12, ww * 0.64, wh * 0.76}
    rl.DrawRectangleRounded(modal, 0.02, 8, app.theme.bg_elevated)
    rl.DrawRectangleRoundedLinesEx(modal, 0.02, 8, 1, app.theme.border)

    // Header
    draw_text_ui(&app.font, "Settings",
        {modal.x + 18, modal.y + 14}, app.theme.text_primary, app.font.ui_size + 5)
    draw_text_ui(&app.font, "Tune editor visuals and behavior",
        {modal.x + 18, modal.y + 44}, app.theme.text_muted, app.font.ui_size)

    close_btn := rl.Rectangle{modal.x + modal.width - 34, modal.y + 10, 24, 24}
    close_hov := rl.CheckCollisionPointRec(mouse, close_btn)
    if close_hov {
        rl.DrawRectangleRounded(close_btn, 0.25, 6, app.theme.bg_highlight)
    }
    draw_text_ui(&app.font, "x", {close_btn.x + 8, close_btn.y + 4}, app.theme.text_primary, app.font.ui_size + 2)
    if close_hov && rl.IsMouseButtonPressed(.LEFT) {
        app.settings_modal_open = false
        return
    }

    // Left nav
    nav := rl.Rectangle{modal.x + 12, modal.y + 76, 180, modal.height - 88}
    rl.DrawRectangleRounded(nav, 0.05, 6, app.theme.bg_base)
    rl.DrawRectangleRoundedLinesEx(nav, 0.05, 6, 1, app.theme.border)

    tabs := [3]string{"Editor", "Appearance", "About"}
    for i in 0..<len(tabs) {
        row := rl.Rectangle{nav.x + 8, nav.y + 8 + f32(i) * 36, nav.width - 16, 30}
        active := app.settings_tab == i
        hov := rl.CheckCollisionPointRec(mouse, row)
        if active || hov {
            bg := active ? app.theme.bg_highlight : rl.Color{app.theme.bg_highlight.r, app.theme.bg_highlight.g, app.theme.bg_highlight.b, 110}
            rl.DrawRectangleRounded(row, 0.18, 5, bg)
        }
        draw_text_ui(&app.font, strings.clone_to_cstring(tabs[i], context.temp_allocator),
            {row.x + 10, row.y + 6}, active ? app.theme.text_primary : app.theme.text_muted, app.font.ui_size)
        if hov && rl.IsMouseButtonPressed(.LEFT) {
            app.settings_tab = i
        }
    }

    body := rl.Rectangle{nav.x + nav.width + 14, nav.y, modal.width - nav.width - 30, nav.height}
    rl.DrawRectangleRounded(body, 0.02, 6, app.theme.bg_base)
    rl.DrawRectangleRoundedLinesEx(body, 0.02, 6, 1, app.theme.border)

    switch app.settings_tab {
    case 0:
        _draw_settings_editor_tab(app, body, mouse)
    case 1:
        _draw_settings_appearance_tab(app, body, mouse)
    case 2:
        _draw_settings_about_tab(app, body)
    }
}

_draw_settings_section_title :: proc(app: ^App, text: string, x, y: f32) {
    draw_text_ui(&app.font, strings.clone_to_cstring(text, context.temp_allocator),
        {x, y}, app.theme.text_primary, app.font.ui_size + 2)
}

_draw_settings_editor_tab :: proc(app: ^App, body: rl.Rectangle, mouse: rl.Vector2) {
    x := body.x + 16
    y := body.y + 16
    _draw_settings_section_title(app, "Typography", x, y)
    y += 32

    if _draw_font_stepper(app, "Editor Font Size", &app.font.font_size, 11, 26, {x, y, body.width - 32, 30}) {
        app.config.font_size = app.font.font_size
        font_recompute_metrics(&app.font, &app.config)
    }
    y += 40

    if _draw_font_stepper(app, "UI Font Size", &app.font.ui_size, 11, 22, {x, y, body.width - 32, 30}) {
        app.config.ui_font_size = app.font.ui_size
    }
    y += 40

    if _draw_font_stepper(app, "Line Height", &app.config.line_height_mult, 1.2, 2.0, {x, y, body.width - 32, 30}, 0.05) {
        font_recompute_metrics(&app.font, &app.config)
    }
    y += 48

    _draw_settings_section_title(app, "Editor", x, y)
    y += 30
    _draw_toggle_row(app, "Show Line Numbers", &app.config.show_line_numbers, {x, y, body.width - 32, 28}, mouse)
}

_draw_settings_appearance_tab :: proc(app: ^App, body: rl.Rectangle, mouse: rl.Vector2) {
    x := body.x + 16
    y := body.y + 16
    _draw_settings_section_title(app, "Rendering", x, y)
    y += 34

    mono_row := rl.Rectangle{x, y, body.width - 32, 30}
    rl.DrawRectangleRounded(mono_row, 0.14, 6, app.theme.bg_elevated)
    draw_text_ui(&app.font, "Code Font Filter", {mono_row.x + 10, mono_row.y + 7}, app.theme.text_primary, app.font.ui_size)

    point_btn := rl.Rectangle{mono_row.x + mono_row.width - 170, mono_row.y + 4, 74, 22}
    smooth_btn := rl.Rectangle{mono_row.x + mono_row.width - 90, mono_row.y + 4, 74, 22}
    _draw_filter_btn(app, point_btn, "Crisp", !app.code_font_smooth, mouse)
    _draw_filter_btn(app, smooth_btn, "Smooth", app.code_font_smooth, mouse)
    if rl.CheckCollisionPointRec(mouse, point_btn) && rl.IsMouseButtonPressed(.LEFT) {
        rl.SetTextureFilter(app.font.mono.texture, .POINT)
        app.code_font_smooth = false
        app_push_toast(app, "Code font set to crisp.")
    }
    if rl.CheckCollisionPointRec(mouse, smooth_btn) && rl.IsMouseButtonPressed(.LEFT) {
        rl.SetTextureFilter(app.font.mono.texture, .BILINEAR)
        app.code_font_smooth = true
        app_push_toast(app, "Code font set to smooth.")
    }

    y += 40
    _draw_toggle_row(app, "Use Soft UI Text", &app.ui_font_soft, {x, y, body.width - 32, 28}, mouse)
    if app.ui_font_soft {
        rl.SetTextureFilter(app.font.ui.texture, .BILINEAR)
    } else {
        rl.SetTextureFilter(app.font.ui.texture, .POINT)
    }
}

_draw_settings_about_tab :: proc(app: ^App, body: rl.Rectangle) {
    x := body.x + 16
    y := body.y + 18
    _draw_settings_section_title(app, "OdinIDE", x, y)
    y += 34
    draw_text_ui(&app.font, "Style: Zed/VSCode inspired",
        {x, y}, app.theme.text_muted, app.font.ui_size)
    y += 22
    draw_text_ui(&app.font, "Runtime: Odin dev-2026-04 + raylib",
        {x, y}, app.theme.text_muted, app.font.ui_size)
    y += 22
    draw_text_ui(&app.font, "Tip: Ctrl+, opens Settings instantly",
        {x, y}, app.theme.text_muted, app.font.ui_size)
}

_draw_font_stepper :: proc(
    app: ^App,
    label: string,
    value: ^f32,
    min_v, max_v: f32,
    row: rl.Rectangle,
    step: f32 = 1,
) -> bool {
    mouse := rl.GetMousePosition()
    changed := false
    rl.DrawRectangleRounded(row, 0.14, 6, app.theme.bg_elevated)
    draw_text_ui(&app.font, strings.clone_to_cstring(label, context.temp_allocator),
        {row.x + 10, row.y + 7}, app.theme.text_primary, app.font.ui_size)

    minus := rl.Rectangle{row.x + row.width - 112, row.y + 4, 24, 22}
    plus  := rl.Rectangle{row.x + row.width - 28, row.y + 4, 24, 22}
    minus_hov := rl.CheckCollisionPointRec(mouse, minus)
    plus_hov  := rl.CheckCollisionPointRec(mouse, plus)
    rl.DrawRectangleRounded(minus, 0.2, 5, minus_hov ? app.theme.bg_highlight : app.theme.bg_base)
    rl.DrawRectangleRounded(plus,  0.2, 5, plus_hov  ? app.theme.bg_highlight : app.theme.bg_base)
    draw_text_ui(&app.font, "-", {minus.x + 8, minus.y + 4}, app.theme.text_primary, app.font.ui_size + 1)
    draw_text_ui(&app.font, "+", {plus.x + 8, plus.y + 4}, app.theme.text_primary, app.font.ui_size + 1)

    val_text := fmt.ctprintf("%.2f", value^)
    draw_text_ui(&app.font, val_text, {row.x + row.width - 78, row.y + 7}, app.theme.text_muted, app.font.ui_size)

    if rl.CheckCollisionPointRec(mouse, minus) && rl.IsMouseButtonPressed(.LEFT) {
        value^ = clamp(value^ - step, min_v, max_v)
        changed = true
    }
    if rl.CheckCollisionPointRec(mouse, plus) && rl.IsMouseButtonPressed(.LEFT) {
        value^ = clamp(value^ + step, min_v, max_v)
        changed = true
    }
    return changed
}

_draw_toggle_row :: proc(app: ^App, label: string, value: ^bool, row: rl.Rectangle, mouse: rl.Vector2) {
    rl.DrawRectangleRounded(row, 0.14, 6, app.theme.bg_elevated)
    draw_text_ui(&app.font, strings.clone_to_cstring(label, context.temp_allocator),
        {row.x + 10, row.y + 6}, app.theme.text_primary, app.font.ui_size)

    toggle := rl.Rectangle{row.x + row.width - 58, row.y + 4, 46, 20}
    on := value^
    bg := on ? app.theme.accent : app.theme.bg_base
    rl.DrawRectangleRounded(toggle, 0.5, 8, bg)
    knob_x := on ? toggle.x + 28 : toggle.x + 2
    rl.DrawCircle(i32(knob_x + 8), i32(toggle.y + 10), 8, app.theme.text_primary)

    if rl.CheckCollisionPointRec(mouse, toggle) && rl.IsMouseButtonPressed(.LEFT) {
        value^ = !value^
    }
}

_draw_filter_btn :: proc(app: ^App, rect: rl.Rectangle, label: string, active: bool, mouse: rl.Vector2) {
    hov := rl.CheckCollisionPointRec(mouse, rect)
    bg := active ? app.theme.bg_highlight : (hov ? rl.Color{app.theme.bg_highlight.r, app.theme.bg_highlight.g, app.theme.bg_highlight.b, 110} : app.theme.bg_base)
    rl.DrawRectangleRounded(rect, 0.2, 5, bg)
    rl.DrawRectangleRoundedLinesEx(rect, 0.2, 5, 1, app.theme.border)
    draw_text_ui(&app.font, strings.clone_to_cstring(label, context.temp_allocator),
        {rect.x + 12, rect.y + 5}, app.theme.text_primary, app.font.ui_size - 1)
}