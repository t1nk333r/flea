.pragma library

// fork: the X11 clipboard route for Copy Path and share links; see FORK.md. Wayland keeps wl-copy.

// X11 only when there is no Wayland display and there is an X one, src/vulkan.rs's rule;
// Quickshell.env answers null for an unset variable, and an empty one counts as unset.
function isX11(waylandDisplay, display) {
    return !waylandDisplay && !!display
}

// The text rides as $1 and is never spliced into the script. Both tools fork a selection owner that
// would keep the Process pipes open, so their output goes to /dev/null and the copy can finish.
function x11Argv(text) {
    return ["sh", "-c",
            "printf '%s' \"$1\" | xclip -selection clipboard -in >/dev/null 2>&1 || printf '%s' \"$1\" | xsel --clipboard --input >/dev/null 2>&1",
            "_", String(text)]
}
