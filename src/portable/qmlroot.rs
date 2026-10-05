// Which Quickshell config root a launch hands qs: Omarchy's ui/boot, or ui/boot-compat, whose
// Commons and Ui are Flea's own fallback (ui/compat). See FORK.md "Which root a launch uses".
use std::ffi::OsStr;
use std::fs::File;
use std::path::{Path, PathBuf};

// "omarchy" or "compat"; unset or empty chooses automatically.
pub const ENV: &str = "FLEA_COMMONS";
// A sibling of ui/boot, so its entries' shellDir + "/../" still lands in ui/.
const COMPAT_DIR: &str = "boot-compat";

#[derive(Debug, PartialEq)]
enum Want {
    Auto,
    Omarchy,
    Compat,
}

// Empty is absent, the rule paths::has_display() applies: a wrapper's unset variable is not a choice.
fn want(value: Option<&OsStr>) -> Result<Want, String> {
    let value = match value {
        Some(value) if !value.is_empty() => value,
        _ => return Ok(Want::Auto),
    };
    match value.to_str() {
        Some("omarchy") => Ok(Want::Omarchy),
        Some("compat") => Ok(Want::Compat),
        _ => Err(format!(
            "flea: {} must be omarchy or compat, got {:?}; choosing automatically",
            ENV,
            value.to_string_lossy()
        )),
    }
}

// Each module with a member Flea reads from it. A module counts when its qmldir or that member opens:
// Quickshell loads a qs. module without a qmldir, so an Omarchy that drops one must not move its users
// to the fallback. Both modules, because a shell missing either one fails the load the same way;
// opened, not just stat'ed, since the tracked links dangle on a box without Omarchy and an unreadable
// file is as absent.
const MODULES: [(&str, &str); 2] = [("Commons", "Color.qml"), ("Ui", "BorderSurface.qml")];

fn modules_readable(boot: &Path) -> bool {
    MODULES.iter().all(|(module, member)| {
        let dir = boot.join(module);
        File::open(dir.join("qmldir")).is_ok() || File::open(dir.join(member)).is_ok()
    })
}

// The entry -p gets, and the one line the operator is owed when an explicit choice could not be honoured.
fn decide(target: PathBuf, value: Option<&OsStr>) -> (PathBuf, Option<String>) {
    let (compat, readable) = match (target.parent(), target.file_name()) {
        (Some(boot), Some(name)) => match boot.parent() {
            Some(ui) => (ui.join(COMPAT_DIR).join(name), modules_readable(boot)),
            None => return (target, None),
        },
        _ => return (target, None),
    };
    let (want, note) = match want(value) {
        Ok(want) => (want, None),
        Err(line) => (Want::Auto, Some(line)),
    };
    match want {
        // An explicit opt-out is kept even when broken, so qs names the missing module as it always has.
        Want::Omarchy => (target, note),
        Want::Compat if compat.is_file() => (compat, note),
        Want::Compat => {
            let line = format!(
                "flea: {}=compat but {} is missing, so {} is used",
                ENV,
                compat.display(),
                target.display()
            );
            (target, Some(line))
        }
        // Silent: off Omarchy the compat root is the normal path, not a downgrade worth a line.
        Want::Auto if !readable && compat.is_file() => (compat, note),
        Want::Auto => (target, note),
    }
}

// target is <ui>/boot/shell.qml or <ui>/boot/picker.qml; a ui tree without boot-compat keeps it.
pub fn entry(target: PathBuf, value: Option<&OsStr>) -> PathBuf {
    let (entry, note) = decide(target, value);
    if let Some(line) = note {
        eprintln!("{}", line);
    }
    entry
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::os::unix::fs::symlink;

    // A ui tree with both roots' entries; modules: Some(true) real qmldirs, Some(false) dangling links, None absent.
    fn tree(dir: &TestDir, commons: Option<bool>, ui: Option<bool>, compat: bool) -> PathBuf {
        let root = dir.dir("ui");
        let boot = dir.dir("ui/boot");
        dir.file("ui/boot/shell.qml", "");
        dir.file("ui/boot/picker.qml", "");
        for (name, state) in [("Commons", commons), ("Ui", ui)] {
            match state {
                Some(true) => {
                    dir.dir(&format!("ui/boot/{}", name));
                    dir.file(&format!("ui/boot/{}/qmldir", name), "module qs.x\n");
                }
                Some(false) => symlink(dir.join("missing-omarchy-shell").join(name), boot.join(name)).expect("dangling link"),
                None => {}
            }
        }
        if compat {
            dir.dir("ui/boot-compat");
            dir.file("ui/boot-compat/shell.qml", "");
            dir.file("ui/boot-compat/picker.qml", "");
        }
        root
    }

    fn os(value: &str) -> Option<&OsStr> {
        Some(OsStr::new(value))
    }

    #[test]
    fn omarchy_box_keeps_its_own_root() {
        let dir = TestDir::new("qmlroot-omarchy");
        let ui = tree(&dir, Some(true), Some(true), true);
        assert_eq!(decide(ui.join("boot/shell.qml"), None), (ui.join("boot/shell.qml"), None));
    }

    #[test]
    fn dangling_modules_open_the_compat_root_for_both_entries() {
        let dir = TestDir::new("qmlroot-dangling");
        let ui = tree(&dir, Some(false), Some(false), true);
        assert_eq!(decide(ui.join("boot/shell.qml"), None), (ui.join("boot-compat/shell.qml"), None));
        assert_eq!(decide(ui.join("boot/picker.qml"), None), (ui.join("boot-compat/picker.qml"), None));
    }

    #[test]
    fn half_an_omarchy_shell_is_not_usable() {
        let dir = TestDir::new("qmlroot-half");
        let ui = tree(&dir, Some(true), Some(false), true);
        assert_eq!(decide(ui.join("boot/shell.qml"), None).0, ui.join("boot-compat/shell.qml"));
        let dir = TestDir::new("qmlroot-half-absent");
        let ui = tree(&dir, None, Some(true), true);
        assert_eq!(decide(ui.join("boot/shell.qml"), None).0, ui.join("boot-compat/shell.qml"));
    }

    #[test]
    fn a_module_without_a_qmldir_still_counts_by_its_member() {
        let dir = TestDir::new("qmlroot-members");
        let ui = tree(&dir, None, None, true);
        for (module, member) in MODULES {
            dir.dir(&format!("ui/boot/{}", module));
            dir.file(&format!("ui/boot/{}/{}", module, member), "");
        }
        assert_eq!(decide(ui.join("boot/shell.qml"), None).0, ui.join("boot/shell.qml"));
        // A member of the other module does not stand in for a missing one.
        std::fs::remove_file(dir.join("ui/boot/Ui/BorderSurface.qml")).expect("remove member");
        dir.file("ui/boot/Ui/Color.qml", "");
        assert_eq!(decide(ui.join("boot/shell.qml"), None).0, ui.join("boot-compat/shell.qml"));
    }

    #[test]
    fn explicit_omarchy_wins_over_dangling_modules() {
        let dir = TestDir::new("qmlroot-optout");
        let ui = tree(&dir, Some(false), Some(false), true);
        assert_eq!(decide(ui.join("boot/shell.qml"), os("omarchy")), (ui.join("boot/shell.qml"), None));
    }

    #[test]
    fn explicit_compat_wins_over_readable_modules() {
        let dir = TestDir::new("qmlroot-optin");
        let ui = tree(&dir, Some(true), Some(true), true);
        assert_eq!(decide(ui.join("boot/picker.qml"), os("compat")), (ui.join("boot-compat/picker.qml"), None));
    }

    #[test]
    fn missing_compat_entry_keeps_the_boot_root() {
        let dir = TestDir::new("qmlroot-nocompat");
        let ui = tree(&dir, Some(false), Some(false), false);
        let target = ui.join("boot/shell.qml");
        assert_eq!(decide(target.clone(), None), (target.clone(), None));
        let (entry, note) = decide(target.clone(), os("compat"));
        assert_eq!(entry, target);
        let note = note.expect("an unhonoured opt-in says so");
        assert!(note.contains("FLEA_COMMONS=compat") && note.contains("boot-compat/shell.qml"), "{}", note);
    }

    #[test]
    fn empty_is_auto_and_unknown_values_name_both_choices() {
        assert_eq!(want(None), Ok(Want::Auto));
        assert_eq!(want(os("")), Ok(Want::Auto));
        for bad in ["Compat", "x"] {
            let line = want(os(bad)).expect_err("only the two lower-case names are choices");
            assert!(line.contains("omarchy or compat") && line.contains(&format!("{:?}", bad)), "{}", line);
        }
        let dir = TestDir::new("qmlroot-unknown");
        let ui = tree(&dir, Some(false), Some(false), true);
        let (entry, note) = decide(ui.join("boot/shell.qml"), os("x"));
        assert_eq!(entry, ui.join("boot-compat/shell.qml"));
        assert!(note.is_some());
    }
}
