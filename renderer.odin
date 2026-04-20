package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

renderer_draw_editor :: proc(app: ^App, e: ^Editor_State) {
    rect := app.layout.editor_area
    rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height))
    rl.DrawRectangleRec(rect, app.theme.bg_base)
    
    gutter_w: f32 = app.font.char_width * 4 + 16
    
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines := strings.split(content, "\n", context.temp_allocator)
    
    active_y := (rect.y - e.scroll_offset.y) + (f32(e.cursor.line) * app.font.line_height)
    rl.DrawRectangleRec({rect.x, active_y, rect.width, app.font.line_height}, app.theme.bg_active_line)
    
    y: f32 = rect.y - e.scroll_offset.y
    char_index := 0 // Track absolute position for selection rendering
    
    sel_start, sel_end := 0, 0
    has_sel := editor_has_selection(e)
    if has_sel do sel_start, sel_end = editor_get_selection_range(e)
    
    for line_str, i in lines {
        line_len := len(line_str)
        
        if y + app.font.line_height > rect.y && y < rect.y + rect.height {
            
            // Selection Background Drawing
            if has_sel {
                if sel_start < char_index + line_len + 1 && sel_end > char_index {
                    s_col := max(0, sel_start - char_index)
                    e_col := min(line_len, sel_end - char_index)
                    
                    if e_col >= s_col {
                        sx := rect.x + gutter_w + f32(s_col) * app.font.char_width
                        sw := f32(e_col - s_col) * app.font.char_width
                        // Add extra width to highlight the \n newline character
                        if sel_end > char_index + line_len do sw += app.font.char_width * 0.5 
                        
                        rl.DrawRectangleRec({sx, y, sw, app.font.line_height}, app.theme.bg_highlight)
                    }
                }
            }

            // Gutter
            c_gutter := fmt.ctprintf("%d", i + 1)
            gw := rl.MeasureTextEx(app.font.ui, c_gutter, app.font.font_size, 0).x
            gutter_color := i == e.cursor.line ? app.theme.text_primary : app.theme.text_muted
            rl.DrawTextEx(app.font.ui, c_gutter, {rect.x + gutter_w - gw - 8, y}, app.font.font_size, 0, gutter_color)
            
            // Text
            if line_len > 0 {
                c_str := strings.clone_to_cstring(line_str, context.temp_allocator)
                rl.DrawTextEx(app.font.mono, c_str, {rect.x + gutter_w, y}, app.font.font_size, 0, app.theme.text_primary)
            }
        }
        char_index += line_len + 1 // +1 for the \n
        y += app.font.line_height
    }
    
    // Draw Cursor
    cx := (rect.x + gutter_w) + (f32(e.cursor.col) * app.font.char_width)
    cy := (rect.y - e.scroll_offset.y) + (f32(e.cursor.line) * app.font.line_height)
    
    blink := i32(rl.GetTime() * 2.0) % 2 == 0
    if blink || rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.UP) || rl.IsKeyDown(.DOWN) {
        rl.DrawRectangleRec({cx, cy, 2, app.font.line_height}, app.theme.accent)
    }
    
    rl.EndScissorMode()
    
    // Scrollbar
    sb_rect := rl.Rectangle{rect.x + rect.width - 6, rect.y, 6, rect.height}
    rl.DrawRectangleRec(sb_rect, app.theme.bg_elevated)
    
    if len(lines) > 0 {
        visible_ratio := rect.height / (f32(len(lines)) * app.font.line_height)
        if visible_ratio > 1.0 do visible_ratio = 1.0
        thumb_h := rect.height * visible_ratio
        if thumb_h < 20 do thumb_h = 20
        
        max_scroll := (f32(len(lines)) * app.font.line_height) - rect.height
        if max_scroll < 0 do max_scroll = 0
        
        scroll_ratio: f32 = 0
        if max_scroll > 0 do scroll_ratio = e.scroll_offset.y / max_scroll
        
        thumb_y := rect.y + scroll_ratio * (rect.height - thumb_h)
        rl.DrawRectangleRec({sb_rect.x, thumb_y, 6, thumb_h}, app.theme.text_disabled)
    }
}