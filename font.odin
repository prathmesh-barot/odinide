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
    fs.font_size = 15.0
    fs.line_height = fs.font_size * config.line_height_mult
    
    mono_path := "assets/fonts/JetBrainsMono-Regular.ttf"
    ui_path   := "assets/fonts/Geist-Regular.ttf"
    
    c_mono := strings.clone_to_cstring(mono_path, context.temp_allocator)
    
    if os.exists(mono_path) {
        fs.mono = rl.LoadFontEx(c_mono, 32, nil, 0)
        rl.SetTextureFilter(fs.mono.texture, .BILINEAR)
    } else {
        fs.mono = rl.GetFontDefault()
    }

    c_ui := strings.clone_to_cstring(ui_path, context.temp_allocator)
    if os.exists(ui_path) {
        fs.ui = rl.LoadFontEx(c_ui, 32, nil, 0)
        rl.SetTextureFilter(fs.ui.texture, .BILINEAR)
    } else {
        fs.ui = fs.mono 
    }
    
    measure := rl.MeasureTextEx(fs.mono, "M", fs.font_size, 0)
    fs.char_width = measure.x
}

font_measure_string :: proc(fs: ^Font_State, s: string, use_ui := false) -> f32 {
    c_str := strings.clone_to_cstring(s, context.temp_allocator)
    active_font := use_ui ? fs.ui : fs.mono
    return rl.MeasureTextEx(active_font, c_str, fs.font_size, 0).x
}