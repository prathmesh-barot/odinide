package main

import "core:strings"
import rl "vendor:raylib"

Edit_Op :: enum { Insert, Delete, ReplaceAll }

Edit_Command :: struct {
    op:            Edit_Op,
    pos:           int,
    text:          string,
    text2:         string, // used by ReplaceAll (new text)
    cursor_before: int,
    cursor_after:  int,
    at_time:       f64,
}

Undo_Stack :: struct {
    stack:          [dynamic]Edit_Command,
    index:          int,
    coalesce_timer: f64,
}

undo_clear :: proc(us: ^Undo_Stack) {
    for cmd in us.stack {
        if len(cmd.text) > 0 {
            delete(cmd.text)
        }
        if len(cmd.text2) > 0 {
            delete(cmd.text2)
        }
    }
    clear(&us.stack)
    us.index = 0
    us.coalesce_timer = 0
}

_is_single_word_char :: proc(text: string) -> bool {
    if len(text) != 1 do return false
    b := text[0]
    if b == ' ' || b == '\t' || b == '\n' || b == '\r' do return false
    return true
}

undo_push :: proc(us: ^Undo_Stack, cmd: Edit_Command) {
    // Truncate redo branch
    if us.index < len(us.stack) {
        for i := us.index; i < len(us.stack); i += 1 {
            if len(us.stack[i].text) > 0 {
                delete(us.stack[i].text)
            }
        }
        resize(&us.stack, us.index)
    }

    // Coalesce adjacent single-character inserts typed quickly.
    if len(us.stack) > 0 && us.index > 0 {
        last := &us.stack[us.index - 1]
        if last.op == .Insert &&
           cmd.op == .Insert &&
           _is_single_word_char(last.text) &&
           _is_single_word_char(cmd.text) &&
           cmd.pos == last.pos + len(last.text) &&
           (cmd.at_time - last.at_time) <= 0.3 {
            combined_buf := make([]u8, len(last.text) + len(cmd.text), context.temp_allocator)
            copy(combined_buf[:len(last.text)], last.text)
            copy(combined_buf[len(last.text):], cmd.text)
            combined := strings.clone(string(combined_buf), context.allocator)
            delete(last.text)
            last.text = combined
            last.cursor_after = cmd.cursor_after
            last.at_time = cmd.at_time
            return
        }
    }

    append(&us.stack, cmd)
    us.index = len(us.stack)
    us.coalesce_timer = cmd.at_time
}

undo_do :: proc(us: ^Undo_Stack, e: ^Editor_State) -> bool {
    if us.index <= 0 do return false
    us.index -= 1
    cmd := us.stack[us.index]

    switch cmd.op {
    case .Insert:
        gap_buffer_delete(&e.buffer, cmd.pos, len(cmd.text))
        e.cursor.pos = cmd.cursor_before
    case .Delete:
        gap_buffer_insert(&e.buffer, cmd.pos, cmd.text)
        e.cursor.pos = cmd.cursor_before
    case .ReplaceAll:
        _gap_buffer_set_string(&e.buffer, cmd.text)
        e.cursor.pos = cmd.cursor_before
    }

    e.is_modified = true
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
    e.last_edit_time = rl.GetTime()
    e.lsp_dirty = true
    return true
}

redo_do :: proc(us: ^Undo_Stack, e: ^Editor_State) -> bool {
    if us.index >= len(us.stack) do return false
    cmd := us.stack[us.index]
    us.index += 1

    switch cmd.op {
    case .Insert:
        gap_buffer_insert(&e.buffer, cmd.pos, cmd.text)
        e.cursor.pos = cmd.cursor_after
    case .Delete:
        gap_buffer_delete(&e.buffer, cmd.pos, len(cmd.text))
        e.cursor.pos = cmd.cursor_after
    case .ReplaceAll:
        _gap_buffer_set_string(&e.buffer, cmd.text2)
        e.cursor.pos = cmd.cursor_after
    }

    e.is_modified = true
    editor_sync_line_col(e)
    e.cursor.sticky_col = e.cursor.col
    e.last_edit_time = rl.GetTime()
    e.lsp_dirty = true
    return true
}

_gap_buffer_set_string :: proc(gb: ^Gap_Buffer, s: string) {
    // Replace buffer contents completely.
    delete(gb.data)
    gap_buffer_init(gb, max(len(s) * 2, 4096))
    if len(s) > 0 {
        gap_buffer_insert(gb, 0, s)
    }
}
