(local M {})

;; Default configuration
(var config {:inbox_file "~/.local/share/clearhead_cli/inbox.actions"
             :project_file ".actions"
             :auto_normalize true})

;; State definitions
(local states {:not-started " "
               :in-progress "-"
               :blocked "="
               :completed "x"
               :cancelled "_"})

;; Cycle order: not-started -> in-progress -> blocked -> completed -> cancelled -> not-started
(local state-cycle [" " "-" "=" "x" "_"])

(fn expand-path [path]
  "Expand ~ and environment variables in path"
  (vim.fn.expand path))

(fn get-current-state [line]
  "Extract the state character from a line with format '[X] ...'"
  (line:match "^%s*%[(.?)%]"))

(fn set-line-state [linenr new-state]
  "Set the state of an action line"
  (let [line (vim.fn.getline linenr)
        new-line (line:gsub "^(%s*)%[.?%]" (.. "%1[" new-state "]"))]
    (vim.fn.setline linenr new-line)))

(fn M.cycle-state []
  "Cycle through states: not-started -> in-progress -> blocked -> completed -> cancelled -> not-started"
  (let [linenr (vim.fn.line ".")
        line (vim.fn.getline linenr)
        current (get-current-state line)]
    (when current
      (var next-state " ")
      (each [i state (ipairs state-cycle)]
        (when (= state current)
          (let [next-idx (if (< i (length state-cycle)) (+ i 1) 1)]
            (set next-state (. state-cycle next-idx))
            (lua "break"))))
      (set-line-state linenr next-state))))

(fn M.set-state [state]
  "Set the state of the current line to a specific state"
  (fn []
    (let [linenr (vim.fn.line ".")]
      (set-line-state linenr state))))

(fn M.normalize [bufnr]
  "Runs clearhead_cli normalize on the buffer's file if CLI is available."
  (let [filename (vim.api.nvim_buf_get_name bufnr)]
    (when (not= filename "")
      ;; Check if clearhead_cli is available
      (if (= (vim.fn.executable "clearhead_cli") 1)
          (vim.fn.jobstart ["clearhead_cli" "normalize" filename "--write"]
                           {:on_exit (fn [_ exit-code]
                                       (when (= exit-code 0)
                                         ;; Reload the buffer to see the new IDs
                                         (vim.schedule (fn [] (vim.api.nvim_command "checktime")))))
                            :on_stderr (fn [_ data]
                                         (when (and data (> (length data) 0))
                                           (let [msg (table.concat data "\n")]
                                             (when (not= msg "")
                                               (vim.notify (.. "clearhead_cli normalize error: " msg)
                                                          vim.log.levels.ERROR)))))})
          ;; CLI not available - silently skip
          nil))))

(fn M.open-inbox []
  "Open the configured inbox file"
  (let [inbox-path (expand-path config.inbox_file)]
    (vim.cmd (.. "edit " inbox-path))))

(fn M.open-dir []
  "Open first .actions file in current directory"
  (let [cwd (vim.fn.getcwd)
        actions-files (vim.fn.glob (.. cwd "/*.actions") true true)]
    (if (> (length actions-files) 0)
        (vim.cmd (.. "edit " (. actions-files 1)))
        (vim.notify "No .actions file found in current directory" vim.log.levels.WARN))))

(fn M.setup [opts]
  ;; Merge user config with defaults
  (when opts
    (each [k v (pairs opts)]
      (tset config k v)))

  (let [group (vim.api.nvim_create_augroup "clearhead" {:clear true})]
    ;; Normalize on save to ensure UUIDs are generated for new hand-written tasks
    (when config.auto_normalize
      (vim.api.nvim_create_autocmd "BufWritePost"
                                   {:pattern "*.actions"
                                    :group group
                                    :callback (fn [args] (M.normalize args.buf))}))

    ;; Set conceallevel for a better UI experience
    (vim.api.nvim_create_autocmd "FileType"
                                 {:pattern "actions"
                                  :group group
                                  :callback (fn []
                                              (set vim.opt_local.conceallevel 2)
                                              (set vim.opt_local.concealcursor "nc"))})

    ;; Create user commands
    (vim.api.nvim_create_user_command "ClearheadInbox" M.open-inbox {})
    (vim.api.nvim_create_user_command "ClearheadOpenDir" M.open-dir {})))

M
