package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

LSP_Request_Kind :: enum {
    Initialize,
    Initialized,
    DidOpen,
    DidChange,
    DidSave,
    DidClose,
    Completion,
    Hover,
    GoToDefinition,
    Shutdown,
}

LSP_Pending :: struct {
    id:   int,
    kind: LSP_Request_Kind,
}

OLS_State :: struct {
    process:      os.Process,
    stdin_w:      ^os.File,
    stdout_r:     ^os.File,
    stderr_r:     ^os.File,

    initialized:  bool,
    next_id:      int,
    pending:      [dynamic]LSP_Pending,
    read_buf:     [dynamic]u8,

    comp_uri:         string,
    comp_anchor_line: int,
    comp_anchor_col:  int,
    comp_trigger_pos: int,

    hover_text:   string,
    hover_visible: bool,
    hover_uri:         string,
    hover_anchor_line: int,
    hover_anchor_col:  int,
}

// ──────────────────────────────────────────────────────────────────────────────
// Process

ols_find_binary :: proc() -> (path: string, found: bool) {
    // Prefer PATH
    if p := os.get_env_alloc("PATH", context.temp_allocator); p != "" {
        // fast check: rely on shell resolution by trying common `ols`
        // If it fails, we fall back to known paths.
        // (We do not want to spawn a shell here; just check common dirs.)
        parts := strings.split(p, ":", context.temp_allocator)
        for dir in parts {
            cand := fmt.tprintf("%s/ols", dir)
            if os.exists(cand) {
                return cand, true
            }
        }
    }

    // Common fallback locations
    home := os.get_env_alloc("HOME", context.temp_allocator)
    cands := []string{
        "./ols",
        home != "" ? fmt.tprintf("%s/.local/bin/ols", home) : "",
        home != "" ? fmt.tprintf("%s/bin/ols", home) : "",
        "/usr/local/bin/ols",
        "/usr/bin/ols",
    }
    for c in cands {
        if c != "" && os.exists(c) { return c, true }
    }
    return "", false
}

ols_start :: proc(state: ^OLS_State, workspace_root: string) -> bool {
    if state.stdin_w != nil || state.stdout_r != nil {
        return true
    }

    bin, ok := ols_find_binary()
    if !ok {
        return false
    }

    // Pipes
    stdout_r, stdout_w, err := os.pipe()
    if err != nil { return false }
    stdin_r,  stdin_w,  err2 := os.pipe()
    if err2 != nil {
        _ = os.close(stdout_r); _ = os.close(stdout_w)
        return false
    }
    stderr_r, stderr_w, err3 := os.pipe()
    if err3 != nil {
        _ = os.close(stdout_r); _ = os.close(stdout_w)
        _ = os.close(stdin_r);  _ = os.close(stdin_w)
        return false
    }

    desc := os.Process_Desc{
        working_dir = workspace_root,
        command     = []string{bin},
        stdin       = stdin_r,
        stdout      = stdout_w,
        stderr      = stderr_w,
    }

    // Start process. Close child-side ends on success either way.
    p, perr := os.process_start(desc)
    _ = os.close(stdin_r)
    _ = os.close(stdout_w)
    _ = os.close(stderr_w)
    if perr != nil {
        _ = os.close(stdout_r)
        _ = os.close(stdin_w)
        _ = os.close(stderr_r)
        return false
    }

    state.process  = p
    state.stdin_w  = stdin_w
    state.stdout_r = stdout_r
    state.stderr_r = stderr_r

    state.initialized = false
    state.next_id     = 1
    state.read_buf    = make([dynamic]u8)
    state.pending     = make([dynamic]LSP_Pending)
    state.hover_visible = false

    // Send initialize
    root_uri := _path_to_uri(workspace_root)
    params := InitializeParams{
        rootUri = root_uri,
        capabilities = ClientCaps{},
    }
    _ = ols_send(state, .Initialize, "initialize", params)
    return true
}

ols_stop :: proc(state: ^OLS_State) {
    if state.stdin_w == nil && state.stdout_r == nil { return }

    // Best effort shutdown (don’t block).
    if state.initialized {
        _ = ols_send(state, .Shutdown, "shutdown", nil)
    }

    if state.stdin_w != nil  { _ = os.close(state.stdin_w);  state.stdin_w = nil }
    if state.stdout_r != nil { _ = os.close(state.stdout_r); state.stdout_r = nil }
    if state.stderr_r != nil { _ = os.close(state.stderr_r); state.stderr_r = nil }
    if state.process.handle != 0 {
        _ = os.process_kill(state.process)
        _, _ = os.process_wait(state.process)
        state.process = {}
    }
    state.initialized = false
}

// ──────────────────────────────────────────────────────────────────────────────
// JSON-RPC framing + send

JSONRPC_Request :: struct {
    jsonrpc: string `json:"jsonrpc"`,
    id:      int    `json:"id"`,
    method:  string `json:"method"`,
    params:  json.Value `json:"params,omitempty"`,
}

JSONRPC_Notification :: struct {
    jsonrpc: string `json:"jsonrpc"`,
    method:  string `json:"method"`,
    params:  json.Value `json:"params,omitempty"`,
}

ols_send :: proc(state: ^OLS_State, kind: LSP_Request_Kind, method: string, params: any) -> bool {
    if state.stdin_w == nil { return false }

    id := state.next_id
    state.next_id += 1
    append(&state.pending, LSP_Pending{id = id, kind = kind})

    pval := json.Value(nil)
    if params != nil {
        data, merr := json.marshal(params, allocator = context.temp_allocator)
        if merr == nil {
            v, perr := json.parse(data, allocator = context.temp_allocator)
            if perr == nil { pval = v }
        }
    }

    req := JSONRPC_Request{jsonrpc = "2.0", id = id, method = method, params = pval}
    payload, err := json.marshal(req, allocator = context.temp_allocator)
    if err != nil { return false }

    hdr := fmt.tprintf("Content-Length: %d\r\n\r\n", len(payload))
    out := make([]u8, len(hdr) + len(payload), context.temp_allocator)
    copy(out[:len(hdr)], hdr)
    copy(out[len(hdr):], payload)

    _, werr := os.write(state.stdin_w, out)
    return werr == nil
}

ols_notify :: proc(state: ^OLS_State, method: string, params: any) -> bool {
    if state.stdin_w == nil { return false }

    pval := json.Value(nil)
    if params != nil {
        data, merr := json.marshal(params, allocator = context.temp_allocator)
        if merr == nil {
            v, perr := json.parse(data, allocator = context.temp_allocator)
            if perr == nil { pval = v }
        }
    }

    note := JSONRPC_Notification{jsonrpc = "2.0", method = method, params = pval}
    payload, err := json.marshal(note, allocator = context.temp_allocator)
    if err != nil { return false }

    hdr := fmt.tprintf("Content-Length: %d\r\n\r\n", len(payload))
    out := make([]u8, len(hdr) + len(payload), context.temp_allocator)
    copy(out[:len(hdr)], hdr)
    copy(out[len(hdr):], payload)
    _, werr := os.write(state.stdin_w, out)
    return werr == nil
}

// ──────────────────────────────────────────────────────────────────────────────
// Poll + dispatch

ols_poll :: proc(state: ^OLS_State, app: ^App) {
    if state.stdout_r == nil { return }

    // Drain stderr (optional, keeps pipe from filling).
    if state.stderr_r != nil {
        _ = _drain_pipe(state.stderr_r)
    }

    _ = _drain_into_buf(state.stdout_r, &state.read_buf)

    // Parse framed messages from read_buf
    for {
        msg, ok := _try_pop_lsp_message(&state.read_buf)
        if !ok do break
        ols_handle_message(state, app, msg)
    }
}

_drain_pipe :: proc(f: ^os.File) -> bool {
    if f == nil { return false }
    buf: [1024]u8
    for {
        has, err := os.pipe_has_data(f)
        if err != nil || !has { return true }
        _, rerr := os.read(f, buf[:])
        if rerr != nil { return false }
    }
}

_drain_into_buf :: proc(f: ^os.File, dst: ^[dynamic]u8) -> bool {
    buf: [4096]u8
    for {
        has, err := os.pipe_has_data(f)
        if err != nil || !has { return true }
        n, rerr := os.read(f, buf[:])
        if rerr != nil || n <= 0 { return false }
        old := len(dst^)
        resize(dst, old + n)
        copy(dst^[old:], buf[:n])
    }
}

_try_pop_lsp_message :: proc(buf: ^[dynamic]u8) -> (string, bool) {
    if len(buf^) < 16 { return "", false }

    // Find header terminator: \r\n\r\n
    term := []u8{'\r','\n','\r','\n'}
    hdr_end := -1
    for i := 0; i + 3 < len(buf^); i += 1 {
        if buf^[i] == term[0] && buf^[i+1] == term[1] && buf^[i+2] == term[2] && buf^[i+3] == term[3] {
            hdr_end = i + 4
            break
        }
    }
    if hdr_end < 0 { return "", false }

    hdr := string(buf^[:hdr_end])
    clen := _parse_content_length(hdr)
    if clen <= 0 { return "", false }

    if len(buf^) < hdr_end + clen { return "", false }

    body := string(buf^[hdr_end : hdr_end + clen])
    // consume
    remain := len(buf^) - (hdr_end + clen)
    if remain > 0 {
        copy(buf^[:remain], buf^[hdr_end+clen:])
    }
    resize(buf, remain)
    return body, true
}

_parse_content_length :: proc(hdr: string) -> int {
    // Very small parser: find `Content-Length:` line.
    lines := strings.split(hdr, "\r\n", context.temp_allocator)
    for ln in lines {
        if strings.has_prefix(ln, "Content-Length:") {
            rest := strings.trim_space(ln[len("Content-Length:"):])
            n, ok := strconv.parse_int(rest, 10)
            if ok { return n }
        }
    }
    return -1
}

// ──────────────────────────────────────────────────────────────────────────────
// Message handling

PublishDiagnosticsParams :: struct {
    uri:         string            `json:"uri"`,
    diagnostics: []LSP_Diagnostic  `json:"diagnostics"`,
}

InitializeResultCaps :: struct {
    hoverProvider:      bool `json:"hoverProvider"`,
    definitionProvider: bool `json:"definitionProvider"`,
    // completionProvider is an object in LSP; we only need presence.
    completionProvider: json.Value `json:"completionProvider,omitempty"`,
}

InitializeResultServerInfo :: struct {
    name:    string  `json:"name"`,
    version: ^string `json:"version,omitempty"`,
}

InitializeResult :: struct {
    capabilities: InitializeResultCaps `json:"capabilities"`,
    serverInfo:   ^InitializeResultServerInfo `json:"serverInfo,omitempty"`,
}

InitializeResponse :: struct {
    jsonrpc: string `json:"jsonrpc"`,
    id:      int    `json:"id"`,
    result:  InitializeResult `json:"result"`,
}

JSONRPC_Response_Any :: struct {
    jsonrpc: string     `json:"jsonrpc"`,
    id:      int        `json:"id"`,
    result:  json.Value `json:"result,omitempty"`,
    method:  ^string    `json:"method,omitempty"`,
}

ols_handle_message :: proc(state: ^OLS_State, app: ^App, json_str: string) {
    v, err := json.parse(transmute([]u8)json_str, allocator = context.temp_allocator)
    if err != nil { return }

    // method?
    if obj, ok := v.(json.Object); ok {
        if mv, has := obj["method"]; has {
            if ms, ok2 := mv.(string); ok2 {
                _handle_notification(state, app, ms, obj)
                return
            }
        }
    }

    // response by id
    resp := JSONRPC_Response_Any{}
    if uerr := json.unmarshal_string(json_str, &resp, allocator = context.temp_allocator); uerr != nil {
        return
    }

    kind := _take_pending_kind(state, resp.id)
    #partial switch kind {
    case .Initialize:
        // Mark initialized and send initialized notification
        state.initialized = true
        _ = ols_notify(state, "initialized", nil)
        // Open any editors that were already loaded before OLS became ready.
        ols_did_open_all(state, app)
    case .Completion:
        _handle_completion_result(state, app, resp.result)
    case .Hover:
        _handle_hover_result(state, resp.result)
    case:
        _ = kind
    }
}

_take_pending_kind :: proc(state: ^OLS_State, id: int) -> LSP_Request_Kind {
    for p, i in state.pending {
        if p.id == id {
            kind := p.kind
            // ordered remove without relying on helpers
            last := len(state.pending) - 1
            for j := i; j < last; j += 1 {
                state.pending[j] = state.pending[j + 1]
            }
            resize(&state.pending, last)
            return kind
        }
    }
    return .Initialize // default-ish
}

_handle_notification :: proc(state: ^OLS_State, app: ^App, method: string, obj: json.Object) {
    switch method {
    case "textDocument/publishDiagnostics":
        // Unmarshal full message into a struct so we don’t depend on json.Value shapes.
        note: struct {
            jsonrpc: string `json:"jsonrpc"`,
            method:  string `json:"method"`,
            params:  PublishDiagnosticsParams `json:"params"`,
        }
        // Re-marshal the object to unmarshal cleanly.
        data, merr := json.marshal(obj, allocator = context.temp_allocator)
        if merr != nil { return }
        if uerr := json.unmarshal(data, &note, allocator = context.temp_allocator); uerr != nil { return }

        // store
        uri := note.params.uri
        diagnostics_set_from_lsp(&app.diagnostics, uri, note.params.diagnostics)
    case:
        _ = method
    }
}

_handle_completion_result :: proc(state: ^OLS_State, app: ^App, result: json.Value) {
    // result can be CompletionList or []CompletionItem
    clear(&app.completion.items)
    app.completion.open = false

    data, err := json.marshal(result, allocator = context.temp_allocator)
    if err != nil { return }

    // Try list form
    cl := LSP_Completion_List{}
    if json.unmarshal(data, &cl, allocator = context.temp_allocator) == nil && len(cl.items) > 0 {
        for it in cl.items { _completion_add_item(app, it) }
        _completion_open_from_state(app, state)
        return
    }
    // Try array form
    arr := []LSP_Completion_Item{}
    if json.unmarshal(data, &arr, allocator = context.temp_allocator) == nil && len(arr) > 0 {
        for it in arr { _completion_add_item(app, it) }
        _completion_open_from_state(app, state)
        return
    }
}

_completion_add_item :: proc(app: ^App, it: LSP_Completion_Item) {
    kind := "fn"
    if it.kind != nil {
        #partial switch it.kind^ {
        case .Function, .Method, .Constructor:
            kind = "fn"
        case .Struct, .Class, .Interface, .Module:
            kind = "ty"
        case .Variable, .Field, .Property:
            kind = "var"
        case .Keyword:
            kind = "kw"
        case:
            kind = "it"
        }
    }
    detail := ""
    if it.detail != nil do detail = it.detail^
    ins := it.label
    if it.insertText != nil do ins = it.insertText^
    append(&app.completion.items, Completion_Item{
        kind   = kind,
        label  = it.label,
        detail = detail,
        insert = ins,
    })
}

_completion_open_from_state :: proc(app: ^App, state: ^OLS_State) {
    if len(app.completion.items) == 0 do return
    app.completion.open        = true
    app.completion.selected    = 0
    app.completion.anchor_line = state.comp_anchor_line
    app.completion.anchor_col  = state.comp_anchor_col
    app.completion.trigger_pos = state.comp_trigger_pos
    app.completion.uri         = state.comp_uri
    app.completion.title       = "OLS completions"
}

_handle_hover_result :: proc(state: ^OLS_State, result: json.Value) {
    state.hover_visible = false
    state.hover_text = ""

    data, err := json.marshal(result, allocator = context.temp_allocator)
    if err != nil { return }

    h := LSP_Hover{}
    if json.unmarshal(data, &h, allocator = context.temp_allocator) != nil { return }

    // Convert hover contents into a readable string (Phase 2: plain text only).
    state.hover_text = _hover_contents_to_text(h.contents)
    state.hover_visible = state.hover_text != ""
}

_hover_contents_to_text :: proc(v: json.Value) -> string {
    // LSP hover contents can be string | MarkupContent | MarkedString | []...
    if s, ok := v.(json.String); ok { return string(s) }
    if obj, ok := v.(json.Object); ok {
        if vv, has := obj["value"]; has {
            if s2, ok2 := vv.(json.String); ok2 { return string(s2) }
        }
    }
    if arr, ok := v.(json.Array); ok {
        parts := make([dynamic]string, 0, context.temp_allocator)
        for it in arr {
            t := _hover_contents_to_text(it)
            if t != "" do append(&parts, t)
        }
        joined, _ := strings.join(parts[:], "\n", context.temp_allocator)
        return joined
    }
    return ""
}

// ──────────────────────────────────────────────────────────────────────────────
// Params structs (Phase 2 subset)

ClientCaps :: struct {}

InitializeParams :: struct {
    rootUri:       string     `json:"rootUri,omitempty"`,
    capabilities:  ClientCaps `json:"capabilities"`,
}

TextDocumentItem :: struct {
    uri:        string `json:"uri"`,
    languageId: string `json:"languageId"`,
    version:    int    `json:"version"`,
    text:       string `json:"text"`,
}

DidOpenParams :: struct {
    textDocument: TextDocumentItem `json:"textDocument"`,
}

VersionedTextDocumentIdentifier :: struct {
    uri:     string `json:"uri"`,
    version: int    `json:"version"`,
}

TextDocumentContentChangeEvent :: struct {
    text: string `json:"text"`,
}

DidChangeParams :: struct {
    textDocument:   VersionedTextDocumentIdentifier     `json:"textDocument"`,
    contentChanges: []TextDocumentContentChangeEvent    `json:"contentChanges"`,
}

TextDocumentIdentifier :: struct { uri: string `json:"uri"` }

DidSaveParams :: struct {
    textDocument: TextDocumentIdentifier `json:"textDocument"`,
}

DidCloseParams :: struct {
    textDocument: TextDocumentIdentifier `json:"textDocument"`,
}

CompletionParams :: struct {
    textDocument: TextDocumentIdentifier `json:"textDocument"`,
    position:     LSP_Position           `json:"position"`,
}

HoverParams :: struct {
    textDocument: TextDocumentIdentifier `json:"textDocument"`,
    position:     LSP_Position           `json:"position"`,
}

// ──────────────────────────────────────────────────────────────────────────────
// Helpers

_path_to_uri :: proc(path: string) -> string {
    // Good enough for local files on Linux. (Phase 2)
    if strings.has_prefix(path, "file://") { return path }
    // Ensure absolute path
    if path == "" { return "" }
    if path[0] == '/' {
        return fmt.tprintf("file://%s", path)
    }
    cwd, err := os.get_working_directory(context.temp_allocator)
    abs := err == nil ? fmt.tprintf("%s/%s", cwd, path) : path
    if len(abs) > 0 && abs[0] == '/' {
        return fmt.tprintf("file://%s", abs)
    }
    return fmt.tprintf("file:///%s", abs)
}

// ──────────────────────────────────────────────────────────────────────────────
// Document sync (Phase 2)

ols_did_open_all :: proc(state: ^OLS_State, app: ^App) {
    if !state.initialized do return
    for &e in app.editors {
        if e.file_path != "" {
            _ = ols_did_open(state, &e)
        }
    }
}

ols_did_open :: proc(state: ^OLS_State, e: ^Editor_State) -> bool {
    if !state.initialized do return false
    uri := _editor_uri(e)
    text := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    if e.lsp_version <= 0 { e.lsp_version = 1 } else { e.lsp_version += 1 }

    params := DidOpenParams{
        textDocument = TextDocumentItem{
            uri        = uri,
            languageId = "odin",
            version    = e.lsp_version,
            text       = text,
        },
    }
    e.lsp_dirty = false
    return ols_notify(state, "textDocument/didOpen", params)
}

ols_did_change :: proc(state: ^OLS_State, e: ^Editor_State) -> bool {
    if !state.initialized do return false
    uri := _editor_uri(e)
    text := gap_buffer_to_string(&e.buffer, context.temp_allocator)
    if e.lsp_version <= 0 { e.lsp_version = 1 } else { e.lsp_version += 1 }

    params := DidChangeParams{
        textDocument = VersionedTextDocumentIdentifier{uri = uri, version = e.lsp_version},
        contentChanges = []TextDocumentContentChangeEvent{{text = text}},
    }
    e.lsp_dirty = false
    return ols_notify(state, "textDocument/didChange", params)
}

ols_did_save :: proc(state: ^OLS_State, e: ^Editor_State) -> bool {
    if !state.initialized do return false
    uri := _editor_uri(e)
    return ols_notify(state, "textDocument/didSave", DidSaveParams{textDocument = TextDocumentIdentifier{uri = uri}})
}

ols_did_close :: proc(state: ^OLS_State, e: ^Editor_State) -> bool {
    if !state.initialized do return false
    uri := _editor_uri(e)
    e.lsp_dirty = false
    return ols_notify(state, "textDocument/didClose", DidCloseParams{textDocument = TextDocumentIdentifier{uri = uri}})
}

_editor_uri :: proc(e: ^Editor_State) -> string {
    if e.file_path != "" { return _path_to_uri(e.file_path) }
    return _path_to_uri("untitled.odin")
}

ols_request_completion :: proc(state: ^OLS_State, e: ^Editor_State) -> bool {
    if !state.initialized do return false
    uri := _editor_uri(e)
    state.comp_uri         = uri
    state.comp_anchor_line = e.cursor.line
    state.comp_anchor_col  = e.cursor.col

    // Determine replacement start in bytes.
    // If triggered right after '.', insert at cursor; otherwise replace current word.
    trigger := e.cursor.pos
    if trigger > 0 && gap_buffer_byte_at(&e.buffer, trigger - 1) != '.' {
        p := trigger
        for p > 0 && _is_ident_byte(gap_buffer_byte_at(&e.buffer, p - 1)) { p -= 1 }
        trigger = p
    }
    state.comp_trigger_pos = trigger

    return ols_send(state, .Completion, "textDocument/completion",
        CompletionParams{
            textDocument = TextDocumentIdentifier{uri = uri},
            position     = LSP_Position{line = e.cursor.line, character = e.cursor.col},
        },
    )
}

ols_request_hover :: proc(state: ^OLS_State, e: ^Editor_State) -> bool {
    if !state.initialized do return false
    uri := _editor_uri(e)
    state.hover_uri         = uri
    state.hover_anchor_line = e.cursor.line
    state.hover_anchor_col  = e.cursor.col
    return ols_send(state, .Hover, "textDocument/hover",
        HoverParams{
            textDocument = TextDocumentIdentifier{uri = uri},
            position     = LSP_Position{line = e.cursor.line, character = e.cursor.col},
        },
    )
}

_is_ident_byte :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') ||
           (b >= 'A' && b <= 'Z') ||
           (b >= '0' && b <= '9') ||
           b == '_'
}

