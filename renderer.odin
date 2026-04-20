package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Token stub for Phase 2 syntax highlighting
Token :: struct {
    start: int,
    end:   int,
    kind:  Token_Kind,
}

Token_Kind :: enum {
    Text, Keyword, Type, Proc, String, Number, Comment, Operator, Punctuation,
}

// ─── Main Editor Draw ─────────────────────────────────────────────────────────

renderer_draw_editor :: proc(app: ^App, e: ^Editor_State) {
    rect := app.layout.editor_area

    // Background
    rl.DrawRectangleRec(rect, app.theme.bg_base)

    // ── Compute layout constants ───────────────────────────────────────────
    content    := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines      := strings.split_lines(content, context.temp_allocator)
    line_count := max(len(lines), 1)

    digit_count := count_digits(line_count)
    gutter_w    := f32(digit_count) * app.font.char_width + 28  // generous padding

    // Gutter background (subtle, slightly lighter than editor bg)
    rl.DrawRectangleRec(
        {rect.x, rect.y, gutter_w - 1, rect.height},
        app.theme.gutter_bg)

    // Gutter right separator
    rl.DrawLineEx(
        {rect.x + gutter_w - 1, rect.y},
        {rect.x + gutter_w - 1, rect.y + rect.height},
        1, app.theme.border)

    // ── Begin scissor for editor text ──────────────────────────────────────
    rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height))

    // ── Active line highlight ──────────────────────────────────────────────
    active_y := (rect.y - e.scroll_offset.y) + f32(e.cursor.line) * app.font.line_height
    rl.DrawRectangleRec(
        {rect.x + gutter_w, active_y, rect.width - gutter_w, app.font.line_height},
        app.theme.bg_active_line)

    // Also highlight the gutter line number row
    rl.DrawRectangleRec(
        {rect.x, active_y, gutter_w - 1, app.font.line_height},
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

            // ── Gutter line number ─────────────────────────────────────────
            if app.config.show_line_numbers {
                c_num  := fmt.ctprintf("%d", i + 1)
                num_w  := rl.MeasureTextEx(app.font.ui, c_num, app.font.ui_size, 0).x
                is_cur := i == e.cursor.line
                gnum_col := is_cur ? app.theme.text_primary : app.theme.text_muted
                // Vertically center within line_height
                text_y := y + (app.font.line_height - app.font.ui_size) * 0.5
                draw_text_ui(&app.font, c_num,
                    {rect.x + gutter_w - num_w - 12, text_y},
                    gnum_col, app.font.ui_size)
            }

            // ── Code text (Phase 1: all primary, Phase 2: tokenized) ───────
            if line_len > 0 {
                c_line := strings.clone_to_cstring(line_str, context.temp_allocator)
                text_y := y + (app.font.line_height - app.font.font_size) * 0.5
                draw_text_mono(&app.font, c_line,
                    {rect.x + gutter_w + 4, text_y},
                    app.theme.text_primary, app.font.font_size)
            }
        }

        char_index += line_len + 1
        y          += app.font.line_height
    }

    // ── Cursor ────────────────────────────────────────────────────────────────
    cx := (rect.x + gutter_w + 4) + f32(e.cursor.col) * app.font.char_width
    cy := (rect.y - e.scroll_offset.y) + f32(e.cursor.line) * app.font.line_height

    show_cursor := (i32(app.cursor_blink_timer * 2.0) % 2) == 0
    if show_cursor {
        // 2px wide solid cursor bar
        rl.DrawRectangleRec({cx, cy + 2, 2, app.font.line_height - 4}, app.theme.accent)
    }

    rl.EndScissorMode()

    // ── Vertical scrollbar ────────────────────────────────────────────────────
    renderer_draw_scrollbar(app, e, rect)
}

// Phase 2 drop-in stub
render_line :: proc(app: ^App, x, y: f32, line_str: string, tokens: []Token) {
    if len(line_str) > 0 {
        c_line := strings.clone_to_cstring(line_str, context.temp_allocator)
        draw_text_mono(&app.font, c_line, {x, y}, app.theme.text_primary, app.font.font_size)
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