# csvtab (extended)

A [Total Commander](https://www.ghisler.com/) Lister (WLX) plugin to view,
filter, search, **edit** and **transform** CSV / TSV / TAB files.

![edit](CSV_Edit.png)
![transform](CSV_Transformation.png)

This is an extended native Lazarus/FPC rewrite of the original
[csvtab-wlx](https://github.com/little-brother/csvtab-wlx) by *little-brother*.
It keeps the fast Lister workflow, but turns CSV viewing into a compact table
workbench: open messy files, inspect them, filter and sort them, edit real CSV
cells, try column transformations, and copy or export exactly what you need.

---

## Feature Highlights

### Open messy CSV files with confidence

csvtab is built for the kind of CSV files that are almost, but not quite,
regular.

* Detects ANSI, UTF-8, UTF-16LE and UTF-16BE, including BOM handling.
* Detects common delimiters automatically: comma, semicolon, TAB, pipe and colon.
* Supports quoted CSV, doubled quotes, multiline cells and empty trailing cells.
* Detects the effective column count from a configurable sample and treats short
  preamble rows before the first full-width row as comments.
* Skips leading comment/preamble rows in Auto/Hidden mode, including `#`,
  `sep=` and single-semicolon comment lines.
* Reports the configured size limit and real file size when a file is too large
  to load.

### Fast table view

* Native owner-data ListView for large tables.
* Lazy cell value decoding: only sampled values are decoded immediately; the
  rest is decoded on demand and then in small background batches.
* Column widths are calculated before the grid is shown, so the first paint uses
  the final widths.
* Optional line-number column sized from the largest visible row number.
* Alternating row colours, current-cell highlight, dark mode and configurable
  fonts/colours.
* Header text is bold, column dragging is disabled, and header/filter columns
  stay aligned during horizontal scrolling and column resizing.

### Filters that stay responsive

* One filter field per data column, placed above the header.
* Filter expressions support text matching and the existing comparison
  operators.
* Filter changes are debounced: the table is updated **250 ms after the last
  keystroke**, which keeps larger files much smoother while typing.
* `Esc` inside a filter field only returns focus to the table; it does not close
  the Lister.

### Navigate like a spreadsheet

* Arrow keys move the current cell up, down, left and right.
* At the visible window edge, the table scrolls by row or column as needed.
* **Ctrl+Arrow** jumps to the first/last row or first/last visible column.
* Hidden columns are skipped during horizontal navigation.

### Edit real CSV data safely

Edit mode turns the viewer into a careful CSV editor without throwing away the
original file structure.

* Toggle **Edit mode** with **Ctrl+E** or **Ctrl+R**.
* Start editing the selected cell with **Enter**, **F2** or double-click.
* **Enter** accepts an active edit, **Esc** cancels it.
* Insert a new empty row below the current row from the context menu.
* Delete selected rows with **Ctrl+X** or the context menu.
* Delete a column from the header/context menu in Edit mode.
* Save with **Ctrl+S**. Saving is atomic and preserves encoding, BOM, delimiter
  and comment handling as far as possible.
* Dirty files are marked in the status bar and prompt before close or reload.

### Transform columns without touching the original

**Transform mode** opens a sidebar for trying column operations as a live,
read-only preview. The source file is not changed until you explicitly export.

| Area | What it does |
|------|--------------|
| Ordering | Move columns up and down |
| Columns | Add, remove or rename columns |
| Values | Set all cells, fill only empty cells, enumerate rows, set number formats |
| Presets | Load and save transformations as JSON |
| Export | Write the transformed result to a new CSV with selectable delimiter |

Transform JSON files are compatible with the bundled Python workflow, so
repeatable cleanup jobs can be saved and reused.

### Status bar control

The status bar is interactive and reloads the document with the selected parser
settings:

| Segment | Options |
|---------|---------|
| Encoding | ANSI, UTF-8, UTF-16LE, UTF-16BE |
| Delimiter | Auto, comma, semicolon, pipe, TAB, colon |
| Comments | Auto, Parse normally, Do not parse, Hide |
| Rows | Visible/total row count |
| Position | Current `row:column`, edit/dirty/transform state |

The Comments segment also shows how many comment/preamble rows are hidden in
the current mode.

### Search, copy and URLs

* Total Commander search is supported via **F3** and **Shift+F3** for forward
  and backward search.
* **C** copies the current cell.
* **Shift+C** copies selected rows, respecting hidden columns and column order.
* **Ctrl+C** copies the current column if configured that way.
* The row-copy delimiter is configurable and defaults to TAB.
* **Alt+click** opens URLs found in cells.

### Decimal alignment

With `decimal-align=1` (default), numeric-looking columns are sampled and drawn
with decimal alignment:

* floats using `.` and `,` are aligned at the decimal separator;
* integer cells in mixed integer/float columns align directly before the decimal
  anchor;
* pure integer columns are right-aligned;
* nonnumeric columns keep normal text layout.

---

## Right-click Menu

The grid context menu keeps the everyday actions close to the table:

| Item | Shortcut |
|------|----------|
| Copy cell | C |
| Copy row(s) | Shift+C |
| Copy column | Ctrl+C |
| Insert row below | Edit mode only |
| Delete row(s) | Ctrl+X, Edit mode only |
| Delete column | Edit mode only |
| Hide column | Ctrl+click header |
| Show all columns | Ctrl+Space |
| Filters | toggle filter row |
| Header row | toggle first row as header |
| Edit mode | Ctrl+E |
| Transform mode | Ctrl+T |
| Save | Ctrl+S |
| Show line numbers | toggle line-number column |
| Dark theme | toggle dark colours |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Arrow keys | Move current cell up/down/left/right |
| Ctrl+Arrow keys | Jump to first/last row or first/last visible column |
| Enter / F2 / Double-click | Edit the current cell in Edit mode |
| Enter / Esc | Accept / cancel the active cell edit |
| Ctrl+E or Ctrl+R | Toggle Edit mode |
| Ctrl+T | Toggle Transform mode |
| Ctrl+X | Delete selected row(s) in Edit mode |
| Ctrl+S | Save the file |
| C | Copy current cell |
| Shift+C | Copy selected row(s) |
| Ctrl+C | Copy current column, depending on `copy-column` |
| Ctrl+Space | Show all columns |
| Ctrl++ / Ctrl+- | Increase / decrease font size |
| Ctrl+Mouse wheel | Zoom font |
| Alt+Click | Open URL in a cell |
| Click header | Sort column; third click restores original order |
| Ctrl+Click header | Hide column |
| F3 / Shift+F3 | Search forward / backward via Total Commander |
| Esc | Close Lister; inside filter, return focus to table |
| 1..8, N, P, Q | Forwarded to Total Commander according to INI options |
| F1 | Open the original wiki |

---

## Installation

1. Build the plugin with Free Pascal / Lazarus to produce `csvtab.wlx` and
   `csvtab.wlx64`.
2. In Total Commander open **Configuration -> Options -> Plugins -> Lister
   plugins (WLX) -> Configure -> Add**, then point it at the `.wlx` or `.wlx64`
   file. Total Commander can also install the packaged zip automatically via
   `pluginst.inf`.
3. Open any CSV/TSV/TAB file in Lister with **F3** or in the Quick View Panel
   with **Ctrl+Q**.

---

## Configuration

Settings live in `csvtab.ini` next to the plugin. A few common options:

| Key | Meaning |
|-----|---------|
| `font` / `font-size` / `font-weight` | Grid font |
| `start-mode` | Start in `default`, `editor` or `transformer` mode |
| `header-row` | Treat the first row as a header (0/1) |
| `filter-row` | Show the per-column filter row (0/1) |
| `show-line-numbers` | Show the row-number column on the left (0/1) |
| `decimal-align` | Align mixed integers/floats at the decimal position (0/1, default 1) |
| `dark-theme` | Use the dark colour set (0/1) |
| `skip-comments` | 0 parse / 1 keep comment as one cell / 2 hide / 3 auto-hide leading comments and blank rows |
| `default-column-delimiter` | Force a CSV delimiter; empty means auto-detect |
| `column-delimiter` | Delimiter used when copying rows (default TAB) |
| `trim-values` | Trim leading/trailing spaces and tabs (0/1) |
| `max-file-size` | Size limit in bytes (0 = unlimited) |
| `max-column-samples` | Rows sampled for width, used-column and numeric detection |
| `max-column-width` | Maximum automatic column width |
| `copy-column` | Ctrl+C copies cell (0) or column (1) |
| `filter-case-sensitive` | Case-sensitive filtering (0/1) |
| `disable-num-keys` | Do not forward number keys to Total Commander (0/1) |
| `disable-np-keys` | Do not forward N/P to Total Commander (0/1) |
| `exit-by-q` | Forward Q as close/exit key to Total Commander (0/1) |

All light- and dark-theme colours are configurable as RGB integers; see the
comments in `csvtab.ini` for the full list.

---

## Notes

* `default-column-delimiter` controls the delimiter used for parsing when set.
  `column-delimiter` controls the delimiter used when copying rows.
* `Comments: Auto` hides only the leading preamble/comment block. Later comment
  lines inside the table remain visible.
* `Comments: Hidden` hides comment lines and blank lines.
* The initial focus is placed on the table only in a separate Lister window; in
  Quick View the focus remains with Total Commander.

---

## Credits

Based on [csvtab-wlx](https://github.com/little-brother/csvtab-wlx) by
*little-brother*. Original project licensed under its respective terms; see
`LICENSE`.
