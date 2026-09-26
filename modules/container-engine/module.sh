# desc: switch docker/compose between Podman and Docker with one command
#
# The engines are repo content; the selection is machine state. install creates
# the link only if absent, so re-running never overrides a machine's choice.

mkdir -p "$HOME/.local/bin"
link_home "$MODULE_DIR/bin/toggle-container-engine" "$HOME/.local/bin/toggle-container-engine"

link="$STATE_DIR/container-engine.sh"
if [[ -L $link ]]; then
  ok "engine selected: $(basename "$(readlink -f -- "$link")" .sh)"
elif dry; then
  changed "would default the engine to podman (toggle-container-engine to change)"
else
  mkdir -p "$STATE_DIR"
  ln -sfn "$MODULE_DIR/engines/podman.sh" "$link"
  changed "engine defaulted to podman"
  note "switch with: toggle-container-engine [podman|docker|--status]"
fi
