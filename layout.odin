package main

import rl "vendor:raylib"

Layout :: struct {
    window:           rl.Rectangle,
    activity_bar:     rl.Rectangle,
    sidebar:          rl.Rectangle,
    tab_bar:          rl.Rectangle,
    breadcrumb_bar:   rl.Rectangle,
    editor_area:      rl.Rectangle,
    status_bar:       rl.Rectangle,

    sidebar_visible:  bool,
    sidebar_width:    f32,
    sidebar_dragging: bool,
    sidebar_drag_x:   f32,
}

layout_recalculate :: proc(layout: ^Layout, w, h: f32) {
    layout.window = {0, 0, w, h}
    
    // Y Offsets
    top_y: f32 = 0
    bottom_y := h

    // Status bar
    sb_height: f32 = 24
    layout.status_bar = {0, bottom_y - sb_height, w, sb_height}
    bottom_y -= sb_height

    // Activity bar
    ab_width: f32 = 42
    layout.activity_bar = {0, top_y, ab_width, bottom_y - top_y}

    // Sidebar
    sb_w := layout.sidebar_visible ? layout.sidebar_width : 0
    layout.sidebar = {ab_width, top_y, sb_w, bottom_y - top_y}

    // Main Area
    main_x := ab_width + sb_w
    main_w := w - main_x
    
    tab_height: f32 = 34
    layout.tab_bar = {main_x, top_y, main_w, tab_height}
    
    crumb_h: f32 = 22
    layout.breadcrumb_bar = {main_x, top_y + tab_height, main_w, crumb_h}

    layout.editor_area = {main_x, top_y + tab_height + crumb_h, main_w, bottom_y - (top_y + tab_height + crumb_h)}
}