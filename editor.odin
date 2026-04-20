package main

import "core:mem"
import "core:strings"
import rl "vendor:raylib"

Gap_Buffer :: struct {
    data:     []u8,
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

Selection :: struct {
    active: bool,
    anchor: int,
    head:   int,
}

Editor_State :: struct {
    buffer:          Gap_Buffer,
    cursor:          Cursor,
    selection:       Selection,
    file_path:       string,
    is_modified:     bool,
    scroll_offset:   rl.Vector2,
    target_scroll_y: f32,
    top_line:        int,
    view_lines:      int,
}

Cursor_Dir :: enum { Left, Right, Up, Down, Line_Start, Line_End, File_Start, File_End }

gap_buffer_init :: proc(gb: ^Gap_Buffer, initial_capacity: int) {
    gb.data = make([]u8, initial_capacity)
    gb.gap_pos = 0
    gb.gap_len = initial_capacity
    gb.length = 0
}

gap_buffer_move_gap :: proc(gb: ^Gap_Buffer, pos: int) {
    if pos == gb.gap_pos do return
    if pos < gb.gap_pos {
        size := gb.gap_pos - pos
        copy(gb.data[pos + gb.gap_len:], gb.data[pos : gb.gap_pos])
    } else {
        size := pos - gb.gap_pos
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
    s := utf8_encode_rune(r)
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

utf8_encode_rune :: proc(r: rune) -> string {
    buf := new([4]u8, context.temp_allocator)
    buf[0] = u8(r)
    return string(buf[:1])
}