# Changelog

All notable changes to bq.nvim are documented here.

## [0.3.0] - 2026-04-09

### Added
- Row, cell, and column preview windows (`<CR>` row · `c` cell · `C` column)
- Visual row/column selection previews (`V<CR>` for selected rows, `^V<CR>` for selected columns)
- Client-side filter stack: `f` add filter · `<BS>` undo · `F` clear all
  - Filters stack with AND logic; `|` within a filter provides OR
  - Column-specific filters: `col=pattern`, `col!=pattern`
  - Bare pattern searches across all columns
  - Lua pattern support (case-insensitive, invalid patterns fail silently)
- CSV export (`e`) with configurable default directory and timestamped filename
- Open last exported CSV with system program (`o`), auto-exports to `/tmp/` if none yet
- Test suite using mini.test: config merging, filter logic, CSV escaping, rendering integration

## [0.2.0] - 2026-03-31

### Added
- Full-text search window (`/` and `?`) showing all rows without truncation
- Preview window dimensions configurable as fractions of editor size

### Fixed
- History replay no longer fails to switch to the results view
- Extmark namespace cleared before re-rendering to prevent virtual text accumulation

### Changed
- Results buffer overhauled to use inline virtual text extmarks for accurate cursor navigation

## [0.1.0] - 2026-03-26

### Added
- Panel with five views: Results, Stats, History, Schema, Debug
- Tabbed winbar with configurable keymaps and click support
- Run BigQuery SQL queries via the `bq` CLI (`bq query --format=prettyjson`)
- Results table with bordered columns, NULL highlighting, and truncation at 50 chars
- Query statistics: rows, bytes processed/billed, slot ms, cache hit, job ID, elapsed
- Query history with status icons and `<CR>` to replay
- Schema browser: navigate datasets → tables → fields via `bq ls` / `bq show`
- Error view with job reference, location, elapsed, console deep-link, and `o` to open in browser
- Async job execution; cancels in-flight jobs when a new query is submitted
- Configurable panel position/size, preview dimensions, max results, and `bq` CLI path
- MiniDoc-generated help documentation

[0.3.0]: https://github.com/cnrrobertson/bq.nvim/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cnrrobertson/bq.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cnrrobertson/bq.nvim/releases/tag/v0.1.0
