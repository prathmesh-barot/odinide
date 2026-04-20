package main

import rl "vendor:raylib"

Theme :: struct {
    bg_base:         rl.Color,
    bg_elevated:     rl.Color,
    bg_highlight:    rl.Color,
    bg_active_line:  rl.Color,
    border:          rl.Color,
    text_primary:    rl.Color,
    text_muted:      rl.Color,
    text_disabled:   rl.Color,
    accent:          rl.Color,
    accent_warm:     rl.Color,

    syn_keyword:     rl.Color,
    syn_type:        rl.Color,
    syn_proc:        rl.Color,
    syn_string:      rl.Color,
    syn_number:      rl.Color,
    syn_comment:     rl.Color,
    syn_operator:    rl.Color,
    syn_punctuation: rl.Color,

    sb_bg:           rl.Color,
    sb_text:         rl.Color,
    tab_active_bg:   rl.Color,
    tab_inactive_bg: rl.Color,
    tab_active_line: rl.Color,
}

theme_odinide_dark :: proc() -> Theme {
    return Theme{
        bg_base         = {26, 27, 38, 255},      // #1A1B26
        bg_elevated     = {31, 32, 48, 255},      // #1F2030
        bg_highlight    = {41, 43, 61, 255},      // #292B3D
        bg_active_line  = {35, 36, 55, 255},      // #232437
        border          = {46, 48, 80, 255},      // #2E3050
        text_primary    = {192, 202, 245, 255},   // #C0CAF5
        text_muted      = {86, 95, 137, 255},     // #565F89
        text_disabled   = {59, 66, 97, 255},      // #3B4261
        accent          = {122, 162, 247, 255},   // #7AA2F7
        accent_warm     = {255, 158, 100, 255},   // #FF9E64

        syn_keyword     = {187, 154, 247, 255},
        syn_type        = {42, 195, 222, 255},
        syn_proc        = {122, 162, 247, 255},
        syn_string      = {158, 206, 106, 255},
        syn_number      = {255, 158, 100, 255},
        syn_comment     = {86, 95, 137, 255},
        syn_operator    = {137, 221, 255, 255},
        syn_punctuation = {192, 202, 245, 255},

        sb_bg           = {122, 162, 247, 255},
        sb_text         = {26, 27, 38, 255},
        tab_active_bg   = {26, 27, 38, 255},
        tab_inactive_bg = {22, 22, 30, 255},
        tab_active_line = {122, 162, 247, 255},
    }
}