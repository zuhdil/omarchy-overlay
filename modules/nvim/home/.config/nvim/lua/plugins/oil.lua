-- omarchy-overlay: oil.nvim as the file explorer, on the keys LazyVim gives
-- its explorer extras.
return {
	"stevearc/oil.nvim",
	-- Loaded at startup so `nvim <dir>` opens oil rather than netrw.
	lazy = false,
	opts = {},
	keys = {
		{ "-", "<CMD>Oil<CR>", desc = "Open parent directory" },
		{
			"<leader>fe",
			function()
				require("oil").open(LazyVim.root())
			end,
			desc = "Explorer Oil (Root Dir)",
		},
		{
			"<leader>fE",
			function()
				require("oil").open(vim.uv.cwd())
			end,
			desc = "Explorer Oil (cwd)",
		},
		{ "<leader>e", "<leader>fe", desc = "Explorer Oil (Root Dir)", remap = true },
		{ "<leader>E", "<leader>fE", desc = "Explorer Oil (cwd)", remap = true },
	},
}
