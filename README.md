# 🌐 i18n.nvim

A lightweight Neovim plugin for displaying and managing project i18n (translation) files directly in the editor.  
Designed to work across most project types (front-end, backend, mixed monorepos), supporting JSON, YAML, Java .properties, and JS/TS translation modules (Tree-sitter parses JS/TS translation objects).

> [!WARNING]
> This plugin is currently in an early stage of rapid validation and development. Configuration and API may change significantly at any time. Please use with caution and keep an eye on the changelog.

## ✨ Key Features

- 📄 Parse translation files (JSON, YAML, .properties, JS/TS via Tree-sitter).
- 🧩 Flatten nested translation objects into dot-separated keys (e.g. `system.title`).
- 🗂 Flexible project configuration (locales & file patterns).
- 👁 Inline virtual text & popup helpers to preview translations.
- 🔁 Recursive placeholder expansion in file patterns (e.g. `{module}`, `{locales}`).
- ⚡ Fast, zero-dependency core (Neovim built-ins + Tree-sitter).

## 📦 Requirements

- Neovim 0.8+ (Tree-sitter integration required)
- A Tree-sitter parser for JavaScript/TypeScript installed for files parsing

## 🛠 Installation (lazy.nvim)

Example configuration using lazy.nvim:

```lua
{
  'yelog/i18n.nvim',
  lazy = true,
  ft = { "vue", "typescript" },
  dependencies = {
    'ibhagwan/fzf-lua',
    'nvim-treesitter/nvim-treesitter'
  },
  config = function()
    require('i18n').setup({
      -- Locales to parse; first is the default locale
      -- Use I18nNextLocale command to switch the default locale in real time
      locales = { 'en', 'zh' },
      -- sources can be string or table { pattern = "...", prefix = "..." }
      sources = {
        'src/locales/{locales}.json',
        -- { pattern = "src/locales/lang/{locales}/{module}.ts",            prefix = "{module}." },
        -- { pattern = "src/views/{bu}/locales/lang/{locales}/{module}.ts", prefix = "{bu}.{module}." },
      },
      -- function patterns used to detect i18n keys in code
      func_pattern = {
        -- t('key') or t("key")
        "t%(['\"]([^'\"]+)['\"]",
        -- $t('key') or $t("key")
        "%$t%(['\"]([^'\"]+)['\"]",
      },
    })
  end
}
```

## 🚀 Quickstart

1. Install the plugin with lazy.nvim (see above).
2. Configure `sources` and `locales` to match your project layout.
3. Ensure Tree-sitter parsers for JavaScript / TypeScript are installed (e.g. via nvim-treesitter).
4. Open a source file and use the provided commands / keymaps to show translations and inline virtual text.

## 🎛 Keymaps & Commands

Recommended keymaps (example using lazy-loaded setup):
```lua
-- Fuzzy find i18n keys (fzf integration)
vim.keymap.set("n", "<leader>fi", require("i18n").show_i18n_keys_with_fzf, { desc = "Fuzzy find i18n key" })
vim.keymap.set("n", "<D-S-n>", require("i18n").show_i18n_keys_with_fzf, { desc = "Fuzzy find i18n key" })
-- Actions inside the picker (defaults / Vim style key notation):
--  <CR>    : copy key
--  <C-y>   : copy current locale translation
--  <C-j>   : jump (current display locale, fallback default)
--  <C-l>   : choose locale then jump (secondary picker)
--  <C-x>   : horizontal split jump
--  <C-v>   : vertical split jump
--  <C-t>   : tab jump
-- You can override these in setup(): fzf.keys = { jump = { "<c-j>" }, choose_locale_jump = { "<c-l>" } }
```


```lua
-- Cycle display language (rotates locales; updates inline virtual text)
vim.keymap.set("n", "<D-S-M-n>", "<cmd>I18nNextLocale<CR>", { desc = "Cycle i18n display language" })
-- Toggle whether inline shows the translated text or the raw i18n key
vim.keymap.set("n", "<leader>io", "<cmd>I18nToggleOrigin<CR>", { desc = "Toggle i18n origin display" })
```

Commands:
- 🔄 :**I18nNextLocale**
  Cycles the active display language used for inline virtual text. It moves to the next entry in `locales` (wrapping back to the first). Inline overlays refresh automatically.
- 👁 :**I18nToggleOrigin**
  Toggles between showing the translated text (current language) and the raw/original i18n key in inline virtual text. When disabled you can easily copy / inspect the key names; toggling again restores the translation overlay.
- 💡 :**I18nToggleTranslation**
  Toggles the inline translation overlay globally (show_translation). When disabled, no translated text is rendered (only original buffer content and/or keys if show_origin is enabled). Re-enable to restore translated overlays.
- 📝 :**I18nToggleLocaleFileEol**
  Toggles showing end-of-line translations in locale source files (per i18n key line). When enabled, each key line in a locale translation file shows the current display locale’s translation as EOL virtual text; disabling hides these overlays (useful for focused editing or cleaner diffs).

## 🔌 blink.cmp Integration

The plugin provides a blink.cmp source (`i18n.integration.blink_source`) that:
- Offers completion items where the label and inserted text are the i18n key.
- Shows the key itself in the detail field (so the preview panel title is stable / language-agnostic).
- Resolves full multi-language translations in the documentation panel (each language on its own line).
- Plays nicely with other sources (LSP, snippets, path, buffer, etc).

Example blink.cmp configuration:
```lua
require('blink.cmp').setup({
  sources = {
    default = { 'i18n', 'snippets', 'lsp', 'path', 'buffer' },
    -- cmdline = {}, -- optionally disable / customize cmdline sources
    providers = {
      lsp = { fallbacks = {} },
      i18n = {
        name = 'i18n',
        module = 'i18n.integration.blink_source',
        opts = {
          -- future options can be placed here
        },
      },
    },
  },
})
```

> [!WARNING]
> Since `blink.cmp` uses a dot (`.`) as a separator for queries, and our i18n keys are also separated by dots, it's recommended to avoid entering dots when searching for keys. For example, instead of typing `common.time.second`, you can type `commonseco` to fuzzy match the i18n key, then press `<c-y>` (or whatever shortcut you have set) to complete the selection.


## ⚙️ Configuration

The plugin exposes `require('i18n').setup(opts)` where `opts` is merged with defaults.

Merge precedence (highest last):
1. Built-in defaults (internal)
2. Options passed to `require('i18n').setup({...})`
3. Project-level config file in the current working directory (if present)

So a project config will override anything you set in your Neovim config for that particular project.

Common options (all optional when a project file is present):
- locales: array of language codes, first is considered default
- sources: array of file patterns or objects:
  * string pattern e.g. `src/locales/{locales}.json`
  * table: `{ pattern = "pattern", prefix = "optional.prefix." }`
- func_pattern: array of Lua patterns to locate i18n function usages in source files
- show_translation / show_origin: control inline rendering behavior
- filetypes / ft: restrict which filetypes are processed
- diagnostic: controls missing translation diagnostics (see below):
  * `false`: disable diagnostics entirely (existing ones are cleared)
  * `true`: enable diagnostics with default behavior (ERROR severity for missing translations)
  * `{ ... }` (table): enable diagnostics and pass the table as the 4th argument to `vim.diagnostic.set` (e.g. `{ underline = false, virtual_text = false }`)

Diagnostics
If `diagnostic` is enabled (true or a table), the plugin emits diagnostics for missing translations at the position of the i18n key. When a table is provided, it is forwarded verbatim to `vim.diagnostic.set(namespace, bufnr, diagnostics, opts)` allowing you to tune presentation (underline, virtual_text, signs, severity_sort, etc). Setting `diagnostic = false` both suppresses generation and clears previously shown diagnostics for the buffer.

Patterns support placeholders like `{locales}` and custom variables such as `{module}` which will be expanded by scanning the project tree.

Navigation
Jump from an i18n key usage to its definition (default locale file + line) using an explicit helper function:
Helper: require('i18n').i18n_definition() -> boolean
Unified API: all public helpers are available via require('i18n') (e.g. i18n_definition, show_popup, reload_project_config, next_locale).
Returns true if it jumped, false if no i18n key / location found (so you can fallback to LSP).

Example keymap that prefers i18n, then falls back to LSP definition:
```lua
vim.keymap.set('n', 'gd', function()
  if not require('i18n').i18n_definition() then
    vim.lsp.buf.definition()
  end
end, { desc = 'i18n or LSP definition' })
```

Separate key (only i18n):
```lua
vim.keymap.set('n', 'gK', function()
  require('i18n').i18n_definition()
end, { desc = 'Jump to i18n definition' })
```

Configuration option:
navigation = {
  open_cmd = "edit", -- or 'vsplit' | 'split' | 'tabedit'
}

Line numbers are best-effort for JSON/YAML/.properties (heuristic matching); JS/TS uses Tree-sitter for higher accuracy.

Popup helper (returns boolean)
You can show a transient popup of all translations for the key under cursor:
Helper: require('i18n').show_popup() -> boolean
Returns true if a popup was shown, false if no key / translations found.

Example combined mapping (try popup first, else fallback to signature help):
```lua
vim.keymap.set({ "n", "i" }, "<C-k>", function()
  if not require('i18n').show_popup() then
    vim.lsp.buf.signature_help()
  end
end, { desc = "i18n popup or signature help" })
```


### 🏗 Project-level Configuration (recommended)

You can place a project-specific config file at the project root. The plugin will auto-detect (in order) the first existing file:
- `.i18nrc.json`
- `i18n.config.json`
- `.i18nrc.lua`

If found, its values override anything you passed to `setup()`.

Example `.i18nrc.json`:
```json
{
  "locales": ["en_US", "zh_CN"],
  "sources": [
    "src/locales/{locales}.json",
    { "pattern": "src/locales/lang/{locales}/{module}.ts", "prefix": "{module}." }
  ]
}
```

Example `.i18nrc.lua`:
```lua
return {
  locales = { "en_US", "zh_CN" },
  sources = {
    "src/locales/{locales}.json",
    { pattern = "src/locales/lang/{locales}/{module}.ts", prefix = "{module}." },
  },
  func_pattern = {
    "t%(['\"]([^'\"]+)['\"]",
    "%$t%(['\"]([^'\"]+)['\"]",
  },
  show_translation = true,
  show_origin = false,
}
```

Minimal Neovim config (global defaults) – can be empty or partial:
```lua
require('i18n').setup({
  locales = { 'en', 'zh' },  -- acts as a fallback if project file absent
  sources = { 'src/locales/{locales}.json' },
})
```

If later you add a project config file, just reopen the project (or call:
```lua
require('i18n').reload_project_config()
require('i18n').setup(require('i18n').options)
```
) to apply overrides.

### Notes
- Unknown fields in project config are ignored.
- You can keep a very small user-level setup and let each project define its own structure.
- If you frequently switch branches that add/remove locale files, you may want to trigger a manual reload (e.g. a custom command that re-runs `setup()`).

## 🧠 How It Works

- JSON/YAML/.properties files are read and decoded (.properties uses simple key=value parsing; YAML uses a simplified parser covering only common scenarios).
- JS/TS modules are parsed with Tree-sitter to find exported objects (supports `export default`, `module.exports`, direct object literals, and nested objects). Parsed keys and string values are normalized (quotes removed) and flattened.
- Translations are merged into an internal table keyed by language and dot-separated keys.

## 📗 Use Case

> [!NOTE]
> If you work on multiple projects, keep the config in the project root to avoid editing your global Neovim config when switching.
> All examples below use a project-level config; see [Project-level Configuration (recommended)](#-project-level-configuration-recommended).

### Simple JSON i18n

One JSON file per locale

```bash
projectA
├── src
│   ├── App.vue
│   ├── locales
│   │   ├── en.json
│   │   └── zh.json
│   └── main.ts
├── package.json
├── tsconfig.json
└── vite.config.ts
```
Create a `.i18nrc.lua` file at the project root:
```lua
return {
  locales = { "en", "zh" },
  sources= { 
    "src/locales/{locales}.json"
  }
}
```

### Multi-module i18n

```bash
projectB
├── src
│   ├── App.vue
│   ├── locales
│   │   ├── en-US
│   │   │   ├── common.ts
│   │   │   ├── system.ts
│   │   │   └── ui.ts
│   │   └── zh-CN
│   │       ├── common.ts
│   │       ├── system.ts
│   │       └── ui.ts
│   └── main.ts
├── package.json
├── tsconfig.json
└── vite.config.ts
```
Create a `.i18nrc.lua` file at the project root:
```lua
return {
    locales = { "en-US", "zh-CN" },
    sources = {
        { pattern = "src/locales/{locales}/{module}.ts", prefix = "{module}." }
    }
}
```

### Multi-module multi-business i18n
```bash
projectC
├── src
│   ├── App.vue
│   ├── locales
│   │   ├── en-US
│   │   │   ├── common.ts
│   │   │   ├── system.ts
│   │   │   └── ui.ts
│   │   └── zh-CN
│   │       ├── common.ts
│   │       ├── system.ts
│   │       └── ui.ts
│   ├── views
│   │   ├── gmail
│   │   │   └── locales
│   │   │       ├── en-US
│   │   │       │   ├── inbox.ts
│   │   │       │   ├── compose.ts
│   │   │       │   └── settings.ts
│   │   │       └── zh-CN
│   │   │           ├── inbox.ts
│   │   │           ├── compose.ts
│   │   │           └── settings.ts
│   │   ├── calendar
│   │   │   └── locales
│   │   │       ├── en-US
│   │   │       │   ├── events.ts
│   │   │       │   ├── reminders.ts
│   │   │       │   └── settings.ts
│   │   │       └── zh-CN
│   │   │           ├── events.ts
│   │   │           ├── reminders.ts
│   │   │           └── settings.ts
│   │   └── search
│   │       └── locales
│   │           ├── en-US
│   │           │   ├── query.ts
│   │           │   ├── results.ts
│   │           │   └── filters.ts
│   │           └── zh-CN
│   │               ├── query.ts
│   │               ├── results.ts
│   │               └── filters.ts
│   └── main.ts
├── package.json
├── tsconfig.json
└── vite.config.ts
```
With the distributed i18n files below, create a `.i18nrc.lua` at the project root:
```lua
return {
    locales = { "en-US", "zh-CN" },
    sources = {
      { pattern = "src/locales/{locales}/{module}.ts", prefix = "{module}." },
      { pattern = "src/views/{business}/locales/{locales}/{module}.ts", prefix = "{business}.{module}." }
    }
}
```

## 🤝 Contributing

Contributions, bug reports and PRs are welcome. Please:

1. Open an issue with reproducible steps.
2. Submit PRs with unit-tested or manually verified changes.
3. Keep coding style consistent with the repository.

## 🩺 Troubleshooting

- If JS/TS parsing fails, ensure Tree-sitter parsers are installed and up-to-date.
- If some values still contain quotes, ensure the source file uses plain string literals; complex template literals or expressions may need custom handling.

## 📄 License

Apache-2.0 License. See [LICENSE](LICENSE) for details.
