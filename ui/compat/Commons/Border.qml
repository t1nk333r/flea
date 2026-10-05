// API and defaults mirror Omarchy 4.0.4 shell/Commons/Border.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
pragma Singleton

import QtQuick

// Flat, uniform specs only: no ui/ caller asks for a gradient or a per-side width.
QtObject {
    id: root

    function sideWidth(value) {
        var n = Number(value);
        return isFinite(n) && n > 0 ? n : 0;
    }

    function flat(color, width) {
        var w = sideWidth(width);
        return {
            color: color || "transparent",
            widths: { top: w, right: w, bottom: w, left: w },
            gradient: { colors: [], angle: 0, enabled: false }
        };
    }

    function none() {
        return flat("transparent", 0);
    }

    function top(spec) { return spec && spec.widths ? spec.widths.top : 0; }
    function right(spec) { return spec && spec.widths ? spec.widths.right : 0; }
    function bottom(spec) { return spec && spec.widths ? spec.widths.bottom : 0; }
    function left(spec) { return spec && spec.widths ? spec.widths.left : 0; }
    function uniformWidth(spec) { return spec && spec.widths ? spec.widths.top : 0; }
    function color(spec) { return spec ? spec.color : "transparent"; }
}
