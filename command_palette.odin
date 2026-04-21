package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

Command_Action :: enum {
    NewFile,
    OpenFile,
    SaveFile,
    CloseTab,
    ToggleSidebar,
    Find,
    Replace,
    Settings,
    Quit,
}

Command :: struct {
    label:    string,
    shortcut: string,
    action:   Command_Action,
}

Command_Palette :: struct {
    visible:      bool,
    query:        string,
    all_commands: [dynamic]Command,
    filtered:     [dynamic]int,
    selected:     int,
}

Scored_Command :: struct {
    idx:   int,
    score: int,
}

command_palette_init :: proc(cp: ^Command_Palette) {
    cp.all_commands = make([dynamic]Command)
    cp.filtered     = make([dynamic]int)
    cp.visible      = false
    cp.selected     = 0
    cp.query        = ""

    append(&cp.all_commands, Command{"New File", "Ctrl+N", .NewFile})
    append(&cp.all_commands, Command{"Open File", "Ctrl+O", .OpenFile})
    append(&cp.all_commands, Command{"Save File", "Ctrl+S", .SaveFile})
    append(&cp.all_commands, Command{"Close Tab", "Ctrl+W", .CloseTab})
    append(&cp.all_commands, Command{"Toggle Sidebar", "Ctrl+B", .ToggleSidebar})
    append(&cp.all_commands, Command{"Find", "Ctrl+F", .Find})
    append(&cp.all_commands, Command{"Find & Replace", "Ctrl+H", .Replace})
    append(&cp.all_commands, Command{"Settings", "Ctrl+,", .Settings})
    append(&cp.all_commands, Command{"Quit", "Ctrl+Q", .Quit})

    _palette_recompute(cp)
}

command_palette_destroy :: proc(cp: ^Command_Palette) {
    delete(cp.all_commands)
    delete(cp.filtered)
    if len(cp.query) > 0 { delete(cp.query) }
}

command_palette_toggle :: proc(app: ^App) {
    if app.palette.visible {
        command_palette_close(app)
    } else {
        command_palette_open(app)
    }
}

command_palette_open :: proc(app: ^App) {
    app.palette.visible = true
    app.palette.selected = 0
    if len(app.palette.query) > 0 { delete(app.palette.query) }
    app.palette.query = ""
    _palette_recompute(&app.palette)
}

command_palette_close :: proc(app: ^App) {
    app.palette.visible = false
    app.palette.selected = 0
    if len(app.palette.query) > 0 { delete(app.palette.query) }
    app.palette.query = ""
    clear(&app.palette.filtered)
    _palette_recompute(&app.palette)
}

command_palette_handle_input :: proc(app: ^App) {
    if !app.palette.visible do return

    ctrl  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    shift := rl.IsKeyDown(.LEFT_SHIFT)   || rl.IsKeyDown(.RIGHT_SHIFT)

    if rl.IsKeyPressed(.ESCAPE) {
        command_palette_close(app)
        return
    }

    if rl.IsKeyPressed(.UP) {
        app.palette.selected -= 1
        if app.palette.selected < 0 do app.palette.selected = len(app.palette.filtered) - 1
    }
    if rl.IsKeyPressed(.DOWN) {
        if len(app.palette.filtered) > 0 {
            app.palette.selected = (app.palette.selected + 1) % len(app.palette.filtered)
        }
    }
    if rl.IsKeyPressed(.ENTER) {
        _palette_execute_selected(app)
        return
    }

    // text input
    if !ctrl {
        ch := rl.GetCharPressed()
        for ch > 0 {
            buf, n := utf8.encode_rune(ch)
            s := string(buf[:n])
            new_q := fmt.tprintf("%s%s", app.palette.query, s)
            if len(app.palette.query) > 0 { delete(app.palette.query) }
            app.palette.query = strings.clone(new_q, context.allocator)
            _palette_recompute(&app.palette)
            ch = rl.GetCharPressed()
        }
    }
    if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
        if len(app.palette.query) > 0 {
            new_q := strings.clone(app.palette.query[:len(app.palette.query)-1], context.allocator)
            delete(app.palette.query)
            app.palette.query = new_q
            _palette_recompute(&app.palette)
        }
    }

    _ = shift
}

command_palette_draw :: proc(app: ^App) {
    if !app.palette.visible do return

    ww := f32(app.window_width)
    wh := f32(app.window_height)
    mouse := rl.GetMousePosition()

    // Backdrop
    rl.DrawRectangleRec({0, 0, ww, wh}, rl.Color{8, 10, 18, 170})

    w : f32 = min(600, ww * 0.7)
    max_rows := 12
    row_h : f32 = 28
    header_h : f32 = 40
    rows := min(len(app.palette.filtered), max_rows)
    h : f32 = header_h + f32(rows) * row_h + 10
    modal := rl.Rectangle{(ww - w) * 0.5, wh * 0.18, w, h}

    rl.DrawRectangleRounded(modal, 0.06, 10, rl.Color{22, 23, 36, 255})
    rl.DrawRectangleRoundedLinesEx(modal, 0.06, 10, 1, app.theme.border)

    // Input line
    prompt := fmt.tprintf("> %s", app.palette.query)
    if app.palette.query == "" {
        prompt = "> "
    }
    draw_text_ui(&app.font, strings.clone_to_cstring(prompt, context.temp_allocator),
        {modal.x + 14, modal.y + 12}, app.theme.text_primary, 13)

    rl.DrawLineEx({modal.x, modal.y + header_h}, {modal.x + modal.width, modal.y + header_h}, 1, app.theme.border)

    // Rows
    for i := 0; i < rows; i += 1 {
        cmd_idx := app.palette.filtered[i]
        cmd := app.palette.all_commands[cmd_idx]
        row := rl.Rectangle{modal.x, modal.y + header_h + f32(i) * row_h, modal.width, row_h}

        hov := rl.CheckCollisionPointRec(mouse, row)
        if i == app.palette.selected || hov {
            rl.DrawRectangleRec(row, rl.Color{41, 43, 61, 255})
        }
        draw_text_ui(&app.font, strings.clone_to_cstring(cmd.label, context.temp_allocator),
            {row.x + 14, row.y + 7}, app.theme.text_primary, 12)
        if cmd.shortcut != "" {
            sw := rl.MeasureTextEx(app.font.ui, strings.clone_to_cstring(cmd.shortcut, context.temp_allocator), 11, 0).x
            draw_text_ui(&app.font, strings.clone_to_cstring(cmd.shortcut, context.temp_allocator),
                {row.x + row.width - sw - 14, row.y + 8}, app.theme.text_muted, 11)
        }

        if hov && rl.IsMouseButtonPressed(.LEFT) {
            app.palette.selected = i
            _palette_execute_selected(app)
            return
        }
    }
}

_palette_execute_selected :: proc(app: ^App) {
    if len(app.palette.filtered) == 0 do return
    idx := clamp(app.palette.selected, 0, len(app.palette.filtered) - 1)
    cmd := app.palette.all_commands[app.palette.filtered[idx]]

    command_palette_close(app)

    switch cmd.action {
    case .NewFile:
        editor_new_empty(app)
    case .OpenFile:
        input_try_open_dialog(app)
    case .SaveFile:
        input_save_file(app)
    case .CloseTab:
        if app.active_editor >= 0 { _close_tab(app, app.active_editor) }
    case .ToggleSidebar:
        app.layout.sidebar_visible = !app.layout.sidebar_visible
        layout_recalculate(&app.layout, f32(app.window_width), f32(app.window_height))
    case .Find:
        find_open(app, false)
    case .Replace:
        find_open(app, true)
    case .Settings:
        app.settings_modal_open = true
        app.settings_tab = 0
    case .Quit:
        app.should_quit = true
    }
}

_palette_recompute :: proc(cp: ^Command_Palette) {
    clear(&cp.filtered)
    if cp.query == "" {
        for i := 0; i < len(cp.all_commands); i += 1 {
            append(&cp.filtered, i)
        }
        return
    }

    // Score commands and keep those that match.
    scored := make([dynamic]Scored_Command, 0, context.temp_allocator)
    for cmd, i in cp.all_commands {
        ok, score := fuzzy_match(cp.query, cmd.label)
        if ok {
            append(&scored, Scored_Command{idx = i, score = score})
        }
    }

    // Simple selection sort for small N
    for i := 0; i < len(scored); i += 1 {
        best := i
        for j := i + 1; j < len(scored); j += 1 {
            if scored[j].score > scored[best].score { best = j }
        }
        scored[i], scored[best] = scored[best], scored[i]
    }

    for s in scored { append(&cp.filtered, s.idx) }
    cp.selected = clamp(cp.selected, 0, max(0, len(cp.filtered) - 1))
}

fuzzy_match :: proc(pattern, candidate: string) -> (matched: bool, score: int) {
    if pattern == "" { return true, 0 }
    p := strings.to_lower(pattern, context.temp_allocator)
    c := strings.to_lower(candidate, context.temp_allocator)

    pi := 0
    last_match := -2
    for i := 0; i < len(c) && pi < len(p); i += 1 {
        if c[i] == p[pi] {
            // base score
            score += 10
            // consecutive bonus
            if i == last_match + 1 { score += 12 }
            // start-of-word bonus
            if i == 0 || c[i-1] == ' ' || c[i-1] == '_' || c[i-1] == '-' { score += 8 }
            last_match = i
            pi += 1
        }
    }
    matched = pi == len(p)
    if matched {
        // shorter candidate slight bonus
        score += max(0, 40 - len(c))
    }
    return
}

