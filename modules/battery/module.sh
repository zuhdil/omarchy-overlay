# desc: battery-combined, Omarchy's power widget fed by it so its popup counts every battery, and battery-recalibrate

link_tree "$MODULE_DIR/home"
copy_tree "$MODULE_DIR/system"
# Linked whole, like a skill directory: the shell scans plugins/*/ by directory.
link_home "$MODULE_DIR/plugin" "$HOME/.config/omarchy/plugins/overlay.power"

# Enabling a plugin cloned from omarchy.power puts it in the built-in's bar slot,
# keeping its position and settings, the way `omarchy plugin clone` does.
shell_json=$HOME/.config/omarchy/shell.json
if jq -e '[.bar.layout[][]?.id] | index("overlay.power")' "$shell_json" &>/dev/null; then
  ok "bar widget: overlay.power"
elif dry; then
  changed "would replace omarchy.power with overlay.power in the bar"
elif ! omarchy-shell shell ping &>/dev/null; then
  note "omarchy-shell not running; enable later with: omarchy plugin enable overlay.power"
else
  # The scan is asynchronous; enabling an id it has not reached yet fails.
  omarchy-shell shell rescanPlugins >/dev/null
  for _ in {1..40}; do
    omarchy-plugin-list --json | jq -e 'any(.[]; .id == "overlay.power")' >/dev/null && break
    sleep 0.05
  done
  omarchy-plugin-enable overlay.power >/dev/null &&
    changed "bar widget: overlay.power replaces omarchy.power" ||
    fail "could not enable overlay.power"
fi
