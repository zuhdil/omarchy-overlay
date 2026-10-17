-- omarchy-overlay: <C-x> opens in a horizontal split, as in Telescope and fzf.
-- <C-s> still does too. Pickers that bind <C-x> themselves (buffers, git
-- branches, marks, scratch) keep their delete action.
return {
	"folke/snacks.nvim",
	opts = {
		picker = {
			win = {
				input = { keys = { ["<c-x>"] = { "edit_split", mode = { "i", "n" } } } },
				list = { keys = { ["<c-x>"] = "edit_split" } },
			},
		},
	},
}
