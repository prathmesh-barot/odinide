package main

import "core:os"
import rl "vendor:raylib"

Font_State :: struct {
    mono:        rl.Font,
    ui:          rl.Font,
    font_size:   f32,
    line_height: f32,
    char_width:  f32,
}

font_init :: proc(fs: ^Font_State, config: ^Config) {
    fs.font_size = 16.0 // Increased to 16 for better readability
    fs.line_height = fs.font_size * config.line_height_mult
    
    mono_path := "assets/fonts/JetBrainsMono-Regular.ttf"
    
    if os.exists(mono_path) {
        // Load at DOUBLE size (32) and use Bilinear filter for perfect crispness when scaled down to 16
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
    return rl.MeasureTextEx(fs.ui, cstring(raw_data(s)), fs.font_size, 0).x
}