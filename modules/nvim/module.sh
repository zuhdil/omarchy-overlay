# desc: trims Omarchy's LazyVim config (noice, trouble, bufferline, neo-tree, some snacks modules) and adds oil.nvim

# Omarchy seeds ~/.config/nvim from omarchy-nvim, and omarchy-nvim-refresh
# moves it aside and copies the defaults again. So the changes live in spec
# files of our own, symlinked into lua/plugins, which lazy.nvim merges over
# theirs.

# Linking into a missing ~/.config/nvim would create it, and omarchy-nvim-setup
# then skips seeding a config that "already exists".
if [[ ! -d $HOME/.config/nvim/lua/plugins ]]; then
  skip "no Omarchy Neovim config at ~/.config/nvim"
  return 0
fi

link_tree "$MODULE_DIR/home"
