// API and defaults mirror Omarchy 4.0.4 shell/Commons/Color.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// ui/Theme.qml reads the theme files and hands their text here, so this object only parses; the one
// file it reads itself is the machine-level shell.toml override Omarchy's own Color layers on top.
QtObject {
    id: root

    property color foreground: "#cacccc"
    property color background: "#101315"
    property color accent: "#cacccc"
    property color urgent: "#a55555"

    // "section.key" to raw string; reassigned whole, so Style re-derives on every load.
    property var shellValues: ({})
    property var themeShellValues: ({})
    property var userShellValues: ({})

    // Omarchy's grammar: explicit keys win over their colorN stand-ins, and red or color1, whichever comes last, is urgent.
    function loadColors(raw) {
        var lines = String(raw || "").split("\n");
        var found = { foreground: false, background: false, accent: false };
        var color0 = "";
        var color4 = "";
        var color7 = "";
        for (var i = 0; i < lines.length; i++) {
            var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
            if (!match)
                continue;
            var key = match[1];
            if (key === "foreground" || key === "background" || key === "accent") {
                root[key] = match[2];
                found[key] = true;
            } else if (key === "color0") {
                color0 = match[2];
            } else if (key === "color4") {
                color4 = match[2];
            } else if (key === "color7") {
                color7 = match[2];
            } else if (key === "red" || key === "color1") {
                urgent = match[2];
            }
        }
        if (!found.background && color0.length > 0)
            background = color0;
        if (!found.foreground && color7.length > 0)
            foreground = color7;
        if (!found.accent && color4.length > 0)
            accent = color4;
    }

    // Quoted strings, bare numbers, bare width lists and bare role names, inline comments allowed; values stay strings.
    function parseShell(raw) {
        var parsed = {};
        var text = String(raw || "");
        if (!text)
            return parsed;
        var lines = text.split("\n");
        var section = "";
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].replace(/^\s+|\s+$/g, "");
            if (!line || line.charAt(0) === "#")
                continue;
            var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/);
            if (sectionMatch) {
                section = sectionMatch[1];
                continue;
            }
            var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
                || line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
                || line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3})\s*(#.*)?$/)
                || line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/);
            if (!kv || !section)
                continue;
            parsed[section + "." + kv[1]] = kv[2];
        }
        return parsed;
    }

    // Theme values first, the user's override on top, so a theme switch keeps the user's keys.
    function mergeShell() {
        var merged = {};
        for (var tk in themeShellValues)
            merged[tk] = themeShellValues[tk];
        for (var uk in userShellValues)
            merged[uk] = userShellValues[uk];
        shellValues = merged;
        Style.applyShellValues(merged);
    }

    function loadShell(raw) {
        themeShellValues = parseShell(raw);
        mergeShell();
    }

    function loadUserShell(raw) {
        userShellValues = parseShell(raw);
        mergeShell();
    }

    // Where `omarchy display text size` writes; absent off Omarchy, which loads nothing.
    property FileView userShellFile: FileView {
        path: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadUserShell(text())
        // text() is stale inside the change signal, so a change reloads and lands in onLoaded.
        onFileChanged: reload()
        onLoadFailed: root.loadUserShell("")
    }
}
