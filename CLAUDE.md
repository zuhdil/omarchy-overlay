# Working in this repo

**omarchy-overlay** — my customisations layered over stock Omarchy. `install`
applies modules to the machine. Read `README.md` for the layout; this file is
the rules that matter.

## Overlay, never replace

The premise of the repo: Omarchy's own files stay untouched. Append to what it
regenerates, insert above an early `return`, add a drop-in that sorts after
theirs, or edit single keys in a package-owned file. Replacing a file means
inheriting its bugs and losing its upstream fixes — and `omarchy refresh` will
undo you anyway.

## The two mechanisms

- `modules/*/home/` is **symlinked** into `$HOME`. Editing the live file edits
  the repo. There is no sync step, and no "which copy is authoritative".
- `modules/*/system/` is **copied** to `/` as root, and must never be symlinked.
  This repo is user-writable; a symlinked `/usr/local/bin/hibernation-check`
  would make `sudo hibernation-check` execute a user-writable file as root, and
  a symlinked `/etc` drop-in would let anything that can write `$HOME` rewrite
  root's policy. Do not "simplify" copy_system into a symlink.

## Packages

A module declares what it needs in `modules/<name>/packages`, one per line;
`install` reads it before sourcing `module.sh`. Prefixes: `aur:` for the AUR,
`?` for optional. Never call `pacman` or `yay` directly — `omarchy pkg add` and
`omarchy pkg aur add` manage their own privilege escalation, so they must not be
wrapped in sudo. They do need a terminal, so a non-interactive run reports what
is missing instead of failing.

## Invariants

- **Idempotent.** A second run reports only `ok`. Verify with `./install --dry-run`.
- **Honour `dry`.** Every write guarded, or done through the `lib/common.sh`
  helpers, which already handle it.
- **Skip, never fail, what does not apply.** No NVIDIA GPU is not a fault. A
  check that cries wolf gets ignored — that failure mode has already happened
  here once.
- **Never commit machine-specific values.** Derive them. See README for the list
  and why each one silently breaks another machine.
- **Scope expensive side effects.** The initramfs rebuild fires only when an
  initramfs-relevant file changed (`INITRAMFS_DIRTY`), not on any change.
- **Backups follow Omarchy's convention**: `<file>.bak.<epoch>`, removed again
  when the content was identical.
- **Use `$OMARCHY_OVERLAY_DIR`**, never a hardcoded repo path. `modules/shell/env.sh`
  derives it from its own location and `install` exports it, so the repo stays
  relocatable. Fall back to `${OMARCHY_OVERLAY_DIR:-$HOME/.config/omarchy-overlay}`
  in scripts that may run before a shell sourced `env.sh`.

## Hibernation module specifics

- `/etc/mkinitcpio.conf.d/omarchy_resume.conf` must keep the literal line
  `HOOKS+=(resume)`. Omarchy's own setup/remove commands grep for it, and
  upstream PR #8888's migration uses it as the trigger to replace the file.
  When that lands, the module detects the `# omarchy:resume-hook` marker and
  stands aside.
- The hook embedded in `docs/hibernation.md` must stay byte-identical to
  `home/.config/omarchy/hooks/post-update.d/check-hibernation.hook`.
- `hibernation-check` adapts to GPU layout, boot loader, swap type and whether a
  lid exists. Keep it that way; it is copied to other machines.

## Verifying

```sh
./install --dry-run      # no sudo, no writes
sudo hibernation-check   # 23 checks, non-zero on failure
```

Neither proves hibernation *works* — only that it is configured. The real test
is a cycle: compare `/proc/sys/kernel/random/boot_id` before and after.
Unchanged means a true resume; changed means it rebooted instead.
