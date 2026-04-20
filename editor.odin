package main

import "core:mem"
import "core:strings"
import rl "vendor:raylib"

Gap_Buffer :: struct {
    data:[]u8,
    gap_pos:  int,
    gap_len:  int,
    length:   int,
}

Cursor :: struct {
    pos:        int,
    line:       int,
    col:        int,
    sticky_col: int,
}

Editor_State :: struct {
    buffer:          Gap_Buffer,
    cursor:          Cursor,
    file_path:       string,
    is_modified:     bool,
    scroll_offset:   rl.Vector2,
    target_scroll_y: f32,
}

gap_buffer_init :: proc(gb: ^Gap_Buffer, initial_capacity: int) {
    gb.data = make([]u8, initial_capacity)
    gb.gap_pos = 0
    gb.gap_len = initial_capacity
    gb.length = 0
}

gap_buffer_move_gap :: proc(gb: ^Gap_Buffer, pos: int) {
    if pos == gb.gap_pos do return
    if pos < gb.gap_pos {
        copy(gb.data[pos + gb.gap_len:], gb.data[pos : gb.gap_pos])
    } else {
        copy(gb.data[gb.gap_pos:], gb.data[gb.gap_pos + gb.gap_len : pos + gb.gap_len])
    }
    gb.gap_pos = pos
}

gap_buffer_insert :: proc(gb: ^Gap_Buffer, pos: int, text: string) {
    if gb.gap_len < len(text) {
        new_cap := (len(gb.data) + len(text)) * 2
        new_data := make([]u8, new_cap)
        copy(new_data[:gb.gap_pos], gb.data[:gb.gap_pos])
        copy(new_data[gb.gap_pos + new_cap - len(gb.data) + gb.gap_len:], gb.data[gb.gap_pos + gb.gap_len:])
        delete(gb.data)
        gb.gap_len += new_cap - len(gb.data)
        gb.data = new_data
    }
    gap_buffer_move_gap(gb, pos)
    copy(gb.data[gb.gap_pos:], text)
    gb.gap_pos += len(text)
    gb.gap_len -= len(text)
    gb.length  += len(text)
}

gap_buffer_delete :: proc(gb: ^Gap_Buffer, pos: int, count: int) {
    gap_buffer_move_gap(gb, pos + count)
    gb.gap_pos -= count
    gb.gap_len += count
    gb.length  -= count
}

gap_buffer_to_string :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator) -> string {
    str := make([]u8, gb.length, allocator)
    copy(str[:gb.gap_pos], gb.data[:gb.gap_pos])
    copy(str[gb.gap_pos:], gb.data[gb.gap_pos + gb.gap_len:])
    return string(str)
}

editor_insert_char :: proc(e: ^Editor_State, r: rune) {
    buf := new([4]u8, context.temp_allocator)
    buf[0] = u8(r)
    s := string(buf[:1])
    gap_buffer_insert(&e.buffer, e.cursor.pos, s)
    e.cursor.pos += len(s)
    e.is_modified = true
}

editor_delete_char_backward :: proc(e: ^Editor_State) {
    if e.cursor.pos > 0 {
        gap_buffer_delete(&e.buffer, e.cursor.pos - 1, 1)
        e.cursor.pos -= 1
        e.is_modified = true
    }
}

// SYNCHRONIZATION LOGIC
editor_sync_line_col :: proc(e: ^Editor_State) {
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    e.cursor.line, e.cursor.col = 0, 0
    for i := 0; i < e.cursor.pos && i < len(content); i += 1 {
        if content[i] == '\n' {
            e.cursor.line += 1
            e.cursor.col = 0
        } else {
            e.cursor.col += 1
        }
    }
}

editor_set_pos_from_line_col :: proc(e: ^Editor_State, target_line, target_col: int) {
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    line, col, pos := 0, 0, 0
    for i := 0; i < len(content); i += 1 {
        if line == target_line && col == target_col { break }
        if content[i] == '\n' {
            if line == target_line { break } // Prevents wrapping to next line if target_col is too high
            line += 1
            col = 0
        } else {
            col += 1
        }
        pos += 1
    }
    e.cursor.pos = pos
    editor_sync_line_col(e)
}