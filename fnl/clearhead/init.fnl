(local M {})

;; Internal state for the loaded configuration
(var config {:data_dir ""
             :config_dir ""
             :default_file "inbox.actions"
             :nvim_auto_normalize true
             :nvim_format_on_save true
             :nvim_lsp_enable true
             :nvim_inbox_file ""
             :nvim_lsp_binary_path ""
             :nvim_default_mappings true})

(fn expand-path [path]
  "Expand ~ and environment variables in path"
  (if (and path (not= path ""))
      (vim.fn.expand path)
      path))

(fn get-default-config-dir []
  "Get the default XDG config directory for clearhead"
  (let [xdg-config (os.getenv :XDG_CONFIG_HOME)
        base (if (and xdg-config (not= xdg-config ""))
                 xdg-config
                 (.. (vim.fn.expand "~") :/.config))]
    (.. base :/clearhead)))

(fn get-default-data-dir []
  "Get the default XDG data directory for clearhead"
  (let [xdg-data (os.getenv :XDG_DATA_HOME)
        base (if (and xdg-data (not= xdg-data ""))
                 xdg-data
                 (.. (vim.fn.expand "~") :/.local/share))]
    (.. base :/clearhead)))

(fn load-env []
  "Load configuration from environment variables"
  (let [env-config {}
        mappings {:CLEARHEAD_DATA_DIR :data_dir
                  :CLEARHEAD_CONFIG_DIR :config_dir
                  :CLEARHEAD_DEFAULT_FILE :default_file
                  :CLEARHEAD_NVIM_AUTO_NORMALIZE :nvim_auto_normalize
                  :CLEARHEAD_NVIM_FORMAT_ON_SAVE :nvim_format_on_save
                  :CLEARHEAD_NVIM_LSP_ENABLE :nvim_lsp_enable
                  :CLEARHEAD_NVIM_INBOX_FILE :nvim_inbox_file
                  :CLEARHEAD_NVIM_LSP_BINARY_PATH :nvim_lsp_binary_path
                  :CLEARHEAD_NVIM_DEFAULT_MAPPINGS :nvim_default_mappings}]
    (each [env-var key (pairs mappings)]
      (let [val (os.getenv env-var)]
        (when (and val (not= val ""))
          (let [parsed-val (if (or (= val :true) (= val :false))
                               (= val :true)
                               (let [num (tonumber val)]
                                 (if num
                                     num
                                     (if (and (val:find "^%[") (val:find "%]$"))
                                         (vim.fn.json_decode val)
                                         val))))]
            (tset env-config key parsed-val)))))
    env-config))

(fn read-json-file [path]
  "Read and decode a JSON file"
  (if (and path (= (vim.fn.filereadable path) 1))
      (let [lines (vim.fn.readfile path)
            content (table.concat lines "")]
        (if (and content (not= content ""))
            (vim.fn.json_decode content)
            {}))
      {}))

(fn load-config-internal [user-opts]
  "Load configuration from all sources with proper precedence"
  (let [defaults {:data_dir ""
                  :config_dir ""
                  :default_file "inbox.actions"
                  :nvim_auto_normalize true
                  :nvim_format_on_save true
                  :nvim_lsp_enable true
                  :nvim_inbox_file ""
                  :nvim_lsp_binary_path ""
                  :nvim_default_mappings true}

        global-config-dir (get-default-config-dir)
        global-config-path (.. global-config-dir :/config.json)
        global-config (read-json-file global-config-path)

        ;; 1. Merge global config into defaults
        base-config (vim.tbl_extend :force defaults global-config)

        ;; 2. Merge environment variables
        base-config (vim.tbl_extend :force base-config (load-env))

        ;; 3. Merge user options from setup()
        final-config (if user-opts
                         (vim.tbl_extend :force base-config user-opts)
                         base-config)]

    ;; Resolve core directories
    (set final-config.config_dir (if (or (= final-config.config_dir "") (not final-config.config_dir))
                                    global-config-dir
                                    (expand-path final-config.config_dir)))

    (set final-config.data_dir (if (or (= final-config.data_dir "") (not final-config.data_dir))
                                  (get-default-data-dir)
                                  (expand-path final-config.data_dir)))

    {:config final-config}))

;; Export for testing
(set M._testing {:load-config-internal load-config-internal})

;; State definitions
(local states {:not-started " "
               :in-progress "-"
               :blocked "="
               :completed :x
               :cancelled "_"})

;; Cycle order: not-started -> in-progress -> blocked -> completed -> cancelled -> not-started
(local state-cycle [" " "-" "=" :x "_"])

(fn get-action-state-node [bufnr linenr]
  "Use Tree-sitter to find the state value node on the given line"
  (let [ok (pcall vim.treesitter.get_parser bufnr :actions)]
    (if ok
        (let [parser (vim.treesitter.get_parser bufnr :actions)
              tree (. (parser:parse) 1)
              root (tree:root)
              query (vim.treesitter.query.parse :actions
                      "((state [
                         (state_not_started)
                         (state_completed)
                         (state_in_progress)
                         (state_blocked)
                         (state_cancelled)
                        ] @val))")]
          (var found-node nil)
          (each [id node (query:iter_captures root bufnr linenr (+ linenr 1))]
            (set found-node node))
          found-node)
        nil)))

(fn M.cycle-state []
  "Cycle through states using Tree-sitter AST and auto-add completion date"
  (let [bufnr (vim.api.nvim_get_current_buf)
        linenr (- (vim.fn.line ".") 1)
        node (get-action-state-node bufnr linenr)]
    (if node
        (let [current (vim.treesitter.get_node_text node bufnr)]
          (var ns " ")
          (each [i state (ipairs state-cycle)]
            (when (= state current)
              (let [next-idx (if (< i (length state-cycle)) (+ i 1) 1)]
                (set ns (. state-cycle next-idx))
                (lua :break))))
          (let [(srow scol erow ecol) (node:range)]
            (vim.api.nvim_buf_set_text bufnr srow scol erow ecol [ns]))
          ;; Auto-add completion date if state is now 'x'
          (when (= ns :x)
            (let [line (vim.fn.getline (+ linenr 1))]
              (when (not (line:find "%%[0-9]"))
                (let [now (vim.fn.strftime "%Y-%m-%dT%H:%M")
                      new-line (.. line " %" now)]
                  (vim.fn.setline (+ linenr 1) new-line))))))
        (vim.notify "No action state found on this line" vim.log.levels.WARN))))

(fn M.set-state [state]
  "Set the state of the current line to a specific state using Tree-sitter"
  (fn []
    (let [bufnr (vim.api.nvim_get_current_buf)
          linenr (- (vim.fn.line ".") 1)
          node (get-action-state-node bufnr linenr)]
      (if node
          (do
            (let [(srow scol erow ecol) (node:range)]
              (vim.api.nvim_buf_set_text bufnr srow scol erow ecol [state]))
            ;; Auto-add completion date if state is 'x'
            (when (= state :x)
              (let [line (vim.fn.getline (+ linenr 1))]
                (when (not (line:find "%%[0-9]"))
                  (let [now (vim.fn.strftime "%Y-%m-%dT%H:%M")
                        new-line (.. line " %" now)]
                    (vim.fn.setline (+ linenr 1) new-line))))))
          (vim.notify "No action state found on this line" vim.log.levels.WARN)))))

(fn M.get-status []
  "Return a status string for the current buffer using Tree-sitter"
  (let [bufnr (vim.api.nvim_get_current_buf)
        ok (pcall vim.treesitter.get_parser bufnr :actions)]
    (if ok
        (let [parser (vim.treesitter.get_parser bufnr :actions)
              tree (. (parser:parse) 1)
              root (tree:root)
              query (vim.treesitter.query.parse :actions
                      "((state [
                         (state_not_started)
                         (state_completed)
                         (state_in_progress)
                         (state_blocked)
                         (state_cancelled)
                        ] @val))")]
          (var total 0)
          (var completed 0)
          (each [id node (query:iter_captures root bufnr 0 -1)]
            (set total (+ total 1))
            (when (= (vim.treesitter.get_node_text node bufnr) :x)
              (set completed (+ completed 1))))
          (if (> total 0)
              (.. "✓ " completed "/" total)
              ""))
        "")))

(fn M.smart-new-action []
  "Create a new action line below, inheriting depth and markers using Tree-sitter"
  (let [bufnr (vim.api.nvim_get_current_buf)
        linenr (- (vim.fn.line ".") 1)
        ;; captures current action node
        parser (vim.treesitter.get_parser bufnr :actions)
        tree (. (parser:parse) 1)
        root (tree:root)
        node (root:named_descendant_for_range linenr 0 linenr -1)]
    (var depth-markers "")
    (var current node)
    ;; Walk up to find depth markers or action types
    (while current
      (let [type (current:type)]
        (if (type:find "depth(%d)_action")
            (let [depth (type:match "depth(%d)_action")
                  markers (string.rep ">" (tonumber depth))]
              (set depth-markers markers)
              (set current nil)) ; stop
            (set current (current:parent)))))

    (let [line (vim.fn.getline (+ linenr 1))
          indent (line:match "^(%s*)")
          now (vim.fn.strftime "%Y-%m-%dT%H:%M")
          prefix (.. indent depth-markers (if (> (length depth-markers) 0) " " ""))]
      (vim.fn.append (+ linenr 1) (.. prefix "[ ]  ^" now))
      (vim.fn.cursor (+ linenr 2) (+ (length (.. prefix "[ ] ")) 1))
      (vim.cmd :startinsert!))))

(fn get-bin-path []
  "Get the path to the clearhead_cli binary"
  (let [bin-name :clearhead_cli]
    (if (and config.nvim_lsp_binary_path (not= config.nvim_lsp_binary_path ""))
        (let [expanded (expand-path config.nvim_lsp_binary_path)]
          (if (= (vim.fn.executable expanded) 1)
              expanded
              nil))
        (if (= (vim.fn.executable bin-name) 1)
            bin-name
            (let [cargo-bin (.. (vim.fn.expand "~") :/.cargo/bin/clearhead_cli)]
              (if (= (vim.fn.executable cargo-bin) 1)
                  cargo-bin
                  nil))))))

(fn M.archive []
  "Archive completed actions from current buffer (prefers LSP command)"
  (let [bufnr (vim.api.nvim_get_current_buf)
        clients (vim.lsp.get_clients {:name :clearhead-lsp : bufnr})]
    (if (> (length clients) 0)
        (let [client (. clients 1)
              uri (vim.uri_from_bufnr bufnr)]
          (client.request :workspace/executeCommand
                          {:command :clearhead/archive
                           :arguments [uri]}
                          (fn [err result]
                            (when err
                              (vim.notify (.. "LSP Archive failed: " err.message)
                                          vim.log.levels.ERROR)))))
        ;; Fallback to CLI job
        (let [filename (vim.api.nvim_buf_get_name bufnr)
              bin (get-bin-path)]
          (if (and (not= filename "") bin)
              (do
                (vim.cmd :write)
                (vim.fn.jobstart [bin :archive filename]
                                 {:on_exit (fn [_ exit-code]
                                             (if (= exit-code 0)
                                                 (do
                                                   (vim.schedule (fn []
                                                                   (vim.api.nvim_command :edit!)
                                                                   (vim.notify "Archived completed actions."))))
                                                 (vim.notify "Archive failed." vim.log.levels.ERROR)))
                                  :on_stdout (fn [_ data]
                                               (when (and data (> (length data) 0))
                                                 (let [msg (table.concat data "\n")]
                                                   (when (and (not= msg "") (not (msg:find "^%s*$")))
                                                     (vim.notify msg)))))
                                  :on_stderr (fn [_ data]
                                               (when (and data (> (length data) 0))
                                                 (let [msg (table.concat data "\n")]
                                                   (when (and (not= msg "") (not (msg:find "^%s*$")))
                                                     (vim.notify (.. "Archive error: " msg)
                                                                 vim.log.levels.ERROR)))))}))
              (vim.notify "Cannot archive: buffer has no file or CLI not found."
                          vim.log.levels.ERROR))))))

(fn M.normalize [bufnr]
  "Runs clearhead_cli normalize on the buffer's file if CLI is available."
  (let [filename (vim.api.nvim_buf_get_name bufnr)
        bin (get-bin-path)]
    (when (and (not= filename "") bin)
      (vim.fn.jobstart [bin :normalize filename :--write]
                       {:on_exit (fn [_ exit-code]
                                   (when (= exit-code 0)
                                     ;; Reload the buffer to see the new IDs
                                     (vim.schedule (fn []
                                                     (vim.api.nvim_command :checktime)))))
                        :on_stderr (fn [_ data]
                                     (when (and data (> (length data) 0))
                                       (let [msg (table.concat data "\n")]
                                         (when (not= msg "")
                                           (vim.notify (.. "clearhead_cli normalize error: "
                                                           msg)
                                                       vim.log.levels.ERROR)))))})
      nil)))

(fn M.format []
  "Format the current buffer using LSP (preferred) or CLI"
  (let [bufnr (vim.api.nvim_get_current_buf)
        attached (vim.lsp.get_clients {:name :clearhead-lsp : bufnr})]
    (if (> (length attached) 0)
        (vim.lsp.buf.format {:name :clearhead-lsp : bufnr})
        (let [all-clients (vim.lsp.get_clients {:name :clearhead-lsp})]
          (if (> (length all-clients) 0)
              (do
                (M.attach-lsp bufnr)
                (vim.schedule (fn [] (vim.lsp.buf.format {:name :clearhead-lsp : bufnr}))))
              (when config.nvim_auto_normalize
                (M.normalize bufnr)))))))

(fn M.get-conform-opts []
  "Returns configuration for conform.nvim"
  {:formatters_by_ft {:actions [:clearhead_cli]}
   :formatters {:clearhead_cli {:command :clearhead_cli
                                :args [:format :$FILENAME]
                                :stdin false}}})

(fn M.open-inbox []
  "Open the configured inbox file"
  (let [ctx (load-config-internal)
        cfg ctx.config
        inbox-path (if (and cfg.nvim_inbox_file (not= cfg.nvim_inbox_file ""))
                       (expand-path cfg.nvim_inbox_file)
                       (let [base (expand-path cfg.data_dir)]
                         (.. base :/ cfg.default_file)))]
    (vim.cmd (.. "edit " inbox-path))))

(fn M.open-workspace []
  "Open the workspace directory for browsing action files"
  (let [workspace (expand-path config.data_dir)]
    (vim.cmd (.. "edit " workspace))))

(fn M.attach-lsp [bufnr]
  "Attach the Language Server to a specific buffer"
  (let [bin (get-bin-path)]
    (when (and config.nvim_lsp_enable bin)
      ;; Use global data directory as LSP root (configurable via config.data_dir)
      (let [root (expand-path config.data_dir)]
        (vim.lsp.start {:name :clearhead-lsp
                        :cmd [bin :lsp]
                        :root_dir root} {:bufnr bufnr})))))

(fn M.setup-lsp [group]
  "Setup the Language Server for .actions files"
  (let [bin (get-bin-path)]
    (if (and config.nvim_lsp_enable bin)
        (vim.api.nvim_create_autocmd :FileType
                                     {:pattern :actions
                                      : group
                                      :callback (fn [args]
                                                  (M.attach-lsp args.buf))})
        (when (and config.nvim_lsp_enable (not bin))
          (vim.notify "clearhead_cli binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory."
                      vim.log.levels.WARN)))))

(fn M.setup [opts]
  ;; Load configuration from all sources
  (let [ctx (load-config-internal opts)]
    (set config ctx.config))

  (let [group (vim.api.nvim_create_augroup :clearhead {:clear true})]
    ;; Setup LSP
    (M.setup-lsp group)
    ;; Format/Normalize on save
    (when config.nvim_format_on_save
      (vim.api.nvim_create_autocmd :BufWritePre
                                   {:pattern :*.actions
                                    : group
                                    :callback (fn [] (M.format))}))
    ;; Set buffer-local settings and mappings for actions files
    (vim.api.nvim_create_autocmd :FileType
                                 {:pattern :actions
                                  : group
                                  :callback (fn [args]
                                              (set vim.opt_local.conceallevel 2)
                                              (set vim.opt_local.concealcursor
                                                   :nc)
                                              ;; Ensure LSP is attached (callback above handles it too but being explicit helps)
                                              (M.attach-lsp args.buf)
                                              (when config.nvim_default_mappings
                                                (let [opts {:buffer true}]
                                                  (vim.keymap.set :n :<localleader><space> M.cycle-state (vim.tbl_extend :force opts {:desc "Cycle action state"}))
                                                  (vim.keymap.set :n :<localleader>f M.format (vim.tbl_extend :force opts {:desc "Format action file"}))
                                                  (vim.keymap.set :n :<localleader>i M.open-inbox (vim.tbl_extend :force opts {:desc "Open inbox"}))
                                                  (vim.keymap.set :n :<localleader>p M.open-workspace (vim.tbl_extend :force opts {:desc "Browse workspace"}))
                                                  (vim.keymap.set :n :<localleader>a M.archive (vim.tbl_extend :force opts {:desc "Archive completed actions"}))
                                                  (vim.keymap.set :n :<localleader>o M.smart-new-action (vim.tbl_extend :force opts {:desc "New action below"}))
                                                  ;; Specific state mappings
                                                  (vim.keymap.set :n :<localleader>x (M.set-state :x) (vim.tbl_extend :force opts {:desc "Set state to Completed"}))
                                                  (vim.keymap.set :n :<localleader>- (M.set-state :-) (vim.tbl_extend :force opts {:desc "Set state to In Progress"}))
                                                  (vim.keymap.set :n :<localleader>= (M.set-state :=) (vim.tbl_extend :force opts {:desc "Set state to Blocked"}))
                                                  (vim.keymap.set :n :<localleader>_ (M.set-state :_) (vim.tbl_extend :force opts {:desc "Set state to Cancelled"})))))})
    ;; Create user commands
    (vim.api.nvim_create_user_command :ClearheadInbox M.open-inbox {})
    (vim.api.nvim_create_user_command :ClearheadWorkspace M.open-workspace {})))

M
