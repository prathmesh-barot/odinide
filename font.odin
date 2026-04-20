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
    
    if os.exists(mono_path) {
        fs.mono = rl.LoadFontEx(cstring(raw_data(mono_path)), 32, nil, 0)
        rl.SetTextureFilter(fs.mono.texture, .BILINEAR)
        fs.ui = fs.mono 
    } else {
        fs.mono = rl.GetFontDefault()
        fs.ui   = rl.GetFontDefault()
    }
    
    measure := rl.MeasureTextEx(fs.mono, "M", fs.font_size, 0)
    fs.char_width = measure.x
}

font_measure_string :: proc(fs: ^Font_State, s: string) -> f32 {
    c_str := strings.clone_to_cstring(s, context.temp_allocator)
    return rl.MeasureTextEx(fs.ui, c_str, fs.font_size, 0).x
}