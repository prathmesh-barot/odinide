package main

import "core:fmt"
import "core:os"
import "core:strings"

_config_dir :: proc() -> string {
    home := os.get_env_alloc("HOME", context.temp_allocator)
    if home != "" {
        return fmt.tprintf("%s/.config/odinide", home)
    }
    return ".odinide"
}

_config_path :: proc() -> string {
    return fmt.tprintf("%s/config.json", _config_dir())
}

config_load :: proc(config: ^Config) -> bool {
    // Keep defaults if file is missing or malformed.
    path := _config_path()
    bytes, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil || len(bytes) == 0 {
        return config_save(config)
    }
    src := string(bytes)
    // Minimal parse for the values we currently persist.
    if strings.contains(src, "\"show_line_numbers\": false") {
        config.show_line_numbers = false
    }
    return true
}

config_save :: proc(config: ^Config) -> bool {
    dir := _config_dir()
    _ = os.make_directory_all(dir)
    body := fmt.tprintf("{\n  \"font_size\": %.1f,\n  \"tab_size\": %d,\n  \"insert_spaces\": %v,\n  \"show_line_numbers\": %v,\n  \"line_height_mult\": %.2f,\n  \"cursor_blink_ms\": %.0f,\n  \"scroll_speed\": %.1f,\n  \"sidebar_width\": %.1f,\n  \"theme\": \"odinide-dark\"\n}\n",
        config.font_size, config.tab_size, config.insert_spaces, config.show_line_numbers,
        config.line_height_mult, config.cursor_blink_ms, config.scroll_speed, config.sidebar_width)
    err := os.write_entire_file(_config_path(), transmute([]u8)body)
    return err == nil
}
