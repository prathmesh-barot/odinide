package main

import "core:os"
import "core:strings"
import rl "vendor:raylib"

App :: struct {
    window_width:   i32,
    window_height:  i32,
    layout:         Layout,
    theme:          Theme,
    font:           Font_State,
    config:         Config,
    sidebar:        Sidebar,
    tabbar:         Tab_Bar,
    editors:        [dynamic]Editor_State,
    active_editor:  int,
    statusbar:      Status_Bar,
    ols:            OLS_State,
    should_quit:    bool,
}

app_init :: proc(app: ^App) {
    app.config = config_default()
    app.theme  = theme_odinide_dark()
    
    font_init(&app.font, &app.config)
    app.layout.sidebar_width   = app.config.sidebar_width
    app.layout.sidebar_visible = true
    
    sidebar_init(&app.sidebar)
    app.editors = make([dynamic]Editor_State)
    app.active_editor = -1

    ols_start(&app.ols, ".")
}

app_update :: proc(app: ^App, dt: f32) {
    input_update(app, dt)
    
    if app.active_editor >= 0 && app.active_editor < len(app.editors) {
        editor := &app.editors[app.active_editor]
        editor.scroll_offset.y = rl.Lerp(editor.scroll_offset.y, editor.target_scroll_y, dt * 20.0)
    }
}

app_draw :: proc(app: ^App) {
    rl.DrawRectangleRec(app.layout.activity_bar, app.theme.bg_elevated)
    rl.DrawLineEx({app.layout.activity_bar.x + app.layout.activity_bar.width, app.layout.activity_bar.y},
                  {app.layout.activity_bar.x + app.layout.activity_bar.width, app.layout.activity_bar.y + app.layout.activity_bar.height}, 
                  1, app.theme.border)
                  
    ax := app.layout.activity_bar.x
    rl.DrawRectangle(i32(ax + 14), i32(app.layout.activity_bar.y + 20), 10, 8, app.theme.accent)
    rl.DrawRectangle(i32(ax + 12), i32(app.layout.activity_bar.y + 22), 20, 14, app.theme.accent)
    rl.DrawCircleLines(i32(ax + 22), i32(app.layout.activity_bar.y + 70), 6, app.theme.text_muted)
    rl.DrawLineEx({ax + 26, app.layout.activity_bar.y + 74}, {ax + 32, app.layout.activity_bar.y + 80}, 2, app.theme.text_muted)
    rl.DrawCircleLines(i32(ax + 24), i32(app.layout.activity_bar.y + app.layout.activity_bar.height - 30), 8, app.theme.text_muted)
    
    if app.layout.sidebar_visible {
        sidebar_draw(app)
    }

    if len(app.editors) > 0 {
        tabbar_draw(app)
        renderer_draw_editor(app, &app.editors[app.active_editor])
    } else {
        rl.DrawRectangleRec(app.layout.editor_area, app.theme.bg_base)
        text := "OdinIDE - Press Ctrl+N to create a file"
        c_text := strings.clone_to_cstring(text, context.temp_allocator)
        w := rl.MeasureTextEx(app.font.ui, c_text, app.font.font_size, 0).x
        rl.DrawTextEx(app.font.ui, c_text, 
            {app.layout.editor_area.x + (app.layout.editor_area.width - w)/2, app.layout.editor_area.y + app.layout.editor_area.height/2}, 
            app.font.font_size, 0, app.theme.text_muted)
    }

    statusbar_draw(app)
}

app_destroy :: proc(app: ^App) {
    for &e in app.editors {
        delete(e.buffer.data)
    }
    delete(app.editors)
    ols_stop(&app.ols)
}