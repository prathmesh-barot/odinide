package main

import "core:strings"
import rl "vendor:raylib"

Line_Tokens :: struct {
    tokens:   []Token,
    is_dirty: bool,
}

Highlighter :: struct {
    lines:      [dynamic]Line_Tokens,
    full_dirty: bool,
}

highlighter_mark_dirty :: proc(h: ^Highlighter, from_line: int) {
    for i := max(0, from_line); i < len(h.lines); i += 1 {
        h.lines[i].is_dirty = true
    }
}

highlighter_update :: proc(h: ^Highlighter, e: ^Editor_State) {
    content := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    lines := strings.split_lines(content, context.temp_allocator)

    if len(h.lines) != len(lines) {
        for lt in h.lines {
            if lt.tokens != nil do delete(lt.tokens)
        }
        clear(&h.lines)
        resize(&h.lines, len(lines))
        for i in 0..<len(h.lines) {
            h.lines[i].is_dirty = true
        }
    }

    if h.full_dirty {
        for i in 0..<len(h.lines) {
            h.lines[i].is_dirty = true
        }
        h.full_dirty = false
    }

    budget := 200
    for i in 0..<len(lines) {
        if budget <= 0 do break
        if !h.lines[i].is_dirty do continue

        if h.lines[i].tokens != nil {
            delete(h.lines[i].tokens)
        }
        h.lines[i].tokens = lexer_tokenize(lines[i], context.allocator)
        h.lines[i].is_dirty = false
        budget -= 1
    }
}

highlighter_get_color :: proc(app: ^App, kind: Token_Kind) -> rl.Color {
    switch kind {
    case .Keyword:
        return app.theme.syn_keyword
    case .Type:
        return app.theme.syn_type
    case .Builtin:
        return app.theme.syn_proc
    case .String, .Rune:
        return app.theme.syn_string
    case .Int, .Float:
        return app.theme.syn_number
    case .Comment_Line, .Comment_Block:
        return app.theme.syn_comment
    case .Operator:
        return app.theme.syn_operator
    case .Directive:
        return app.theme.syn_keyword
    case .Punctuation:
        return app.theme.syn_punctuation
    case .Ident, .Unknown, .EOF:
        return app.theme.text_primary
    }
    return app.theme.text_primary
}

renderer_draw_highlighted_line :: proc(
    app: ^App,
    line_str: string,
    tokens: []Token,
    x, y: f32,
) {
    if len(line_str) == 0 do return
    if len(tokens) == 0 {
        draw_text_mono(&app.font, strings.clone_to_cstring(line_str, context.temp_allocator), {x, y}, app.theme.text_primary, app.font.font_size)
        return
    }

    for tok in tokens {
        if tok.kind == .EOF do break
        if tok.start >= tok.end || tok.start < 0 || tok.end > len(line_str) do continue
        seg := line_str[tok.start:tok.end]
        if len(seg) == 0 do continue
        draw_x := x + f32(tok.start) * app.font.char_width
        draw_text_mono(&app.font, strings.clone_to_cstring(seg, context.temp_allocator), {draw_x, y}, highlighter_get_color(app, tok.kind), app.font.font_size)
    }
}
