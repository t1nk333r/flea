use std::fs::File;
use std::io::{self, Read};
use std::path::Path;

#[derive(Debug, PartialEq, Eq)]
enum Refusal {
    Window,
    Terminal,
    Defaults,
    Update,
    Shelf,
    Unknown,
}

impl Refusal {
    fn message(&self) -> &'static str {
        match self {
            Self::Window => "this picker-only install has no file-manager window; install the full Flea package to browse files",
            Self::Terminal => "this picker-only install has no terminal file manager; install the full Flea package to browse files",
            Self::Defaults => "this picker-only install does not manage file-manager defaults; use flea --picker for file dialogs",
            Self::Update => "this picker-only install has no in-app updater; update flea-picker with your package manager or reinstall it from the fork",
            Self::Shelf => "this picker-only install has no shelf; install the full Flea package to use it",
            Self::Unknown => "this picker-only install does not provide that command; install the full Flea package to use it",
        }
    }
}

// The first arguments the portal, its helpers and the picker window invoke. Anything else is
// refused, so a mode upstream adds stays off a picker install until it is reviewed here.
const PICKER_MODES: &[&str] = &[
    "--backend", "--thumb-worker", "--figure-helper", "--figure-compile", "--figure-store", "--launch-warm",
    "--prewarm", "--open", "--terminal", "--picker", "--pick", "--clip", "--clip-own", "--ui-state",
    "--favourites", "--version",
];

// Helper values are never scanned as flags; only the browse parse below reads past args[1].
fn refusal(args: &[String]) -> Option<Refusal> {
    match args.get(1).map(String::as_str) {
        Some(mode) if PICKER_MODES.contains(&mode) => return None,
        Some("--default" | "--youleftmeforstrata") => return Some(Refusal::Defaults),
        Some("--update") => return Some(Refusal::Update),
        Some("shelf") => return Some(Refusal::Shelf),
        _ => {}
    }
    let mut tui = false;
    let mut window = false;
    let mut print_target = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--tui" => tui = true,
            "--print-target" => print_target = true,
            "--select" => i += 1,
            flag if flag.starts_with("--") && flag != "--gui" => return Some(Refusal::Unknown),
            _ => window = true,
        }
        i += 1;
    }
    // The reveal diagnostic opens no window: --print-target with only --select beside it.
    if print_target && !tui && !window {
        None
    } else if tui {
        Some(Refusal::Terminal)
    } else {
        Some(Refusal::Window)
    }
}

fn profile(executable: &Path) -> io::Result<bool> {
    let Some(prefix) = executable.parent().and_then(Path::parent) else {
        return Ok(false);
    };
    let marker = prefix.join("share/flea/picker-only");
    let metadata = match std::fs::symlink_metadata(&marker) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };
    if !metadata.is_file() || metadata.len() != 12 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid installation profile"));
    }
    let mut file = File::open(marker)?;
    let mut bytes = [0; 13];
    file.read_exact(&mut bytes[..12])?;
    if &bytes[..12] != b"picker-only\n" || file.read(&mut bytes[12..])? != 0 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid installation profile"));
    }
    Ok(true)
}

fn profile_error() -> ! {
    eprintln!("flea: the installation profile could not be read; reinstall the Flea package");
    std::process::exit(2);
}

pub fn picker_only(executable: &Path) -> bool {
    profile(executable).unwrap_or_else(|_| profile_error())
}

pub fn guard(args: &[String]) {
    let Some(refusal) = refusal(args) else { return };
    let executable = std::env::current_exe().unwrap_or_else(|_| profile_error());
    if picker_only(&executable) {
        eprintln!("flea: {}", refusal.message());
        std::process::exit(2);
    }
}

#[cfg(test)]
#[path = "package_mode_tests.rs"]
mod tests;
