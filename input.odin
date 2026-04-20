package main

import "core:os"
import rl "vendor:raylib"

input_update :: proc(app: ^App, dt: f32) {
    if rl.IsKeyDown(.LEFT_CONTROL) {
        if rl.IsKeyPressed(.N) {
            append(&app.editors, Editor_State{})
            app.active_editor = len(app.editors) - 1
            gap_buffer_init(&app.editors[app.active_editor].buffer, 1024)
        }
        if rl.IsKeyPressed(.W) && app.active_editor >= 0 {
            ordered_remove(&app.editors, app.active_editor)
            app.active_editor -= 1
            if app.active_editor < 0 && len(app.editors) > 0 do app.active_editor = 0
        }
        if rl.IsKeyPressed(.B) {
            app.layout.sidebar_visible = !app.layout.sidebar_visible
        }
    }
    
    // Exact Mouse Interaction Logic
    if rl.IsMouseButtonPressed(.LEFT) {
        mouse_pos := rl.GetMousePosition()
        
        // Tab Bar Clicks
        if rl.CheckCollisionPointRec(mouse_pos, app.layout.tab_bar) {
            tab_w: f32 = 180
            
            // Check '+' button
            plus_rect := rl.Rectangle{app.layout.tab_bar.x + f32(len(app.editors)) * tab_w, app.layout.tab_bar.y, 40, app.layout.tab_bar.height}
            if rl.CheckCollisionPointRec(mouse_pos, plus_rect) {
                append(&app.editors, Editor_State{})
                app.active_editor = len(app.editors) - 1
                gap_buffer_init(&app.editors[app.active_editor].buffer, 1024)
            } else {
                clicked_index := int((mouse_pos.x - app.layout.tab_bar.x) / tab_w)
                if clicked_index >= 0 && clicked_index < len(app.editors) {
                    app.active_editor = clicked_index
                }
            }
        }
        
        // Editor Cursor placement
        if rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area) && app.active_editor >= 0 {
            e := &app.editors[app.active_editor]
            gutter_w: f32 = app.font.char_width * 4 + 16
            
            rel_x := mouse_pos.x - app.layout.editor_area.x - gutter_w
            rel_y := mouse_pos.y - app.layout.editor_area.y + e.scroll_offset.y
            
            if rel_x > 0 && rel_y > 0 {
                t_col  := int((rel_x + app.font.char_width * 0.5) / app.font.char_width)
                t_line := int(rel_y / app.font.line_height)
                editor_set_pos_from_line_col(e, t_line, t_col)
                e.cursor.sticky_col = e.cursor.col
            }
        }
    }
    
    // Editor Typing
    if app.active_editor >= 0 {
        e := &app.editors[app.active_editor]
        
        ch := rl.GetCharPressed()
        for ch > 0 {
            editor_insert_char(e, ch)
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
            ch = rl.GetCharPressed()
        }

        if rl.IsKeyPressed(.BACKSPACE) {
            editor_delete_char_backward(e)
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.ENTER) {
            editor_insert_char(e, '\n')
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.TAB) {
            for i in 0..<app.config.tab_size { editor_insert_char(e, ' ') }
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        
        if rl.IsKeyPressed(.LEFT) {
            if e.cursor.pos > 0 do e.cursor.pos -= 1
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.RIGHT) {
            if e.cursor.pos < e.buffer.length do e.cursor.pos += 1
            editor_sync_line_col(e)
            e.cursor.sticky_col = e.cursor.col
        }
        if rl.IsKeyPressed(.UP) && e.cursor.line > 0 {
            editor_set_pos_from_line_col(e, e.cursor.line - 1, e.cursor.sticky_col)
        }
        if rl.IsKeyPressed(.DOWN) {
            editor_set_pos_from_line_col(e, e.cursor.line + 1, e.cursor.sticky_col)
        }
        
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            e.target_scroll_y -= wheel * app.font.line_height * app.config.scroll_speed
            if e.target_scroll_y < 0 do e.target_scroll_y = 0
        }
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
    gap_buffer_insert(&e.buffer, 0, string(bytes))
    e.file_path = path
    append(&app.editors, e)
    app.active_editor = len(app.editors) - 1
    
    app.editors[app.active_editor].cursor.pos = 0
    editor_sync_line_col(&app.editors[app.active_editor])
}