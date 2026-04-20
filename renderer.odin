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
    
    // Draw Active Line Background Full Width
    active_y := (rect.y - e.scroll_offset.y) + (f32(e.cursor.line) * app.font.line_height)
    rl.DrawRectangleRec({rect.x, active_y, rect.width, app.font.line_height}, app.theme.bg_active_line)
    
    y: f32 = rect.y - e.scroll_offset.y
    
    for line_str, i in lines {
        // Only draw visible lines to save performance
        if y + app.font.line_height > rect.y && y < rect.y + rect.height {
            
            // Gutter
            gutter_text := fmt.tprintf("%d", i + 1)
            gw := rl.MeasureTextEx(app.font.ui, cstring(raw_data(gutter_text)), app.font.font_size, 0).x
            gutter_color := i == e.cursor.line ? app.theme.text_primary : app.theme.text_muted
            rl.DrawTextEx(app.font.ui, cstring(raw_data(gutter_text)), {rect.x + gutter_w - gw - 8, y}, app.font.font_size, 0, gutter_color)
            
            // Text
            if len(line_str) > 0 {
                rl.DrawTextEx(app.font.mono, cstring(raw_data(line_str)), {rect.x + gutter_w, y}, app.font.font_size, 0, app.theme.text_primary)
            }
        }
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
    thumb_h := rect.height * 0.2
    rl.DrawRectangleRec({sb_rect.x, rect.y + 10, 6, thumb_h}, app.theme.text_disabled)
}