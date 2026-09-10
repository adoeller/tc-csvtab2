# Changelog

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
