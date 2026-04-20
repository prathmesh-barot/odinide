package main

import "core:os"
import "core:strings"
import rl "vendor:raylib"

Font_State :: struct {
    mono:        rl.Font,
    ui:          rl.Font,
    font_size:   f32,
    line_height: f32,
    char_width:  f32,
}

font_init :: proc(fs: ^Font_State, config: ^Config) {
    fs.font_size   = config.font_size
    fs.line_height = fs.font_size * config.line_height_mult

    mono_path := "assets/fonts/JetBrainsMono-Regular.ttf"
    ui_path   := "assets/fonts/Geist-Regular.ttf"

    c_mono := strings.clone_to_cstring(mono_path, context.temp_allocator)
    if os.exists(mono_path) {
        fs.mono = rl.LoadFontEx(c_mono, 128, nil, 0)
        rl.SetTextureFilter(fs.mono.texture, .BILINEAR)
    } else {
        fs.mono = rl.GetFontDefault()
    }

    c_ui := strings.clone_to_cstring(ui_path, context.temp_allocator)
    if os.exists(ui_path) {
        fs.ui = rl.LoadFontEx(c_ui, 128, nil, 0)
        rl.SetTextureFilter(fs.ui.texture, .BILINEAR)
    } else {
        fs.ui = fs.mono
    }

    font_recompute_metrics(fs, config)
}

font_recompute_metrics :: proc(fs: ^Font_State, config: ^Config) {
    fs.line_height = fs.font_size * config.line_height_mult
    measure        := rl.MeasureTextEx(fs.mono, "M", fs.font_size, 0)
    fs.char_width  = measure.x
}

font_change_size :: proc(fs: ^Font_State, config: ^Config, delta: f32) {
    new_size := fs.font_size + delta
    new_size  = clamp(new_size, 10, 24)
    if new_size == fs.font_size do return
    fs.font_size    = new_size
    config.font_size = new_size
    font_recompute_metrics(fs, config)
}

font_measure_string :: proc(fs: ^Font_State, s: string, use_ui := false) -> f32 {
    c_str  := strings.clone_to_cstring(s, context.temp_allocator)
    active := use_ui ? fs.ui : fs.mono
    return rl.MeasureTextEx(active, c_str, fs.font_size, 0).x
}