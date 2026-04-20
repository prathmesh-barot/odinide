package main

import "core:os"
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

    // Using "." for current working directory to bypass core:os API flux
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
    
    if app.layout.sidebar_visible {
        sidebar_draw(app)
    }

    if len(app.editors) > 0 {
        tabbar_draw(app)
        renderer_draw_editor(app, &app.editors[app.active_editor])
    } else {
        rl.DrawRectangleRec(app.layout.editor_area, app.theme.bg_base)
        text := "OdinIDE - Press Ctrl+N to create a file"
        w := font_measure_string(&app.font, text)
        rl.DrawTextEx(app.font.ui, cstring(raw_data(text)), 
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