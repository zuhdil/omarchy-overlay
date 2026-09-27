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

# ~/.claude/CLAUDE.md and the status line. link_tree symlinks each file
# individually, so ~/.claude keeps everything Claude Code owns there — its
# credentials, projects and state are untouched.
link_tree "$MODULE_DIR/home"

# The skill is linked as a whole directory, not file by file, matching how
# Omarchy links its own (~/.claude/skills/omarchy is one link to a directory of
# SKILL.md plus topic files). A skill grows supporting files, and a directory
# link picks them up — and drops the ones deleted from the repo — with no
# re-install. File-level links would leave a dangling entry behind instead.
#
# Only this subdirectory: ~/.claude/skills itself must stay a real directory,
# since Omarchy and claude.ai put their own entries in it.
link_home "$MODULE_DIR/skills/git-conventions" "$HOME/.claude/skills/git-conventions"

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
