// API and defaults mirror Omarchy 4.0.4 shell/Commons/Style.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Every token here derives from shell.toml through applyShellValues, which Color.loadShell calls, and
// resets to Omarchy's default when its key is absent.
QtObject {
    id: root

    // Hyprland's decoration:rounding; 0 anywhere else, which is also what Omarchy's failed query leaves.
    property int cornerRadius: 0

    // [controls] (or the legacy [style]) values, raw strings coerced on read.
    property var styleOverrides: ({})

    function styleNum(key, fallback) {
        var n = Number(styleOverrides[key]);
        return isFinite(n) ? n : fallback;
    }

    function styleAlpha(key, fallback) { return Util.clampAlpha(styleNum(key, fallback)); }

    function styleString(key, fallback) {
        var v = styleOverrides[key];
        if (typeof v !== "string")
            return fallback;
        v = v.replace(/^\s+|\s+$/g, "");
        return v.length > 0 ? v : fallback;
    }

    readonly property int normalBorderWidth: Math.max(0, Math.round(styleNum("normal-border-width", 1)))
    readonly property real normalFillAlpha: styleAlpha("normal-fill-alpha", 0.04)
    readonly property real hoverFillAlpha: styleAlpha("hover-cursor-fill-alpha", 0.08)
    readonly property real selectedFillAlpha: styleAlpha("selected-fill-alpha", 0.18)
    readonly property real selectionFillAlpha: styleAlpha("selection-fill-alpha", 0.35)
    readonly property real hoverBorderAlpha: styleAlpha("hover-cursor-border-alpha", 0.25)

    // #rgb, #rrggbb and #rrggbbaa, alpha LAST as Omarchy writes it; Qt.color would read #aarrggbb.
    function colorFromHex(value, fallback) {
        var s = String(value || "").replace(/^\s+|\s+$/g, "");
        var shortHex = s.match(/^#([0-9A-Fa-f]{3})$/);
        if (shortHex) {
            var sh = shortHex[1];
            return Qt.rgba(parseInt(sh.charAt(0) + sh.charAt(0), 16) / 255,
                           parseInt(sh.charAt(1) + sh.charAt(1), 16) / 255,
                           parseInt(sh.charAt(2) + sh.charAt(2), 16) / 255, 1);
        }
        var hex = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/);
        if (!hex)
            return fallback;
        var h = hex[1];
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255,
                       parseInt(h.substr(4, 2), 16) / 255, hex[2] ? parseInt(hex[2], 16) / 255 : 1);
    }

    // A state colour token is a palette role or a hex colour; anything else falls back to the foreground.
    function stateColor(key) {
        var s = styleString(key, "foreground");
        var role = s.toLowerCase();
        if (role === "foreground" || role === "text")
            return Color.foreground;
        if (role === "accent")
            return Color.accent;
        if (role === "urgent")
            return Color.urgent;
        if (role === "background")
            return Color.background;
        if (role === "transparent")
            return Qt.rgba(0, 0, 0, 0);
        return colorFromHex(s, Color.foreground);
    }

    readonly property color normalFill: Util.alpha(stateColor("normal-color"), normalFillAlpha)
    readonly property color hoverFill: Util.alpha(stateColor("hover-cursor-color"), hoverFillAlpha)
    readonly property color selectedFill: Util.alpha(stateColor("selected-color"), selectedFillAlpha)
    readonly property color selectionFill: Util.alpha(stateColor("selection-color"), selectionFillAlpha)
    readonly property color selectedAccentFill: Util.alpha(Color.accent, selectedFillAlpha)
    readonly property color hoverBorderColor: Util.alpha(stateColor("hover-cursor-color"), hoverBorderAlpha)

    // Spacing is rem-like: [spacing] scale, times the font scale unless scale-with-font is off.
    property real spacingScale: 1.0
    property bool spacingScaleWithFont: true
    property var spacingOverrides: ({})
    readonly property real effectiveSpacingScale: spacingScale * (spacingScaleWithFont ? fontScale : 1)

    function space(px) {
        var n = Number(px);
        n = isFinite(n) && n > 0 ? n * effectiveSpacingScale : 0;
        if (n <= 0)
            return 0;
        return Math.max(1, Math.round(n));
    }

    function spacingToken(key, fallback) {
        var n = Number(spacingOverrides[key]);
        return isFinite(n) && n >= 0 ? Math.round(n) : space(fallback);
    }

    readonly property QtObject spacing: QtObject {
        readonly property int hairline: root.space(1)
        readonly property int controlPaddingY: root.spacingToken("control-padding-y", 6)
        readonly property int rowGap: root.spacingToken("row-gap", 8)
        readonly property int rowPaddingX: root.spacingToken("row-padding-x", 12)
        readonly property int panelGap: root.spacingToken("panel-gap", 14)
    }

    // "monospace" is the fontconfig alias Omarchy's font tooling writes; the resolved name is for display only.
    property string resolvedFontFamily: "monospace"
    property int fontBaseSize: 12
    property var fontOverrides: ({})
    readonly property real fontScale: Math.max(1 / 12, fontBaseSize / 12)

    function fontPx(mult) {
        return Math.max(1, Math.round(fontBaseSize * mult));
    }

    function fontToken(key, fallback) {
        var n = Number(fontOverrides[key]);
        return isFinite(n) && n > 0 ? Math.round(n) : fallback;
    }

    readonly property QtObject font: QtObject {
        readonly property string family: "monospace"
        readonly property string resolvedFamily: root.resolvedFontFamily
        readonly property int baseSize: root.fontBaseSize
        readonly property int caption: root.fontToken("caption", root.fontPx(0.833))
        readonly property int bodySmall: root.fontToken("body-small", root.fontPx(0.917))
        readonly property int body: root.fontToken("body", root.fontPx(1.0))
        readonly property int icon: root.fontToken("icon", root.fontToken("title", root.fontPx(1.167)))
    }

    function boolToken(value, fallback) {
        if (value === undefined || value === null)
            return fallback;
        var s = String(value).replace(/^\s+|\s+$/g, "").toLowerCase();
        if (s === "true" || s === "1" || s === "yes" || s === "on")
            return true;
        if (s === "false" || s === "0" || s === "no" || s === "off")
            return false;
        return fallback;
    }

    // Omarchy's walk over the merged shell.toml dictionary; [bar] has no reader here, so it is skipped.
    function applyShellValues(values) {
        var fontOut = {};
        var styleOut = {};
        var spacingOut = {};
        var nextBase = 12;
        var nextScale = 1.0;
        var nextScaleWithFont = true;
        var v = values || {};
        for (var fullKey in v) {
            var dot = fullKey.indexOf(".");
            if (dot < 0)
                continue;
            var section = fullKey.substr(0, dot);
            var key = fullKey.substr(dot + 1);
            var raw = v[fullKey];
            if (section === "font") {
                var ival = parseInt(raw, 10);
                if (!isFinite(ival))
                    continue;
                if (key === "base-size")
                    nextBase = ival;
                else
                    fontOut[key] = ival;
            } else if (section === "spacing") {
                if (key === "scale-with-font") {
                    nextScaleWithFont = boolToken(raw, nextScaleWithFont);
                } else {
                    var fval = parseFloat(raw);
                    if (!isFinite(fval))
                        continue;
                    if (key === "scale")
                        nextScale = fval;
                    else
                        spacingOut[key] = fval;
                }
            } else if (section === "controls" || section === "style") {
                styleOut[key] = raw;
            }
        }
        if (!isFinite(nextBase) || nextBase < 1)
            nextBase = 1;
        if (!isFinite(nextScale) || nextScale < 0)
            nextScale = 1.0;
        spacingScale = nextScale;
        spacingScaleWithFont = nextScaleWithFont;
        fontBaseSize = nextBase;
        fontOverrides = fontOut;
        spacingOverrides = spacingOut;
        styleOverrides = styleOut;
    }

    function applyRoundingJson(raw) {
        try {
            var n = Number(JSON.parse(raw || "{}").int);
            if (isFinite(n) && n >= 0)
                cornerRadius = n;
        } catch (e) {
            // Not an answer from Hyprland; the previous value stands.
        }
    }

    // Asked of Hyprland only: elsewhere hyprctl is absent or talks to nothing, and 0 stands either way.
    function refresh() {
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            roundingQuery.running = true;
    }

    function scheduleRefresh() {
        refreshTimer.restart();
    }

    property Process roundingQuery: Process {
        command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyRoundingJson(text)
        }
    }

    // A theme switch reloads Hyprland asynchronously, so the query waits a beat, as Omarchy's does.
    property Timer refreshTimer: Timer {
        interval: 200
        repeat: false
        onTriggered: root.refresh()
    }

    property Process fontQuery: Process {
        command: ["fc-match", "-f", "%{family[0]}", "monospace"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var name = String(text || "").trim();
                if (name.length > 0)
                    root.resolvedFontFamily = name;
            }
        }
    }

    Component.onCompleted: {
        refresh();
        fontQuery.running = true;
    }
}
