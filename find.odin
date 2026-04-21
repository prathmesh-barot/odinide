package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

Find_Focus :: enum { Search, Replace }

Find_Match :: struct {
    line:      int,
    col_start: int,
    col_end:   int,
    abs_start: int,
    abs_end:   int,
}

Find_State :: struct {
    visible:        bool,
    replace_mode:   bool,
    query:          string,
    replace_str:    string,
    matches:        [dynamic]Find_Match,
    current:        int,
    case_sensitive: bool,
    input_focused:  Find_Focus,
}

find_init :: proc(f: ^Find_State) {
    f.matches = make([dynamic]Find_Match)
    f.visible = false
    f.current = 0
    f.input_focused = .Search
}

find_destroy :: proc(f: ^Find_State) {
    delete(f.matches)
    if len(f.query) > 0 { delete(f.query) }
    if len(f.replace_str) > 0 { delete(f.replace_str) }
}

find_open :: proc(app: ^App, replace: bool) {
    app.find.visible = true
    app.find.replace_mode = replace
    app.find.input_focused = .Search
    app.find.current = 0
    _find_recompute(app)
}

find_close :: proc(app: ^App) {
    app.find.visible = false
    app.find.current = 0
    clear(&app.find.matches)
    if len(app.find.query) > 0 { delete(app.find.query); app.find.query = "" }
    if len(app.find.replace_str) > 0 { delete(app.find.replace_str); app.find.replace_str = "" }
}

_find_recompute :: proc(app: ^App) {
    clear(&app.find.matches)
    if !app.find.visible do return
    if app.active_editor < 0 || app.active_editor >= len(app.editors) do return
    e := &app.editors[app.active_editor]
    if app.find.query == "" do return

    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines := strings.split_lines(content, context.temp_allocator)
    abs := 0

    needle := app.find.query
    if !app.find.case_sensitive {
        needle = strings.to_lower(needle, context.temp_allocator)
    }

    for line_str, i in lines {
        hay := line_str
        if !app.find.case_sensitive {
            hay = strings.to_lower(line_str, context.temp_allocator)
        }
        start := 0
        for {
            idx := strings.index(hay[start:], needle)
            if idx < 0 do break
            cs := start + idx
            ce := cs + len(needle)
            append(&app.find.matches, Find_Match{
                line      = i,
                col_start = cs,
                col_end   = ce,
                abs_start = abs + cs,
                abs_end   = abs + ce,
            })
            start = ce
        }
        abs += len(line_str) + 1
    }

    if len(app.find.matches) == 0 {
        app.find.current = 0
    } else {
        app.find.current = clamp(app.find.current, 0, len(app.find.matches) - 1)
    }
}

find_draw :: proc(app: ^App) {
    if !app.find.visible do return
    if app.active_editor < 0 || app.active_editor >= len(app.editors) do return
    e := &app.editors[app.active_editor]

    rect := app.layout.editor_area
    pad: f32 = 10
    h_find: f32 = app.find.replace_mode ? 64 : 36
    bar := rl.Rectangle{rect.x + pad, rect.y + pad, rect.width - pad * 2, h_find}

    rl.DrawRectangleRounded(bar, 0.18, 8, rl.Color{22, 23, 36, 255})
    rl.DrawRectangleRoundedLinesEx(bar, 0.18, 8, 1, app.theme.border)

    // Search box
    box_w: f32 = bar.width - 160
    search := rl.Rectangle{bar.x + 10, bar.y + 8, box_w, 20}
    rl.DrawRectangleRounded(search, 0.18, 6, app.theme.bg_base)
    rl.DrawRectangleRoundedLinesEx(search, 0.18, 6, 1, app.find.input_focused == .Search ? app.theme.accent : app.theme.border)

    q := app.find.query
    if q == "" { q = "Find..." }
    q_col := app.find.query == "" ? app.theme.text_disabled : app.theme.text_primary
    draw_text_ui(&app.font, strings.clone_to_cstring(q, context.temp_allocator), {search.x + 8, search.y + 4}, q_col, 11)

    // Match counter + nav
    total := len(app.find.matches)
    cur := total > 0 ? app.find.current + 1 : 0
    counter := fmt.ctprintf("%d/%d", cur, total)
    draw_text_ui(&app.font, counter, {bar.x + bar.width - 138, bar.y + 11}, app.theme.text_muted, 11)

    prev_btn := rl.Rectangle{bar.x + bar.width - 76, bar.y + 8, 28, 20}
    next_btn := rl.Rectangle{bar.x + bar.width - 44, bar.y + 8, 28, 20}
    mouse := rl.GetMousePosition()
    if rl.CheckCollisionPointRec(mouse, prev_btn) { rl.DrawRectangleRounded(prev_btn, 0.3, 6, app.theme.bg_highlight) }
    if rl.CheckCollisionPointRec(mouse, next_btn) { rl.DrawRectangleRounded(next_btn, 0.3, 6, app.theme.bg_highlight) }
    draw_text_ui(&app.font, "◀", {prev_btn.x + 8, prev_btn.y + 2}, app.theme.text_primary, 12)
    draw_text_ui(&app.font, "▶", {next_btn.x + 8, next_btn.y + 2}, app.theme.text_primary, 12)
    if rl.IsMouseButtonPressed(.LEFT) {
        if rl.CheckCollisionPointRec(mouse, prev_btn) { find_prev(app, e) }
        if rl.CheckCollisionPointRec(mouse, next_btn) { find_next(app, e) }
    }

    if app.find.replace_mode {
        rep := rl.Rectangle{bar.x + 10, bar.y + 36, box_w, 20}
        rl.DrawRectangleRounded(rep, 0.18, 6, app.theme.bg_base)
        rl.DrawRectangleRoundedLinesEx(rep, 0.18, 6, 1, app.find.input_focused == .Replace ? app.theme.accent : app.theme.border)
        r := app.find.replace_str
        if r == "" { r = "Replace..." }
        r_col := app.find.replace_str == "" ? app.theme.text_disabled : app.theme.text_primary
        draw_text_ui(&app.font, strings.clone_to_cstring(r, context.temp_allocator), {rep.x + 8, rep.y + 4}, r_col, 11)

        repl_btn := rl.Rectangle{bar.x + bar.width - 140, bar.y + 34, 62, 22}
        all_btn  := rl.Rectangle{bar.x + bar.width - 72,  bar.y + 34, 62, 22}
        if rl.CheckCollisionPointRec(mouse, repl_btn) { rl.DrawRectangleRounded(repl_btn, 0.22, 6, app.theme.bg_highlight) }
        if rl.CheckCollisionPointRec(mouse, all_btn)  { rl.DrawRectangleRounded(all_btn,  0.22, 6, app.theme.bg_highlight) }
        rl.DrawRectangleRoundedLinesEx(repl_btn, 0.22, 6, 1, app.theme.border)
        rl.DrawRectangleRoundedLinesEx(all_btn,  0.22, 6, 1, app.theme.border)
        draw_text_ui(&app.font, "Replace", {repl_btn.x + 10, repl_btn.y + 4}, app.theme.text_primary, 11)
        draw_text_ui(&app.font, "All",     {all_btn.x + 22,  all_btn.y + 4},  app.theme.text_primary, 11)

        if rl.IsMouseButtonPressed(.LEFT) {
            if rl.CheckCollisionPointRec(mouse, repl_btn) { find_replace_current(app, e) }
            if rl.CheckCollisionPointRec(mouse, all_btn)  { find_replace_all(app, e) }
            if rl.CheckCollisionPointRec(mouse, search)   { app.find.input_focused = .Search }
            if rl.CheckCollisionPointRec(mouse, rep)      { app.find.input_focused = .Replace }
        }
    } else {
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, search) {
            app.find.input_focused = .Search
        }
    }
}

find_next :: proc(app: ^App, e: ^Editor_State) {
    if len(app.find.matches) == 0 do return
    app.find.current = (app.find.current + 1) % len(app.find.matches)
    _find_scroll_to_current(app, e)
}

find_prev :: proc(app: ^App, e: ^Editor_State) {
    if len(app.find.matches) == 0 do return
    app.find.current -= 1
    if app.find.current < 0 do app.find.current = len(app.find.matches) - 1
    _find_scroll_to_current(app, e)
}

_find_scroll_to_current :: proc(app: ^App, e: ^Editor_State) {
    if len(app.find.matches) == 0 do return
    m := app.find.matches[app.find.current]
    editor_set_pos_from_line_col(e, m.line, m.col_start)
    e.cursor.sticky_col = e.cursor.col
    editor_scroll_to_cursor(e, app.layout.editor_area, &app.font)
}

find_handle_input :: proc(app: ^App) {
    if !app.find.visible do return
    if app.active_editor < 0 || app.active_editor >= len(app.editors) do return
    e := &app.editors[app.active_editor]

    ctrl  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    shift := rl.IsKeyDown(.LEFT_SHIFT)   || rl.IsKeyDown(.RIGHT_SHIFT)

    if rl.IsKeyPressed(.ESCAPE) {
        find_close(app)
        return
    }

    if rl.IsKeyPressed(.TAB) {
        if app.find.replace_mode {
            app.find.input_focused = app.find.input_focused == .Search ? .Replace : .Search
        }
    }

    if rl.IsKeyPressed(.ENTER) {
        if shift { find_prev(app, e) } else { find_next(app, e) }
    }

    // Text input
    if !ctrl {
        ch := rl.GetCharPressed()
        for ch > 0 {
            buf, n := utf8.encode_rune(ch)
            s := string(buf[:n])
            if app.find.input_focused == .Search {
                new_q := fmt.tprintf("%s%s", app.find.query, s)
                if len(app.find.query) > 0 { delete(app.find.query) }
                app.find.query = strings.clone(new_q, context.allocator)
                _find_recompute(app)
            } else if app.find.replace_mode && app.find.input_focused == .Replace {
                new_r := fmt.tprintf("%s%s", app.find.replace_str, s)
                if len(app.find.replace_str) > 0 { delete(app.find.replace_str) }
                app.find.replace_str = strings.clone(new_r, context.allocator)
            }
            ch = rl.GetCharPressed()
        }
    }

    if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
        if app.find.input_focused == .Search && len(app.find.query) > 0 {
            new_q := strings.clone(app.find.query[:len(app.find.query)-1], context.allocator)
            delete(app.find.query)
            app.find.query = new_q
            _find_recompute(app)
        } else if app.find.replace_mode && app.find.input_focused == .Replace && len(app.find.replace_str) > 0 {
            new_r := strings.clone(app.find.replace_str[:len(app.find.replace_str)-1], context.allocator)
            delete(app.find.replace_str)
            app.find.replace_str = new_r
        }
    }
}

find_replace_current :: proc(app: ^App, e: ^Editor_State) {
    if !app.find.replace_mode do return
    if len(app.find.matches) == 0 do return
    m := app.find.matches[app.find.current]
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    if m.abs_start < 0 || m.abs_end > len(content) do return

    deleted := content[m.abs_start:m.abs_end]
    _push_delete_undo(e, m.abs_start, deleted, e.cursor.pos, m.abs_start)
    gap_buffer_delete(&e.buffer, m.abs_start, m.abs_end - m.abs_start)
    e.cursor.pos = m.abs_start

    before := e.cursor.pos
    gap_buffer_insert(&e.buffer, before, app.find.replace_str)
    e.cursor.pos += len(app.find.replace_str)
    _push_insert_undo(e, before, app.find.replace_str, before, e.cursor.pos)
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
    e.last_edit_time = rl.GetTime()
    e.lsp_dirty = true
    highlighter_mark_dirty(&app.highlighter, e.cursor.line)
    _find_recompute(app)
}

find_replace_all :: proc(app: ^App, e: ^Editor_State) {
    if !app.find.replace_mode do return
    if app.find.query == "" do return

    old_text := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    // Build new text by repeated replace (simple, non-overlapping by match list).
    if len(app.find.matches) == 0 {
        _find_recompute(app)
    }
    if len(app.find.matches) == 0 do return

    // Replace from end to start using absolute offsets.
    new_buf := make([]u8, len(old_text), context.temp_allocator)
    copy(new_buf, old_text)
    new_text := string(new_buf)

    // We rebuild via a builder-like splice strategy to avoid O(n^2).
    parts := make([dynamic]string, 0, context.temp_allocator)
    last := 0
    for m in app.find.matches {
        if m.abs_start < last do continue
        append(&parts, old_text[last:m.abs_start])
        append(&parts, app.find.replace_str)
        last = m.abs_end
    }
    append(&parts, old_text[last:])
    new_text, _ = strings.join(parts[:], "", context.temp_allocator)

    cmd := Edit_Command{
        op = .ReplaceAll,
        pos = 0,
        text  = strings.clone(old_text, context.allocator),
        text2 = strings.clone(new_text, context.allocator),
        cursor_before = e.cursor.pos,
        cursor_after  = e.cursor.pos,
        at_time = rl.GetTime(),
    }
    undo_push(&e.undo_stack, cmd)

    // Apply new content
    delete(e.buffer.data)
    gap_buffer_init(&e.buffer, max(len(new_text) * 2, 4096))
    if len(new_text) > 0 { gap_buffer_insert(&e.buffer, 0, new_text) }
    e.cursor.pos = clamp(e.cursor.pos, 0, e.buffer.length)
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
    e.last_edit_time = rl.GetTime()
    e.lsp_dirty = true
    highlighter_mark_dirty(&app.highlighter, e.cursor.line)
    _find_recompute(app)
}

