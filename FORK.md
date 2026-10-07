# The general-linux fork

This repository (`t1nk333r/flea`) is a fork of `thisisgm/flea` that runs Flea on any glibc-based
Linux distro with Quickshell 0.3.1 or newer, not only on Omarchy. Nothing here is sent upstream.
Everything upstream ships keeps working the same way on an Omarchy box; the fork only adds a second
path for the boxes where Omarchy is absent.

musl distros (Alpine, Void musl, Chimera) are not supported: upstream links glibc-only symbols
(`pidfd_open`, `renameat2`, `close_range`, `mallopt`) in `src/heap.rs`, `src/backend/child.rs`,
`src/backend/menu_registry.rs`, `src/backend/thumbworker.rs`, `src/backend/renamecompat.rs` and
`src/backend/trashdelete.rs`, and the fork leaves upstream files untouched where it can, so automatic
rebases stay conflict-free. The jail's handling of a real `/lib` stays: it serves glibc systems
without a merged `/usr` too.

## Branches

| Branch | What it holds | Who moves it |
|---|---|---|
| `main` | A pure fast-forward mirror of upstream `main`. No fork commit ever lands here. | `fork-sync` |
| `general-linux` | `main` plus the fork's ordered patch stack (this file, the compat modules, the launcher seam, the fixes, packaging and the sync workflows). The fork's default branch. | `fork-sync`, or the owner by hand |

`git merge-base main general-linux` is always `main`'s tip. A sync fast-forwards `main` to upstream
and replays the patch stack on top; both refs move together in one atomic push, or neither moves.

## What the fork changes

Flea's QML imports `qs.Commons` and `qs.Ui`, two modules Omarchy owns under
`/usr/share/omarchy/shell`. Upstream reaches them through four tracked symlinks (`ui/Commons`,
`ui/Ui`, `ui/boot/Commons`, `ui/boot/Ui`); without Omarchy the shell stops at
`module "qs.Commons" is not installed`.

The fork ships its own fallback for the part of those modules Flea reads, and a second Quickshell
config root that uses it:

```
ui/compat/Commons/            qs.Commons: Border, Color, Style, Util (only what ui/ reads)
ui/compat/Ui/                 qs.Ui: PanelSectionHeader, PanelSeparator, BorderSurface
ui/compat/LICENSE.omarchy     Omarchy's MIT licence; the API and defaults mirror Omarchy 4.0.4
ui/boot-compat/*.qml      -> ../boot/*.qml         (symlinks: shell, picker, fleatab, tabtearoff)
ui/boot-compat/Commons    -> ../compat/Commons     (symlink)
ui/boot-compat/Ui         -> ../compat/Ui          (symlink)
```

`import qs.Commons` resolves against the config root, so a launch from `ui/boot-compat` reads the
fallback in the entry and in every `file:`-loaded body, while `Quickshell.shellDir` stays
`ui/boot-compat` and `shellDir + "/../WindowBody.qml"` still lands in `ui/`. The entries are
symlinks, so the pragmas (AppId, ShellId, CacheDir) are upstream's own and cannot drift. Every
`ui/boot/*.qml` gets one, because ui/ also loads `shellDir + "/fleatab.qml"` and the like;
`compat-surface.sh` goes red when upstream adds an entry the fork has not linked.

### Which root a launch uses: `FLEA_COMMONS`

The launcher (`src/portable/qmlroot.rs`, hooked into `gui::qs_command`) picks the root for both the
main window and the file chooser:

| `FLEA_COMMONS` | Root |
|---|---|
| unset or empty (auto) | `ui/boot` when `ui/boot/Commons` and `ui/boot/Ui` each open their `qmldir` or a member Flea reads (`Color.qml`, `BorderSurface.qml`; Quickshell loads a module without a `qmldir`); else `ui/boot-compat` when its entry exists; else `ui/boot` |
| `omarchy` | `ui/boot`, always |
| `compat` | `ui/boot-compat` when its entry exists, else `ui/boot` with one line on stderr |
| anything else | one line on stderr, then auto |

On an Omarchy box auto always picks `ui/boot`, byte for byte what upstream launches.
`FLEA_COMMONS=compat` lets an Omarchy user try the fallback. Dev tools that hard-code
`-p ui/boot` (`tools/flea-ipc-pid`, `omarchy-drive ipc -p ui/boot`) stay Omarchy lab tools; for a
compat launch pass `-p ui/boot-compat` to them yourself.

### Theming without Omarchy

`ui/Theme.qml` keeps reading `~/.local/state/omarchy/current/theme/{colors,shell}.toml`. With no
files the fallback's defaults equal Omarchy's out-of-the-box palette and type scale. Writing those
two files in Omarchy's format themes Flea on any distro; `~/.config/omarchy/shell.toml` overrides
them the same way it does on Omarchy.

## Picker-only installation profile

`flea-picker` ships the same binary, but owns `<prefix>/share/flea/picker-only`
with exactly `picker-only\n`. The executable-relative guard allows only the
first arguments the portal, its helpers and the picker window invoke (listed in
`src/portable/package_mode.rs`); browser, TUI, defaults, updater, shelf and any
other mode refuse with one sentence before any user writes or handoffs, so a
mode upstream adds stays refused until it is reviewed into that list.
Missing means full installation; malformed or unreadable fails closed.
UI overrides do not change the profile and development binaries stay independent.
Backend, picker, shared state and file/terminal handoffs retain their contracts.
Undo full-package defaults with `flea --default off` before switching packages;
the picker does not clean old user registrations or shelf plugins.

`tools/flea-picker-closure --repo . --output DIR` tokenizes the picker dependency
graph, follows scripts, registry types, deferred loads and static assets, and
fails on unresolved or unapproved dependencies. Its sorted file list, filtered
qmldir, module inventory and source-location reasons are generated, never tracked.
The full small compat modules are support payload; `boot/shell.qml` is only a
discovery sentinel and is not traversed or a supported direct Quickshell launch.
`picker-closure.sh` also reads the real UI a second way, with plain regexes and no
shared tokenizer: every quoted `.qml`/`.js`/`.mjs` name and every Loader `source`,
`setSource` or `createComponent` path in a listed file must resolve to a listed
file. It catches a component the generator silently drops when it is named by a
literal; a type reached only by name is left to the installed compile probe.
The review measurement is not a count contract: the actual graph also reaches
DeviceMounts' deferred PowerSectorsReader. Dependency drift must be resolved and
verified with the installed engine, not hidden by shipping the full UI.

`PKGBUILD.picker` inherits upstream's version and binary build, then adds a
picker release suffix and installs only the generated closure through
`packaging/flea-picker-install`. It conflicts with full Flea packages without
providing a file-manager capability. Its direct runtime dependencies exclude
Omarchy, multimedia, WebEngine and terminal emulators. It resets upstream's
`checkdepends`, `groups` and `backup`, and its `check()` runs only the guard's
unit tests, which need no fixture root; the picker suites run in CI. No package scriptlet or
ALPM hook changes user routing. The service still activates the existing Python
FileChooser backend; legal notices and both complete compat modules are retained.

`tools/flea-install --picker` selects that recipe without changing the default
full install. Its existing manifest and confinement rules own variant transitions
and removal; obsolete desktop/FileManager1/shelf payload is removed on a switch
to picker, and the marker is removed on a switch back. Unmanifested files remain
untouched. `picker-install.sh` exercises both directions and refusal boundaries.

`picker-load.sh [UI_DIR FLEA_BIN]` loads the installed picker offscreen in five
isolated processes: open/list, stored grid, suggested save name, folder and
SaveFiles. IPC must report the fixture path and exact rows, not merely readiness.
It also uses the closure generator's runtime graph to generate a test-only probe
against that same installed tree: every component the generator reached compiles
and every retained singleton is accessed. Because the probe list comes from the
generator, it proves the installed tree loads what the generator found, not that
the generator found everything; `picker-closure.sh`'s regex oracle covers that
for literal references. No checkout UI fallback, timeout success, missing
dependency skip or load-error whitelist is accepted. Logs survive failures.
`picker-modes.sh [FLEA_BIN]` proves refused commands, an unknown mode included,
name the picker-only install and do not execute handoffs or
change user files, while file/terminal handoffs and reversible FileChooser-only
registration still work. Neither suite opens a visible host window.
Offscreen loading is not visual or successful frontend accept/save evidence;
those remain guest-session labs. Remove a required QML and imported JS from
separate staged copies and require this load gate to fail when checking a release.

## The patch stack and when to drop each commit

| Subject | Files | Drop it when |
|---|---|---|
| `docs(fork): describe the general-linux branch` | `FORK.md` | never |
| `feat(ui): add Flea's own qs.Commons and qs.Ui` | `ui/compat/**`, `ui/boot-compat/*` | upstream stops importing Omarchy's modules, or ships its own |
| `feat(gui): open the compat root without Omarchy's shell` | `src/portable.rs`, `src/portable/qmlroot.rs`, `src/main.rs` (+1, at the head of the mod block, where upstream does not append), `src/gui.rs` (1 line) | with the commit above |
| `test(fork): guard the compat surface and root` | `tests/generic/**` | with the two commits above (keep the suites of any commit that stays) |
| `fix(defaults): skip Hyprland keys without bindings.lua` | `src/hyprkeys.rs`, `tests/modes.sh` (2 lines) | upstream handles a missing `bindings.lua` itself |
| `fix(network): hide Dropbox install without its installer` | `ui/NetworkDialog.qml` (1 line) | upstream gates the install section on its installer |
| `fix(gvfs): find gvfsd-fuse outside /usr/lib` | `src/portable/gvfsfuse.rs`, `src/portable.rs` | upstream looks beyond `/usr/lib/gvfsd-fuse` |
| `feat(terminal): fall back to a known terminal` | `src/portable/terminal.rs`, `src/portable.rs`, `src/terminal.rs` (1 line) | upstream merges PR #231 or an equivalent terminal fallback (it serves distros and plain installs without `xdg-terminal-exec`; the Arch package still depends on it, from `extra`) |
| `feat(clipboard): copy through xclip or xsel on X11` | `ui/js/X11Copy.js` (upstream's `ui/js/Clipboard.js` is its file clipboard), `ui/Opener.qml`, `ui/ShareLink.qml`, `tests/generic/js/*` | upstream merges PR #231 or an equivalent X11 clipboard |
| `build(fork): package for Arch-likes and plain installs` | `PKGBUILD.generic` (repo root: `BUILDDIR=$(mktemp -d) makepkg -p PKGBUILD.generic -si`), `packaging/flea-compat-install`, `tools/flea-install`, `docs/install-linux.md` | never |
| `ci(fork): sync upstream and rebase general-linux` | `.github/workflows/fork-*.yml`, `tools/fork-sync`, `tools/fork-verify` | never |
| `test(fork): run the X11 clipboard copy against stub tools` | `tests/generic/clipboard-x11.sh`, `tests/generic/js/clipboard.js`, `tests/generic/run.sh` | with `feat(clipboard)` |
| `test(fork): open the fallback terminal end to end` | `tests/generic/terminal-fallback.sh`, `tests/generic/run.sh` | with `feat(terminal)` |
| `fix(sandbox): mirror the host's /bin and /lib in the jail` | `src/portable/jailroots.rs`, `src/portable.rs`, `src/backend/sandbox.rs` (its four `/usr` links become one call per wrapper) | upstream's jail follows the host's own `/bin`, `/sbin`, `/lib` and `/lib64` |
| `feat(picker): guard picker-only package modes` | `src/portable/package_mode.rs`, `src/portable/package_mode_tests.rs`, `src/portable.rs`, `src/main.rs` (+1, the second hook, right after the `--backend` dispatch) | upstream ships its own picker-only package, or the fork drops `flea-picker`; review `PICKER_MODES` whenever upstream adds a mode the picker invokes |
| `build(picker): derive the picker UI closure` | `tools/flea-picker-closure`, `tools/picker/{closure,lexer,resolver}.py`, `tests/generic/picker-closure.sh`, `tests/generic/picker/{closure,oracle,sandbox}.py`, `tests/generic/run.sh` | with `feat(picker)` |
| `build(picker): add the picker-only package` | `PKGBUILD.picker`, `packaging/flea-picker-install`, `docs/install-linux.md`, `tests/generic/picker-package.sh`, `tests/generic/picker/layout.py`, `tests/generic/run.sh` | with `feat(picker)` |
| `feat(install): support picker-only plain installs` | `tools/flea-install` (`--picker`), `PKGBUILD.picker` (`!strip`), `docs/install-linux.md`, `tests/generic/picker-install.sh`, `tests/generic/picker/install.py`, `tests/generic/run.sh` | with `build(picker): add the picker-only package` |
| `test(picker): load the installed UI closure` | `tests/generic/picker-load.sh`, `tests/generic/picker-modes.sh`, `tests/generic/picker/{load,modes,probe}.py`, `tests/generic/run.sh` | with `build(picker): add the picker-only package` |

Rules every fork commit keeps, so a rebase stays cheap:

- New code lives in new files (`src/portable*`, `ui/compat`, `ui/boot-compat`, `tests/generic`,
  `tools/picker`, `PKGBUILD.generic`, `PKGBUILD.picker`, `packaging/`). An existing upstream file gets a one-line hook at most, and never grows
  past its `tools/flea-file-budget` ceiling (`src/gui.rs` sits exactly at 501, so its hook is net
  zero lines).
- `tests/run-all.sh`, `tests/js/harness.qml`, `AGENTS.md`, `README.md`, the root `PKGBUILD` and
  upstream's workflows are never edited. The one upstream test the stack touches is
  `tests/modes.sh` (two lines, in the `fix(defaults)` commit): its failing picker-window case used a
  missing `bindings.lua`, which that commit makes a skip, so the case now uses a directory there.
- Upstream's own conventions hold: Rust 1.77, zero crates, `//` comments only, the clippy ratchet,
  and the commit subject and body format of `tools/flea-commit-rules` (the author pin excepted).

## Tests the fork adds

`tests/generic/run.sh` runs every `tests/generic/*.sh`:

| Suite | Proves |
|---|---|
| `compat-surface.sh` | every `Style`/`Color`/`Border`/`Util` member and every Omarchy `qs.Ui` type `ui/` uses is declared by the fallback, and `ui/boot-compat` links every `ui/boot` entry (static; also runs in the generic PKGBUILD's `check()`) |
| `compat-parity.sh` | the fallback computes the same values as Omarchy's own modules for an empty, a stock and a hostile theme, and for the stock theme under a `~/.config/omarchy/shell.toml` override (skips when no Omarchy reference is available; `run.sh` then shows SKIP) |
| `shellload-compat.sh [UI_DIR]` | the shell loads from `boot-compat` with no load error, and with no warning the Omarchy root does not also print |
| `launch-root.sh [FLEA_BIN] [UI_DIR]` | `flea --gui` and `flea --pick` hand `qs -p` the root the table above promises |
| `js.sh` | the fork's pure JavaScript (`ui/js/X11Copy.js`) |
| `clipboard-x11.sh` | the X11 copy script hands xclip, else xsel, the exact text on the CLIPBOARD selection, reports failure when neither copies, and exits while the tool's selection owner lingers |
| `terminal-fallback.sh [FLEA_BIN]` | with no xdg-terminal-exec, `flea --terminal` opens `$TERMINAL`, else the first known emulator, in the canonical directory with no inherited pipe and its own process group, and exits 2 when none is installed |
| `picker-closure.sh` | the closure generator follows imports, registry types, deferred loads and assets in miniature trees and fails closed on nine unresolved or unapproved cases; on the real UI, a regex reading that shares nothing with its tokenizer finds no literal component or script reference outside the generated list |
| `picker-package.sh [STAGE]` | the staged package payload has the picker-only layout (portal service, pruned registry, profile marker, confined compat links) and its backend answers |
| `picker-install.sh` | `tools/flea-install --picker` switches full to picker to full, then uninstalls, with manifest pruning, payload equal to the package's, the marker only on picker, and the confinement refusals intact |
| `picker-modes.sh [FLEA_BIN]` | on a picker install every refused mode, an unknown one included, exits 2 with one sentence naming the picker-only install and touches no user file or handoff; `--open`, `--terminal`, `--ui-state`, the reveal diagnostic and reversible `--picker` routing still work |
| `picker-load.sh [UI_DIR FLEA_BIN]` | the installed picker lists exact fixture rows in five offscreen request kinds, and every component the closure generator reached compiles against the installed tree |

`FORK_OMARCHY_REF` points the parity and shell-load suites at an Omarchy `shell/` checkout (CI uses
basecamp/omarchy v4.0.4); otherwise they use `/usr/share/omarchy/shell` when it exists.

## Keeping up with upstream

### Automatic

`.github/workflows/fork-sync.yml` runs daily and on demand. Job `rebase` (no secrets) fast-forwards
a candidate `main` to upstream and replays the patch stack onto it; job `verify` builds and tests the
candidate against upstream's own result at the same base; job `publish`, the only one holding the
token, pushes both refs in one `--atomic --force-with-lease` push. A failure moves nothing and the
run summary names the commit or gate that failed.

`verify` (`.github/workflows/fork-verify.yml`) runs upstream's gates, `tests/modes.sh` and the Rust
1.77 check included, on the candidate and on upstream main, on two separate runners. On each, the
supervisor is `tools/fork-verify` taken from the published commit the workflow came from, never the
candidate's own copy; it runs as root, runs every gate as an unprivileged `build` user, and keeps
each gate's status, log and failure names in a directory only root can write, which a trusted step
uploads. A third job, which runs no candidate code, compares the two (`tools/fork-verify compare`).
`cargo test`, `tests/modes.sh` and the Rust 1.77 check block on any failing test, check or error
name upstream main does not also fail; the other upstream gates block when only the candidate is
red. `tests/modes.sh` runs with `FLEA_COMMONS=omarchy`, because it asserts upstream's `ui/boot`
launch, and off Omarchy the launcher picks `ui/boot-compat`, which `launch-root.sh` covers. The
fork's own `tests/generic/run.sh` always blocks.

Threat model: the owner and the published `general-linux` are trusted; upstream and every staged or
rebased candidate are not. Verification exists to catch accidental breakage from a rebase or an
upstream change, and the split above keeps a candidate's gates from rewriting their own verdict or
upstream's. It cannot detect deliberately malicious upstream code that passes the gates; the
protected-path acceptance below is the guard for the code that runs with the token.

`publish` refuses when upstream's `main..new main` diff touches `.github` (the directory or a file of
that name), `tools/fork-sync`, `tools/fork-verify`, or a path a fork commit adds. `publish` runs
`tools/fork-sync` from `general-linux` with the token, so these are the paths through which upstream
code could reach `FORK_SYNC_TOKEN`. Upstream edits to upstream files the fork only modifies
(`src/main.rs`, `src/gui.rs`, `ui/Opener.qml`, ...) need no acceptance: they never run with the
token, and `verify` gates them. A fork-added path stops being protected once upstream absorbs its
whole commit, so a file `tools/fork-sync` runs must be named in its list, not merely fork-added.

To accept, review exactly the upstream commit the refusal names, then rerun with that commit:

```
git fetch upstream main
git diff <old main> <new main>                    # both ids are in the refusal; read every protected path
git diff <old main> <new main> -- .github         # and the `on:` triggers of every new workflow
gh workflow run fork-sync.yml -R t1nk333r/flea -f accept_upstream_main=<new main, all 40 hex digits>
```

Accepting means accepting code that runs with the token. `publish` refuses unless upstream main is
still exactly that commit, so anything upstream pushed after the review needs a new review. A pushed
`on: push` workflow can run once before `gh workflow disable <file> -R t1nk333r/flea` stops it, so
disable any new one the fork should not run. As defense in depth, consider a required reviewer on the
`fork-sync` environment (Settings, Environments), so every publish also waits for a click.

GitHub stops `schedule` triggers after 60 days without repository activity; re-enable the workflow
from the Actions tab if that happens.

The container digest pins the image, not the pacman repositories `verify` installs from, so a
distro packaging skew reaches CI the day it lands. On 2026-10-07 Arch moved `qt6-base` to 6.12.0
while `quickshell` 0.3.1-1 was still built against 6.11.2; Quickshell uses private Qt API, so
Omarchy's own shell stops reading its `Color` singleton, and `compat-parity` fails for every
candidate with "the omarchy probe never finished" until Arch rebuilds `quickshell`. Wait it out
rather than pin Qt alone; local replays against the 2026-10-07 archive snapshot are evidence for
the fork, not for live CI. Drop this note once a live run is green again.

### By hand (a conflict, or a sync that refused)

Rebase, resolving conflicts as they come:

```
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/thisisgm/flea.git
git fetch upstream main
git fetch origin main general-linux
git switch -C general-linux origin/general-linux    # the published stack, never a stale local one
git rebase --onto upstream/main origin/main general-linux
# resolve, git add, git rebase --continue; a commit upstream absorbed can be dropped with `git rebase --skip`
```

Then review. The protected paths upstream changed are listed by a refused automatic sync, and again
by `manual` below, which refuses them unreviewed exactly like `publish`. Read them the way "To
accept" above says, including the triggers of any new workflow:

```
git diff origin/main upstream/main -- .github tools/fork-sync tools/fork-verify   # plus any fork-added path it lists
```

Then hand the result to GitHub, as a separate step, with the helper that is already published, never
the rebased checkout's own `tools/fork-sync` (upstream may have changed it; `manual` also refuses to
run when its own bytes differ from `origin/general-linux:tools/fork-sync`):

```
tmp=$(mktemp) && git show origin/general-linux:tools/fork-sync > "$tmp"
bash "$tmp" manual --accept <upstream/main, all 40 hex digits>   # or no --accept when it lists none
```

`manual` runs nothing from the candidate and verifies nothing on your machine. It refuses while a
rebase is in progress, off `general-linux`, on unmerged or uncommitted changes, when `upstream/main`
is not a fast-forward of `origin/main`, when `general-linux` is not a linear stack on top of
`upstream/main`, and, before pushing anything, when protected paths changed and `--accept` is not
exactly `upstream/main`. Then it pushes the candidate, with hooks off and leased, to the staging
branch `fork-sync/candidate` only, and starts Fork sync with `candidate_ref` (and your
`accept_upstream_main`) through `gh workflow run`. That run takes the staged commit instead of
rebasing, checks it sits linearly on upstream main, verifies it in the secretless `verify` jobs and
publishes it with the usual `publish`: `main` and `general-linux` move in one atomic leased push that
also deletes `fork-sync/candidate`. Verification and the token stay on GitHub's runners; your
checkout only builds what you choose to build in it. `tools/fork-verify` remains for CI, and for an
owner who wants to run the gates themselves in a disposable machine or container, never on a box
holding credentials, since the gates execute the candidate's code.

A drift failure (`compat-surface`, `compat-parity` or `shellload-compat` red after a sync) means
upstream started reading a `qs.Commons`/`qs.Ui` member the fallback does not have: extend
`ui/compat` to match Omarchy's definition and amend the `feat(ui)` commit.

### Do not install upstream's commit hook

Upstream's hk `commit-msg` hook pins the author to upstream's maintainer, which no fork commit can
satisfy. Do not run `hk install` in a fork clone. Fork commits still follow the subject and body
rules of `tools/flea-commit-rules`.

## One-time setup (owner)

1. Push `general-linux` and make it the default branch:
   `gh repo edit t1nk333r/flea --default-branch general-linux`.
2. Create a fine-grained token limited to `t1nk333r/flea` with Contents and Workflows read/write.
   Create the environment `fork-sync` (deployment branch `general-linux` only) and store the token
   there: `gh secret set FORK_SYNC_TOKEN --env fork-sync -R t1nk333r/flea`.
3. Protect `main`, `general-linux` and the staging branches `fork-sync/*` with a ruleset that blocks
   creating, updating, deleting and force pushing them for everyone but repository admins, so
   GitHub Actions' own token cannot move them, or stage a candidate, even if an upstream workflow
   asks for write permission; the owner, and the token, which acts as the owner, bypass it. Not
   exercised on GitHub yet: check the first Fork sync publish after creating it.
   ```
   gh api -X POST repos/t1nk333r/flea/rulesets --input - <<'EOF'
   {"name": "fork-sync branches", "target": "branch", "enforcement": "active",
    "conditions": {"ref_name": {"include": ["refs/heads/main", "refs/heads/general-linux", "refs/heads/fork-sync/*"], "exclude": []}},
    "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}],
    "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]}
   EOF
   ```
   (`actor_id` 5 is the Admin repository role.)
4. Enable Actions on the fork, which starts with workflows disabled: the Actions tab, "I understand my
   workflows, go ahead and enable them".
5. Right after, disable upstream's release workflow on the fork:
   `gh workflow disable release.yml -R t1nk333r/flea`.
6. Turn on Actions failure notifications for the account.
7. Run the gates once on `general-linux` itself:
   `gh workflow run fork-verify.yml -R t1nk333r/flea --ref general-linux`.
8. `gh workflow run fork-sync.yml -R t1nk333r/flea -f dry_run=true`, read the summary, then run it
   for real. While the fork's `main` already equals upstream's, Fork sync finds nothing to do and
   verifies and publishes nothing; the first run that has a changed candidate is the one that
   exercises the artifact handoff, the `fork-sync` environment and the token.
