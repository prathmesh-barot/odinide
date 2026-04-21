package main

import "core:strings"

Diag_Severity :: enum { Error, Warning, Info, Hint }

Diag_Entry :: struct {
    line:      int,
    col_start: int,
    col_end:   int,
    message:   string,
    severity:  Diag_Severity,
    source:    string,
}

Diagnostics :: struct {
    entries: map[string][dynamic]Diag_Entry, // uri -> entries
}

diagnostics_init :: proc(d: ^Diagnostics) {
    d.entries = make(map[string][dynamic]Diag_Entry)
}

diagnostics_destroy :: proc(d: ^Diagnostics) {
    for _, uri_diags in d.entries {
        for p in uri_diags {
            if len(p.message) > 0 { delete(p.message) }
            if len(p.source) > 0 { delete(p.source) }
        }
        delete(uri_diags)
    }
    delete(d.entries)
}

diagnostics_set_from_lsp :: proc(d: ^Diagnostics, uri: string, lsp_diags: []LSP_Diagnostic) {
    if prev, ok := d.entries[uri]; ok {
        for p in prev {
            if len(p.message) > 0 { delete(p.message) }
            if len(p.source) > 0 { delete(p.source) }
        }
    }
    clear(&d.entries[uri])
    for ld in lsp_diags {
        sev := Diag_Severity.Error
        if ld.severity != nil {
            switch ld.severity^ {
            case .Error:       sev = .Error
            case .Warning:     sev = .Warning
            case .Information: sev = .Info
            case .Hint:        sev = .Hint
            }
        }
        src := ""
        if ld.source != nil do src = ld.source^
        append(&d.entries[uri], Diag_Entry{
            line      = ld.range.start.line,
            col_start = ld.range.start.character,
            col_end   = ld.range.end.character,
            message   = strings.clone(ld.message, context.allocator),
            severity  = sev,
            source    = strings.clone(src, context.allocator),
        })
    }
}

diagnostics_clear_uri :: proc(d: ^Diagnostics, uri: string) {
    if prev, ok := d.entries[uri]; ok {
        for p in prev {
            if len(p.message) > 0 { delete(p.message) }
            if len(p.source) > 0 { delete(p.source) }
        }
    }
    clear(&d.entries[uri])
}

diagnostics_best_for_line :: proc(d: ^Diagnostics, uri: string, line: int) -> (found: bool, entry: Diag_Entry) {
    best := Diag_Entry{}
    have := false
    if ds, ok := d.entries[uri]; ok {
        for e in ds {
            if e.line != line do continue
            if !have {
                best = e
                have = true
                continue
            }
            // Prefer error > warning > info > hint
            if e.severity == .Error && best.severity != .Error { best = e }
            if e.severity == .Warning && best.severity != .Error && best.severity != .Warning { best = e }
            if e.severity == .Info && best.severity == .Hint { best = e }
        }
    }
    return have, best
}

