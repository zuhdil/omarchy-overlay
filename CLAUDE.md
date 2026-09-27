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
- **`warn` means "I did not do this."** It is counted, and a run with warnings
  reports `Nothing applied` or `Changes applied (N warnings above)` rather than
  `Already up to date`. Use `note` for anything advisory, or the summary
  overstates. `skip` is for what does not apply here and is not counted.
- **Honour `dry`.** Every write guarded, or done through the `lib/common.sh`
  helpers, which already handle it.
- **Skip, never fail, what does not apply.** No NVIDIA GPU is not a fault. A
  check that cries wolf gets ignored — that failure mode has already happened
  here once.
- **Never commit machine-specific values.** Derive them. See README for the list
  and why each one silently breaks another machine.
- **Scope expensive side effects.** The initramfs rebuild fires only when an
  initramfs-relevant file changed (`INITRAMFS_DIRTY`), not on any change.
- **Never call `sudo` directly without `root_available`.** A prompt from a hook
  or a non-interactive run is a hang, not an error. `copy_system` already
  guards; module code must too.
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
- `docs/hibernation.md` must not reproduce the post-update hook. It used to
  carry an inline copy that had to match
  `home/.config/omarchy/hooks/post-update.d/check-hibernation.hook` byte for
  byte, and the copy drifted anyway. It links to the file instead.
- `hibernation-check` adapts to GPU layout, boot loader, swap type and whether a
  lid exists. Keep it that way; it is copied to other machines.

## AI agent module specifics

- `claude` is not a package. `packages` names `mise-bin` (the omarchy-repo
  package that owns `/usr/bin/mise`, listed in `omarchy-base.packages`), and
  `module.sh` calls `omarchy-mise-install claude` when no wrapper exists. Do
  not "fix" that to `mise` — that names a package this machine does not have
  and would collide with `mise-bin`.
- Test for the wrapper at `~/.local/bin/claude` as well as on `PATH`. This
  module sorts before `shell`, so on a fresh machine `~/.local/bin` is not on
  `PATH` yet and a `command -v` test alone reinstalls what is already there.
- `~/.claude/settings.json` is merged key by key, never replaced: Claude Code
  writes its own state there. A file that is already invalid JSON is reported,
  not rewritten — Claude Code ignores an unparseable settings file silently,
  and overwriting it would hide that.
- The conventions are one file, `conventions/AGENTS.md`, linked under whatever
  name each agent reads: `~/.claude/CLAUDE.md` for Claude, `~/.codex/AGENTS.md`
  for Codex. Not in `home/`, because `home/` maps a path to the same path and
  these targets differ. **Do not** link it to `~/.claude/AGENTS.md`: the
  AGENTS.md candidates Claude Code compiles in are project-scope, it calls
  `~/.claude/CLAUDE.md` "your user-level memory file", and it ships a Codex
  importer that copies a user `AGENTS.md` *to* `CLAUDE.md` — which would be
  pointless if it read the former. Linking under the name Claude already reads
  does not depend on that inference.
- An agent is linked into only when it is actually in use, which is neither of
  the two obvious tests. Its config directory existing proves nothing: Omarchy
  seeds `~/.agents`, `~/.claude`, `~/.codex` and `~/.pi/agent` with its own
  skills on every install. Its CLI being on `PATH` proves little more:
  `install/user/mise.sh` runs `omarchy-mise-install` for every agent Omarchy
  ships — codex, crush, gemini, opencode, pi, grok, cursor-agent — and each
  writes a wrapper that downloads on first use. `agent_in_use` therefore
  requires a mise-backed CLI to have an install directory, which mise creates
  only after a real run.
- Add an agent as a row in that table only once its user-level instruction path
  is confirmed. A guessed path leaves a file no agent reads — the clutter the
  in-use test exists to prevent.
- The skill lives in `skills/`, not `home/`, and `module.sh` links the whole
  directory with `link_home`. That matches Omarchy (`~/.claude/skills/omarchy`
  is one link to a directory of `SKILL.md` plus topic files) and means a
  supporting file added to the repo is live without re-running `install`, while
  a deleted one leaves no dangling link. Never link `~/.claude/skills` itself:
  Omarchy and claude.ai put their own entries there.
- The split between `conventions/AGENTS.md` and the `git-conventions` skill is
  deliberate. A skill only loads when the model matches its description, and an
  agent may have no skill mechanism at all, so anything that must hold on every
  turn — no AI attribution, GPG signing — stays in the conventions file.
  `attribution` in `settings.json` enforces the first of those in the harness,
  where no instruction can outrank it, but only for Claude: that is why the
  rule is stated in both places rather than moved.

## Git module specifics

- Settings go in with `git config --global`, never by shipping a config file:
  Omarchy seeds `~/.config/git/config`, and `omarchy refresh config git/config`
  would discard a replacement.
- `user.signingkey` is derived from the local keyring, never committed.
- `git lgs` resolves to `git-log-signed` in `home/.local/bin/`. The `%G?`
  letter-to-symbol mapping lives in that script because git can neither colour
  nor translate `%G?` inside a format string.

## Verifying

```sh
./install --dry-run      # no sudo, no writes
sudo hibernation-check   # 23 checks, non-zero on failure
```

Neither proves hibernation *works* — only that it is configured. The real test
is a cycle: compare `/proc/sys/kernel/random/boot_id` before and after.
Unchanged means a true resume; changed means it rebooted instead.
