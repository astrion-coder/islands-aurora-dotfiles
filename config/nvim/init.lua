-- Use the terminal's 16 colours (kitty's, generated from the wallpaper by
-- matugen) so nvim follows wallpaper changes automatically
vim.o.termguicolors = false

-- Transparent background so kitty's translucency (and Hyprland's blur) shows
-- through. Re-applied after any :colorscheme change.
local function clear_backgrounds()
  for _, group in ipairs({
    "Normal", "NormalNC", "NormalFloat", "FloatBorder", "SignColumn",
    "EndOfBuffer", "LineNr", "FoldColumn", "WinSeparator", "StatusLineNC",
  }) do
    vim.api.nvim_set_hl(0, group, vim.tbl_extend("force",
      vim.api.nvim_get_hl(0, { name = group, link = false }), { bg = "NONE" }))
  end
end

vim.api.nvim_create_autocmd("ColorScheme", { callback = clear_backgrounds })
clear_backgrounds()
