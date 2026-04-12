vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.actions",
  callback = function() vim.bo.filetype = "actions" end,
})
