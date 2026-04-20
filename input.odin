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

    // ── Editor interaction (only when an editor is active) ────────────────────
    if app.active_editor < 0 || app.active_editor >= len(app.editors) do return
    e := &app.editors[app.active_editor]

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
        }
        if rl.IsKeyPressed(.V) {
            c_text := rl.GetClipboardText()
            if c_text != nil {
                text := string(c_text)
                editor_snapshot_undo(e)
                editor_delete_selection(e)
                gap_buffer_insert(&e.buffer, e.cursor.pos, text)
                e.cursor.pos += len(text)
                editor_sync_line_col(e)
                e.is_modified = true
                app.cursor_blink_timer = 0
            }
        }
        if rl.IsKeyPressed(.A) {
            e.selection.active = true
            e.selection.anchor = 0
            e.cursor.pos       = e.buffer.length
            editor_sync_line_col(e)
            app.cursor_blink_timer = 0
        }
        if rl.IsKeyPressed(.Z) {
            editor_undo(e)
            app.cursor_blink_timer = 0
        }
    }

    // ── Mouse interaction ──────────────────────────────────────────────────────
    input_handle_mouse(app, e, shift)

    // ── Character input (non-ctrl)  ── DO NOT move GetCharPressed above ───────
    if !ctrl {
        ch := rl.GetCharPressed()
        for ch > 0 {
            editor_insert_char(e, ch)
            editor_sync_line_col(e)
            e.cursor.sticky_col    = e.cursor.col
            app.cursor_blink_timer = 0  // reset blink on every char typed
            ch = rl.GetCharPressed()
        }
    }

    // ── Structural keys ────────────────────────────────────────────────────────
    if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
        editor_delete_char_backward(e)
        editor_sync_line_col(e)
        app.cursor_blink_timer = 0
    }
    if rl.IsKeyPressed(.DELETE) || rl.IsKeyPressedRepeat(.DELETE) {
        editor_delete_char_forward(e)
        editor_sync_line_col(e)
        app.cursor_blink_timer = 0
    }
    if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressedRepeat(.ENTER) {
        editor_insert_newline(e)
        app.cursor_blink_timer = 0
    }
    if rl.IsKeyPressed(.TAB) && !ctrl {
        editor_handle_tab(e, &app.config)
        app.cursor_blink_timer = 0
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
    }
    if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) {
        if ctrl { _mv(app, e, .Word_Right, shift) } else { _mv(app, e, .Right, shift) }
    }
    if rl.IsKeyPressed(.UP) || rl.IsKeyPressedRepeat(.UP) {
        _mv(app, e, .Up, shift)
    }
    if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) {
        _mv(app, e, .Down, shift)
    }
    if rl.IsKeyPressed(.HOME) {
        if ctrl { _mv(app, e, .File_Start, shift) } else { _mv(app, e, .Line_Start, shift) }
    }
    if rl.IsKeyPressed(.END) {
        if ctrl { _mv(app, e, .File_End, shift) } else { _mv(app, e, .Line_End, shift) }
    }

    // ── Scroll wheel ────────────────────────────────────────────────────────────
    if rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area) {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            e.target_scroll_y -= wheel * app.font.line_height * app.config.scroll_speed
            if e.target_scroll_y < 0 do e.target_scroll_y = 0
        }
    }

    // Smooth scroll
    e.scroll_offset.y += (e.target_scroll_y - e.scroll_offset.y) * 15.0 * dt

    // Auto-scroll cursor into view after movement
    editor_scroll_to_cursor(e, app.layout.editor_area, &app.font)
}

// ─── Mouse handling ───────────────────────────────────────────────────────────

input_handle_mouse :: proc(app: ^App, e: ^Editor_State, shift: bool) {
    mouse_pos := rl.GetMousePosition()

    // Text X start must MATCH renderer_draw_editor exactly:
    //   gutter_w = digits * char_width + 28
    //   text_x   = rect.x + gutter_w + 4  (same +4 offset as renderer)
    digit_count := count_digits(max(1, gap_buffer_line_count(&e.buffer)))
    gutter_w    := f32(digit_count) * app.font.char_width + 28
    text_x_off  := gutter_w + 4   // == renderer's "rect.x + gutter_w + 4"

    in_editor := rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area)
    in_tabbar := rl.CheckCollisionPointRec(mouse_pos, app.layout.tab_bar)

    if rl.IsMouseButtonPressed(.LEFT) {
        if in_tabbar do return  // tab bar handles its own clicks in tabbar_draw

        if in_editor {
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
    }

    if rl.IsMouseButtonReleased(.LEFT) { app.mouse_selecting = false }
}

// ─── Tab close helper (used by both Ctrl+W and the tab bar X button) ──────────

_close_tab :: proc(app: ^App, idx: int) {
    if idx < 0 || idx >= len(app.editors) do return

    // Free owned buffer/undo data for the tab being closed.
    closing := app.editors[idx]
    delete(closing.buffer.data)
    if closing.has_undo { delete(closing.undo_entry.content) }

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
    append(&app.editors, new_e)
    app.active_editor = len(app.editors) - 1
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
    append(&app.editors, e)
    app.active_editor = len(app.editors) - 1
    editor_sync_line_col(&app.editors[app.active_editor])
    app_push_toast(app, "Opened file")
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