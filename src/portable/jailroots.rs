// The jail's /bin, /sbin, /lib and /lib64, copied from the host's own layout rather than assuming a
// merged /usr: a host symlink is recreated with its own target, a real directory (Alpine's /lib, which
// holds the musl loader) is bound read-only like /usr, and an absent one stays absent. The jail binds
// /usr and /etc itself, so a target into /usr resolves inside it.
use std::path::Path;
use std::sync::OnceLock;

const ROOTS: [&str; 4] = ["bin", "sbin", "lib", "lib64"];

// The bwrap arguments for a host rooted at root; each names the jail's own /<name>.
fn args_under(root: &Path) -> Vec<String> {
    let mut args = Vec::new();
    for name in ROOTS {
        let host = root.join(name);
        let jail = format!("/{}", name);
        let Ok(meta) = host.symlink_metadata() else { continue };
        if meta.file_type().is_symlink() {
            if let Ok(target) = std::fs::read_link(&host) {
                args.extend(["--symlink".to_string(), target.to_string_lossy().into_owned(), jail]);
            }
        } else if meta.is_dir() {
            args.extend(["--ro-bind".to_string(), format!("/{}", name), jail]);
        }
    }
    args
}

// Read once: the layout of / does not change under a running Flea, and every jailed tool asks.
// OnceLock, not LazyLock, which needs Rust 1.80 over the 1.77 floor.
pub fn args() -> &'static [String] {
    static ARGS: OnceLock<Vec<String>> = OnceLock::new();
    ARGS.get_or_init(|| args_under(Path::new("/")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::os::unix::fs::symlink;

    #[test]
    fn links_keep_their_target_directories_are_bound_and_absent_ones_are_skipped() {
        let dir = TestDir::new("jailroots");
        dir.dir("usr/bin");
        symlink("usr/bin", dir.join("bin")).expect("bin link");
        symlink("/usr/bin", dir.join("sbin")).expect("sbin link");
        dir.dir("lib");
        let got = args_under(dir.path());
        assert_eq!(got, ["--symlink", "usr/bin", "/bin", "--symlink", "/usr/bin", "/sbin", "--ro-bind", "/lib", "/lib"]);
    }

    #[test]
    fn a_plain_file_in_a_root_slot_is_neither_bound_nor_linked() {
        let dir = TestDir::new("jailroots-file");
        dir.file("lib64", "");
        assert!(args_under(dir.path()).is_empty());
    }

    // This host's own layout reproduced: every root it has appears, and only those.
    #[test]
    fn the_hosts_layout_is_what_the_jail_gets() {
        for name in ROOTS {
            let present = Path::new("/").join(name).symlink_metadata().is_ok();
            assert_eq!(args().iter().any(|a| *a == format!("/{}", name)), present, "/{}", name);
        }
    }
}
