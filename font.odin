package main

import "core:os"
import "core:strings"
import rl "vendor:raylib"

Font_State :: struct {
    mono:        rl.Font,
    ui:          rl.Font,
    font_size:   f32,
    ui_size:     f32,
    line_height: f32,
    char_width:  f32,
}

font_init :: proc(fs: ^Font_State, config: ^Config) {
    fs.font_size = config.font_size
    fs.ui_size   = config.ui_font_size
    fs.line_height = fs.font_size * config.line_height_mult

    mono_path := "assets/fonts/JetBrainsMono-Regular.ttf"
    ui_path   := "assets/fonts/Geist-Regular.ttf"

    c_mono := strings.clone_to_cstring(mono_path, context.temp_allocator)
    if os.exists(mono_path) {
        fs.mono = rl.LoadFontEx(c_mono, 32, nil, 0)
        // Smooth by default for better anti-aliased readability.
        rl.SetTextureFilter(fs.mono.texture, .BILINEAR)
    } else {
        fs.mono = rl.GetFontDefault()
    }

    c_ui := strings.clone_to_cstring(ui_path, context.temp_allocator)
    if os.exists(ui_path) {
        fs.ui = rl.LoadFontEx(c_ui, 28, nil, 0)
        // Slight smoothing gives cleaner UI chrome.
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

font_change_ui_size :: proc(fs: ^Font_State, config: ^Config, delta: f32) {
    new_size := fs.ui_size + delta
    new_size  = clamp(new_size, 11, 22)
    if new_size == fs.ui_size do return
    fs.ui_size = new_size
    config.ui_font_size = new_size
}

font_measure_string :: proc(fs: ^Font_State, s: string, use_ui := false) -> f32 {
    c_str  := strings.clone_to_cstring(s, context.temp_allocator)
    active := use_ui ? fs.ui : fs.mono
    return rl.MeasureTextEx(active, c_str, fs.font_size, 0).x
}

_snap_px :: #force_inline proc(v: f32) -> f32 {
    return f32(i32(v + 0.5))
}

draw_text_ui :: proc(fs: ^Font_State, text: cstring, pos: rl.Vector2, color: rl.Color, size: f32 = -1, spacing: f32 = 0) {
    s := size > 0 ? size : fs.ui_size
    rl.DrawTextEx(fs.ui, text, {_snap_px(pos.x), _snap_px(pos.y)}, s, spacing, color)
}

draw_text_mono :: proc(fs: ^Font_State, text: cstring, pos: rl.Vector2, color: rl.Color, size: f32 = -1, spacing: f32 = 0) {
    s := size > 0 ? size : fs.font_size
    rl.DrawTextEx(fs.mono, text, {_snap_px(pos.x), _snap_px(pos.y)}, s, spacing, color)
}