# desc: Claude Code via mise, a status line, conventions for every agent in use

# Claude ships faster than any distro package can follow, so Omarchy installs it
# through mise: omarchy-mise-install writes a ~/.local/bin wrapper that pins the
# version and execs it. That is why `packages` names mise-bin and not claude.
#
# Checked at the wrapper path as well as on PATH: this module sorts before the
# shell module, so on a fresh machine ~/.local/bin may not be on PATH yet and a
# PATH-only test would reinstall something that is already there.
if command -v claude >/dev/null || [[ -x $HOME/.local/bin/claude ]]; then
  ok "claude ($(command -v claude || echo "$HOME/.local/bin/claude"))"
elif dry; then
  changed "would install claude with omarchy-mise-install"
elif ! command -v omarchy-mise-install >/dev/null; then
  warn "claude is missing and omarchy-mise-install is not available"
  note "this module assumes Omarchy; otherwise install claude yourself"
elif omarchy-mise-install claude; then
  changed "claude installed via mise"
else
  fail "omarchy-mise-install claude failed"
fi

# The status line. link_tree symlinks each file individually, so ~/.claude
# keeps everything Claude Code owns there — its credentials, projects and
# state are untouched.
link_tree "$MODULE_DIR/home"

# --- conventions -------------------------------------------------------------

# One file, linked under whatever name each agent reads. Named AGENTS.md for
# the cross-agent spelling; kept out of home/, because home/ maps a path to the
# same path and these targets differ.
conventions=$MODULE_DIR/conventions/AGENTS.md

# The agent this module installs, and so uses by declaration. It is exempt from
# the in-use test below, which would otherwise be wrong on exactly the machine
# this repo exists for: on a fresh install the block above has written the
# wrapper, nothing has run it yet, mise holds nothing, and the conventions —
# the whole point of carrying the repo to another PC — would be skipped.
managed_agent=claude

# Whether an agent is actually in use on this machine.
#
# Not "does its config directory exist": Omarchy seeds ~/.agents, ~/.claude,
# ~/.codex and ~/.pi/agent with its own skills on every install, so those
# directories say nothing. And not "is the CLI on PATH" alone: Omarchy's
# install/user/mise.sh runs omarchy-mise-install for every agent it ships —
# codex, crush, gemini, opencode, pi, grok, cursor-agent — and each writes a
# wrapper that downloads the tool on first use. A wrapper means offered, not
# used, and mise only has the tool once it has really run — so ask mise.
#
# `mise where` rather than a test for ~/.local/share/mise/installs/<cli>:
# MISE_DATA_DIR relocates that directory and `mise where` follows it, exiting
# 0 with a path when installed and 1 when not.
agent_in_use() {
  local cli=$1 wrapper
  wrapper=$(command -v "$cli" 2>/dev/null) || return 1
  if grep -qs 'mise x' -- "$wrapper"; then
    mise where "$cli" >/dev/null 2>&1
  else
    return 0   # installed some other way; being on PATH is the evidence
  fi
}

# cli, user-level instruction file, skills directory — all relative to $HOME.
#
# Only agents whose instruction path is known. Claude's is confirmed; Codex's
# is corroborated by Claude Code's own Codex importer, which reads AGENTS.md
# from the codex home. Omarchy also ships pi, gemini, crush, opencode and
# others, and seeds ~/.pi/agent/skills — but their user-level instruction
# filenames are not established here. Add a row once the path is confirmed;
# guessing one leaves a file no agent reads, which is the clutter this avoids.
while read -r cli instructions skills; do
  [[ -n $cli ]] || continue
  if [[ $cli != "$managed_agent" ]] && ! agent_in_use "$cli"; then
    skip "$cli is not in use — conventions not linked"
    continue
  fi
  link_home "$conventions" "$HOME/$instructions"
  # No test that the skills directory already exists: link_home creates the
  # parent, and this line is only reached for an agent in use, so creating its
  # skills directory is right. Requiring it first meant a fresh machine — where
  # nothing has created ~/.claude/skills yet — got no skill at all.
  [[ -n $skills ]] &&
    link_home "$MODULE_DIR/skills/git-conventions" "$HOME/$skills/git-conventions"
done <<'AGENTS'
claude .claude/CLAUDE.md .claude/skills
codex  .codex/AGENTS.md  .codex/skills
AGENTS

# --- settings.json ------------------------------------------------------------

# Claude Code owns this file and writes to it itself (theme, notification
# preferences, dialogs you have accepted). Merge the two keys we care about and
# leave the rest alone — replacing it would discard machine-local state that was
# never ours.
#
# attribution is here rather than in the conventions file on purpose. That file
# asks the model not to add "Co-Authored-By" and "Generated with Claude Code";
# this makes the harness not offer them at all, so the rule holds even on a
# turn where the instruction is outranked or missing. Claude-only, though — no
# other agent reads this file, which is why the rule stays in both places.
settings=$HOME/.claude/settings.json

if ! command -v jq >/dev/null; then
  skip "jq not installed — cannot merge $settings"
elif [[ -e $settings ]] && ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
  # Claude Code silently ignores a settings file it cannot parse, so rewriting
  # one that is already broken would hide the real problem behind our change.
  # Tested for object, not merely valid JSON: an array parses fine and then
  # cannot be multiplied, which would leave the merge below empty.
  fail "$settings is not a JSON object — leaving it alone"
else
  # Built here, below the guard: this calls jq, and doing it above printed a
  # raw "jq: command not found" ahead of the skip on a machine without it.
  #
  # An absolute path, not ~/...: settings.json is machine-local and never
  # committed, so a portable spelling buys nothing, and whether the harness
  # runs this through a shell that would expand the tilde is not documented.
  want=$(jq -n --arg cmd "$HOME/.claude/statusline-command.sh" '{
    statusLine: { type: "command", command: $cmd },
    attribution: { commit: "", pr: "", sessionUrl: false }
  }')

  if [[ -e $settings ]]; then
    merged=$(jq --argjson want "$want" '. * $want' "$settings") || merged=""
    current=$(jq -S . "$settings")
  else
    merged=$(jq -n --argjson want "$want" '$want')
    current=""
  fi

  if [[ -z $merged ]]; then
    # Never write what a failed jq left behind: printf would happily truncate
    # the file to a single newline and the run would still report success.
    fail "could not merge into $settings — leaving it alone"
  elif [[ $current == "$(jq -S . <<<"$merged")" ]]; then
    ok "$settings (statusLine, attribution)"
  elif dry; then
    changed "would set statusLine and attribution in $settings"
  else
    bak=$(back_up "$settings")
    mkdir -p -- "$(dirname -- "$settings")"
    # Written through a temp file: a redirect truncates the target first, so a
    # failure half way would leave Claude Code with no settings at all.
    if printf '%s\n' "$merged" >"$settings.tmp" && mv -- "$settings.tmp" "$settings"; then
      changed "$settings (statusLine, attribution)"
    else
      rm -f -- "$settings.tmp"
      fail "could not write $settings"
    fi
    drop_backup_if_same "$bak" "$settings"
  fi
fi

note "the status line and settings apply to new claude sessions"
