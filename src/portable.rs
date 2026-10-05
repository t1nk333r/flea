// The general-Linux seams this fork adds; see FORK.md. Upstream files reach them through one-line hooks.
mod gvfsfuse;
mod qmlroot;

use std::path::PathBuf;
use std::process::Command;

// The qs command gui::qs_command starts from, and the entry it hands -p: ui/boot-compat when
// Omarchy's shell modules are absent, see qmlroot.
pub fn qs_command(target: PathBuf) -> (Command, PathBuf) {
    let entry = qmlroot::entry(target, std::env::var_os(qmlroot::ENV).as_deref());
    let mut cmd = Command::new("qs");
    gvfsfuse::apply(&mut cmd);
    (cmd, entry)
}
