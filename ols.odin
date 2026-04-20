package main

OLS_State :: struct {
    process:      uintptr,
    stdin:        uintptr,
    stdout:       uintptr,
    stderr:       uintptr,
    initialized:  bool,
    capabilities: OLS_Caps,
}

OLS_Caps :: struct {
    hover:           bool,
    completion:      bool,
    go_to_def:       bool,
    diagnostics:     bool,
    formatting:      bool,
}

ols_start :: proc(state: ^OLS_State, workspace_root: string) -> bool {
    // TODO: spawn `ols` process, open stdin/stdout pipes
    return false
}

ols_stop :: proc(state: ^OLS_State) {
    // TODO: shutdown process
}