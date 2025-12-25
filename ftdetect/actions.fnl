(vim.api.nvim_create_autocmd [:BufRead :BufNewFile]
                            {:pattern :*.actions
                             :callback (fn []
                                         (set vim.bo.filetype :actions))})
