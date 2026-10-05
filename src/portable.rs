// The general-Linux seams this fork adds; see FORK.md. Upstream files reach them through one-line hooks.
mod gvfsfuse;
mod qmlroot;
mod terminal;

use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};

// The qs command gui::qs_command starts from, and the entry it hands -p: ui/boot-compat when
// Omarchy's shell modules are absent, see qmlroot.
pub fn qs_command(target: PathBuf) -> (Command, PathBuf) {
    let entry = qmlroot::entry(target, std::env::var_os(qmlroot::ENV).as_deref());
    let mut cmd = Command::new("qs");
    gvfsfuse::apply(&mut cmd);
    (cmd, entry)
}

// src/terminal.rs's hook: where xdg-terminal-exec is not installed, a terminal named by $TERMINAL or a
// known emulator opens in dir instead; see terminal.
pub fn terminal_fallback(first: io::Error, dir: &Path) -> io::Result<Child> {
    terminal::fallback(first, dir)
}
