.import "../../../ui/js/X11Copy.js" as X11Copy

// ui/Opener.qml and ui/ShareLink.qml pick wl-copy or xclip/xsel from these two answers; what the X11
// script then copies is run against stub tools by tests/generic/clipboard-x11.sh.

function run(check) {
    check("an X display with no Wayland one is X11", X11Copy.isX11(null, ":0"), true)
    check("an exported but empty WAYLAND_DISPLAY counts as unset", X11Copy.isX11("", ":0"), true)
    check("a Wayland display wins, so XWayland keeps wl-copy", X11Copy.isX11("wayland-1", ":0"), false)
    check("no display at all keeps wl-copy, as before", X11Copy.isX11(null, null), false)
    var hostile = "a b'c\"$(touch x)`id`"
    var argv = X11Copy.x11Argv(hostile)
    check("the copy runs one fixed sh script", argv.slice(0, 2).join(" "), "sh -c")
    check("the text is the script's $1, untouched", argv[4], hostile)
    check("and nothing else follows it", argv.length, 5)
    check("a number is copied as its text", X11Copy.x11Argv(42)[4], "42")
}
