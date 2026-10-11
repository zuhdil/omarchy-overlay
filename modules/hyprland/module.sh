# desc: vim-style window keys (focus, swap, resize on hjkl) layered over Omarchy's Hyprland bindings

# Omarchy seeds ~/.config/hypr/bindings.lua for personal overrides, and
# `omarchy refresh hyprland` rewrites it. So the bindings live in a file of our
# own, symlinked, and one guarded require is appended to theirs: loaded after
# Omarchy's defaults, so the unbinds find what they remove.

link_tree "$MODULE_DIR/home"

# Guarded so a missing overlay file leaves Hyprland's config loading, rather
# than failing the whole config on a require error.
append_once "$HOME/.config/hypr/bindings.lua" 'hypr.overlay-bindings' '
-- omarchy-overlay: vim-style window keys.
local overlay = io.open((os.getenv("HOME") or "") .. "/.config/hypr/overlay-bindings.lua")
if overlay then
  overlay:close()
  require("hypr.overlay-bindings")
end'
