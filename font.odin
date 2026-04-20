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
    fs.font_size = config.font_size
    fs.line_height = fs.font_size * config.line_height_mult
    
    mono_path := "assets/fonts/JetBrainsMono-Regular.ttf"
    
    // Load JetBrains Mono (we know this works from your logs!)
    if os.exists(mono_path) {
        fs.mono = rl.LoadFontEx(cstring(raw_data(mono_path)), i32(fs.font_size), nil, 0)
        rl.SetTextureFilter(fs.mono.texture, .BILINEAR)
        
        // Use the exact same high-quality font for the UI to guarantee it looks clean
        fs.ui = fs.mono 
    } else {
        // Absolute fallback (should not happen based on your logs)
        fs.mono = rl.GetFontDefault()
        fs.ui   = rl.GetFontDefault()
    }
    
    // Measure the exact width of a single monospace character
    measure := rl.MeasureTextEx(fs.mono, "M", fs.font_size, 0)
    fs.char_width = measure.x
}

font_measure_string :: proc(fs: ^Font_State, s: string) -> f32 {
    return rl.MeasureTextEx(fs.ui, cstring(raw_data(s)), fs.font_size, 0).x
}