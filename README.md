# csvtab (extended)

A [Total Commander](https://www.ghisler.com/) Lister (WLX) plugin to view, **edit** and
**transform** CSV / TSV / TAB files.

This is an extended rewrite of the original
[**csvtab-wlx**](https://github.com/little-brother/csvtab-wlx) by *little-brother*.
It keeps the original viewing experience and adds in-place editing, a column
transformation workbench with live preview, an interactive status bar, and a number
of usability features described below.

---

## Original features (inherited)

* Auto-detect code page and delimiter
* Per-column filters
* Sort data by clicking a column header
* Supports ANSI, UTF-8 and UTF-16 (LE/BE)

---

## What's new in this version

### ✏️ Edit mode

Edit cell values directly in the grid and write the result back to the source file,
preserving its original encoding and delimiter.

* Toggle edit mode with **Ctrl+E** (or **Ctrl+R**), via the right-click menu, or the
  status bar.
* Start editing a cell with **F2** or by **double-clicking** it.
* **Enter** accepts the change, **Esc** cancels it.
* Delete whole rows with **Ctrl+X** or the right-click menu (*Delete row(s)*). The
  selected rows are removed; with no selection the row under the cursor is deleted.
* **Ctrl+S** saves the file. Saving is **atomic** (write-to-temp + replace) so a failed
  write never corrupts the original file. Encoding, delimiter and comment handling are
  preserved on save.
* The status bar shows the current state: `EDIT`, `EDIT *` (unsaved edit) or `MODIFIED *`.
* If you close the viewer or reload the document with unsaved changes, you are asked
  whether to save first.

### 🔧 Transform mode (column workbench)

A side panel for reshaping the table without touching the source file, with a **live
preview** directly in the grid.

Toggle transform mode with **Ctrl+T**, via the right-click menu, or the status bar.

The sidebar groups the actions by purpose (each group is colour-coded):

| Group | Actions | Description |
|-------|---------|-------------|
| **Ordering** | Up / Down | Move the selected column |
| **Columns** | Add / Remove / Rename | Add new (virtual) columns, drop or rename existing ones. *Add* accepts several names separated by `;` |
| **Cell values** | Set all cells / Fill empty cells / Enumerate cells | Set a constant value, fill only the empty cells, or number rows over a `start:stop` range |
| **Load / Save** | Load / Save transformation | Persist the whole transformation as a JSON file and reload it later |
| **Export** | Export CSV / Delimiter / Number format | Write the transformed table to a new CSV; choose the export delimiter (`;` `,` TAB) and number format (keep `original`, force `.` or force `,`) |
| **Apply** | Apply to grid | Render the transformation live in the grid; the button turns into *Reset grid view* |

* The input field uses a placeholder hint (*"Value / name / enumeration start:stop"*).
* **Apply to grid** shows the transformed columns, headers and values in the grid itself
  (read-only preview). The status bar shows a `TRANSFORM` indicator. Press the button
  again (now *Reset grid view*) to return to the normal view. The source data is never
  modified by the preview.

### 🖱️ Interactive status bar

Click the status-bar segments to change how the file is parsed; the document is reloaded
on the fly:

* **Encoding** → ANSI / UTF-8 / UTF-16LE / UTF-16BE
* **Delimiter** → `,` `;` `|` TAB `:`
* **Comments** → parse normally / do not parse / hide
* **Rows** → visible / total count
* **Position** → current `row:column` plus edit/modified/transform indicators

### 📋 Copy helpers

* **C** – copy the current cell
* **Shift+C** – copy the selected row(s), honouring column order and hidden columns
* **Ctrl+C** – copy the current column (configurable via `copy-column`)

### 🔎 Other usability features

* **Hide column**: Ctrl+click a header or use the menu; **Show all columns** with
  **Ctrl+Space**.
* **Line numbers**: an optional, colour-separated, right-aligned row-number column on
  the left (`show-line-numbers` in the ini or *Show line numbers* in the menu).
* **Font scaling**: **Ctrl++ / Ctrl+-** or **Ctrl+Mouse wheel**.
* **Open URL in a cell**: **Alt+click** a cell containing a link.
* **Dark theme** toggle (menu) with fully configurable light/dark colours in the ini.
* **Search** integrated with Lister (forwards/backwards, match case, whole words).
* Bold, separately themed column headers.

### 🖱️ Right-click menu

The grid context menu mirrors the keyboard shortcuts (shown in parentheses):

| Item | Shortcut |
|------|----------|
| Copy cell | C |
| Copy row(s) | Shift+C |
| Copy column | Ctrl+C |
| Delete row(s) | Ctrl+X *(edit mode only)* |
| Hide column | Ctrl+Click header |
| Show all columns | Ctrl+Space |
| Filters | — |
| Header row | — |
| Edit mode | Ctrl+E |
| Transform mode | Ctrl+T |
| Save | Ctrl+S |
| Show line numbers | — |
| Dark theme | — |

---

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| F2 / Double-click | Edit the current cell (edit mode) |
| Enter / Esc | Accept / cancel the cell edit |
| Ctrl+E or Ctrl+R | Toggle edit mode |
| Ctrl+T | Toggle transform mode |
| Ctrl+X | Delete the selected row(s) (edit mode) |
| Ctrl+S | Save the file |
| C | Copy current cell |
| Shift+C | Copy selected row(s) |
| Ctrl+C | Copy current column |
| Ctrl+Space | Show all columns |
| Ctrl++ / Ctrl+- | Increase / decrease font size |
| Ctrl+Mouse wheel | Zoom font |
| Alt+Click | Open the URL in a cell |
| Click / Ctrl+Click header | Sort column / hide column |
| F1 | Open the wiki |

---

## Installation

1. Build the plugin (Free Pascal / Lazarus) to produce `csvtab.wlx` / `csvtab.wlx64`.
2. In Total Commander: **Configuration → Options → Plugins → Lister plugins (WLX) →
   Configure → Add**, and point it at the `.wlx`/`.wlx64` file (TC can also install it
   from the packaged zip automatically via `pluginst.inf`).
3. Open any CSV/TSV/TAB file in Lister (**F3**) or the Quick View Panel (**Ctrl+Q**).

---

## Configuration

Settings live in `csvtab.ini` (rename the bundled sample). A few common options:

| Key | Meaning |
|-----|---------|
| `font` / `font-size` / `font-weight` | Grid font |
| `header-row` | Treat the first row as a header (0/1) |
| `filter-row` | Show the per-column filter row (0/1) |
| `show-line-numbers` | Show the row-number column on the left (0/1) |
| `dark-theme` | Use the dark colour set (0/1) |
| `skip-comments` | Comment handling: 0 parse / 1 keep / 2 hide |
| `default-column-delimiter` | Force a delimiter (empty = auto-detect) |
| `column-delimiter` | Delimiter used when copying rows (default TAB) |
| `trim-values` | Trim leading/trailing spaces and tabs (0/1) |
| `max-file-size` | Size limit in bytes (0 = unlimited) |
| `copy-column` | Ctrl+C copies cell (0) or column (1) |

All light- and dark-theme colours are configurable as RGB integers; see the comments
in `csvtab.ini` for the full list.

---

## Credits

Based on [csvtab-wlx](https://github.com/little-brother/csvtab-wlx) by *little-brother*.
Original project licensed under its respective terms — see `LICENSE`.
