package main

import rl "vendor:raylib"

Config :: struct {
    font_size:         f32,
    tab_size:          int,
    insert_spaces:     bool,
    word_wrap:         bool,
    show_line_numbers: bool,
    show_minimap:      bool,
    line_height_mult:  f32,
    cursor_blink_ms:   f32,
    scroll_speed:      f32,
    sidebar_width:     f32,
}

config_default :: proc() -> Config {
    return Config{
        font_size         = 15,
        tab_size          = 4,
        insert_spaces     = true,
        word_wrap         = false,
        show_line_numbers = true,
        show_minimap      = false,
        line_height_mult  = 1.5,
        cursor_blink_ms   = 500,
        scroll_speed      = 3,
        sidebar_width     = 240,
    }
}