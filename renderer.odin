package main

import "core:fmt"
import rl "vendor:raylib"

renderer_draw_editor :: proc(app: ^App, e: ^Editor_State) {
    rect := app.layout.editor_area
    rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height))
    rl.DrawRectangleRec(rect, app.theme.bg_base)
    
    // Gutter width
    gutter_w: f32 = app.font.char_width * 4 + 16
    
    // Draw string block line by line (Simplification for Phase 1 MVP)
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    
    y: f32 = rect.y - e.scroll_offset.y
    x: f32 = rect.x + gutter_w
    
    line_num := 1
    
    // Active line background placeholder
    rl.DrawRectangleRec({rect.x, y, rect.width, app.font.line_height}, app.theme.bg_active_line)
    
    // Quick parse content
    for ch in content {
        if ch == '\n' {
            // Draw gutter
            gutter_text := fmt.tprintf("%d", line_num)
            gw := rl.MeasureTextEx(app.font.ui, cstring(raw_data(gutter_text)), app.font.font_size, 0).x
            rl.DrawTextEx(app.font.ui, cstring(raw_data(gutter_text)), {rect.x + gutter_w - gw - 8, y}, app.font.font_size, 0, app.theme.text_muted)
            
            y += app.font.line_height
            x = rect.x + gutter_w
            line_num += 1
            continue
        }
        
        buf: [2]u8 = {u8(ch), 0}
        rl.DrawTextEx(app.font.mono, cstring(raw_data(buf[:])), {x, y}, app.font.font_size, 0, app.theme.text_primary)
        x += app.font.char_width
    }
    
    // Cursor Rendering
    // Sub-pixel accuracy via exact char width math
    cx := (rect.x + gutter_w) + (f32(e.cursor.col) * app.font.char_width)
    cy := (rect.y - e.scroll_offset.y) + (f32(e.cursor.line) * app.font.line_height)
    
    blink := i32(rl.GetTime() * 2.0) % 2 == 0
    if blink {
        rl.DrawRectangleRec({cx, cy, 2, app.font.line_height}, app.theme.accent)
    }
    
    rl.EndScissorMode()
    
    // Scrollbar
    sb_rect := rl.Rectangle{rect.x + rect.width - 6, rect.y, 6, rect.height}
    rl.DrawRectangleRec(sb_rect, app.theme.bg_elevated)
    thumb_h := rect.height * 0.2 // placeholder thumb sizing
    rl.DrawRectangleRec({sb_rect.x, rect.y + 10, 6, thumb_h}, app.theme.text_disabled)
}