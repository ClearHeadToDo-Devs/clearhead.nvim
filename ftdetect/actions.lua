local function _1_()
  vim.bo.filetype = "actions"
  return nil
end
return vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {pattern = "*.actions", callback = _1_})
