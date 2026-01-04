(local M {})

;; Internal state for the loaded configuration
(var config {:data_dir ""
             :config_dir ""
             :default_file "inbox.actions"
             :project_files ["next.actions"]
             :use_project_config true
             :nvim_auto_normalize true
             :nvim_format_on_save true
             :nvim_lsp_enable true
             :nvim_inbox_file ""
             :nvim_lsp_binary_path ""})

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
                  :CLEARHEAD_PROJECT_FILES :project_files
                  :CLEARHEAD_USE_PROJECT_CONFIG :use_project_config
                  :CLEARHEAD_NVIM_AUTO_NORMALIZE :nvim_auto_normalize
                  :CLEARHEAD_NVIM_FORMAT_ON_SAVE :nvim_format_on_save
                  :CLEARHEAD_NVIM_LSP_ENABLE :nvim_lsp_enable
                  :CLEARHEAD_NVIM_INBOX_FILE :nvim_inbox_file
                  :CLEARHEAD_NVIM_LSP_BINARY_PATH :nvim_lsp_binary_path}]
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

(fn discover-project [project-files]
  "Search upward for a project root"
  (var current (vim.fn.getcwd))
  (var found nil)
  (var depth 0)
  (while (and (not found) (< depth 100))
    (let [dot-clearhead (.. current :/.clearhead)]
      (if (= (vim.fn.isdirectory dot-clearhead) 1)
          (set found {:root current
                      :config (let [cfg (.. dot-clearhead :/config.json)]
                                (if (= (vim.fn.filereadable cfg) 1) cfg nil))
                      :default-file (.. dot-clearhead :/inbox.actions)})
          (do
            (each [_ f (ipairs project-files)]
              (let [f-path (.. current :/ f)]
                (if (and (not found) (= (vim.fn.filereadable f-path) 1))
                    (set found {:root current
                                :config (let [cfg (.. current :/.clearhead/config.json)]
                                          (if (= (vim.fn.filereadable cfg) 1) cfg nil))
                                :default-file f-path})))))))
    (if found
        nil
        (let [parent (vim.fn.fnamemodify current ":h")]
          (if (= parent current)
              (set depth 100)
              (do
                (set current parent)
                (set depth (+ depth 1)))))))
  found)

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
                  :project_files ["next.actions"]
                  :use_project_config true
                  :nvim_auto_normalize true
                  :nvim_format_on_save true
                  :nvim_lsp_enable true
                  :nvim_inbox_file ""
                  :nvim_lsp_binary_path ""}

        global-config-dir (get-default-config-dir)
        global-config-path (.. global-config-dir :/config.json)
        global-config (read-json-file global-config-path)

        ;; 1. Merge global config into defaults
        base-config (vim.tbl_extend :force defaults global-config)

        ;; 2. Project discovery (using project_files from combined defaults+global)
        project-context (if base-config.use_project_config
                             (discover-project base-config.project_files)
                             nil)

        ;; 3. Merge project config if found
        base-config (if (and project-context project-context.config)
                         (vim.tbl_extend :force base-config (read-json-file project-context.config))
                         base-config)

        ;; 4. Merge environment variables
        base-config (vim.tbl_extend :force base-config (load-env))

        ;; 5. Merge user options from setup()
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

    {:config final-config :project project-context}))

;; Export for testing
(set M._testing {:load-config-internal load-config-internal
                 :discover-project discover-project})

;; State definitions
(local states {:not-started " "
               :in-progress "-"
               :blocked "="
               :completed :x
               :cancelled "_"})

;; Cycle order: not-started -> in-progress -> blocked -> completed -> cancelled -> not-started
(local state-cycle [" " "-" "=" :x "_"])

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
            (lua :break))))
      (set-line-state linenr next-state))))

(fn M.set-state [state]
  "Set the state of the current line to a specific state"
  (fn []
    (let [linenr (vim.fn.line ".")]
      (set-line-state linenr state))))

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
  (let [clients (vim.lsp.get_clients {:name :clearhead-lsp})]
    (if (> (length clients) 0)
        (vim.lsp.buf.format {:name :clearhead-lsp})
        (when config.nvim_auto_normalize
          (M.normalize (vim.api.nvim_get_current_buf))))))

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
        project ctx.project
        inbox-path (if (and cfg.nvim_inbox_file (not= cfg.nvim_inbox_file ""))
                       (expand-path cfg.nvim_inbox_file)
                       (if (and project project.default-file)
                           project.default-file
                           (let [base (expand-path cfg.data_dir)]
                             (.. base :/ cfg.default_file))))]
    (vim.cmd (.. "edit " inbox-path))))

(fn M.open-dir []
  "Open the project default file or first .actions file in current directory"
  (let [project (discover-project config.project_files)]
    (if (and project project.default-file)
        (vim.cmd (.. "edit " project.default-file))
        (let [cwd (vim.fn.getcwd)
              actions-files (vim.fn.glob (.. cwd :/*.actions) true true)]
          (if (> (length actions-files) 0)
              (vim.cmd (.. "edit " (. actions-files 1)))
              (vim.notify "No .actions file found in current directory"
                          vim.log.levels.WARN))))))

(fn M.setup-lsp [group]
  "Setup the Language Server for .actions files"
  (let [bin (get-bin-path)]
    (if (and config.nvim_lsp_enable bin)
        (vim.api.nvim_create_autocmd :FileType
                                     {:pattern :actions
                                      : group
                                      :callback (fn [args]
                                                  (let [project (discover-project config.project_files)
                                                        root (or (and project project.root)
                                                                 (vim.fs.dirname args.file)
                                                                 (vim.fn.getcwd))]
                                                    (vim.lsp.start {:name :clearhead-lsp
                                                                    :cmd [bin :lsp]
                                                                    :root_dir root})))} )
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
    ;; Set conceallevel for a better UI experience
    (vim.api.nvim_create_autocmd :FileType
                                 {:pattern :actions
                                  : group
                                  :callback (fn []
                                              (set vim.opt_local.conceallevel 2)
                                              (set vim.opt_local.concealcursor
                                                   :nc))})
    ;; Create user commands
    (vim.api.nvim_create_user_command :ClearheadInbox M.open-inbox {})
    (vim.api.nvim_create_user_command :ClearheadOpenDir M.open-dir {})))

M
