# Environment every shell needs — sourced ABOVE ~/.bashrc's interactive guard.
#
# Anything a script, editor task, systemd user unit or hook must also see goes
# here, not in rc.sh. Omarchy does the same with its env-bootstrap: the guard
# `[[ $- != *i* ]] && return` stops a non-interactive shell before it reaches
# anything below it.

# Where this overlay lives. Derived from this file's own location rather than
# hardcoded, so moving or cloning the repo elsewhere needs no edits — only
# ~/.bashrc's source line, which install rewrites.
if [[ -z ${OMARCHY_OVERLAY_DIR:-} ]]; then
  export OMARCHY_OVERLAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# Which container engine this machine uses. The symlink is created by
# toggle-container-engine and is never committed.
_overlay_engine="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-overlay/container-engine.sh"
[[ -r $_overlay_engine ]] && source "$_overlay_engine"
unset _overlay_engine

# Scripts installed by overlay modules.
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
