package main

import "core:mem"

Token_Kind :: enum u8 {
    Ident, Int, Float, String, Rune,
    Keyword, Type, Builtin, Operator, Punctuation,
    Comment_Line, Comment_Block, Directive,
    Unknown, EOF,
}

Token :: struct {
    kind:  Token_Kind,
    start: int,
    end:   int,
}

_is_alpha :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b == '_'
}

_is_digit :: proc(b: u8) -> bool {
    return b >= '0' && b <= '9'
}

_is_ident :: proc(b: u8) -> bool {
    return _is_alpha(b) || _is_digit(b)
}

_keyword_kind :: proc(s: string) -> Token_Kind {
    switch s {
    case "package", "import", "proc", "struct", "enum", "union", "if", "else",
         "for", "when", "switch", "case", "return", "break", "continue",
         "fallthrough", "defer", "using", "distinct", "map", "dynamic", "in",
         "not_in", "or_else", "or_return", "cast", "transmute", "auto_cast",
         "context", "nil":
        return .Keyword
    case "int", "i8", "i16", "i32", "i64", "uint", "u8", "u16", "u32", "u64",
         "f16", "f32", "f64", "string", "cstring", "bool", "byte", "rune",
         "rawptr", "typeid", "any":
        return .Type
    case "len", "cap", "make", "new", "delete", "append", "clear", "free",
         "panic", "assert", "print", "println", "printf":
        return .Builtin
    }
    return .Ident
}

lexer_tokenize :: proc(src: string, allocator: mem.Allocator) -> []Token {
    out := make([dynamic]Token, allocator)
    i := 0
    n := len(src)

    for i < n {
        c := src[i]
        if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
            i += 1
            continue
        }

        start := i

        if c == '/' && i+1 < n && src[i+1] == '/' {
            i += 2
            for i < n && src[i] != '\n' { i += 1 }
            append(&out, Token{kind = .Comment_Line, start = start, end = i})
            continue
        }
        if c == '/' && i+1 < n && src[i+1] == '*' {
            i += 2
            depth := 1
            for i < n && depth > 0 {
                if i+1 < n && src[i] == '/' && src[i+1] == '*' {
                    depth += 1
                    i += 2
                    continue
                }
                if i+1 < n && src[i] == '*' && src[i+1] == '/' {
                    depth -= 1
                    i += 2
                    continue
                }
                i += 1
            }
            append(&out, Token{kind = .Comment_Block, start = start, end = i})
            continue
        }

        if c == '"' {
            i += 1
            for i < n {
                if src[i] == '\\' && i+1 < n {
                    i += 2
                    continue
                }
                if src[i] == '"' {
                    i += 1
                    break
                }
                i += 1
            }
            append(&out, Token{kind = .String, start = start, end = i})
            continue
        }
        if c == '\'' {
            i += 1
            for i < n {
                if src[i] == '\\' && i+1 < n {
                    i += 2
                    continue
                }
                if src[i] == '\'' {
                    i += 1
                    break
                }
                i += 1
            }
            append(&out, Token{kind = .Rune, start = start, end = i})
            continue
        }

        if c == '#' {
            i += 1
            for i < n && _is_ident(src[i]) { i += 1 }
            append(&out, Token{kind = .Directive, start = start, end = i})
            continue
        }

        if _is_digit(c) {
            is_float := false
            i += 1
            for i < n {
                b := src[i]
                if _is_digit(b) || b == '_' ||
                   (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F') ||
                   b == 'x' || b == 'X' || b == 'b' || b == 'B' || b == 'o' || b == 'O' {
                    i += 1
                    continue
                }
                if b == '.' && i+1 < n && _is_digit(src[i+1]) {
                    is_float = true
                    i += 1
                    continue
                }
                break
            }
            append(&out, Token{kind = is_float ? .Float : .Int, start = start, end = i})
            continue
        }

        if _is_alpha(c) {
            i += 1
            for i < n && _is_ident(src[i]) { i += 1 }
            kind := _keyword_kind(src[start:i])
            append(&out, Token{kind = kind, start = start, end = i})
            continue
        }

        // Operators & punctuation
        if i+1 < n {
            pair := src[i : i+2]
            if pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" ||
               pair == "&&" || pair == "||" || pair == "->" || pair == ".." ||
               pair == ":=" || pair == "+=" || pair == "-=" || pair == "*=" || pair == "/=" {
                append(&out, Token{kind = .Operator, start = i, end = i + 2})
                i += 2
                continue
            }
        }
        if c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '=' ||
           c == '<' || c == '>' || c == '!' || c == '&' || c == '|' || c == '^' || c == ':' {
            append(&out, Token{kind = .Operator, start = i, end = i + 1})
            i += 1
            continue
        }
        if c == '(' || c == ')' || c == '{' || c == '}' || c == '[' || c == ']' ||
           c == ',' || c == ';' || c == '.' || c == '@' || c == '$' {
            append(&out, Token{kind = .Punctuation, start = i, end = i + 1})
            i += 1
            continue
        }

        append(&out, Token{kind = .Unknown, start = i, end = i + 1})
        i += 1
    }

    append(&out, Token{kind = .EOF, start = n, end = n})
    return out[:]
}
