# Changelog

## 2026-09-28

- Kept text input in the transformer sidebar from forwarding `N`, `P`, number
  keys, and other viewer navigation keys to Total Commander.
- Made language codes dynamically load matching `<code>.lng` catalogs, with
  regional fallback and automatic Total Commander/Windows UI language detection.
- Added a complete Czech (`cs.lng`) localization.

## 2026-09-11

- Added a complete built-in English catalog so missing or inaccessible language
  files never expose internal translation keys in the GUI.
- Improved several English status, transformation, and column-sizing labels.
- Added a test that keeps every external English string identical to its
  built-in fallback.
- Prevented the table context menu from reopening after selecting a command
  from a header right-click.

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
