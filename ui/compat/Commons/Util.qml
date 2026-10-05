// API and defaults mirror Omarchy 4.0.4 shell/Commons/Util.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
pragma Singleton

import QtQuick

QtObject {
    id: root

    function clampAlpha(value) {
        var n = Number(value);
        if (!isFinite(n))
            return 0;
        return Math.max(0, Math.min(1, n));
    }

    // A falsy colour is transparent black at the asked alpha, and a string goes through Qt.color, as Omarchy's does.
    function alpha(c, opacity) {
        var a = clampAlpha(opacity);
        if (!c)
            return Qt.rgba(0, 0, 0, a);
        if (typeof c === "string")
            c = Qt.color(c);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Each segment percent-encoded, so a space or a # in a user's path cannot break an Image source.
    function fileUrl(path) {
        if (!path)
            return "";
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }
}
