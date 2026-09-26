# desc: switch docker/compose between Podman and Docker with one command
#
# The engines are repo content; the selection is machine state. A selection that
# already resolves into this module is left alone, so re-running never overrides
# a machine's choice.

# No mkdir here: link_home creates the parent, and only when not a dry run.
link_home "$MODULE_DIR/bin/toggle-container-engine" "$HOME/.local/bin/toggle-container-engine"

link="$STATE_DIR/container-engine.sh"

# The link has to resolve to a readable engine *inside this module*. Testing
# only that it exists accepts a link left behind by a repo that has since moved:
# that reports a selection while sourcing nothing, so the shell ends up with no
# DOCKER_HOST while claiming podman.
target=$(readlink -f -- "$link" 2>/dev/null) || target=

if [[ -n $target && -r $target && $target == "$MODULE_DIR/engines/"* ]]; then
  ok "engine selected: $(basename -- "$target" .sh)"
else
  # A stale link still records which engine was wanted; keep that rather than
  # silently resetting the machine to the default.
  want=podman
  if [[ -L $link ]]; then
    stale=$(basename -- "$(readlink -- "$link")" .sh)
    [[ -r $MODULE_DIR/engines/$stale.sh ]] && want=$stale
  fi

  if dry; then
    if [[ -L $link ]]; then
      changed "would re-point a stale engine selection to $want"
    else
      changed "would default the engine to $want (toggle-container-engine to change)"
    fi
  elif mkdir -p "$STATE_DIR" && ln -sfn "$MODULE_DIR/engines/$want.sh" "$link"; then
    if [[ -L $link && -n ${stale:-} ]]; then
      changed "engine selection re-pointed to $want"
    else
      changed "engine defaulted to $want"
      note "switch with: toggle-container-engine [podman|docker|--status]"
    fi
  else
    fail "could not record the engine selection at $link"
  fi
fi
