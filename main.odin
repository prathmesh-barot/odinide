package main

import "core:os"
import rl "vendor:raylib"

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
    rl.InitWindow(1280, 800, "OdinIDE")
    rl.SetTargetFPS(120)
    defer rl.CloseWindow()

    app: App
    app_init(&app)
    defer app_destroy(&app)

    // Open file from arguments if provided
    if len(os.args) > 1 {
        editor_open_file(&app, os.args[1])
    }

    for !rl.WindowShouldClose() && !app.should_quit {
        dt := rl.GetFrameTime()

        // Handle window resize
        if rl.IsWindowResized() || app.window_width == 0 {
            app.window_width  = rl.GetScreenWidth()
            app.window_height = rl.GetScreenHeight()
            layout_recalculate(&app.layout, f32(app.window_width), f32(app.window_height))
        }

        app_update(&app, dt)

        rl.BeginDrawing()
        rl.ClearBackground(app.theme.bg_base)
        app_draw(&app)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}