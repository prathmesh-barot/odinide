package main

import "core:os"
import "core:strings"
import rl "vendor:raylib"

Font_State :: struct {
    mono:        rl.Font,
    ui:          rl.Font,
    icons:       rl.Font,
    font_size:   f32,
    ui_size:     f32,
    line_height: f32,
    char_width:  f32,
}

font_init :: proc(fs: ^Font_State, config: ^Config) {
    fs.font_size = config.font_size
    fs.ui_size   = config.ui_font_size
    fs.line_height = fs.font_size * config.line_height_mult

    // Try JetBrains Mono first, fallback to Geist, then default
    mono_paths := []string{
        "assets/fonts/JetBrainsMono-2.304/ttf/JetBrainsMono-Regular.ttf",
        "assets/fonts/JetBrainsMono-Regular.ttf",
        "assets/fonts/Geist-Regular.ttf"
    }
    
    fs.mono = rl.GetFontDefault()
    for path in mono_paths {
        if os.exists(path) {
            c_path := strings.clone_to_cstring(path, context.temp_allocator)
            fs.mono = rl.LoadFontEx(c_path, 32, nil, 0)
            rl.SetTextureFilter(fs.mono.texture, .BILINEAR)
            break
        }
    }

    // Try Geist first for UI, fallback to JetBrains Mono, then default
    ui_paths := []string{
        "assets/fonts/Geist-Regular.ttf",
        "assets/fonts/geist-font-1.8.0/static/ttf/Geist-Regular.ttf",
        "assets/fonts/JetBrainsMono-Regular.ttf"
    }
    
    for path in ui_paths {
        if os.exists(path) {
            c_path := strings.clone_to_cstring(path, context.temp_allocator)
            fs.ui = rl.LoadFontEx(c_path, 28, nil, 0)
            rl.SetTextureFilter(fs.ui.texture, .BILINEAR)
            break
        }
    }
    
    // If UI font failed to load, use mono font as fallback
    if fs.ui.texture.id == 0 {
        fs.ui = fs.mono
    }

    // Icon loading with multiple fallback paths
    icon_paths := []string{
        "assets/icons/codicon.ttf",
        "assets/codicons-src/vscode-codicons-0.0.45/dist/codicon.ttf"
    }
    
    fs.icons = fs.ui  // Default fallback
    for path in icon_paths {
        if os.exists(path) {
            c_icon := strings.clone_to_cstring(path, context.temp_allocator)
            // Codicons use private-use Unicode codepoints. Load explicit glyphs.
            icon_codepoints := [21]rune{
                rune(60008), // source-control
                rune(60013), // search
                rune(60035), // folder
                rune(60134), // extensions
                rune(60144), // files
                rune(60152), // gear
                rune(60151), // folder-opened
                rune(60150), // folder-active
                rune(60037), // terminal
                rune(60022), // close
                rune(60198), // chevron-right
                rune(60197), // chevron-down
                rune(60313), // account
                rune(60230), // circle-large-filled
                rune(60231), // circle-large-outline
                rune(60317), // output
                rune(60001), // loading
                rune(60017), // sync
                rune(60073), // preview
                rune(60094), // debug
                rune(60010), // new-file / add
            }
            // Some codicon glyphs have large bounding boxes and raylib warns during glyph bake.
            // Suppress those warnings only for the bake step.
            rl.SetTraceLogLevel(.ERROR)
            loaded_icons := rl.LoadFontEx(c_icon, 64, raw_data(icon_codepoints[:]), len(icon_codepoints))
            rl.SetTraceLogLevel(.INFO)
            if loaded_icons.texture.id != 0 {
                fs.icons = loaded_icons
                rl.SetTextureFilter(fs.icons.texture, .BILINEAR)
                break
            }
        }
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
    // Keep sub-pixel positioning for editor text to avoid jitter while smooth scrolling.
    rl.DrawTextEx(fs.mono, text, pos, s, spacing, color)
}

draw_text_icon :: proc(fs: ^Font_State, text: cstring, pos: rl.Vector2, color: rl.Color, size: f32 = -1, spacing: f32 = 0) {
    s := size > 0 ? size : fs.ui_size
    rl.DrawTextEx(fs.icons, text, {_snap_px(pos.x), _snap_px(pos.y)}, s, spacing, color)
}