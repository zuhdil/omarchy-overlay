-- omarchy-overlay: options set over LazyVim's, in an init that runs after
-- LazyVim has loaded its own options.
return {
	"LazyVim/LazyVim",
	init = function()
		-- LazyVim hides the intro screen, expecting the snacks dashboard to
		-- take its place, and overlay-disabled.lua turns that dashboard off.
		vim.opt.shortmess:remove("I")
		-- LazyVim's conceallevel=2 hides markdown backticks, link URLs and code
		-- fences except on the cursor line, so text shifts as the cursor moves.
		vim.o.conceallevel = 0
		-- Mark both states of wrap: showbreak opens a continuation line, and
		-- extends/precedes flag text running off screen when unwrapped.
		vim.opt.breakindent = true
		vim.opt.showbreak = "↳…"
		vim.opt.breakat:append({ ["\\"] = true, ["_"] = true })
		vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣", extends = "…", precedes = "…" }
	end,
}
