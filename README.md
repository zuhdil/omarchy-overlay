# omarchy-overlay

My customisations layered over a stock [Omarchy](https://omarchy.org) install.

Nothing here replaces Omarchy's own files. Everything is an *overlay*: a drop-in
that sorts after theirs, an append to a file they regenerate, a symlink beside
their defaults, or a single key edited in a file a package owns. Omarchy updates
keep working; my preferences ride on top.

```sh
git clone <repo-url> ~/.config/omarchy-overlay
cd ~/.config/omarchy-overlay
./install --dry-run     # see exactly what would change
./install               # apply
```

Re-running is safe. On a configured machine every line reports `ok`.

Installing packages needs a **terminal** — `omarchy pkg add` prompts for a
password and manages its own privilege escalation. Run from a script or a hook
and missing packages are reported with the command to run, rather than failing.

## Usage

```sh
./install                    # all modules
./install <module>           # just one
./install --list             # what's available
./install --dry-run          # no sudo, no writes, full report
./install --no-packages      # report missing packages instead of installing them
```

## The overlay techniques

Every mechanism here leaves Omarchy's own files intact:

| Situation | Technique | Example |
| --- | --- | --- |
| Omarchy regenerates the file | append idempotently | `autostart.lua` — `omarchy refresh hyprland` rewrites it |
| Must load before an early `return` | insert above the anchor | `~/.bashrc`, above its interactive guard |
| A package owns the file | edit only the keys needed | `/etc/UPower/UPower.conf`, so a `.pacnew` still carries the rest |
| A drop-in directory exists | add a file that sorts after theirs | `/etc/systemd/logind.conf.d/50-hibernate.conf` |
| Plain user config | symlink it | `~/.config/hypr/hypridle.conf` |

## How files reach the system

| Directory | Mechanism | Why |
| --- | --- | --- |
| `modules/*/home/` | **symlinked** into `$HOME` | editing the live file edits the repo — no sync step, nothing to forget |
| `modules/*/system/` | **copied** to `/` as root | this repo is user-writable; root must not read policy, or run sudo'd scripts, from a path you can rewrite |

That second row is a security boundary, not a style choice. A symlinked
`/usr/local/bin/hibernation-check` would mean `sudo hibernation-check` executes
a user-writable file as root.

Existing files are backed up as `<file>.bak.<epoch>` before being replaced —
Omarchy's own convention — and the backup is removed again if the content turned
out to be identical, so repeated runs leave no litter.

## `$OMARCHY_OVERLAY_DIR`

`modules/shell/env.sh` exports it, derived from that file's own location rather
than hardcoded, so the repo can be cloned anywhere — only `~/.bashrc`'s source
line points at a fixed path, and `install` writes that. `install` exports the
same value for modules and anything they call.

```sh
echo $OMARCHY_OVERLAY_DIR        # /home/you/.config/omarchy-overlay
```

Scripts should prefer it over a hardcoded path, with the default location as a
fallback for the case where the shell has not sourced `env.sh`:

```sh
REPO=${OMARCHY_OVERLAY_DIR:-$HOME/.config/omarchy-overlay}
```

## Modules

| Module | What it does |
| --- | --- |
| `hibernation` | Makes hibernate actually resume on this hybrid Intel+NVIDIA laptop, then wires up lid, idle and critical-battery triggers. See its `docs/hibernation.md`. |
| `git` | `git lg` (graph) and `git lgs` (signature column) log aliases, enforced commit and tag signing, and the SSH and GPG keys uploaded to GitHub if they are not there already. |
| `container-engine` | `toggle-container-engine` switches docker/compose between Podman and Docker. Selecting Podman also sets `DOCKER_BUILDKIT=0`, because Podman's API does not serve BuildKit and builds otherwise hang. |
| `shell` | Shared shell config, split by interactivity and sourced from `~/.bashrc`. `rc.sh` sets `GPG_TTY`, which commit signing needs wherever pinentry has no GUI. |

## What is never committed

Machine-specific values. Copying them to another machine produces a system that
looks fine and silently misbehaves:

- **`resume_offset`** — the physical offset of *this* swapfile. `omarchy
  hibernation setup` generates it per machine; the module refuses to run without it.
- **`/etc/mkinitcpio.conf.d/nvidia.conf`** — removing NVIDIA from the initramfs
  is correct on a *hybrid* machine and wrong on an NVIDIA-only one, where it is
  the early KMS. The module branches on `omarchy-hw-hybrid-gpu`.
- **`/etc/UPower/UPower.conf`** — package-owned. Keys are edited in place so a
  future `.pacnew` still carries everything else.
- **`~/.bashrc`** — Omarchy seeds it and it collects per-machine settings. Shared
  shell config lives in `modules/shell/`, wired in with two source lines.
- **The selected container engine** — a local choice, recorded as a symlink under
  `~/.local/state/omarchy-overlay/`. The repo ships the options, not the pick.
- **`user.signingkey`** — another machine has another GPG key. The `git` module
  derives it from the local keyring, matching the configured `user.email`.

## Adding a module

```
modules/<name>/
├── module.sh     # required. First line: "# desc: one-line description"
├── packages      # optional. What the module needs, one per line
├── home/         # optional. Symlinked into $HOME at the same relative path
└── system/       # optional. Copied to / at the same path, root-owned
```

`packages` is read automatically before `module.sh` runs, so a module can rely
on what it declared:

```
# modules/<name>/packages
some-package      # official repos
aur:other-package # from the AUR
?nice-to-have     # optional: a failure warns instead of failing the run
?aur:optional-aur # optional, from the AUR
```

Blank lines and everything after `#` are ignored. `cat modules/*/packages` shows
everything the repo needs without reading any shell.

`module.sh` runs with the helpers from `lib/common.sh` already sourced:
`link_tree`, `copy_tree`, `link_home`, `copy_system`, `need_packages`,
`append_once`, `insert_once`, `back_up`, and the reporters
`ok`/`changed`/`skip`/`warn`/`fail`. `$MODULE_DIR` points at the module,
`$STATE_DIR` at machine-local state, `$OMARCHY_OVERLAY_DIR` at the repo.

Rules to keep:

- **Overlay, never replace.** If Omarchy or a package owns the file, append,
  insert, or edit only the keys you need. Replacing it means inheriting their
  bugs and losing their fixes.
- **Idempotent.** Re-running must report only `ok`. Check with `--dry-run`.
- **Honour `dry`.** Guard every write with `if dry; then ... fi` or use the helpers.
- **Skip what does not apply**, never fail it. A machine without an NVIDIA GPU
  is not a broken machine.
- **Derive machine-specific values**, never commit them.

## Machine state

Local choices live outside the repo, in `~/.local/state/omarchy-overlay/`:

```
container-engine.sh -> modules/container-engine/engines/podman.sh
```

Toggle scripts flip these links. `install` only creates one when it is missing,
so re-running never overrides a machine's choice.
