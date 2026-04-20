package main

import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// ─── Gap Buffer ───────────────────────────────────────────────────────────────

Gap_Buffer :: struct {
    data:     []u8,
    gap_pos:  int,
    gap_len:  int,
    length:   int, // total logical byte count
}

gap_buffer_init :: proc(gb: ^Gap_Buffer, initial_capacity: int) {
    cap := max(initial_capacity, 64)
    gb.data    = make([]u8, cap)
    gb.gap_pos = 0
    gb.gap_len = cap
    gb.length  = 0
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

gap_buffer_grow :: proc(gb: ^Gap_Buffer, needed: int) {
    new_cap := (len(gb.data) + needed) * 2
    new_data := make([]u8, new_cap)
    // copy pre-gap
    copy(new_data[:gb.gap_pos], gb.data[:gb.gap_pos])
    // copy post-gap shifted to end
    old_post_start := gb.gap_pos + gb.gap_len
    new_gap_len    := new_cap - gb.length
    new_post_start := gb.gap_pos + new_gap_len
    copy(new_data[new_post_start:], gb.data[old_post_start:])
    delete(gb.data)
    gb.data    = new_data
    gb.gap_len = new_gap_len
}

gap_buffer_insert :: proc(gb: ^Gap_Buffer, pos: int, text: string) {
    if len(text) == 0 do return
    if gb.gap_len < len(text) {
        gap_buffer_grow(gb, len(text))
    }
    gap_buffer_move_gap(gb, pos)
    copy(gb.data[gb.gap_pos:], text)
    gb.gap_pos += len(text)
    gb.gap_len -= len(text)
    gb.length  += len(text)
}

gap_buffer_delete :: proc(gb: ^Gap_Buffer, pos: int, count: int) {
    if count <= 0 || pos < 0 do return
    actual := min(count, gb.length - pos)
    if actual <= 0 do return
    gap_buffer_move_gap(gb, pos)
    gb.gap_len += actual
    gb.length  -= actual
}

gap_buffer_to_string :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator) -> string {
    if gb.length == 0 do return ""
    str := make([]u8, gb.length, allocator)
    copy(str[:gb.gap_pos], gb.data[:gb.gap_pos])
    post := gb.gap_pos + gb.gap_len
    copy(str[gb.gap_pos:], gb.data[post:])
    return string(str)
}

gap_buffer_byte_at :: proc(gb: ^Gap_Buffer, pos: int) -> u8 {
    if pos < 0 || pos >= gb.length do return 0
    if pos < gb.gap_pos do return gb.data[pos]
    return gb.data[pos + gb.gap_len]
}

gap_buffer_char_at :: proc(gb: ^Gap_Buffer, pos: int) -> rune {
    b := gap_buffer_byte_at(gb, pos)
    return rune(b)
}

gap_buffer_line_count :: proc(gb: ^Gap_Buffer) -> int {
    lines := 1
    for i := 0; i < gb.length; i += 1 {
        if gap_buffer_byte_at(gb, i) == '\n' do lines += 1
    }
    return lines
}

gap_buffer_line_start :: proc(gb: ^Gap_Buffer, line: int) -> int {
    if line == 0 do return 0
    current_line := 0
    for i := 0; i < gb.length; i += 1 {
        if gap_buffer_byte_at(gb, i) == '\n' {
            current_line += 1
            if current_line == line do return i + 1
        }
    }
    return gb.length
}

gap_buffer_line_end :: proc(gb: ^Gap_Buffer, line_start: int) -> int {
    i := line_start
    for i < gb.length && gap_buffer_byte_at(gb, i) != '\n' {
        i += 1
    }
    return i
}

// Count digits in a positive integer (for gutter width)
count_digits :: proc(n: int) -> int {
    if n <= 0 do return 1
    d := 0
    v := n
    for v > 0 {
        d += 1
        v /= 10
    }
    return d
}

// ─── Cursor & Selection ────────────────────────────────────────────────────────

Cursor :: struct {
    pos:        int,
    line:       int,
    col:        int,
    sticky_col: int,
}

Selection :: struct {
    active: bool,
    anchor: int,
    head:   int, // same as cursor.pos when active
}

Cursor_Dir :: enum {
    Left,
    Right,
    Up,
    Down,
    Line_Start,
    Line_End,
    File_Start,
    File_End,
    Word_Left,
    Word_Right,
}

// ─── Undo ─────────────────────────────────────────────────────────────────────

Undo_Entry :: struct {
    content:    string,   // full buffer snapshot (simple single-level undo)
    cursor_pos: int,
}

// ─── Editor State ─────────────────────────────────────────────────────────────

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

    // Single-level undo
    undo_entry:      Undo_Entry,
    has_undo:        bool,
}

// ─── Editor Helpers ───────────────────────────────────────────────────────────

editor_has_selection :: proc(e: ^Editor_State) -> bool {
    return e.selection.active && e.selection.anchor != e.cursor.pos
}

editor_get_selection_range :: proc(e: ^Editor_State) -> (int, int) {
    start := min(e.selection.anchor, e.cursor.pos)
    end   := max(e.selection.anchor, e.cursor.pos)
    return start, end
}

editor_delete_selection :: proc(e: ^Editor_State) {
    if !editor_has_selection(e) do return
    start, end := editor_get_selection_range(e)
    gap_buffer_delete(&e.buffer, start, end - start)
    e.cursor.pos       = start
    e.selection.active = false
    e.is_modified      = true
    editor_sync_line_col(e)
}

editor_get_selection_text :: proc(e: ^Editor_State, allocator: mem.Allocator) -> string {
    if !editor_has_selection(e) do return ""
    start, end := editor_get_selection_range(e)
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    return strings.clone(content[start:end], allocator)
}

// Snapshot current state into undo buffer before a modification
editor_snapshot_undo :: proc(e: ^Editor_State) {
    if e.has_undo {
        delete(e.undo_entry.content)
    }
    e.undo_entry.content    = gap_buffer_to_string(&e.buffer, context.allocator)
    e.undo_entry.cursor_pos = e.cursor.pos
    e.has_undo = true
}

editor_undo :: proc(e: ^Editor_State) {
    if !e.has_undo do return
    content := e.undo_entry.content
    saved_pos := e.undo_entry.cursor_pos

    // Rebuild the buffer
    delete(e.buffer.data)
    cap := max(len(content) * 2, 1024)
    gap_buffer_init(&e.buffer, cap)
    if len(content) > 0 {
        gap_buffer_insert(&e.buffer, 0, content)
    }
    e.cursor.pos = clamp(saved_pos, 0, e.buffer.length)
    e.is_modified = true
    e.has_undo = false
    editor_sync_line_col(e)
}

// ─── Text Operations ──────────────────────────────────────────────────────────

editor_insert_char :: proc(e: ^Editor_State, r: rune) {
    editor_snapshot_undo(e)
    editor_delete_selection(e)
    // dev-2026-04: encode_rune(rune) -> ([4]u8, int)
    buf, n := utf8.encode_rune(r)
    s := string(buf[:n])
    gap_buffer_insert(&e.buffer, e.cursor.pos, s)
    e.cursor.pos += n
    e.is_modified = true
}

editor_insert_newline :: proc(e: ^Editor_State) {
    editor_snapshot_undo(e)
    editor_delete_selection(e)

    // Carry indentation from current line
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    line_start := e.cursor.pos
    for line_start > 0 && content[line_start-1] != '\n' { line_start -= 1 }
    spaces := 0
    for i := line_start; i < e.cursor.pos && content[i] == ' '; i += 1 { spaces += 1 }

    gap_buffer_insert(&e.buffer, e.cursor.pos, "\n")
    e.cursor.pos += 1
    for i in 0..<spaces {
        gap_buffer_insert(&e.buffer, e.cursor.pos, " ")
        e.cursor.pos += 1
    }
    e.is_modified = true
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
}

editor_handle_tab :: proc(e: ^Editor_State, config: ^Config) {
    editor_snapshot_undo(e)
    editor_delete_selection(e)
    spaces := config.tab_size
    for i in 0..<spaces {
        gap_buffer_insert(&e.buffer, e.cursor.pos, " ")
        e.cursor.pos += 1
    }
    e.is_modified = true
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
}

editor_delete_char_backward :: proc(e: ^Editor_State) {
    if editor_has_selection(e) {
        editor_snapshot_undo(e)
        editor_delete_selection(e)
        return
    }
    if e.cursor.pos > 0 {
        editor_snapshot_undo(e)
        gap_buffer_delete(&e.buffer, e.cursor.pos - 1, 1)
        e.cursor.pos -= 1
        e.is_modified = true
        editor_sync_line_col(e)
        e.cursor.sticky_col = e.cursor.col
    }
}

editor_delete_char_forward :: proc(e: ^Editor_State) {
    if editor_has_selection(e) {
        editor_snapshot_undo(e)
        editor_delete_selection(e)
        return
    }
    if e.cursor.pos < e.buffer.length {
        editor_snapshot_undo(e)
        gap_buffer_delete(&e.buffer, e.cursor.pos, 1)
        e.is_modified = true
    }
}

// ─── Sync line/col from cursor.pos ────────────────────────────────────────────

editor_sync_line_col :: proc(e: ^Editor_State) {
    e.cursor.line, e.cursor.col = 0, 0
    for i := 0; i < e.cursor.pos && i < e.buffer.length; i += 1 {
        b := gap_buffer_byte_at(&e.buffer, i)
        if b == '\n' {
            e.cursor.line += 1
            e.cursor.col   = 0
        } else {
            e.cursor.col += 1
        }
    }
}

editor_set_pos_from_line_col :: proc(e: ^Editor_State, target_line, target_col: int) {
    line_start := gap_buffer_line_start(&e.buffer, target_line)
    line_end   := gap_buffer_line_end(&e.buffer, line_start)
    line_len   := line_end - line_start
    col        := min(target_col, line_len)
    e.cursor.pos = line_start + col
    editor_sync_line_col(e)
}

// ─── Cursor movement ──────────────────────────────────────────────────────────

_is_word_char :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') ||
           (b >= 'A' && b <= 'Z') ||
           (b >= '0' && b <= '9') ||
           b == '_'
}

editor_move_cursor :: proc(e: ^Editor_State, dir: Cursor_Dir) {
    switch dir {
    case .Left:
        if e.cursor.pos > 0 { e.cursor.pos -= 1 }
        editor_sync_line_col(e)
        e.cursor.sticky_col = e.cursor.col
    case .Right:
        if e.cursor.pos < e.buffer.length { e.cursor.pos += 1 }
        editor_sync_line_col(e)
        e.cursor.sticky_col = e.cursor.col
    case .Up:
        if e.cursor.line > 0 {
            editor_set_pos_from_line_col(e, e.cursor.line - 1, e.cursor.sticky_col)
        }
    case .Down:
        total := gap_buffer_line_count(&e.buffer)
        if e.cursor.line < total - 1 {
            editor_set_pos_from_line_col(e, e.cursor.line + 1, e.cursor.sticky_col)
        }
    case .Line_Start:
        editor_set_pos_from_line_col(e, e.cursor.line, 0)
        e.cursor.sticky_col = 0
    case .Line_End:
        editor_set_pos_from_line_col(e, e.cursor.line, 999999)
        e.cursor.sticky_col = e.cursor.col
    case .File_Start:
        e.cursor.pos = 0
        editor_sync_line_col(e)
        e.cursor.sticky_col = 0
    case .File_End:
        e.cursor.pos = e.buffer.length
        editor_sync_line_col(e)
        e.cursor.sticky_col = e.cursor.col
    case .Word_Left:
        pos := e.cursor.pos
        // skip non-word chars backward
        for pos > 0 && !_is_word_char(gap_buffer_byte_at(&e.buffer, pos - 1)) { pos -= 1 }
        // skip word chars backward
        for pos > 0 && _is_word_char(gap_buffer_byte_at(&e.buffer, pos - 1)) { pos -= 1 }
        e.cursor.pos = pos
        editor_sync_line_col(e)
        e.cursor.sticky_col = e.cursor.col
    case .Word_Right:
        pos := e.cursor.pos
        // skip non-word chars forward
        for pos < e.buffer.length && !_is_word_char(gap_buffer_byte_at(&e.buffer, pos)) { pos += 1 }
        // skip word chars forward
        for pos < e.buffer.length && _is_word_char(gap_buffer_byte_at(&e.buffer, pos)) { pos += 1 }
        e.cursor.pos = pos
        editor_sync_line_col(e)
        e.cursor.sticky_col = e.cursor.col
    }
}

// ─── Scroll-to-cursor ─────────────────────────────────────────────────────────

editor_scroll_to_cursor :: proc(e: ^Editor_State, rect: rl.Rectangle, font: ^Font_State) {
    cursor_y := f32(e.cursor.line) * font.line_height
    view_top    := e.target_scroll_y
    view_bottom := e.target_scroll_y + rect.height - font.line_height * 2

    if cursor_y < view_top {
        e.target_scroll_y = cursor_y - font.line_height
    } else if cursor_y > view_bottom {
        e.target_scroll_y = cursor_y - rect.height + font.line_height * 3
    }
    if e.target_scroll_y < 0 do e.target_scroll_y = 0
}