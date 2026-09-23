# Changelog

## 2026-09-23

- Added a Simplified Chinese (`language/zh-CN.lng`) and a Traditional Chinese
  (`language/zh-TW.lng`) catalog.
- Added `src/uLanguage.pas` with the UTF-8 catalog loader, the complete built-in
  English fallback and the `language` alias table.
- `language = Auto` now maps Total Commander's `LanguageIni` for Chinese as
  well: `wcmd_chn.lng` selects Simplified, `wcmd_cht.lng`/`wcmd_tw.lng` select
  Traditional Chinese.
- An unknown `language` value is now used as a catalog file name, so a new
  language can be added by dropping a single `<name>.lng` next to the plugin.
- Localized the remaining hardcoded GUI strings (status bar, transformer
  sidebar, dialogs, "Loading..." placeholder, default column headers).
- The settings reader now also handles UTF-16 ini files (with and without a
  BOM). Total Commander stores `wincmd.ini` as UTF-16LE, so without this
  `language = Auto` could never read `LanguageIni`.
- Catalog placeholders are no longer expanded with `SysUtils.Format`, which
  converts the text to the system code page first: that turned Chinese into
  `?` on a Cyrillic Windows and umlauts into `?` on a Chinese one. `%s` values
  such as file names and column headers now stay real `UnicodeString`s.
- Synced `language/en.lng` with the wording of the released build.

## 2026-09-10

- Added `allColumnsToMaxWidth` and `Ctrl+H` for unrestricted column sizing.
- Changed two-column sizing so `max-column-width` limits only the first column.
- Show selected row and column counts only when multiple rows are selected.
- Localized the GUI, context menus, status bar, dialogs, and transformer sidebar.
- Added German, English, Ukrainian, and Russian UTF-8 catalogs under `language`.
- Added `language=Auto` detection using Total Commander's `LanguageIni` setting.
- Added English fallback for missing language files and translation keys.
- Updated the INI template, documentation, installer metadata, and tests.
- Rebuilt and verified the 32-bit and 64-bit plugins.
- Grouped the three appearance choices in a localized Theme submenu.
- Made automatic language detection fall back to `COMMANDER_INI` and the
  running Total Commander directory when the SDK-provided INI has no language.
