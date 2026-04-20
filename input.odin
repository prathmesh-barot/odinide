package main

import "core:os"
import "core:strings"
import rl "vendor:raylib"

input_update :: proc(app: ^App, dt: f32) {
    ctrl  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    shift := rl.IsKeyDown(.LEFT_SHIFT)   || rl.IsKeyDown(.RIGHT_SHIFT)

    // DRAG AND DROP FILE OPENING (Universal standard fallback for Phase 1)
    if rl.IsFileDropped() {
        fps := rl.LoadDroppedFiles()
        if fps.count > 0 {
            editor_open_file(app, string(fps.paths[0]))
        }
        rl.UnloadDroppedFiles(fps)
    }

    // Window / Global Settings
    if ctrl && rl.IsKeyPressed(.Q) do app.should_quit = true
    if ctrl && rl.IsKeyPressed(.B) do app.layout.sidebar_visible = !app.layout.sidebar_visible

    // Sidebar Resizing Logic
    mouse_pos := rl.GetMousePosition()
    handle_x := app.layout.sidebar_visible ? (app.layout.activity_bar.width + app.layout.sidebar.width) : app.layout.activity_bar.width
    handle_rect := rl.Rectangle{handle_x - 2, 0, 4, f32(app.window_height)}

    if rl.CheckCollisionPointRec(mouse_pos, handle_rect) {
        rl.SetMouseCursor(.RESIZE_EW)
        if rl.IsMouseButtonPressed(.LEFT) do app.layout.sidebar_dragging = true
    } else if !app.layout.sidebar_dragging {
        rl.SetMouseCursor(.DEFAULT)
    }

    if app.layout.sidebar_dragging {
        rl.SetMouseCursor(.RESIZE_EW)
        app.layout.sidebar_width = mouse_pos.x - app.layout.activity_bar.width
        if app.layout.sidebar_width < 100 do app.layout.sidebar_width = 100
        if !rl.IsMouseButtonDown(.LEFT) do app.layout.sidebar_dragging = false
        layout_recalculate(&app.layout, f32(app.window_width), f32(app.window_height))
    }

    // Tabs / Files
    if ctrl {
        if rl.IsKeyPressed(.N) {
            new_e: Editor_State
            gap_buffer_init(&new_e.buffer, 1024)
            append(&app.editors, new_e)
            app.active_editor = len(app.editors) - 1
        }
        if rl.IsKeyPressed(.W) && app.active_editor >= 0 {
            ordered_remove(&app.editors, app.active_editor)
            app.active_editor -= 1
            if app.active_editor < 0 && len(app.editors) > 0 do app.active_editor = 0
        }
        
        // Save File (Fixed for dev-2026-04 Error return)
        if rl.IsKeyPressed(.S) && app.active_editor >= 0 {
            e := &app.editors[app.active_editor]
            save_path := e.file_path != "" ? e.file_path : "untitled.odin"
            content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
            
            err := os.write_entire_file(save_path, transmute([]u8)content)
            if err == nil {
                e.file_path = save_path
                e.is_modified = false
            }
        }
        
        // Next/Prev Tab
        if rl.IsKeyPressed(.TAB) && len(app.editors) > 1 {
            if shift {
                app.active_editor -= 1
                if app.active_editor < 0 do app.active_editor = len(app.editors) - 1
            } else {
                app.active_editor = (app.active_editor + 1) % len(app.editors)
            }
        }
    }
    
    // Editor Interaction
    if app.active_editor >= 0 {
        e := &app.editors[app.active_editor]
        
        // --- CLIPBOARD ---
        if ctrl && rl.IsKeyPressed(.C) && editor_has_selection(e) {
            text := editor_get_selection_text(e, context.temp_allocator)
            c_text := strings.clone_to_cstring(text, context.temp_allocator)
            rl.SetClipboardText(c_text)
        }
        if ctrl && rl.IsKeyPressed(.X) && editor_has_selection(e) {
            text := editor_get_selection_text(e, context.temp_allocator)
            c_text := strings.clone_to_cstring(text, context.temp_allocator)
            rl.SetClipboardText(c_text)
            editor_delete_selection(e)
        }
        if ctrl && rl.IsKeyPressed(.V) {
            c_text := rl.GetClipboardText()
            if c_text != nil {
                editor_delete_selection(e)
                text := string(c_text)
                gap_buffer_insert(&e.buffer, e.cursor.pos, text)
                e.cursor.pos += len(text)
                editor_sync_line_col(e)
                e.is_modified = true
            }
        }
        if ctrl && rl.IsKeyPressed(.A) {
            e.selection.active = true
            e.selection.anchor = 0
            e.cursor.pos = e.buffer.length
            editor_sync_line_col(e)
        }

        // Mouse Clicks
        if rl.IsMouseButtonPressed(.LEFT) {
            mouse_pos := rl.GetMousePosition()
            
            // Tab Clicking
            if rl.CheckCollisionPointRec(mouse_pos, app.layout.tab_bar) {
                tab_w: f32 = 180
                plus_rect := rl.Rectangle{app.layout.tab_bar.x + f32(len(app.editors)) * tab_w, app.layout.tab_bar.y, 40, app.layout.tab_bar.height}
                if rl.CheckCollisionPointRec(mouse_pos, plus_rect) {
                    new_e: Editor_State
                    gap_buffer_init(&new_e.buffer, 1024)
                    append(&app.editors, new_e)
                    app.active_editor = len(app.editors) - 1
                } else {
                    clicked_index := int((mouse_pos.x - app.layout.tab_bar.x) / tab_w)
                    if clicked_index >= 0 && clicked_index < len(app.editors) {
                        app.active_editor = clicked_index
                    }
                }
            }
            
            // Editor Area Clicking
            if rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area) {
                gutter_w: f32 = app.font.char_width * 4 + 16
                rel_x := mouse_pos.x - app.layout.editor_area.x - gutter_w
                rel_y := mouse_pos.y - app.layout.editor_area.y + e.scroll_offset.y
                
                if rel_x > 0 && rel_y > 0 {
                    t_col  := int((rel_x + app.font.char_width * 0.5) / app.font.char_width)
                    t_line := int(rel_y / app.font.line_height)
                    
                    if shift && !e.selection.active {
                        e.selection.active = true
                        e.selection.anchor = e.cursor.pos
                    } else if !shift {
                        e.selection.active = false
                    }
                    
                    editor_set_pos_from_line_col(e, t_line, t_col)
                    e.cursor.sticky_col = e.cursor.col
                }
            }
        }
        
        // Typing
        if !ctrl {
            ch := rl.GetCharPressed()
            for ch > 0 {
                editor_insert_char(e, ch)
                editor_sync_line_col(e)
                e.cursor.sticky_col = e.cursor.col
                ch = rl.GetCharPressed()
            }
        }

        if rl.IsKeyPressed(.BACKSPACE) {
            editor_delete_char_backward(e)
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        
        if rl.IsKeyPressed(.DELETE) {
            editor_delete_char_forward(e)
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        
        // Enter & Auto-Indent
        if rl.IsKeyPressed(.ENTER) {
            editor_delete_selection(e)
            
            content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
            line_start := e.cursor.pos
            for line_start > 0 && content[line_start-1] != '\n' { line_start -= 1 }
            spaces := 0
            for i := line_start; i < e.cursor.pos && content[i] == ' '; i += 1 { spaces += 1 }

            editor_insert_char(e, '\n')
            for i in 0..<spaces { editor_insert_char(e, ' ') }
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        
        if rl.IsKeyPressed(.TAB) && !ctrl {
            for i in 0..<app.config.tab_size { editor_insert_char(e, ' ') }
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        
        // --- NAVIGATION & SELECTION ---
        handle_selection :: proc(e: ^Editor_State, shift: bool) {
            if shift && !e.selection.active {
                e.selection.active = true
                e.selection.anchor = e.cursor.pos
            } else if !shift && e.selection.active {
                e.selection.active = false
            }
        }

        if rl.IsKeyPressed(.LEFT) {
            handle_selection(e, shift)
            if e.cursor.pos > 0 do e.cursor.pos -= 1
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.RIGHT) {
            handle_selection(e, shift)
            if e.cursor.pos < e.buffer.length do e.cursor.pos += 1
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.UP) && e.cursor.line > 0 {
            handle_selection(e, shift)
            editor_set_pos_from_line_col(e, e.cursor.line - 1, e.cursor.sticky_col)
        }
        if rl.IsKeyPressed(.DOWN) {
            handle_selection(e, shift)
            editor_set_pos_from_line_col(e, e.cursor.line + 1, e.cursor.sticky_col)
        }
        if rl.IsKeyPressed(.HOME) {
            handle_selection(e, shift)
            editor_set_pos_from_line_col(e, e.cursor.line, 0)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.END) {
            handle_selection(e, shift)
            editor_set_pos_from_line_col(e, e.cursor.line, 999999)
            e.cursor.sticky_col = e.cursor.col
        }
        
        // Scroll Wheel (Smooth logic)
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            e.target_scroll_y -= wheel * app.font.line_height * app.config.scroll_speed
            if e.target_scroll_y < 0 do e.target_scroll_y = 0
        }
        
        // Apply smooth scroll
        e.scroll_offset.y += (e.target_scroll_y - e.scroll_offset.y) * 15.0 * dt
    }
}

editor_open_file :: proc(app: ^App, path: string) {
    for i in 0..<len(app.editors) {
        if app.editors[i].file_path == path {
            app.active_editor = i
            return
        }
    }
    bytes, err := os.read_entire_file(path, context.allocator)
    if err != nil do return
    
    e: Editor_State
    gap_buffer_init(&e.buffer, len(bytes) * 2)
    if len(bytes) > 0 {
        gap_buffer_insert(&e.buffer, 0, string(bytes))
    }
    e.file_path = path
    append(&app.editors, e)
    app.active_editor = len(app.editors) - 1
    
    app.editors[app.active_editor].cursor.pos = 0
    editor_sync_line_col(&app.editors[app.active_editor])
}