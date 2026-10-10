# desc: vim-style pane navigation and x/X/C-x kill bindings layered over Omarchy's tmux config

# Omarchy seeds ~/.config/tmux/tmux.conf, its migrations edit it in place, and
# `omarchy refresh tmux` overwrites it. So the preferences live in a file of
# our own, symlinked, and one source line is appended to theirs. Appended, not
# inserted: tmux has no drop-in directory, and the last binding wins.
#
# Never symlink tmux.conf itself. Migrations write through the path to keep
# dotfile symlinks intact, so they would edit this repo instead.
#
# ~/.tmux.conf is no alternative: tmux reads it before the XDG path, so
# Omarchy's h and k would win.

before=$CHANGED
link_tree "$MODULE_DIR/home"

conf=$HOME/.config/tmux/tmux.conf

if ! command -v tmux >/dev/null; then
  skip "tmux not installed"
else
  # -q: tmux starts cleanly even if the overlay file goes missing.
  append_once "$conf" 'tmux/overlay.conf' '
# omarchy-overlay preferences — last, so its bindings win.
source-file -q ~/.config/tmux/overlay.conf'

  # A running server keeps its bindings until the config is sourced again.
  if ((CHANGED > before)) && ! dry && tmux has-session 2>/dev/null; then
    if tmux source-file "$conf" 2>/dev/null; then
      changed "reloaded the running tmux server"
    else
      warn "could not reload tmux — press prefix q in a session"
    fi
  fi
fi
