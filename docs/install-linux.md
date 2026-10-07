# Installing Flea on any Linux

This branch (`general-linux` of `t1nk333r/flea`) runs Flea without Omarchy. When Omarchy's shell
modules are absent, the launcher opens the `ui/boot-compat/` root, which carries Flea's own
`qs.Commons` and `qs.Ui` (`ui/compat/`, API and defaults mirror Omarchy 4.0.4, MIT). On an Omarchy
box nothing changes: `ui/boot/` and Omarchy's modules are used as upstream does. `FLEA_COMMONS=compat`
or `FLEA_COMMONS=omarchy` forces one root; unset or empty chooses automatically. See `FORK.md`.

Requirements: a glibc-based distro, Quickshell 0.3.1 or newer, built by your distro (it uses private
Qt API and must match the Qt it runs on), Rust 1.77 or newer to build, and a Wayland compositor or an
X11 session. musl distros (Alpine, Void musl, Chimera) are not supported: upstream links glibc-only
symbols (`pidfd_open`, `renameat2`, `close_range`, `mallopt`) in `src/heap.rs`, `src/backend/child.rs`,
`src/backend/menu_registry.rs`, `src/backend/thumbworker.rs`, `src/backend/renamecompat.rs` and
`src/backend/trashdelete.rs`, and the fork keeps upstream files untouched where it can so automatic
rebases stay conflict-free.

## Arch Linux and Arch-likes (CachyOS, EndeavourOS, Manjaro)

`PKGBUILD.generic` wraps the repo's own `PKGBUILD`: the same file list, plus the compat root, minus
the `omarchy` dependency, which is not in Arch's official repos (it becomes optional). makepkg only
reads a build file from the current directory, so run it from the repo root, and always give it a
`BUILDDIR`: without one, makepkg's `$srcdir` is the repo's `src/`, the Rust source tree, which
`--clean` and `-C` delete.

```sh
git clone -b general-linux https://github.com/t1nk333r/flea.git && cd flea
BUILDDIR=$(mktemp -d) makepkg -p PKGBUILD.generic -si
```

`-s` installs every dependency from the official repos. pacman owns the result: `pacman -Rns flea`
removes it. Never pass `--clean`/`-C` without `BUILDDIR`. The package is named `flea` and owns
`/usr/bin/flea`, like every other Flea package (`flea-bin`, `flea-git`); install one of them only.

### Picker-only: `flea-picker`

For portal file dialogs without Flea as a file manager:

```sh
BUILDDIR=$(mktemp -d) makepkg -p PKGBUILD.picker -si
flea --picker
# before package removal, each user runs:
flea --picker off
```

This package installs no app-menu entry, directory MIME association,
FileManager1 service or shelf plugin. It conflicts with `flea`, `flea-bin` and
`flea-git`; it does not satisfy dependencies asking for a file manager.
Only applications using the XDG FileChooser portal are routed, not native
nonportal dialogs. GUI/TUI browsing, `--default`, `--update`, `flea shelf` and
every other mode the picker does not use refuse; `--open`, `--terminal` and
shared picker helpers keep their contracts.
Update with the package manager, not Flea's in-app updater.

Before switching an existing full installation, each affected user must run
`flea --default off` using the full package (it also releases picker routing),
and disable/remove an existing shelf plugin through the full package if desired.
Then replace the package and run `flea --picker`. Transactions never modify home
directories or erase stale user desktop entries, FileManager1 services or plugins.
Fresh installs need only `flea --picker`; removal needs `flea --picker off`.
To switch back to full, install `flea` (for example with `PKGBUILD.generic`),
accept pacman's prompt to remove the conflicting `flea-picker`, then each user
runs `flea --default` again.
The shipped `boot/shell.qml` is a discovery sentinel, not a working file-manager
entry. Direct `qs -p .../boot/shell.qml` is unsupported.

Picker runtime requirements are Bash/coreutils, bubblewrap, D-Bus, Fontconfig,
GLib/GIO with GVFS, Python with GObject, Qt declarative (Quick, Layouts, Shapes,
XML), Quickshell >= 0.3.1, shared-mime-info, util-linux and xdg-desktop-portal.
GVFS protocol/phone backends, HEIC image decoders, video thumbnailers,
xdg-desktop-portal-gtk and a terminal handoff/emulator are optional. No Omarchy,
QtMultimedia, PDF/WebEngine, quickjs, expect or clipboard tools are required.

## Other distros: `tools/flea-install`

Build as your user, then install as root. The installer runs `PKGBUILD.generic`'s `package()` into a
staging directory, so it installs exactly what the Arch package does (minus the pacman hook), and
records every path in `/usr/share/flea/install-manifest`.

```sh
cargo build --release --locked
sudo tools/flea-install                  # --force to overwrite a foreign /usr/bin/flea
sudo tools/flea-install --uninstall      # first, each user runs: flea --default off; flea --picker off
tools/flea-install --destdir DIR         # stage elsewhere, as your own user, into a directory only you can write
tools/flea-install --picker --destdir DIR # stage the picker-only variant as your user
sudo tools/flea-install --picker         # install only after preparing full-package migration
```

The prefix is `/usr` and cannot be changed: the binary, the D-Bus service files and the portal all
name `/usr/share/flea` and `/usr/lib/flea`. It refuses to overwrite a `/usr/bin/flea` that a package
manager owns unless you pass `--force`. Rerunning it upgrades in place and removes files the new
version no longer ships. As root it installs only into `/`; it refuses a `--destdir` there, and any
symlinked directory inside the destination.

`--picker` selects the same package payload as `PKGBUILD.picker`, with licensing
under `flea-picker`. Upgrades between full and picker remove only obsolete
manifest-owned paths, including the profile marker when returning to full.
Uninstall follows the manifest regardless of variant; do not combine
`--picker` and `--uninstall`. For picker removal each user first runs
`flea --picker off`. Dependencies are never installed automatically.
For other distros, use the shared requirements below but omit full-preview,
clipboard and expect packages for picker-only. Add Qt declarative modules:
Debian's `qml6-module-qtquick`, `qml6-module-qtquick-layouts`,
`qml6-module-qtquick-shapes`, `qml6-module-qtqml-xmllistmodel`, or Fedora's
`qt6-qtdeclarative` (Nix: `qt6.qtdeclarative`), plus Bash, coreutils, D-Bus,
Fontconfig and xdg-desktop-portal. Optional protocol backends remain optional.
These mappings are installation guidance, not proof of a non-Arch runtime.

### Runtime dependencies

The Debian and Fedora names were checked on Debian sid and Fedora 44. The NixOS names were not checked
on a real system; confirm them with `nix search nixpkgs <name>`.

Debian: sid and forky ship `quickshell` 0.3.1. Trixie (13, stable) has no `quickshell` package and
only cargo 1.85.

Fedora: its own `quickshell` is a 0.2.1 snapshot, too old (the shell stops at
`Unrecognized pragma "AppId ..."`). Run `sudo dnf copr enable errornointernet/quickshell` before
installing it, and check that `qs --version` reports 0.3.1 or newer.

| Need (Arch name) | Debian sid/forky | Fedora 44 (+ COPR `errornointernet/quickshell`) | NixOS |
|---|---|---|---|
| quickshell >= 0.3.1 | `quickshell` | `quickshell` (COPR) | `quickshell` (unstable) |
| qt6-multimedia, qt6-webengine (QtQuick.Pdf) | `qml6-module-qtmultimedia`, `qml6-module-qtquick-pdf` | `qt6-qtmultimedia`, `qt6-qtpdf` | `qt6.qtmultimedia`, `qt6.qtwebengine` |
| kimageformats, libheif | `kimageformat6-plugins`, `libheif1` | `kf6-kimageformats`, `libheif` | `kdePackages.kimageformats`, `libheif` |
| glib2 (gio), gvfs, gvfs-afc, gvfs-dnssd, gvfs-gphoto2, gvfs-mtp, gvfs-nfs, gvfs-smb, usbmuxd | `libglib2.0-bin`, `gvfs`, `gvfs-backends`, `gvfs-fuse`, `usbmuxd` | `glib2`, `gvfs`, `gvfs-mtp`, `gvfs-gphoto2`, `gvfs-afc`, `gvfs-smb`, `gvfs-nfs`, `gvfs-fuse`, `usbmuxd` | `glib`, `services.gvfs.enable = true` |
| bubblewrap, util-linux (prlimit), expect | same names | same names | same names |
| python, python-gobject | `python3`, `python3-gi` | `python3`, `python3-gobject` | `python3` with `pygobject3` |
| shared-mime-info, xdg-utils, hicolor-icon-theme | same | same | same |
| wl-clipboard (Wayland) / xclip or xsel (X11) | same | same | same |
| xdg-terminal-exec (optional) | `xdg-terminal-exec` | `xdg-terminal-exec` | `xdg-terminal-exec` |
| libarchive (bsdtar, optional) | `libarchive-tools` | `bsdtar` | `libarchive` |
| build: cargo >= 1.77 | `cargo` | `cargo` | `cargo` |
| quickjs-ng (full package figures) | `qjs` (source package `quickjs-ng`) | `quickjs-ng` **[INFERENCE]**, not found in the checked Fedora 44 indexes | `quickjs` **[INFERENCE]**; confirm the NG engine |
| gcc-libs, glibc | `libgcc-s1`, `libstdc++6`, `libc6` **[INFERENCE]** | `libgcc`, `libstdc++`, `glibc` **[INFERENCE]** | `stdenv.cc.cc.lib`, `glibc` **[INFERENCE]** |
| omarchy (upstream; optional in this fork) | no package needed: fork compat modules | no package needed: fork compat modules | no package needed: fork compat modules |

The full package's figure helper defaults to `/usr/bin/qjs` (`FLEA_QJS` may
name an absolute alternative). Debian sid's `qjs` 0.17.0-1 metadata identifies
source package `quickjs-ng`, and its downloaded package contains `/usr/bin/qjs`
and `/usr/bin/qjsc`. The checked Fedora 44 image returned no matching
`quickjs-ng` package, so that mapping is **[INFERENCE]**, not a verified install.
`dependencies-doc.sh` blocks new upstream dependencies missing an Arch-column
mapping. This covers full-package requirements; picker-only does not need qjs.

`gvfsd-fuse` is looked up at `/usr/lib/gvfsd-fuse`, then `/usr/libexec/gvfsd-fuse`, then
`/usr/lib/gvfs/gvfsd-fuse` (the first executable one); set `FLEA_GVFS_FUSE` for any other path.

### NixOS

There is no derivation. A package has to substitute its store paths for the fixed ones: `FLEA_UI`
(the `ui/` directory), `FLEA_GIO_AUTH` (`flea-gio-auth`), `FLEA_GVFS_FUSE`, and the `Exec=` lines of
`packaging/org.freedesktop.impl.portal.desktop.flea.service` and
`packaging/com.thisisgm.flea.FileManager1.service`.

## After installing

Each user who wants Flea as the default file manager and file chooser runs `flea --default` (or
`flea --picker` for the file chooser alone). Outside Hyprland, or without
`~/.config/hypr/bindings.lua`, no key is bound: bind `flea --gui` in your desktop's keyboard
settings. The terminal button uses `xdg-terminal-exec` when installed, else `$TERMINAL` (a name on
`PATH` or an absolute path; any arguments in it are not passed), `x-terminal-emulator`, `foot`,
`alacritty`, `kitty` or `xterm`, each looked up only in the absolute directories of `PATH`.

## Theme

Without Omarchy, Flea uses Omarchy's default palette and type scale. To theme it, write
`~/.local/state/omarchy/current/theme/colors.toml` (keys such as `foreground`, `background`,
`accent`, `red`, `cyan`, `green` or `color0`..`color15`, as `#rrggbb`) and optionally `shell.toml`
in Omarchy's format (`[font] base-size`, `[spacing] scale`, `[controls] ...`). Flea reads them at
startup and again whenever `~/.local/state/omarchy/current/theme.name` is rewritten.
`~/.config/omarchy/shell.toml` overrides the theme's `shell.toml` key by key.

## Not available without Omarchy

The shelf bar plugin, `flea --update` (the About row shows the version without an update check),
and Hyprland key and window rules on other compositors.
