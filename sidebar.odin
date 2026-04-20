package main
import "core:fmt"
import "core:os"
import "core:path/filepath"
import rl "vendor:raylib"

Tree_Node :: struct {
    name:       string,
    path:       string,
    is_dir:     bool,
    expanded:   bool,
    depth:      int,
    children:   [dynamic]Tree_Node,
}

Sidebar :: struct {
    root:         Tree_Node,
    scroll_y:     f32,
    hovered_path: string,
    selected_path: string,
}

sidebar_init :: proc(sb: ^Sidebar) {
    sb.root = Tree_Node{
        name = "Project",
        path = ".",
        is_dir = true,
        expanded = true,
        depth = 0,
    }
    
    // Read the current directory and populate the sidebar
    f, err := os.open(sb.root.path)
    if err == nil {
        defer os.close(f)
        fis, _ := os.read_dir(f, -1, context.temp_allocator)
        for fi in fis {
            append(&sb.root.children, Tree_Node{
                name = filepath.base(fi.fullpath),
                path = fi.fullpath,
                is_dir = os.is_dir(fi.fullpath), // Fix: use os.is_dir() helper
                depth = 1,
            })
        }
    }
}

sidebar_draw :: proc(app: ^App) {
    rl.DrawRectangleRec(app.layout.sidebar, app.theme.bg_elevated)
    rl.DrawLineEx({app.layout.sidebar.x + app.layout.sidebar.width, app.layout.sidebar.y},
                  {app.layout.sidebar.x + app.layout.sidebar.width, app.layout.sidebar.y + app.layout.sidebar.height},
                  1, app.theme.border)
    
    rl.DrawTextEx(app.font.ui, "EXPLORER", {app.layout.sidebar.x + 16, app.layout.sidebar.y + 10}, 11, 0, app.theme.text_muted)
    
    y := app.layout.sidebar.y + 30
    rl.DrawTextEx(app.font.ui, cstring(raw_data(app.sidebar.root.name)), {app.layout.sidebar.x + 16, y}, app.font.font_size, 0, app.theme.text_primary)
    y += app.font.line_height
    
    mouse_pos := rl.GetMousePosition()
    
    // Draw files
    for &child in app.sidebar.root.children {
        rect := rl.Rectangle{app.layout.sidebar.x, y, app.layout.sidebar.width, app.font.line_height}
        
        // Hover and Click detection
        if rl.CheckCollisionPointRec(mouse_pos, rect) {
            rl.DrawRectangleRec(rect, app.theme.bg_highlight)
            if rl.IsMouseButtonPressed(.LEFT) && !child.is_dir {
                editor_open_file(app, child.path)
            }
        }
        
        // Highlight .odin files with the Accent color
        color := child.is_dir ? app.theme.text_primary : app.theme.text_muted
        if filepath.ext(child.name) == ".odin" do color = app.theme.accent
        
        rl.DrawTextEx(app.font.ui, cstring(raw_data(child.name)), {app.layout.sidebar.x + 32, y}, app.font.font_size, 0, color)
        y += app.font.line_height
    }
}

Tab_Bar :: struct { scroll_x: f32 }

tabbar_draw :: proc(app: ^App) {
    rl.DrawRectangleRec(app.layout.tab_bar, app.theme.bg_elevated)
    rl.DrawLineEx({app.layout.tab_bar.x, app.layout.tab_bar.y + app.layout.tab_bar.height - 1},
                  {app.layout.tab_bar.x + app.layout.tab_bar.width, app.layout.tab_bar.y + app.layout.tab_bar.height - 1},
                  1, app.theme.border)
    
    tab_w: f32 = 180
    x := app.layout.tab_bar.x
    for i in 0..<len(app.editors) {
        e := &app.editors[i]
        rect := rl.Rectangle{x, app.layout.tab_bar.y, tab_w, app.layout.tab_bar.height}
        
        bg := i == app.active_editor ? app.theme.tab_active_bg : app.theme.tab_inactive_bg
        rl.DrawRectangleRec(rect, bg)
        
        name := e.file_path != "" ? filepath.base(e.file_path) : "Untitled"
        rl.DrawTextEx(app.font.ui, cstring(raw_data(name)), {x + 16, app.layout.tab_bar.y + 10}, app.font.font_size, 0, app.theme.text_primary)
        
        if i == app.active_editor {
            rl.DrawRectangleRec({x, rect.y + rect.height - 2, tab_w, 2}, app.theme.tab_active_line)
        }
        x += tab_w
    }
}

Status_Bar :: struct {}

statusbar_draw :: proc(app: ^App) {
    
    rl.DrawRectangleRec(app.layout.status_bar, app.theme.sb_bg)
    rl.DrawCircle(i32(app.layout.status_bar.x + 14), i32(app.layout.status_bar.y + app.layout.status_bar.height / 2), 4, app.theme.sb_text)
    
    rl.DrawTextEx(app.font.ui, "Odin dev-2026-04", {app.layout.status_bar.x + 24, app.layout.status_bar.y + 6}, 11, 0, app.theme.sb_text)
    
    if app.active_editor >= 0 {
        e := &app.editors[app.active_editor]
        right_text := fmt.tprintf("Ln %d, Col %d    Spaces: %d    UTF-8", e.cursor.line + 1, e.cursor.col + 1, app.config.tab_size)
        w := font_measure_string(&app.font, right_text)
        rl.DrawTextEx(app.font.ui, cstring(raw_data(right_text)), {app.layout.status_bar.x + app.layout.status_bar.width - w - 10, app.layout.status_bar.y + 6}, 11, 0, app.theme.sb_text)
    }
}