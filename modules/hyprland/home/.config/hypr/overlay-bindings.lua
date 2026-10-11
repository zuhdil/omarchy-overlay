-- omarchy-overlay: vim-style window keys, matching the tmux module with SUPER
-- in place of the prefix. Omarchy's arrow bindings stay as they are.
--
--   tmux prefix h/j/k/l      focus   SUPER + h/j/k/l
--   tmux prefix H/J/K/L      resize  SUPER + SHIFT + h/j/k/l
--   tmux prefix Alt+h/j/k/l  swap    SUPER + ALT + h/j/k/l
--   tmux prefix ?            keys    SUPER + ?

-- Displaced Omarchy bindings. Keybindings moves; the rest are dropped.
hl.unbind("SUPER + J")       -- Toggle window split
hl.unbind("SUPER + K")       -- Keybindings, now SUPER + ?
hl.unbind("SUPER + L")       -- Toggle workspace layout
hl.unbind("SUPER + ALT + K") -- Tmux keybindings

o.bind("SUPER + SHIFT + SLASH", "Keybindings", "omarchy-menu-keybindings")

local directions = {
  { key = "H", dir = "l", name = "left", x = -100, y = 0 },
  { key = "J", dir = "d", name = "down", x = 0, y = 100 },
  { key = "K", dir = "u", name = "up", x = 0, y = -100 },
  { key = "L", dir = "r", name = "right", x = 100, y = 0 },
}

for _, d in ipairs(directions) do
  o.bind("SUPER + " .. d.key, "Focus window " .. d.name, hl.dsp.focus({ direction = d.dir }))
  o.bind("SUPER + ALT + " .. d.key, "Swap window " .. d.name, hl.dsp.window.swap({ direction = d.dir }))
  -- Same step as Omarchy's SUPER + minus/equal, repeating while held like
  -- tmux's -r. Moves the border in that direction, as tmux's resize-pane does.
  o.bind("SUPER + SHIFT + " .. d.key, "Resize window " .. d.name,
    hl.dsp.window.resize({ x = d.x, y = d.y, relative = true }), { repeating = true })
end
