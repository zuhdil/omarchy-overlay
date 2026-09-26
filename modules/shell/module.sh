# desc: shared shell config wired into ~/.bashrc, split by interactivity

# Two source lines, and the split matters. ~/.bashrc returns early for
# non-interactive shells, so anything below that guard never reaches a script,
# an editor task, or a hook. env.sh goes above it; rc.sh below.
#
# Sourced straight from the repo — no symlink, so there is never a question of
# which copy is authoritative.

insert_once "$HOME/.bashrc" 'omarchy-overlay/modules/shell/env.sh' \
  '[[ $- != *i* ]] && return' \
  "
# omarchy-overlay environment — above the interactive guard on purpose, so scripts and
# editor tasks see it too, not just interactive shells.
[[ -r $MODULE_DIR/env.sh ]] && source $MODULE_DIR/env.sh"

append_once "$HOME/.bashrc" 'omarchy-overlay/modules/shell/rc.sh' "
# omarchy-overlay interactive shell config (this file stays machine-local).
[[ -r $MODULE_DIR/rc.sh ]] && source $MODULE_DIR/rc.sh"

# A hardcoded DOCKER_HOST predating this module would pin the engine above the
# guard and quietly defeat toggle-container-engine for non-interactive shells.
# Report it rather than editing it out: this file is the machine's, not ours.
if grep -qE '^[[:space:]]*export[[:space:]]+DOCKER_HOST=' "$HOME/.bashrc" 2>/dev/null; then
  warn "~/.bashrc sets DOCKER_HOST directly"
  note "that overrides toggle-container-engine. Remove this line:"
  note "  $(grep -nE '^[[:space:]]*export[[:space:]]+DOCKER_HOST=' "$HOME/.bashrc" | head -1)"
fi
