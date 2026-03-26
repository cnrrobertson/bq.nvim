# bq.nvim

A BigQuery client for Neovim. Run queries, browse schemas, and view results in a tabbed panel — powered by the `bq` CLI.

## Requirements

- [Google Cloud SDK](https://cloud.google.com/sdk) (`bq`, `gcloud`)
- Neovim 0.10+

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cnrrobertson/bq.nvim",
  config = function()
    require("bq").setup()
  end,
}
```

Using [mini.deps](https://github.com/echasnovski/mini.deps):

```lua
require("mini.deps").add({ source = "cnrrobertson/bq.nvim" })
require("bq").setup()
```

## Setup

```lua
require("bq").setup({
  windows = {
    position = "below", -- "above" | "below" | "left" | "right"
    size = 0.35,        -- fraction of screen (< 1) or fixed lines/columns (>= 1)
  },
  winbar = {
    show = true,
    show_keymap_hints = true,
    default_section = "results",
    sections = { "results", "stats", "history", "schema" },
  },
  preview = {
    max_width  = 120,   -- max columns for the row preview float
    max_height = 40,    -- max lines for the row preview float
  },
  bq_path = "bq",       -- path to bq CLI
  max_results = 1000,   -- max rows returned per query
})
```

## Commands

All commands go through `:BQ <subcommand>`.

| Command | Description |
|---|---|
| `:BQ toggle` | Toggle the panel open/closed |
| `:BQ open` | Open the panel |
| `:BQ close` | Close the panel |
| `:BQ connect [project]` | Connect to a project (omit to use gcloud default) |
| `:BQ run` | Run current buffer as SQL |
| `:'<,'>BQ run` | Run visual selection as SQL |
| `:BQ schema [dataset]` | Open schema browser (optionally scoped to a dataset) |
| `:BQ view <name>` | Switch to a named tab (results, stats, history, schema, debug) |
| `:BQ navigate <n>[!]` | Navigate n sections forward (use `!` to wrap) |

## Keymaps

These are active inside the bq panel buffer:

| Key | Action |
|---|---|
| `R` | Results view |
| `S` | Stats view |
| `H` | History view |
| `C` | Schema view |
| `]v` | Next section |
| `[v` | Previous section |
| `gr` | Re-run last query |
| `<CR>` | Replay query (History) / drill down (Schema) |
| `-` | Go up one level (Schema) |
| `q` | Close panel |
| `g?` | Show help |

## Views

**Results** — Query output rendered as a formatted table. NULL values are highlighted.

**Stats** — Execution metadata: status, row count, elapsed time, bytes processed/billed, cache hit, slot ms, job ID, and connected project.

**History** — All queries from the current session in reverse order. Shows status, timestamp, elapsed time, project, and a SQL preview. Press `<CR>` to replay.

**Schema** — A three-level browser: datasets → tables → field definitions (name, type, mode, description). Also shows row count, table size, and creation time.

## Highlights

Override any of these in your colorscheme:

| Group | Used for |
|---|---|
| `BQTab` | Inactive winbar tabs |
| `BQTabSelected` | Active winbar tab |
| `BQTabFill` | Winbar background |
| `BQHeader` | Column headers |
| `BQStatKey` | Stat label keys |
| `BQHistoryOk` | Successful query indicator |
| `BQHistoryErr` | Failed query indicator |
| `BQNullValue` | NULL values in results |
| `BQBorderChar` | Table border characters |
| `BQLoading` | Loading text |
| `BQMissingData` | Empty state messages |

## Acknowledgements

The panel UI — split window, winbar tabs, single shared buffer, cursor-position-per-view — is directly inspired by [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view).
