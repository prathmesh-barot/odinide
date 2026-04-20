package main

import "core:os"
import rl "vendor:raylib"

input_update :: proc(app: ^App, dt: f32) {
    // Global Keyboard Shortcuts
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
        if rl.IsKeyPressed(.S) && app.active_editor >= 0 {
            e := &app.editors[app.active_editor]
            if e.file_path != "" {
                content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
                _ = os.write_entire_file(e.file_path, transmute([]u8)content)
                e.is_modified = false
            }
        }
    }
    
    // Mouse Interaction
    if rl.IsMouseButtonPressed(.LEFT) {
        mouse_pos := rl.GetMousePosition()
        
        // 1. Click on Tab Bar to switch tabs
        if rl.CheckCollisionPointRec(mouse_pos, app.layout.tab_bar) {
            tab_w: f32 = 180
            clicked_index := int((mouse_pos.x - app.layout.tab_bar.x) / tab_w)
            if clicked_index >= 0 && clicked_index < len(app.editors) {
                app.active_editor = clicked_index
            }
        }
        
        // 2. Click in Editor Area to place Cursor
        if rl.CheckCollisionPointRec(mouse_pos, app.layout.editor_area) && app.active_editor >= 0 {
            e := &app.editors[app.active_editor]
            gutter_w: f32 = app.font.char_width * 4 + 16
            
            rel_x := mouse_pos.x - app.layout.editor_area.x - gutter_w
            rel_y := mouse_pos.y - app.layout.editor_area.y + e.scroll_offset.y
            
            if rel_x < 0 do rel_x = 0
            if rel_y < 0 do rel_y = 0
            
            e.cursor.col  = int((rel_x + app.font.char_width * 0.5) / app.font.char_width)
            e.cursor.line = int(rel_y / app.font.line_height)
        }
    }
    
    // Editor Typing & Cursor Movement
    if app.active_editor >= 0 {
        e := &app.editors[app.active_editor]
        
        ch := rl.GetCharPressed()
        for ch > 0 {
            editor_insert_char(e, ch)
            e.cursor.col += 1
            ch = rl.GetCharPressed()
        }

        if rl.IsKeyPressed(.BACKSPACE) {
            editor_delete_char_backward(e)
            if e.cursor.col > 0 do e.cursor.col -= 1
        }
        if rl.IsKeyPressed(.ENTER) {
            editor_insert_char(e, '\n')
            e.cursor.line += 1
            e.cursor.col = 0
        }
        if rl.IsKeyPressed(.TAB) {
            for i in 0..<app.config.tab_size { editor_insert_char(e, ' ') }
            e.cursor.col += app.config.tab_size
        }
        
        // Arrow Keys Navigation
        if rl.IsKeyPressed(.LEFT)  && e.cursor.col > 0  do e.cursor.col -= 1
        if rl.IsKeyPressed(.RIGHT)                      do e.cursor.col += 1
        if rl.IsKeyPressed(.UP)    && e.cursor.line > 0 do e.cursor.line -= 1
        if rl.IsKeyPressed(.DOWN)                       do e.cursor.line += 1
        
        // Scroll Wheel
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            e.target_scroll_y -= wheel * app.font.line_height * app.config.scroll_speed
            if e.target_scroll_y < 0 do e.target_scroll_y = 0
        }
    }
}

editor_open_file :: proc(app: ^App, path: string) {
    // Prevent opening duplicates: check if file is already open
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
}