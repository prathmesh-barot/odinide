package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// ─── Main Editor Draw ─────────────────────────────────────────────────────────

renderer_draw_editor :: proc(app: ^App, e: ^Editor_State) {
    rect := app.layout.editor_area
    highlighter_update(&app.highlighter, e)

    // Background
    rl.DrawRectangleRec(rect, app.theme.bg_base)

    // ── Compute layout constants ───────────────────────────────────────────
    content    := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines      := strings.split_lines(content, context.temp_allocator)
    line_count := max(len(lines), 1)

    // Mock layout: diagnostics column (14px) + fixed line number column (32px) + separator (1px)
    diag_w : f32 = 14
    ln_w   : f32 = app.config.show_line_numbers ? 32 : 0
    sep_w  : f32 = 1
    gutter_w := diag_w + ln_w + sep_w
    code_pad : f32 = 8
    code_x   := rect.x + gutter_w + code_pad
    uri := e.file_path != "" ? _path_to_uri(e.file_path) : ""

    // Gutter background (subtle, slightly lighter than editor bg)
    rl.DrawRectangleRec(
        {rect.x, rect.y, gutter_w - 1, rect.height},
        app.theme.gutter_bg)

    // Gutter right separator
    rl.DrawLineEx(
        {rect.x + diag_w + ln_w, rect.y},
        {rect.x + diag_w + ln_w, rect.y + rect.height},
        1, app.theme.border)

    // ── Begin scissor for editor text ──────────────────────────────────────
    rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height))

    // ── Active line highlight ──────────────────────────────────────────────
    active_y := (rect.y - e.scroll_offset.y) + f32(e.cursor.line) * app.font.line_height
    rl.DrawRectangleRec(
        {rect.x, active_y, rect.width, app.font.line_height},
        app.theme.bg_active_line)

    // ── Selection range ────────────────────────────────────────────────────
    sel_start, sel_end := 0, 0
    has_sel := editor_has_selection(e)
    if has_sel do sel_start, sel_end = editor_get_selection_range(e)

    y          := rect.y - e.scroll_offset.y
    char_index := 0

    for line_str, i in lines {
        line_len   := len(line_str)
        line_btm   := y + app.font.line_height

        if line_btm > rect.y && y < rect.y + rect.height {

            // ── Selection background ───────────────────────────────────────
            if has_sel {
                line_end_abs := char_index + line_len
                if sel_start <= line_end_abs && sel_end > char_index {
                    s_col := max(0, sel_start - char_index)
                    e_col := min(line_len, sel_end - char_index)
                    if e_col >= s_col {
                        sx := rect.x + gutter_w + f32(s_col) * app.font.char_width
                        sw := f32(e_col - s_col) * app.font.char_width
                        if sel_end > char_index + line_len do sw += app.font.char_width * 0.5
                        sel_color := app.theme.bg_highlight
                        sel_color.a = 160
                        rl.DrawRectangleRec({sx, y, sw, app.font.line_height}, sel_color)
                    }
                }
            }

            // ── Find match highlights ──────────────────────────────────────
            if app.find.visible && app.find.query != "" && len(app.find.matches) > 0 {
                for m, mi in app.find.matches {
                    if m.line != i do continue
                    sx := code_x + f32(m.col_start) * app.font.char_width
                    sw := max(f32(1), f32(m.col_end - m.col_start) * app.font.char_width)
                    col := app.theme.syn_string
                    col.a = 55
                    rl.DrawRectangleRec({sx, y, sw, app.font.line_height}, col)
                    if mi == app.find.current {
                        rl.DrawRectangleLinesEx({sx, y + 1, sw, app.font.line_height - 2}, 1, app.theme.accent)
                    }
                }
            }

            // ── Gutter line number ─────────────────────────────────────────
            if app.config.show_line_numbers {
                c_num  := fmt.ctprintf("%d", i + 1)
                is_cur := i == e.cursor.line
                gnum_col := is_cur ? app.theme.text_primary : app.theme.text_muted
                text_y := y + (app.font.line_height - app.font.ui_size) * 0.5
                // Right-aligned inside 32px column
                num_w  := rl.MeasureTextEx(app.font.ui, c_num, app.font.ui_size, 0).x
                draw_text_ui(&app.font, c_num, {rect.x + diag_w + ln_w - num_w - 6, text_y},
                    gnum_col, app.font.ui_size)
            }

            // ── Diagnostic glyphs ──────────────────────────────────────────
            if uri != "" {
                found, dg := diagnostics_best_for_line(&app.diagnostics, uri, i)
                if found {
                    glyph := dg.severity == .Warning ? "▲" : "●"
                    if dg.severity == .Info  do glyph = "●"
                    if dg.severity == .Hint  do glyph = "·"
                    col := rl.Color{247, 118, 142, 255}
                    if dg.severity == .Warning do col = app.theme.accent_warm
                    if dg.severity == .Info    do col = app.theme.accent
                    if dg.severity == .Hint    do col = app.theme.text_muted
                    gy := y + (app.font.line_height - 11) * 0.5
                    draw_text_ui(&app.font, strings.clone_to_cstring(glyph, context.temp_allocator),
                        {rect.x + 3, gy}, col, 11)
                }
            }

            // ── Code text (Phase 2 highlighting) ───────────────────────────
            if line_len > 0 {
                text_y := y + (app.font.line_height - app.font.font_size) * 0.5
                toks := i < len(app.highlighter.lines) ? app.highlighter.lines[i].tokens : nil
                renderer_draw_highlighted_line(app, line_str, toks, code_x, text_y)

                // Wavy underlines for diagnostics (Phase 2)
                if uri != "" {
                    _draw_diag_underlines(app, uri, i, y, code_x)
                }
            }
        }

        char_index += line_len + 1
        y          += app.font.line_height
    }

    // ── Cursor ────────────────────────────────────────────────────────────────
    cx := code_x + f32(e.cursor.col) * app.font.char_width
    cy := (rect.y - e.scroll_offset.y) + f32(e.cursor.line) * app.font.line_height

    show_cursor := (i32(app.cursor_blink_timer * 2.0) % 2) == 0
    if show_cursor {
        // 2px wide solid cursor bar
        rl.DrawRectangleRec({cx, cy + 2, 2, app.font.line_height - 4}, app.theme.accent)
    }

    rl.EndScissorMode()

    // ── Vertical scrollbar ────────────────────────────────────────────────────
    renderer_draw_scrollbar(app, e, rect)

    // ── Overlays (completion + diagnostic hover) ──────────────────────────────
    if uri != "" {
        _draw_diag_hover(app, uri, e, rect, code_x)
    }
    _mock_draw_completion_popup(app, e, rect, code_x)
    if uri != "" {
        _draw_hover_popup(app, uri, e, rect, code_x)
    }
}

// ─── Scrollbar ────────────────────────────────────────────────────────────────

renderer_draw_scrollbar :: proc(app: ^App, e: ^Editor_State, rect: rl.Rectangle) {
    sb_w    : f32 = 8
    sb_rect := rl.Rectangle{rect.x + rect.width - sb_w, rect.y, sb_w, rect.height}

    content  := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines    := strings.split_lines(content, context.temp_allocator)
    total_h  := f32(max(len(lines), 1)) * app.font.line_height
    if total_h <= rect.height do return

    visible_ratio := rect.height / total_h
    thumb_h       := max(rect.height * visible_ratio, 28)
    max_scroll    := total_h - rect.height
    scroll_ratio  := clamp(e.scroll_offset.y / max_scroll, 0, 1)
    thumb_y       := rect.y + scroll_ratio * (rect.height - thumb_h)

    thumb_rect := rl.Rectangle{sb_rect.x + 1, thumb_y, sb_w - 2, thumb_h}

    mouse  := rl.GetMousePosition()
    hov    := rl.CheckCollisionPointRec(mouse, sb_rect)

    if rl.CheckCollisionPointRec(mouse, thumb_rect) && rl.IsMouseButtonPressed(.LEFT) {
        app.scrollbar_dragging   = true
        app.scrollbar_drag_start = mouse.y - thumb_y
    }
    if app.scrollbar_dragging {
        if rl.IsMouseButtonDown(.LEFT) {
            new_thumb_y      := mouse.y - app.scrollbar_drag_start
            new_scroll_ratio := (new_thumb_y - rect.y) / (rect.height - thumb_h)
            e.target_scroll_y = clamp(new_scroll_ratio * max_scroll, 0, max_scroll)
        } else {
            app.scrollbar_dragging = false
        }
    }

    // Track (very subtle)
    active := hov || app.scrollbar_dragging
    track_a : u8 = active ? 40 : 15
    rl.DrawRectangleRec(sb_rect,
        {app.theme.text_muted.r, app.theme.text_muted.g, app.theme.text_muted.b, track_a})

    // Thumb (rounded)
    thumb_a : u8 = active ? 180 : 70
    rl.DrawRectangleRounded(thumb_rect, 0.5, 6,
        {app.theme.text_muted.r, app.theme.text_muted.g, app.theme.text_muted.b, thumb_a})
}

// ─── Diagnostics rendering (OLS-driven) ───────────────────────────────────────

_draw_diag_underlines :: proc(app: ^App, uri: string, line: int, row_y: f32, code_x: f32) {
    ds, ok := app.diagnostics.entries[uri]
    if !ok do return

    for d in ds {
        if d.line != line do continue
        if d.col_end <= d.col_start do continue

        x0 := code_x + f32(d.col_start) * app.font.char_width
        x1 := code_x + f32(d.col_end)   * app.font.char_width
        y  := row_y + app.font.line_height - 4

        col := rl.Color{247, 118, 142, 255}
        if d.severity == .Warning do col = app.theme.accent_warm
        if d.severity == .Info    do col = app.theme.accent
        if d.severity == .Hint    do col = app.theme.text_muted

        // Wavy underline (always; closest to mock)
        step : f32 = 4
        amp  : f32 = 1.5
        x := x0
        up := true
        for x < x1 {
            nx := min(x + step, x1)
            yy0 := y + (up ? -amp : amp)
            yy1 := y + (!up ? -amp : amp)
            rl.DrawLineEx({x, yy0}, {nx, yy1}, 1, col)
            up = !up
            x = nx
        }
    }
}

_draw_diag_hover :: proc(app: ^App, uri: string, e: ^Editor_State, rect: rl.Rectangle, code_x: f32) {
    mouse := rl.GetMousePosition()
    if !rl.CheckCollisionPointRec(mouse, rect) do return

    rel_y := mouse.y - rect.y + e.scroll_offset.y
    line  := int(rel_y / app.font.line_height)
    if line < 0 || line >= 200000 do return

    // Only show tooltip when hovering inside the error range
    ds, ok := app.diagnostics.entries[uri]
    if !ok do return

    for d in ds {
        if d.line != line do continue
        x0 := code_x + f32(d.col_start) * app.font.char_width
        x1 := code_x + f32(max(d.col_end, d.col_start+1)) * app.font.char_width
        row_y := (rect.y - e.scroll_offset.y) + f32(line) * app.font.line_height
        if mouse.x < x0 || mouse.x > x1 || mouse.y < row_y || mouse.y > row_y + app.font.line_height do continue

        // Tooltip box (below row)
        tip_w : f32 = 260
        tip_h : f32 = 56
        tx := clamp(mouse.x - 40, rect.x + 10, rect.x + rect.width - tip_w - 10)
        ty := clamp(row_y + app.font.line_height + 6, rect.y + 8, rect.y + rect.height - tip_h - 8)
        tip := rl.Rectangle{tx, ty, tip_w, tip_h}

        border_col := rl.Color{59, 66, 97, 255}
        sev_txt := "● info"
        sev_col := app.theme.accent
        if d.severity == .Error { sev_txt = "● error"; sev_col = rl.Color{247, 118, 142, 255}; border_col = sev_col }
        if d.severity == .Warning { sev_txt = "▲ warning"; sev_col = app.theme.accent_warm; border_col = sev_col }
        if d.severity == .Hint { sev_txt = "· hint"; sev_col = app.theme.text_muted }

        rl.DrawRectangleRounded(tip, 0.12, 6, rl.Color{28, 29, 46, 245})
        rl.DrawRectangleRoundedLinesEx(tip, 0.12, 6, 1, border_col)

        draw_text_ui(&app.font, strings.clone_to_cstring(sev_txt, context.temp_allocator),
            {tip.x + 10, tip.y + 8}, sev_col, 10)
        if d.source != "" {
            draw_text_ui(&app.font, strings.clone_to_cstring(d.source, context.temp_allocator),
                {tip.x + 86, tip.y + 8}, app.theme.text_disabled, 9)
        }

        draw_text_ui(&app.font, strings.clone_to_cstring(d.message, context.temp_allocator),
            {tip.x + 10, tip.y + 26}, app.theme.text_primary, 11)
        return
    }
}

_mock_draw_completion_popup :: proc(app: ^App, e: ^Editor_State, rect: rl.Rectangle, code_x: f32) {
    if !app.completion.open || len(app.completion.items) == 0 do return

    line_y := (rect.y - e.scroll_offset.y) + f32(app.completion.anchor_line) * app.font.line_height
    x := code_x + f32(app.completion.anchor_col) * app.font.char_width
    y := line_y + app.font.line_height

    w : f32 = 230
    header_h : f32 = 18
    row_h : f32 = 22
    h := header_h + row_h * f32(len(app.completion.items)) + 16

    px := clamp(x, rect.x + 8, rect.x + rect.width - w - 8)
    py := clamp(y, rect.y + 8, rect.y + rect.height - h - 8)
    popup := rl.Rectangle{px, py, w, h}

    rl.DrawRectangleRounded(popup, 0.08, 6, rl.Color{22, 23, 36, 255})
    rl.DrawRectangleRoundedLinesEx(popup, 0.08, 6, 1, rl.Color{59, 66, 97, 255})

    // Header
    draw_text_ui(&app.font, strings.clone_to_cstring(app.completion.title, context.temp_allocator),
        {popup.x + 10, popup.y + 4}, app.theme.text_disabled, 10)
    rl.DrawLineEx({popup.x, popup.y + header_h}, {popup.x + popup.width, popup.y + header_h}, 1,
        rl.Color{42, 43, 64, 255})

    // Items
    for it, i in app.completion.items {
        row := rl.Rectangle{popup.x, popup.y + header_h + f32(i) * row_h, popup.width, row_h}
        if i == app.completion.selected {
            rl.DrawRectangleRec(row, rl.Color{41, 43, 61, 255})
        }

        // kind pill
        pill := rl.Rectangle{row.x + 10, row.y + 4, 16, 14}
        rl.DrawRectangleRounded(pill, 0.25, 6, app.theme.accent)
        draw_text_ui(&app.font, strings.clone_to_cstring(it.kind, context.temp_allocator),
            {pill.x + 4, pill.y + 1}, app.theme.bg_base, 9)

        label_col := i == app.completion.selected ? app.theme.text_primary : app.theme.text_muted
        draw_text_ui(&app.font, strings.clone_to_cstring(it.label, context.temp_allocator),
            {row.x + 34, row.y + 5}, label_col, 12)
        if it.detail != "" {
            dw := rl.MeasureTextEx(app.font.ui, strings.clone_to_cstring(it.detail, context.temp_allocator), 10, 0).x
            draw_text_ui(&app.font, strings.clone_to_cstring(it.detail, context.temp_allocator),
                {row.x + row.width - dw - 10, row.y + 6}, app.theme.text_disabled, 10)
        }
    }

    // Footer
    draw_text_ui(&app.font, strings.clone_to_cstring("↑↓ navigate   ↵ accept   esc dismiss", context.temp_allocator),
        {popup.x + 10, popup.y + popup.height - 14}, rl.Color{46, 48, 80, 255}, 10)
}

_draw_hover_popup :: proc(app: ^App, uri: string, e: ^Editor_State, rect: rl.Rectangle, code_x: f32) {
    if !app.ols.hover_visible || app.ols.hover_text == "" do return
    if app.ols.hover_uri != uri do return

    line_y := (rect.y - e.scroll_offset.y) + f32(app.ols.hover_anchor_line) * app.font.line_height
    x := code_x + f32(app.ols.hover_anchor_col) * app.font.char_width
    y := line_y - 6

    lines := strings.split_lines(app.ols.hover_text, context.temp_allocator)
    if len(lines) == 0 do return

    font_sz : f32 = 11
    pad_x   : f32 = 10
    pad_y   : f32 = 8
    max_w   : f32 = min(480, rect.width - 24)

    // Compute width as max measured line width, clamped.
    w : f32 = 180
    for ln in lines {
        mw := rl.MeasureTextEx(app.font.ui, strings.clone_to_cstring(ln, context.temp_allocator), font_sz, 0).x
        w = max(w, mw + pad_x * 2)
    }
    w = min(w, max_w)
    h : f32 = pad_y * 2 + f32(len(lines)) * (font_sz + 4)

    px := clamp(x, rect.x + 8, rect.x + rect.width - w - 8)
    py := clamp(y - h, rect.y + 8, rect.y + rect.height - h - 8)
    pop := rl.Rectangle{px, py, w, h}

    rl.DrawRectangleRounded(pop, 0.10, 6, rl.Color{22, 23, 36, 255})
    rl.DrawRectangleRoundedLinesEx(pop, 0.10, 6, 1, rl.Color{59, 66, 97, 255})

    ty := pop.y + pad_y
    for ln in lines {
        draw_text_ui(&app.font, strings.clone_to_cstring(ln, context.temp_allocator),
            {pop.x + pad_x, ty}, app.theme.text_primary, font_sz)
        ty += font_sz + 4
    }
}