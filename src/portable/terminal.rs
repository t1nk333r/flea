// The terminal Flea opens when xdg-terminal-exec is not installed, which some distros and plain
// installs lack. Each candidate resolves to an absolute executable before the terminal's working
// directory is set, through PATH's absolute entries only, so nothing is looked up inside the directory
// being opened; it starts with no arguments, so no emulator's own flag syntax is assumed.
use std::ffi::{OsStr, OsString};
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};

const KNOWN: [&str; 5] = ["x-terminal-emulator", "foot", "alacritty", "kitty", "xterm"];

// $TERMINAL's first word comes first, a bare name or an absolute path; a relative path is skipped.
// The bool is true when $TERMINAL held more words, which are not passed and are owed one line.
fn candidates(terminal: Option<&OsStr>) -> (Vec<OsString>, bool) {
    let mut names: Vec<OsString> = Vec::new();
    let mut more = false;
    if let Some(value) = terminal {
        let mut words = value.as_bytes().split(|b| b.is_ascii_whitespace()).filter(|w| !w.is_empty());
        if let Some(first) = words.next() {
            more = words.next().is_some();
            if first.starts_with(b"/") || !first.contains(&b'/') {
                names.push(OsStr::from_bytes(first).to_os_string());
            }
        }
    }
    for name in KNOWN.iter().map(OsStr::new) {
        if !names.iter().any(|n| n.as_os_str() == name) {
            names.push(name.to_os_string());
        }
    }
    (names, more)
}

// A regular file with an execute bit, symlinks followed: what execve would at least try.
fn executable(path: &Path) -> bool {
    path.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

// An absolute name stands for itself; a bare one is the first absolute PATH entry holding it as an
// executable. Empty and relative entries are skipped: they would resolve against a working directory.
fn resolve(name: &OsStr, path: Option<&OsStr>, executable: impl Fn(&Path) -> bool) -> Option<PathBuf> {
    let name = Path::new(name);
    if name.is_absolute() {
        return executable(name).then(|| name.to_path_buf());
    }
    std::env::split_paths(path?).filter(|dir| dir.is_absolute()).map(|dir| dir.join(name)).find(|p| executable(p))
}

// A candidate that is absent or may not be run moves on; a start or any other refusal is the answer.
// None: nothing answered.
fn try_each<T>(names: &[OsString], mut spawn: impl FnMut(&OsStr) -> io::Result<T>) -> Option<io::Result<T>> {
    for name in names {
        match spawn(name) {
            Err(e) if matches!(e.kind(), io::ErrorKind::NotFound | io::ErrorKind::PermissionDenied) => continue,
            other => return Some(other),
        }
    }
    None
}

// first is xdg-terminal-exec's own failure; only its absence falls back, and nothing starting keeps it.
pub fn fallback(first: io::Error, dir: &Path) -> io::Result<Child> {
    if first.kind() != io::ErrorKind::NotFound {
        return Err(first);
    }
    let (names, more) = candidates(std::env::var_os("TERMINAL").as_deref());
    if more {
        eprintln!("flea: $TERMINAL holds arguments, which are not passed; its first word is started without them");
    }
    let path = std::env::var_os("PATH");
    let started = try_each(&names, |name| {
        let program = resolve(name, path.as_deref(), executable).ok_or_else(|| io::Error::from(io::ErrorKind::NotFound))?;
        let mut terminal = Command::new(program);
        crate::terminal::detach(&mut terminal);
        terminal.current_dir(dir).spawn()
    });
    started.unwrap_or(Err(first))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    fn names(terminal: &str) -> (Vec<String>, bool) {
        let (list, more) = candidates(Some(OsStr::new(terminal)));
        (list.iter().map(|n| n.to_string_lossy().into_owned()).collect(), more)
    }

    #[test]
    fn terminal_comes_first_as_a_bare_name_or_an_absolute_path_and_never_twice() {
        assert_eq!(names("wezterm").0[..2], ["wezterm", "x-terminal-emulator"]);
        assert_eq!(names("/opt/wez/wezterm").0[0], "/opt/wez/wezterm");
        assert_eq!(names("bin/wezterm").0, KNOWN.to_vec());
        assert_eq!(names("").0, KNOWN.to_vec());
        assert_eq!(names(" \t").0, KNOWN.to_vec());
        assert_eq!(candidates(None), (KNOWN.iter().map(OsString::from).collect(), false));
        let foot = names("foot").0;
        assert_eq!(foot[0], "foot");
        assert_eq!(foot.iter().filter(|n| *n == "foot").count(), 1);
        assert!(!names("wezterm").1);
    }

    #[test]
    fn a_terminal_with_arguments_starts_its_first_word_and_says_the_rest_is_dropped() {
        assert_eq!(names("kitty -1"), (vec!["kitty".to_string(), "x-terminal-emulator".into(), "foot".into(), "alacritty".into(), "xterm".into()], true));
        let (list, more) = names("  /usr/bin/wezterm start --cwd x");
        assert_eq!((list[0].as_str(), more), ("/usr/bin/wezterm", true));
    }

    // The relative spelling of an absolute directory, against this process's working directory.
    fn relative(abs: &Path) -> PathBuf {
        let cwd = std::env::current_dir().expect("cwd");
        let mut rel: PathBuf = cwd.components().skip(1).map(|_| "..").collect();
        rel.push(abs.strip_prefix("/").expect("absolute"));
        rel
    }

    #[test]
    fn resolution_uses_absolute_path_entries_and_skips_what_cannot_run() {
        let dir = TestDir::new("terminal-resolve");
        let shadow = dir.dir("shadow");
        let bin = dir.dir("bin");
        let foot = dir.script("bin/foot", "#!/bin/sh\n");
        dir.file("shadow/foot", "#!/bin/sh\n");
        dir.script("shadow/kitty", "#!/bin/sh\n");
        let path = std::env::join_paths([relative(&shadow), PathBuf::new(), shadow.clone(), bin.clone()]).expect("PATH");
        // The relative entry would reach shadow/kitty from here, yet only the absolute ones count.
        assert!(executable(&relative(&shadow).join("kitty")));
        assert_eq!(resolve(OsStr::new("kitty"), Some(&path), executable), Some(shadow.join("kitty")));
        let rel_only = std::env::join_paths([relative(&shadow), PathBuf::from("."), PathBuf::new()]).expect("PATH");
        assert_eq!(resolve(OsStr::new("kitty"), Some(&rel_only), executable), None);
        // shadow/foot has no execute bit, so the walk goes on to bin/foot.
        assert_eq!(resolve(OsStr::new("foot"), Some(&path), executable), Some(foot.clone()));
        assert_eq!(resolve(OsStr::new("foot"), None, executable), None);
        assert_eq!(resolve(foot.as_os_str(), None, executable), Some(foot));
        assert_eq!(resolve(dir.join("shadow/foot").as_os_str(), Some(&path), executable), None);
        assert_eq!(resolve(bin.as_os_str(), Some(&path), executable), None);
    }

    #[test]
    fn the_walk_skips_absent_and_refused_names_and_stops_on_a_start_or_another_error() {
        let list = candidates(None).0;
        let mut asked = Vec::new();
        let found = try_each(&list, |name| {
            asked.push(name.to_string_lossy().into_owned());
            match name.to_str() {
                Some("alacritty") => Ok(7),
                Some("foot") => Err(io::Error::from(io::ErrorKind::PermissionDenied)),
                _ => Err(io::Error::from(io::ErrorKind::NotFound)),
            }
        });
        assert_eq!(found.expect("alacritty answered").expect("started"), 7);
        assert_eq!(asked, ["x-terminal-emulator", "foot", "alacritty"]);

        let broken: Option<io::Result<()>> = try_each(&list, |name| {
            if name == "foot" { Err(io::Error::from(io::ErrorKind::InvalidData)) } else { Err(io::Error::from(io::ErrorKind::NotFound)) }
        });
        assert_eq!(broken.expect("foot answered").expect_err("refused").kind(), io::ErrorKind::InvalidData);

        let none: Option<io::Result<()>> = try_each(&list, |_| Err(io::Error::from(io::ErrorKind::PermissionDenied)));
        assert!(none.is_none());
    }
}
