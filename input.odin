package main

import "core:os"
import "core:strings"
import rl "vendor:raylib"

Active_Panel :: enum { Files, Search, Git, Settings }

input_update :: proc(app: ^App, dt: f32) {
    ctrl  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    shift := rl.IsKeyDown(.LEFT_SHIFT)   || rl.IsKeyDown(.RIGHT_SHIFT)
    alt   := rl.IsKeyDown(.LEFT_ALT)     || rl.IsKeyDown(.RIGHT_ALT)

    // ── Blink timer ────────────────────────────────────────────────────────────
    // IMPORTANT: Do NOT call GetCharPressed() or GetKeyPressed() here —
    // they consume the event queues and break typing / navigation below.
    // Instead, check key STATE with IsKeyDown/IsKeyPressed (non-consuming).
    app.cursor_blink_timer += dt

    // ── Drag & Drop ───────────────────────────────────────────────────────────
    if rl.IsFileDropped() {
        fps := rl.LoadDroppedFiles()
        if fps.count > 0 {
            editor_open_file(app, string(fps.paths[0]))
        }
        rl.UnloadDroppedFiles(fps)
    }

    // ── Activity bar clicks ────────────────────────────────────────────────────
    mouse_pos := rl.GetMousePosition()
    if rl.IsMouseButtonPressed(.LEFT) {
        ab := app.layout.activity_bar
        for icon_i in 0..<4 {
            ix  := ab.x + (ab.width - 36) * 0.5
            iy  := ab.y + 12 + f32(icon_i) * (36 + 4)
            ir  := rl.Rectangle{ix, iy, 36, 36}
            if rl.CheckCollisionPointRec(mouse_pos, ir) {
                panel := Active_Panel(icon_i)
                if app.active_panel == panel {
                    app.layout.sidebar_visible = !app.layout.sidebar_visible
                } else {
                    app.active_panel = panel
                    app.layout.sidebar_visible = true
                }
                layout_recalculate(&app.layout, f32(app.window_width), f32(app.window_height))
                break
            }
        }
    }

    // ── Global shortcuts ───────────────────────────────────────────────────────
    if ctrl && rl.IsKeyPressed(.Q)  { app.should_quit = true }
    if alt  && rl.IsKeyPressed(.F4) { app.should_quit = true }
    if ctrl && rl.IsKeyPressed(.B)  {
        app.layout.sidebar_visible = !app.layout.sidebar_visible
        layout_recalculate(&app.layout, f32(app.window_width), f32(app.window_height))
    }
    if ctrl && rl.IsKeyPressed(.COMMA) {
        app.settings_modal_open = !app.settings_modal_open
        app.settings_tab = 0
        app_push_toast(app, app.settings_modal_open ? "Settings opened" : "Settings closed")
    }
    if ctrl && rl.IsKeyPressed(.P) {
        command_palette_toggle(app)
    }

    // ── Sidebar resize handle (drag) ──────────────────────────────────────────
    handle_x := app.layout.activity_bar.x + app.layout.activity_bar.width
    if app.layout.sidebar_visible { handle_x += app.layout.sidebar.width }
    handle_rect := rl.Rectangle{handle_x - 3, 0, 6, f32(app.window_height)}

    if app.layout.sidebar_dragging {
        rl.SetMouseCursor(.RESIZE_EW)
        new_w := mouse_pos.x - app.layout.activity_bar.width - app.layout.activity_bar.x
        app.layout.sidebar_width = clamp(new_w, 120, 600)
        if !rl.IsMouseButtonDown(.LEFT) { app.layout.sidebar_dragging = false }
        layout_recalculate(&app.layout, f32(app.window_width), f32(app.window_height))
    } else if rl.CheckCollisionPointRec(mouse_pos, handle_rect) {
        rl.SetMouseCursor(.RESIZE_EW)
        if rl.IsMouseButtonPressed(.LEFT) { app.layout.sidebar_dragging = true }
    } else if !app.scrollbar_dragging {
        rl.SetMouseCursor(.DEFAULT)
    }

    // ── Tab management ─────────────────────────────────────────────────────────
    if ctrl {
        if rl.IsKeyPressed(.N) {
            editor_new_empty(app)
            app.cursor_blink_timer = 0
            app_push_toast(app, "New file")
        }
        if rl.IsKeyPressed(.W) && app.active_editor >= 0 && len(app.editors) > 0 {
            _close_tab(app, app.active_editor)
            app_push_toast(app, "Tab closed")
        }
        if rl.IsKeyPressed(.TAB) && len(app.editors) > 1 {
            if shift {
                app.active_editor -= 1
                if app.active_editor < 0 do app.active_editor = len(app.editors) - 1
            } else {
                app.active_editor = (app.active_editor + 1) % len(app.editors)
            }
            app.cursor_blink_timer = 0
        }
        if rl.IsKeyPressed(.O) { input_try_open_dialog(app) }
        if rl.IsKeyPressed(.S) { input_save_file(app) }
        if rl.IsKeyPressed(.F) { find_open(app, false) }
        if rl.IsKeyPressed(.H) { find_open(app, true) }

        // Font size
        if rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD) {
            font_change_size(&app.font, &app.config, 1)
            app_push_toast(app, "Font size increased")
        }
        if rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT) {
            font_change_size(&app.font, &app.config, -1)
            app_push_toast(app, "Font size decreased")
        }
    }

    // When settings modal is open, keep global shortcuts but block editor editing.
    if app.settings_modal_open do return

    if app.palette.visible {
        command_palette_handle_input(app)
        return
    }

    // Find bar captures input while visible.
    if app.find.visible {
        find_handle_input(app)
        return
    }

    // ── Editor interaction (only when an editor is active) ────────────────────
    if app.active_editor < 0 || app.active_editor >= len(app.editors) do return
    e := &app.editors[app.active_editor]
    cursor_moved := false

    // ── Hover chord (Ctrl+K, Ctrl+I) ──────────────────────────────────────────
    if ctrl && rl.IsKeyPressed(.K) {
        app.ctrl_k_armed = true
        app.ctrl_k_time  = rl.GetTime()
    }
    if app.ctrl_k_armed && (rl.GetTime() - app.ctrl_k_time) > 1.0 {
        app.ctrl_k_armed = false
    }
    if ctrl && rl.IsKeyPressed(.I) && app.ctrl_k_armed {
        app.ctrl_k_armed = false
        if app.ols.initialized {
            _ = ols_request_hover(&app.ols, e)
        }
    }

    // ── Completion popup key handling ─────────────────────────────────────────
    if app.completion.open {
        if rl.IsKeyPressed(.ESCAPE) {
            _completion_close(app)
        } else {
            if rl.IsKeyPressed(.UP) {
                app.completion.selected -= 1
                if app.completion.selected < 0 do app.completion.selected = len(app.completion.items) - 1
            }
            if rl.IsKeyPressed(.DOWN) {
                app.completion.selected = (app.completion.selected + 1) % len(app.completion.items)
            }
            if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.TAB) {
                _completion_accept(app, e)
                highlighter_mark_dirty(&app.highlighter, e.cursor.line)
                app.cursor_blink_timer = 0
                cursor_moved = true
            }
        }
        // While completion is open, don't process typing/navigation that would desync UI.
        // (Mouse selection + scroll still work below.)
    }

    if rl.IsKeyPressed(.ESCAPE) && app.ols.hover_visible {
        app.ols.hover_visible = false
    }

    // ── Clipboard ─────────────────────────────────────────────────────────────
    if ctrl {
        if rl.IsKeyPressed(.C) && editor_has_selection(e) {
            text   := editor_get_selection_text(e, context.temp_allocator)
            c_text := strings.clone_to_cstring(text, context.temp_allocator)
            rl.SetClipboardText(c_text)
        }
        if rl.IsKeyPressed(.X) && editor_has_selection(e) {
            text   := editor_get_selection_text(e, context.temp_allocator)
            c_text := strings.clone_to_cstring(text, context.temp_allocator)
            rl.SetClipboardText(c_text)
            editor_delete_selection(e)
            app.cursor_blink_timer = 0
            cursor_moved = true
        }
        if rl.IsKeyPressed(.V) {
            c_text := rl.GetClipboardText()
            if c_text != nil {
                text := string(c_text)
                if editor_has_selection(e) {
                    start, end := editor_get_selection_range(e)
                    deleted := gap_buffer_to_string(&e.buffer, context.temp_allocator)[start:end]
                    _push_delete_undo(e, start, deleted, e.cursor.pos, start)
                    editor_delete_selection(e)
                }
                before := e.cursor.pos
                gap_buffer_insert(&e.buffer, before, text)
                e.cursor.pos += len(text)
                _push_insert_undo(e, before, text, before, e.cursor.pos)
                e.last_edit_time = rl.GetTime()
                editor_sync_line_col(e)
                e.is_modified = true
                highlighter_mark_dirty(&app.highlighter, e.cursor.line)
                app.cursor_blink_timer = 0
                cursor_moved = true
            }
        }
        if rl.IsKeyPressed(.A) {
            e.selection.active = true
            e.selection.anchor = 0
            e.cursor.pos       = e.buffer.length
            editor_sync_line_col(e)
            app.cursor_blink_timer = 0
            cursor_moved = true
        }
        if rl.IsKeyPressed(.Z) {
            if shift {
                redo_do(&e.undo_stack, e)
            } else {
                undo_do(&e.undo_stack, e)
            }
            highlighter_mark_dirty(&app.highlighter, e.cursor.line)
            app.cursor_blink_timer = 0
            cursor_moved = true
        }
        if rl.IsKeyPressed(.Y) {
            redo_do(&e.undo_stack, e)
            highlighter_mark_dirty(&app.highlighter, e.cursor.line)
            app.cursor_blink_timer = 0
            cursor_moved = true
        }
    }

    // ── Mouse interaction ──────────────────────────────────────────────────────
    cursor_moved = cursor_moved || input_handle_mouse(app, e, shift)

    // ── Character input (non-ctrl)  ── DO NOT move GetCharPressed above ───────
    if !ctrl {
        ch := rl.GetCharPressed()
        for ch > 0 {
            if app.completion.open {
                // If user types while completion is open, dismiss it (mock-like).
                _completion_close(app)
            }
            if app.ols.hover_visible {
                app.ols.hover_visible = false
            }
            editor_insert_char(e, ch)
            editor_sync_line_col(e)
            e.cursor.sticky_col    = e.cursor.col
            highlighter_mark_dirty(&app.highlighter, e.cursor.line)
            app.cursor_blink_timer = 0  // reset blink on every char typed
            cursor_moved = true
            if ch == '.' && app.ols.initialized {
                _ = ols_request_completion(&app.ols, e)
            }
            ch = rl.GetCharPressed()
        }
    }

    // ── Structural keys ────────────────────────────────────────────────────────
    if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
        editor_delete_char_backward(e)
        editor_sync_line_col(e)
        highlighter_mark_dirty(&app.highlighter, e.cursor.line)
        app.cursor_blink_timer = 0
        cursor_moved = true
    }
    if rl.IsKeyPressed(.DELETE) || rl.IsKeyPressedRepeat(.DELETE) {
        editor_delete_char_forward(e)
        editor_sync_line_col(e)
        highlighter_mark_dirty(&app.highlighter, e.cursor.line)
        app.cursor_blink_timer = 0
        cursor_moved = true
    }
    if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressedRepeat(.ENTER) {
        if app.completion.open {
            // handled above
        }
        editor_insert_newline(e)
        highlighter_mark_dirty(&app.highlighter, e.cursor.line)
        app.cursor_blink_timer = 0
        cursor_moved = true
    }
    if rl.IsKeyPressed(.TAB) && !ctrl {
        if app.completion.open {
            // handled above
        }
        editor_handle_tab(e, &app.config)
        highlighter_mark_dirty(&app.highlighter, e.cursor.line)
        app.cursor_blink_timer = 0
        cursor_moved = true
    }

    // ── Invoke completion (OLS) ───────────────────────────────────────────────
    if ctrl && rl.IsKeyPressed(.SPACE) {
        if app.ols.initialized {
            _ = ols_request_completion(&app.ols, e)
        }
    }

    // ── Navigation ─────────────────────────────────────────────────────────────
    _sel :: proc(e: ^Editor_State, shift: bool) {
        if shift && !e.selection.active {
            e.selection.active = true
            e.selection.anchor = e.cursor.pos
        } else if !shift {
            e.selection.active = false
        }
    }

    _mv :: proc(app: ^App, e: ^Editor_State, dir: Cursor_Dir, shift: bool) {
        _sel(e, shift)
        editor_move_cursor(e, dir)
        app.cursor_blink_timer = 0
    }

    if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) {
        if ctrl { _mv(app, e, .Word_Left,  shift) } else { _mv(app, e, .Left,  shift) }
        cursor_moved = true
    }
    if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) {
        if ctrl { _mv(app, e, .Word_Right, shift) } else { _mv(app, e, .Right, shift) }
        cursor_moved = true
    }
    if rl.IsKeyPressed(.UP) || rl.IsKeyPressedRepeat(.UP) {
        _mv(app, e, .Up, shift)
        cursor_moved = true
    }
    if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) {
        _mv(app, e, .Down, shift)
        cursor_moved = true
    }
    if rl.IsKeyPressed(.HOME) {
        if ctrl { _mv(app, e, .File_Start, shift) } else { _mv(app, e, .Line_Start, shift) }
        cursor_moved = true
    }
    if rl.IsKeyPressed(.END) {
        if ctrl { _mv(app, e, .File_End, shift) } else { _mv(app, e, .Line_End, shift) }
        cursor_moved = true
    }

    // ── Scroll wheel ────────────────────────────────────────────────────────────
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines := strings.split_lines(content, context.temp_allocator)
    total_h := f32(max(len(lines), 1)) * app.font.line_height
    view_h := app.layout.editor_area.height
    max_scroll := max(f32(0), total_h - view_h)

    if rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area) {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            e.target_scroll_y -= wheel * app.font.line_height * app.config.scroll_speed
            e.target_scroll_y = clamp(e.target_scroll_y, 0, max_scroll)
        }
    }

    // Smooth scroll - reduced interpolation factor to prevent bounce
    smooth_factor := 8.0 * dt  // Reduced from 15.0 for less bounce
    e.scroll_offset.y += (e.target_scroll_y - e.scroll_offset.y) * smooth_factor
    
    // Ensure we never overshoot the target to prevent bounce
    if abs(e.target_scroll_y - e.scroll_offset.y) < 0.1 {
        e.scroll_offset.y = e.target_scroll_y
    }
    
    e.scroll_offset.y = clamp(e.scroll_offset.y, 0, max_scroll)
    e.target_scroll_y = clamp(e.target_scroll_y, 0, max_scroll)

    // Auto-scroll cursor into view only when the cursor changed this frame.
    // Otherwise free scrolling would "bounce" back to the cursor.
    if cursor_moved {
        editor_scroll_to_cursor(e, app.layout.editor_area, &app.font)
        e.target_scroll_y = clamp(e.target_scroll_y, 0, max_scroll)
    }
}

// ─── Mouse handling ───────────────────────────────────────────────────────────

input_handle_mouse :: proc(app: ^App, e: ^Editor_State, shift: bool) -> bool {
    mouse_pos := rl.GetMousePosition()

    // Text X start must MATCH renderer_draw_editor exactly (Phase-2 mock layout):
    //   gutter = diag(14) + linenum(32) + sep(1)
    //   code_x = rect.x + gutter + pad(8)
    diag_w : f32 = 14
    ln_w   : f32 = app.config.show_line_numbers ? 32 : 0
    sep_w  : f32 = 1
    code_pad : f32 = 8
    text_x_off := diag_w + ln_w + sep_w + code_pad

    in_editor := rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area)
    in_tabbar := rl.CheckCollisionPointRec(mouse_pos, app.layout.tab_bar)
    cursor_moved := false

    if rl.IsMouseButtonPressed(.LEFT) {
        if in_tabbar do return false  // tab bar handles its own clicks in tabbar_draw

        if in_editor {
            if app.completion.open { _completion_close(app) }
            rel_x := mouse_pos.x - app.layout.editor_area.x - text_x_off
            rel_y := mouse_pos.y - app.layout.editor_area.y + e.scroll_offset.y

            t_col  := max(0, int((rel_x + app.font.char_width * 0.5) / app.font.char_width))
            t_line := max(0, int(rel_y / app.font.line_height))

            if shift && !e.selection.active {
                e.selection.active = true
                e.selection.anchor = e.cursor.pos
            } else if !shift {
                e.selection.active = false
            }

            editor_set_pos_from_line_col(e, t_line, t_col)
            e.cursor.sticky_col    = e.cursor.col
            app.mouse_selecting    = true
            app.cursor_blink_timer = 0
            cursor_moved = true
        }
    }

    // Drag to extend selection
    if app.mouse_selecting && rl.IsMouseButtonDown(.LEFT) && in_editor {
        if !e.selection.active {
            e.selection.active = true
            e.selection.anchor = e.cursor.pos
        }
        rel_x  := mouse_pos.x - app.layout.editor_area.x - text_x_off
        rel_y  := mouse_pos.y - app.layout.editor_area.y + e.scroll_offset.y
        t_col  := max(0, int((rel_x + app.font.char_width * 0.5) / app.font.char_width))
        t_line := max(0, int(rel_y / app.font.line_height))
        editor_set_pos_from_line_col(e, t_line, t_col)
        cursor_moved = true
    }

    if rl.IsMouseButtonReleased(.LEFT) { app.mouse_selecting = false }
    return cursor_moved
}

// ─── Completion UI helpers (OLS-driven) ───────────────────────────────────────

_completion_close :: proc(app: ^App) {
    app.completion.open = false
    clear(&app.completion.items)
    app.completion.selected = 0
    app.completion.trigger_pos = 0
    app.completion.uri = ""
}

_completion_accept :: proc(app: ^App, e: ^Editor_State) {
    if !app.completion.open || len(app.completion.items) == 0 do return
    idx := clamp(app.completion.selected, 0, len(app.completion.items) - 1)
    ins := app.completion.items[idx].insert

    // Replace from trigger_pos..cursor.pos with insert text.
    start := clamp(app.completion.trigger_pos, 0, e.buffer.length)
    end   := clamp(e.cursor.pos, 0, e.buffer.length)
    if end < start { start, end = end, start }

    if end > start {
        content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
        deleted := content[start:end]
        _push_delete_undo(e, start, deleted, e.cursor.pos, start)
        gap_buffer_delete(&e.buffer, start, end - start)
        e.cursor.pos = start
    }

    before := e.cursor.pos
    gap_buffer_insert(&e.buffer, before, ins)
    e.cursor.pos += len(ins)
    _push_insert_undo(e, before, ins, before, e.cursor.pos)
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
    e.is_modified = true
    e.last_edit_time = rl.GetTime()
    e.lsp_dirty = true
    _completion_close(app)
}

// ─── Tab close helper (used by both Ctrl+W and the tab bar X button) ──────────

_close_tab :: proc(app: ^App, idx: int) {
    if idx < 0 || idx >= len(app.editors) do return

    // Free owned buffer/undo data for the tab being closed.
    closing := app.editors[idx]
    if app.ols.initialized && closing.file_path != "" {
        _ = ols_did_close(&app.ols, &closing)
    }
    delete(closing.buffer.data)
    undo_clear(&closing.undo_stack)

    prev_active := app.active_editor
    ordered_remove(&app.editors, idx)

    if len(app.editors) == 0 {
        app.active_editor = -1
        return
    }

    if idx < prev_active {
        app.active_editor = prev_active - 1
    } else if idx == prev_active {
        app.active_editor = min(idx, len(app.editors) - 1)
    } else {
        app.active_editor = prev_active
    }
}

// ─── File operations ──────────────────────────────────────────────────────────

editor_new_empty :: proc(app: ^App) {
    new_e: Editor_State
    gap_buffer_init(&new_e.buffer, 4096)
    new_e.lsp_version = 0
    new_e.lsp_dirty   = false
    append(&app.editors, new_e)
    app.active_editor = len(app.editors) - 1
    app.highlighter.full_dirty = true
}

editor_open_file :: proc(app: ^App, path: string) {
    for i in 0..<len(app.editors) {
        if app.editors[i].file_path == path {
            app.active_editor = i
            app_push_toast(app, "Switched to open tab")
            return
        }
    }
    bytes, err := os.read_entire_file(path, context.allocator)
    if err != nil do return

    e: Editor_State
    cap := max(len(bytes) * 2, 4096)
    gap_buffer_init(&e.buffer, cap)
    if len(bytes) > 0 {
        gap_buffer_insert(&e.buffer, 0, string(bytes))
    }
    e.file_path = strings.clone(path, context.allocator)
    e.lsp_version = 0
    e.lsp_dirty   = false
    append(&app.editors, e)
    app.active_editor = len(app.editors) - 1
    editor_sync_line_col(&app.editors[app.active_editor])
    app.highlighter.full_dirty = true
    app_push_toast(app, "Opened file")

    if app.ols.initialized {
        _ = ols_did_open(&app.ols, &app.editors[app.active_editor])
    }
}

input_save_file :: proc(app: ^App) {
    if app.active_editor < 0 || app.active_editor >= len(app.editors) do return
    e := &app.editors[app.active_editor]
    save_path := e.file_path
    if save_path == "" {
        save_path = input_pick_file_path(false)
        if save_path == "" {
            app_push_toast(app, "Save canceled")
            return
        }
    }
    content   := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    err       := os.write_entire_file(save_path, transmute([]u8)content)
    if err == nil {
        e.file_path   = save_path
        e.is_modified = false
        app_push_toast(app, "Saved file")
        if app.ols.initialized {
            _ = ols_did_save(&app.ols, e)
        }
    } else {
        app_push_toast(app, "Save failed")
    }
}

input_try_open_dialog :: proc(app: ^App) {
    picked := input_pick_file_path(true)
    if picked == "" {
        app_push_toast(app, "Open canceled")
        return
    }
    editor_open_file(app, picked)
}

input_pick_file_path :: proc(open_mode: bool) -> string {
    path := input_pick_file_path_zenity(open_mode)
    if path != "" do return path
    path = input_pick_file_path_kdialog(open_mode)
    return path
}

input_pick_file_path_zenity :: proc(open_mode: bool) -> string {
    cmd: []string
    if open_mode {
        cmd = []string{
            "zenity", "--file-selection",
            "--title", "Open Odin File",
            "--file-filter", "*.odin",
        }
    } else {
        cmd = []string{
            "zenity", "--file-selection", "--save", "--confirm-overwrite",
            "--title", "Save Odin File",
            "--file-filter", "*.odin",
        }
    }

    state, out, err_out, err := os.process_exec(os.Process_Desc{command = cmd}, context.temp_allocator)
    defer delete(out)
    defer delete(err_out)
    if err != nil || !state.exited || state.exit_code != 0 || len(out) == 0 do return ""

    picked := strings.trim_space(string(out))
    if picked == "" do return ""
    return picked
}

input_pick_file_path_kdialog :: proc(open_mode: bool) -> string {
    cmd := []string{"kdialog", open_mode ? "--getopenfilename" : "--getsavefilename", ".", "*.odin"}
    state, out, err_out, err := os.process_exec(os.Process_Desc{command = cmd}, context.temp_allocator)
    defer delete(out)
    defer delete(err_out)
    if err != nil || !state.exited || state.exit_code != 0 || len(out) == 0 do return ""

    picked := strings.trim_space(string(out))
    if picked == "" do return ""
    return picked
}