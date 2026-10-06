.import "../../../ui/js/X11Copy.js" as X11Copy

// ui/Opener.qml and ui/ShareLink.qml pick wl-copy or xclip/xsel from these two answers.

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
    check("the script never holds the text", argv[2].indexOf("touch") < 0 && argv[2].indexOf("a b") < 0, true)
    check("xclip is tried first and xsel after it", argv[2].indexOf("xclip -selection clipboard") < argv[2].indexOf("xsel --clipboard"), true)
    check("a number is copied as its text", X11Copy.x11Argv(42)[4], "42")
}
