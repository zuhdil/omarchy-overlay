-- omarchy-overlay: plugins switched off on top of Omarchy's LazyVim config.
-- lazy.nvim merges specs by name, so `enabled = false` here wins over the
-- spec in LazyVim without editing it.
return {
	{ "folke/noice.nvim", enabled = false },
	{ "folke/trouble.nvim", enabled = false },
	{ "akinsho/bufferline.nvim", enabled = false },
	-- Omarchy's lazyvim.json enables the neo-tree extra, which keeps LazyVim's
	-- snacks explorer extra out too; oil.lua takes the explorer keys.
	{ "nvim-neo-tree/neo-tree.nvim", enabled = false },
	-- Dependencies left without users once noice and neo-tree are off. monokai-pro
	-- needs nui only for its filter-picker menu.
	{ "MunifTanjim/nui.nvim", enabled = false },
	{ "nvim-lua/plenary.nvim", enabled = false },
	-- These keys open Trouble, which is disabled above.
	{
		"folke/todo-comments.nvim",
		keys = {
			{ "<leader>xt", false },
			{ "<leader>xT", false },
		},
	},
	{
		"folke/snacks.nvim",
		opts = {
			dashboard = { enabled = false },
			notifier = { enabled = false },
			input = { enabled = false },
			explorer = { enabled = false },
		},
		-- Notification history and dismiss only work through the notifier.
		keys = {
			{ "<leader>n", false },
			{ "<leader>un", false },
		},
	},
}
