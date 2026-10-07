use super::{profile, refusal, Refusal};
use std::fs;

fn classify(args: &[&str]) -> Option<Refusal> {
    refusal(&std::iter::once("flea").chain(args.iter().copied()).map(str::to_owned).collect::<Vec<_>>())
}

#[test]
fn unavailable_modes_and_reveal_values() {
    for args in [vec![], vec!["/tmp"], vec!["--gui", "/tmp"], vec!["--select", "/tmp/--tui"], vec!["--select", "/tmp/a", "--print-target", "/tmp"]] {
        assert_eq!(classify(&args), Some(Refusal::Window), "{args:?}");
    }
    for args in [vec!["--tui", "/tmp"], vec!["--tui", "--gui"]] {
        assert_eq!(classify(&args), Some(Refusal::Terminal), "{args:?}");
    }
    for args in [vec!["--default"], vec!["--default", "off"], vec!["--default", "wrong"], vec!["--youleftmeforstrata"]] {
        assert_eq!(classify(&args), Some(Refusal::Defaults), "{args:?}");
    }
    for args in [vec!["--update"], vec!["--update", "check"], vec!["--update", "wrong"]] {
        assert_eq!(classify(&args), Some(Refusal::Update), "{args:?}");
    }
    assert_eq!(classify(&["shelf", "status"]), Some(Refusal::Shelf));
}

#[test]
fn a_mode_the_picker_does_not_name_is_refused() {
    for args in [vec!["--unknown"], vec!["--new-upstream-window"], vec!["/tmp", "--unknown"], vec!["--select", "/tmp/a", "--gu"]] {
        assert_eq!(classify(&args), Some(Refusal::Unknown), "{args:?}");
    }
}

#[test]
fn picker_helpers_and_the_reveal_diagnostic_do_not_read_profile() {
    for args in [
        vec!["--open", "/tmp/--gui"], vec!["--terminal", "/tmp/--tui"],
        vec!["--pick", "--gui"], vec!["--picker"], vec!["--picker", "off"],
        vec!["--ui-state", "{}"], vec!["--backend"], vec!["--thumb-worker"],
        vec!["--prewarm", "/tmp", "1", "/tmp/out"], vec!["--launch-warm", "-", "-", "-"],
        vec!["--clip", "get"], vec!["--clip-own"], vec!["--favourites"], vec!["--figure-helper"],
        vec!["--figure-compile"], vec!["--figure-store"],
        vec!["--select", "/tmp/a", "--print-target"], vec!["--print-target", "--select", "/tmp/--gui"],
    ] {
        assert_eq!(classify(&args), None, "{args:?}");
    }
}

#[test]
fn profile_is_executable_relative_and_rejects_bad_markers() {
    let root = std::env::temp_dir().join(format!("flea-profile-{}", std::process::id()));
    fs::create_dir_all(root.join("usr/share/flea")).unwrap();
    let executable = root.join("usr/bin/flea");
    let marker = root.join("usr/share/flea/picker-only");
    assert!(!profile(&executable).unwrap());
    fs::write(&marker, b"picker-only\n").unwrap();
    assert!(profile(&executable).unwrap());
    assert!(!profile(&root.join("dev/target/flea")).unwrap());
    for bad in [b"picker-only".as_slice(), b"full-------\n", b"picker-only\nextra", b""] {
        fs::write(&marker, bad).unwrap();
        assert!(profile(&executable).is_err());
    }
    fs::remove_file(&marker).unwrap();
    fs::create_dir(&marker).unwrap();
    assert!(profile(&executable).is_err());
    fs::remove_dir_all(root).unwrap();
}
