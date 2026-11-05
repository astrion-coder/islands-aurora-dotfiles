import QtQuick
import Quickshell

// One launcher menu: the rows for what's typed, and what Enter does with a row.
// Rows: { title, subtitle, icon (theme name or path), glyph (emoji), thumb (image file),
// swatch (colour), positions, ... }
Scope {
    property string prompt: "search"
    property string placeholder: "search…"
    property string hint: ""             // shown under the search field
    property string query: ""
    property var rows: []
    property var current: null           // the selected row (set by the launcher)
    property Component preview: null     // a pane beside the list showing `current`

    // the search field should be emptied (e.g. after saving a calculation)
    signal clearQuery

    function opened() {}

    // how: "enter", "shift" (Shift+Enter), "ctrl" (Ctrl+Enter), "alt" (Alt+1),
    // "delete" (Shift+Delete). row is undefined when nothing matched.
    function activate(row, how) {}
}
