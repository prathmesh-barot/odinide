package main

import "core:encoding/json"

LSP_Position :: struct {
    line:      int `json:"line"`,
    character: int `json:"character"`,
}

LSP_Range :: struct {
    start: LSP_Position `json:"start"`,
    end:   LSP_Position `json:"end"`,
}

LSP_Location :: struct {
    uri:   string    `json:"uri"`,
    range: LSP_Range `json:"range"`,
}

LSP_Diagnostic_Severity :: enum int {
    Error = 1,
    Warning,
    Information,
    Hint,
}

LSP_Diagnostic :: struct {
    range:    LSP_Range                `json:"range"`,
    severity: ^LSP_Diagnostic_Severity `json:"severity,omitempty"`,
    message:  string                   `json:"message"`,
    source:   ^string                  `json:"source,omitempty"`,
}

LSP_Completion_Kind :: enum int {
    Text = 1,
    Method,
    Function,
    Constructor,
    Field,
    Variable,
    Class,
    Interface,
    Module,
    Property,
    Unit,
    Value,
    Enum,
    Keyword,
    Snippet,
    Color,
    File,
    Reference,
    Folder,
    EnumMember,
    Constant,
    Struct,
    Event,
    Operator,
    TypeParameter,
}

LSP_Completion_Item :: struct {
    label:         string               `json:"label"`,
    kind:          ^LSP_Completion_Kind `json:"kind,omitempty"`,
    detail:        ^string              `json:"detail,omitempty"`,
    documentation: ^string              `json:"documentation,omitempty"`,
    insertText:    ^string              `json:"insertText,omitempty"`,
    sortText:      ^string              `json:"sortText,omitempty"`,
}

LSP_Completion_List :: struct {
    isIncomplete: bool                 `json:"isIncomplete"`,
    items:        []LSP_Completion_Item `json:"items"`,
}

LSP_Hover :: struct {
    contents: json.Value  `json:"contents"`,
    range:    ^LSP_Range  `json:"range,omitempty"`,
}

