package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:slice"
import rl "vendor:raylib"

// ─── File Tree ────────────────────────────────────────────────────────────────

Tree_Node :: struct {
    name:            string,
    path:            string,
    is_dir:          bool,
    expanded:        bool,
    depth:           int,
    children:        [dynamic]Tree_Node,
    children_loaded: bool,
}

Sidebar :: struct {
    root:          Tree_Node,
    scroll_y:      f32,
    target_scroll: f32,
    hovered_path:  string,
    selected_path: string,
    search_query:  string,
}

sidebar_init :: proc(sb: ^Sidebar) {
    cwd, err := os.get_working_directory(context.allocator)
    root_path := err == nil ? cwd : "."

    sb.root = Tree_Node{
        name     = strings.clone(filepath.base(root_path), context.allocator),
        path     = root_path,
        is_dir   = true,
        expanded = true,
        depth    = 0,
    }
    sidebar_load_children(&sb.root)
}

sidebar_load_children :: proc(node: ^Tree_Node) {
    if node.children_loaded do return
    node.children_loaded = true

    f, err := os.open(node.path)
    if err != nil do return
    defer os.close(f)

    fis, read_err := os.read_dir(f, -1, context.allocator)
    if read_err != nil do return

    slice.sort_by(fis, proc(a, b: os.File_Info) -> bool {
        a_dir := os.is_dir(a.fullpath)
        b_dir := os.is_dir(b.fullpath)
        if a_dir != b_dir do return a_dir
        return a.name < b.name
    })

    for fi in fis {
        if len(fi.name) > 0 && fi.name[0] == '.' do continue
        append(&node.children, Tree_Node{
            name   = strings.clone(fi.name,     context.allocator),
            path   = strings.clone(fi.fullpath, context.allocator),
            is_dir = os.is_dir(fi.fullpath),
            depth  = node.depth + 1,
        })
    }
}

// ─── Sidebar Draw ─────────────────────────────────────────────────────────────

sidebar_draw :: proc(app: ^App) {
    rect := app.layout.sidebar
    rl.DrawRectangleRec(rect, app.theme.bg_elevated)

    // Right border – 1px divider
    rl.DrawLineEx(
        {rect.x + rect.width, rect.y},
        {rect.x + rect.width, rect.y + rect.height},
        1, app.theme.border)

    // ── Header ─────────────────────────────────────────────────────────────
    header_h : f32 = 36
    title := "EXPLORER"
    switch app.active_panel {
    case .Files:    title = "EXPLORER"
    case .Search:   title = "SEARCH"
    case .Git:      title = "SOURCE CONTROL"
    case .Settings: title = "SETTINGS"
    }

    rl.DrawTextEx(app.font.ui, strings.clone_to_cstring(title, context.temp_allocator),
        {rect.x + 14, rect.y + 10}, 10, 1.5, app.theme.text_muted)
    // Thin separator below header
    rl.DrawLineEx(
        {rect.x, rect.y + header_h},
        {rect.x + rect.width, rect.y + header_h},
        1, app.theme.border)

    mouse_pos := rl.GetMousePosition()
    body_rect := rl.Rectangle{rect.x, rect.y + header_h, rect.width, rect.height - header_h}

    switch app.active_panel {
    case .Files:
        // ── Tree content (scissored) ───────────────────────────────────────
        rl.BeginScissorMode(
            i32(body_rect.x), i32(body_rect.y),
            i32(body_rect.width - 1), i32(body_rect.height))

        y           := body_rect.y + 4 - app.sidebar.scroll_y
        new_hovered := ""
        sidebar_draw_node(app, &app.sidebar.root, &y, mouse_pos, &new_hovered)

        rl.EndScissorMode()
        app.sidebar.hovered_path = new_hovered

        // ── Scroll wheel ───────────────────────────────────────────────────
        if rl.CheckCollisionPointRec(mouse_pos, rect) {
            wheel := rl.GetMouseWheelMove()
            if wheel != 0 {
                app.sidebar.target_scroll -= wheel * app.font.line_height * 3
                if app.sidebar.target_scroll < 0 do app.sidebar.target_scroll = 0
            }
        }
        dt := rl.GetFrameTime()
        app.sidebar.scroll_y += (app.sidebar.target_scroll - app.sidebar.scroll_y) * 15.0 * dt
    case .Search:
        sidebar_draw_search_panel(app, body_rect, mouse_pos)
        app.sidebar.target_scroll = 0
        app.sidebar.scroll_y      = 0
    case .Git:
        sidebar_draw_git_panel(app, body_rect, mouse_pos)
        app.sidebar.target_scroll = 0
        app.sidebar.scroll_y      = 0
    case .Settings:
        sidebar_draw_settings_panel(app, body_rect, mouse_pos)
        app.sidebar.target_scroll = 0
        app.sidebar.scroll_y      = 0
    }
}

sidebar_draw_panel_card :: proc(app: ^App, rect: rl.Rectangle, title, body: string) {
    bg := app.theme.bg_highlight
    bg.a = 145
    rl.DrawRectangleRounded(rect, 0.2, 6, bg)
    rl.DrawRectangleRoundedLinesEx(rect, 0.2, 6, 1, app.theme.border)

    rl.DrawTextEx(app.font.ui, strings.clone_to_cstring(title, context.temp_allocator),
        {rect.x + 10, rect.y + 8}, 11, 0, app.theme.text_primary)
    rl.DrawTextEx(app.font.ui, strings.clone_to_cstring(body, context.temp_allocator),
        {rect.x + 10, rect.y + 27}, 11, 0, app.theme.text_muted)
}

sidebar_draw_search_panel :: proc(app: ^App, body_rect: rl.Rectangle, mouse_pos: rl.Vector2) {
    box_h : f32 = 30
    search_box := rl.Rectangle{body_rect.x + 10, body_rect.y + 12, body_rect.width - 20, box_h}
    rl.DrawRectangleRounded(search_box, 0.18, 6, app.theme.bg_base)
    rl.DrawRectangleRoundedLinesEx(search_box, 0.18, 6, 1, app.theme.border)

    query := app.sidebar.search_query
    if query == "" {
        query = "Type to search symbols and text..."
    }
    q_col := app.sidebar.search_query == "" ? app.theme.text_disabled : app.theme.text_primary
    rl.DrawTextEx(app.font.ui, strings.clone_to_cstring(query, context.temp_allocator),
        {search_box.x + 10, search_box.y + 8}, 11, 0, q_col)

    if rl.CheckCollisionPointRec(mouse_pos, search_box) && rl.IsMouseButtonPressed(.LEFT) {
        app_push_toast(app, "Search panel ready (input shortcuts coming next).")
    }

    sidebar_draw_panel_card(
        app,
        {body_rect.x + 10, body_rect.y + 52, body_rect.width - 20, 54},
        "Quick Action",
        "Press Ctrl+O to open files quickly.",
    )
    sidebar_draw_panel_card(
        app,
        {body_rect.x + 10, body_rect.y + 112, body_rect.width - 20, 54},
        "Tip",
        "Use Ctrl+Tab to switch tabs fast.",
    )
}

sidebar_draw_git_panel :: proc(app: ^App, body_rect: rl.Rectangle, mouse_pos: rl.Vector2) {
    card := rl.Rectangle{body_rect.x + 10, body_rect.y + 12, body_rect.width - 20, 76}
    sidebar_draw_panel_card(
        app, card,
        "Source Control",
        "Git integration UI is stubbed.\nUse terminal for now.",
    )

    btn := rl.Rectangle{body_rect.x + 10, body_rect.y + 98, body_rect.width - 20, 28}
    hov := rl.CheckCollisionPointRec(mouse_pos, btn)
    bcol := hov ? app.theme.bg_highlight : app.theme.bg_base
    rl.DrawRectangleRounded(btn, 0.2, 6, bcol)
    rl.DrawRectangleRoundedLinesEx(btn, 0.2, 6, 1, app.theme.border)
    rl.DrawTextEx(app.font.ui, "Refresh Status",
        {btn.x + 10, btn.y + 7}, 11, 0, app.theme.text_primary)
    if hov && rl.IsMouseButtonPressed(.LEFT) {
        app_push_toast(app, "Git panel refreshed.")
    }
}

sidebar_draw_settings_panel :: proc(app: ^App, body_rect: rl.Rectangle, mouse_pos: rl.Vector2) {
    sidebar_draw_panel_card(
        app,
        {body_rect.x + 10, body_rect.y + 12, body_rect.width - 20, 54},
        "Editor Font",
        "Use +/- buttons to change size.",
    )
    size_text := fmt.ctprintf("Current: %.0f px", app.font.font_size)
    rl.DrawTextEx(app.font.ui, size_text,
        {body_rect.x + 20, body_rect.y + 40}, 11, 0, app.theme.text_primary)

    minus_btn := rl.Rectangle{body_rect.x + 10, body_rect.y + 74, 34, 28}
    plus_btn  := rl.Rectangle{body_rect.x + 50, body_rect.y + 74, 34, 28}

    btns   := [2]rl.Rectangle{minus_btn, plus_btn}
    labels := [2]string{"-", "+"}
    for i in 0..<2 {
        btn   := btns[i]
        label := labels[i]
        hov := rl.CheckCollisionPointRec(mouse_pos, btn)
        bg  := hov ? app.theme.bg_highlight : app.theme.bg_base
        rl.DrawRectangleRounded(btn, 0.2, 6, bg)
        rl.DrawRectangleRoundedLinesEx(btn, 0.2, 6, 1, app.theme.border)
        rl.DrawTextEx(app.font.ui, strings.clone_to_cstring(label, context.temp_allocator),
            {btn.x + 12, btn.y + 6}, 14, 0, app.theme.text_primary)
    }

    if rl.CheckCollisionPointRec(mouse_pos, minus_btn) && rl.IsMouseButtonPressed(.LEFT) {
        font_change_size(&app.font, &app.config, -1)
        app_push_toast(app, "Font size decreased.")
    }
    if rl.CheckCollisionPointRec(mouse_pos, plus_btn) && rl.IsMouseButtonPressed(.LEFT) {
        font_change_size(&app.font, &app.config, 1)
        app_push_toast(app, "Font size increased.")
    }
}

sidebar_draw_node :: proc(app: ^App, node: ^Tree_Node, y: ^f32, mouse_pos: rl.Vector2, new_hovered: ^string) {
    rect   := app.layout.sidebar
    row_h  := app.font.line_height + 2  // a little more breathing room
    indent := f32(node.depth) * 14 + 6

    row_rect := rl.Rectangle{rect.x, y^, rect.width, row_h}
    is_selected := node.path == app.sidebar.selected_path
    is_hovered  := rl.CheckCollisionPointRec(mouse_pos, row_rect)

    // ── Row background ─────────────────────────────────────────────────────
    if is_selected {
        rl.DrawRectangleRounded(
            {rect.x + 3, y^ + 1, rect.width - 6, row_h - 2},
            0.3, 4, app.theme.bg_highlight)
    } else if is_hovered {
        hover_bg   := app.theme.bg_highlight
        hover_bg.a  = 90
        rl.DrawRectangleRounded(
            {rect.x + 3, y^ + 1, rect.width - 6, row_h - 2},
            0.3, 4, hover_bg)
        new_hovered^ = node.path
    }

    cx     := rect.x + indent
    mid_y  := y^ + row_h * 0.5
    text_x := cx + 20

    // ── Chevron or file icon ───────────────────────────────────────────────
    if node.is_dir {
        // Draw proper triangle chevron
        if node.expanded {
            // ▼ pointing down
            rl.DrawTriangle(
                {cx + 4,  mid_y - 3},
                {cx + 12, mid_y - 3},
                {cx + 8,  mid_y + 4},
                app.theme.text_muted)
        } else {
            // ▶ pointing right
            rl.DrawTriangle(
                {cx + 4,  mid_y - 5},
                {cx + 4,  mid_y + 5},
                {cx + 11, mid_y},
                app.theme.text_muted)
        }
    } else {
        // File icon: small rounded square
        ext := filepath.ext(node.name)
        icon_col := ext == ".odin" ? app.theme.accent : app.theme.text_disabled
        rl.DrawRectangleRounded(
            {cx + 3, mid_y - 5, 10, 12},
            0.3, 4, icon_col)
        // Fold corner
        corner_col := app.theme.bg_elevated
        rl.DrawTriangle(
            {cx + 10, mid_y - 5},
            {cx + 13, mid_y - 2},
            {cx + 10, mid_y - 2},
            corner_col)
        text_x = cx + 18
    }

    // ── Label text ─────────────────────────────────────────────────────────
    col: rl.Color
    if is_selected {
        col = app.theme.text_primary
    } else if node.is_dir {
        col = app.theme.text_primary
    } else if filepath.ext(node.name) == ".odin" {
        col = {192, 202, 245, 230}    // text_primary slightly bright
    } else {
        col = app.theme.text_muted
    }

    c_name := strings.clone_to_cstring(node.name, context.temp_allocator)
    rl.DrawTextEx(app.font.ui, c_name,
        {text_x, y^ + (row_h - app.font.font_size) * 0.5},
        app.font.font_size, 0, col)

    // ── Click handler ──────────────────────────────────────────────────────
    if is_hovered && rl.IsMouseButtonPressed(.LEFT) {
        if node.is_dir {
            node.expanded = !node.expanded
            if node.expanded && !node.children_loaded {
                sidebar_load_children(node)
            }
        } else {
            editor_open_file(app, node.path)
            app.sidebar.selected_path = node.path
        }
    }

    y^ += row_h

    if node.is_dir && node.expanded {
        for &child in node.children {
            sidebar_draw_node(app, &child, y, mouse_pos, new_hovered)
        }
    }
}

// ─── Tab Bar ──────────────────────────────────────────────────────────────────

Tab_Bar :: struct {
    scroll_x: f32,
}

tabbar_draw :: proc(app: ^App) {
    tb  := app.layout.tab_bar
    rl.DrawRectangleRec(tb, app.theme.tab_inactive_bg)

    // Bottom 1px border
    rl.DrawLineEx(
        {tb.x, tb.y + tb.height - 1},
        {tb.x + tb.width, tb.y + tb.height - 1},
        1, app.theme.border)

    tab_w     : f32 = 170
    x         := tb.x
    mouse_pos := rl.GetMousePosition()

    for i in 0..<len(app.editors) {
        e         := &app.editors[i]
        rect      := rl.Rectangle{x, tb.y, tab_w, tb.height}
        is_active := i == app.active_editor
        hov       := rl.CheckCollisionPointRec(mouse_pos, rect)

        // Tab background
        bg := is_active ? app.theme.tab_active_bg : app.theme.tab_inactive_bg
        if !is_active && hov { bg = app.theme.bg_highlight }
        rl.DrawRectangleRec(rect, bg)

        // Right separator (thin)
        sep_col := app.theme.border
        rl.DrawLineEx({x + tab_w, tb.y + 6}, {x + tab_w, tb.y + tb.height - 2}, 1, sep_col)

        // Active tab: bright top-edge accent line (like Zed)
        if is_active {
            rl.DrawRectangleRec({x, tb.y, tab_w, 2}, app.theme.tab_active_line)
        }

        // Close button rect (drawn as an X)
        close_rect := rl.Rectangle{x + tab_w - 26, tb.y + (tb.height - 18) * 0.5, 18, 18}
        close_hov  := rl.CheckCollisionPointRec(mouse_pos, close_rect)

        // Modified indicator dot OR close X
        dot_x : f32 = x + 12
        if e.is_modified && !hov && !is_active {
            // Orange unsaved dot
            rl.DrawCircle(i32(dot_x + 3), i32(tb.y + tb.height * 0.5), 4, app.theme.accent_warm)
        } else if hov || is_active {
            // Draw × as two crossed lines
            x1 := close_rect.x + 4
            y1 := close_rect.y + 4
            x2 := close_rect.x + close_rect.width - 4
            y2 := close_rect.y + close_rect.height - 4
            x_col: rl.Color = close_hov ? app.theme.text_primary : app.theme.text_muted
            if close_hov {
                rl.DrawRectangleRounded(close_rect, 0.4, 6,
                    {app.theme.text_muted.r, app.theme.text_muted.g, app.theme.text_muted.b, 50})
            }
            rl.DrawLineEx({x1, y1}, {x2, y2}, 1.5, x_col)
            rl.DrawLineEx({x2, y1}, {x1, y2}, 1.5, x_col)
        }

        // Tab label
        name    := e.file_path != "" ? filepath.base(e.file_path) : "Untitled"
        c_name  := strings.clone_to_cstring(name, context.temp_allocator)
        text_col := is_active ? app.theme.text_primary : app.theme.text_muted
        label_x  := x + 14
        if e.is_modified { label_x = x + 22 }
        rl.DrawTextEx(app.font.ui, c_name,
            {label_x, tb.y + (tb.height - app.font.font_size) * 0.5},
            app.font.font_size, 0, text_col)

        // Clicks
        if rl.IsMouseButtonPressed(.LEFT) && hov {
            if close_hov {
                _close_tab(app, i)
                app_push_toast(app, "Tab closed")
                return
            }
            app.active_editor = i
        }

        x += tab_w
    }

    // + New tab button
    plus_rect := rl.Rectangle{x + 4, tb.y + (tb.height - 22) * 0.5, 22, 22}
    plus_hov  := rl.CheckCollisionPointRec(mouse_pos, plus_rect)
    if plus_hov {
        rl.DrawRectangleRounded(plus_rect, 0.35, 6,
            {app.theme.text_muted.r, app.theme.text_muted.g, app.theme.text_muted.b, 50})
        if rl.IsMouseButtonPressed(.LEFT) { editor_new_empty(app) }
    }
    px := plus_rect.x + plus_rect.width * 0.5
    py := plus_rect.y + plus_rect.height * 0.5
    plus_col := plus_hov ? app.theme.text_primary : app.theme.text_muted
    rl.DrawLineEx({px - 5, py}, {px + 5, py}, 1.5, plus_col)
    rl.DrawLineEx({px, py - 5}, {px, py + 5}, 1.5, plus_col)
}

// ─── Status Bar ───────────────────────────────────────────────────────────────

Status_Bar :: struct {}

statusbar_draw :: proc(app: ^App) {
    sb := app.layout.status_bar
    rl.DrawRectangleRec(sb, app.theme.sb_bg)

    // Thin top shadow line
    rl.DrawLineEx({sb.x, sb.y}, {sb.x + sb.width, sb.y}, 1,
        {0, 0, 0, 60})

    font_sz  : f32 = 12
    y_center := sb.y + (sb.height - font_sz) * 0.5

    // Left block: Odin dot + version + branch
    ox : f32 = sb.x + 10
    // green Odin dot
    rl.DrawCircle(i32(ox + 4), i32(sb.y + sb.height * 0.5), 4, app.theme.sb_text)
    ox += 14

    rl.DrawTextEx(app.font.ui, "Odin dev-2026-04",
        {ox, y_center}, font_sz, 0, app.theme.sb_text)
    ox += rl.MeasureTextEx(app.font.ui, "Odin dev-2026-04", font_sz, 0).x + 10

    // Separator dot
    rl.DrawCircle(i32(ox), i32(sb.y + sb.height * 0.5), 2, app.theme.sb_text)
    ox += 10

    rl.DrawTextEx(app.font.ui, "main",
        {ox, y_center}, font_sz, 0, app.theme.sb_text)

    // Right block: cursor + encoding
    if app.active_editor >= 0 && app.active_editor < len(app.editors) {
        e       := &app.editors[app.active_editor]
        c_right := fmt.ctprintf("Ln %d, Col %d  |  Spaces: %d  |  UTF-8  |  LF",
            e.cursor.line + 1, e.cursor.col + 1, app.config.tab_size)
        right_w := rl.MeasureTextEx(app.font.ui, c_right, font_sz, 0).x
        rl.DrawTextEx(app.font.ui, c_right,
            {sb.x + sb.width - right_w - 14, y_center},
            font_sz, 0, app.theme.sb_text)
    }
}