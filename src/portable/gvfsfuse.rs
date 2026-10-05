// Where gvfsd-fuse lives off Arch. ui/js/GvfsBridge.js starts /usr/lib/gvfsd-fuse unless
// FLEA_GVFS_FUSE names another, and Debian ships it as /usr/libexec/gvfsd-fuse and
// /usr/lib/gvfs/gvfsd-fuse, Fedora as /usr/libexec/gvfsd-fuse; so the launcher names the one that runs.
use std::ffi::OsStr;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

const ENV: &str = "FLEA_GVFS_FUSE";
// The path ui/js/GvfsBridge.js already defaults to, Arch's and so Omarchy's.
const ARCH: &str = "/usr/lib/gvfsd-fuse";
const ELSEWHERE: [&str; 2] = ["/usr/libexec/gvfsd-fuse", "/usr/lib/gvfs/gvfsd-fuse"];

// None leaves the environment alone: an operator's own value, or the box where the UI's default is right.
fn default_for(env: Option<&OsStr>, runnable: impl Fn(&Path) -> bool) -> Option<&'static str> {
    if env.is_some_and(|value| !value.is_empty()) || runnable(Path::new(ARCH)) {
        return None;
    }
    ELSEWHERE.iter().copied().find(|path| runnable(Path::new(path)))
}

// A regular file with an execute bit, symlinks followed; a bridge that cannot be started is absent.
fn runnable(path: &Path) -> bool {
    path.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

// Called on the qs command, so every window and chooser the shell starts reads the same bridge.
pub fn apply(cmd: &mut Command) {
    if let Some(path) = default_for(std::env::var_os(ENV).as_deref(), runnable) {
        cmd.env(ENV, path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn only(present: &'static [&'static str]) -> impl Fn(&Path) -> bool {
        move |path| present.iter().any(|p| Path::new(p) == path)
    }

    #[test]
    fn arch_keeps_the_uis_own_default() {
        assert_eq!(default_for(None, only(&[ARCH, "/usr/libexec/gvfsd-fuse"])), None);
    }

    #[test]
    fn debian_and_fedora_get_the_path_they_ship() {
        assert_eq!(default_for(None, only(&["/usr/libexec/gvfsd-fuse"])), Some("/usr/libexec/gvfsd-fuse"));
        assert_eq!(default_for(None, only(&["/usr/lib/gvfs/gvfsd-fuse"])), Some("/usr/lib/gvfs/gvfsd-fuse"));
        // libexec first when a box carries both.
        assert_eq!(
            default_for(None, only(&["/usr/lib/gvfs/gvfsd-fuse", "/usr/libexec/gvfsd-fuse"])),
            Some("/usr/libexec/gvfsd-fuse")
        );
    }

    #[test]
    fn an_operators_value_wins_and_an_empty_one_is_absent() {
        assert_eq!(default_for(Some(OsStr::new("/opt/fuse")), only(&["/usr/libexec/gvfsd-fuse"])), None);
        assert_eq!(default_for(Some(OsStr::new("")), only(&["/usr/libexec/gvfsd-fuse"])), Some("/usr/libexec/gvfsd-fuse"));
    }

    #[test]
    fn no_bridge_anywhere_sets_nothing() {
        assert_eq!(default_for(None, only(&[])), None);
    }

    #[test]
    fn only_an_executable_file_is_a_bridge() {
        let dir = crate::backend::testdir::TestDir::new("gvfsfuse-runnable");
        assert!(runnable(&dir.script("gvfsd-fuse", "#!/bin/sh\n")));
        assert!(!runnable(&dir.file("plain", "#!/bin/sh\n")));
        assert!(!runnable(&dir.dir("a-dir")));
        assert!(!runnable(&dir.join("absent")));
    }
}
