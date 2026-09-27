# desc: Claude Code — install via mise, status line, and my global conventions

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

# ~/.claude/CLAUDE.md, the status line, and the skills tree. link_tree symlinks
# each file individually, so ~/.claude/skills keeps the entries Omarchy and
# claude.ai put there — only our own subdirectory is ours.
link_tree "$MODULE_DIR/home"

# --- settings.json ------------------------------------------------------------

# Claude Code owns this file and writes to it itself (theme, notification
# preferences, dialogs you have accepted). Merge the two keys we care about and
# leave the rest alone — replacing it would discard machine-local state that was
# never ours.
#
# attribution is here rather than in CLAUDE.md on purpose. CLAUDE.md asks the
# model not to add "Co-Authored-By" and "Generated with Claude Code"; this makes
# the harness not offer them at all, so the rule holds even on a turn where the
# instruction is outranked or missing.
settings=$HOME/.claude/settings.json
want='{
  "statusLine": { "type": "command", "command": "~/.claude/statusline-command.sh" },
  "attribution": { "commit": "", "pr": "", "sessionUrl": false }
}'

if ! command -v jq >/dev/null; then
  skip "jq not installed — cannot merge $settings"
elif [[ -e $settings ]] && ! jq -e . "$settings" >/dev/null 2>&1; then
  # Claude Code silently ignores a settings file it cannot parse, so rewriting
  # one that is already broken would hide the real problem behind our change.
  fail "$settings is not valid JSON — leaving it alone"
else
  if [[ -e $settings ]]; then
    merged=$(jq --argjson want "$want" '. * $want' "$settings")
    current=$(jq -S . "$settings")
  else
    merged=$(jq -n --argjson want "$want" '$want')
    current=""
  fi

  if [[ $current == "$(jq -S . <<<"$merged")" ]]; then
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
