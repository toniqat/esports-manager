# addons/draft_import/ — Draft runtime JSON → mental event tables

Converts the Draft runtime export of the mental events (`res://data/draft/*.json`, written by the Draft project
`narrative/` on save) into the game's data: `data/csv/mental_events.csv`, `data/csv/mental_texts.csv` and the
`mental.<event>.<id>` rows of `data/l10n/src/mental.csv`, then rebuilds game.db (which ends with l10n `build dev`).
The game never reads the JSON. Authoring convention: `narrative/README.md`.

| File | Role |
|---|---|
| `draft_import.gd` | Static importer (no `class_name`, preload it). `read_events(dir)` → parsed events + warnings; `run(dir, dry)` → syncs l10n (issues keys only through `StatusOps.new_keys`, edits through `cmd_edit`, removes texts no longer produced with `cmd_remove_key`) and writes both csv tables. Report `{error, warnings, events, new, edited, removed}` |
| `cli.gd` | Headless: `godot --headless --path . --script res://addons/draft_import/cli.gd [-- --dry] [-- --no-rebuild]` |
| `plugin.gd` · `plugin.cfg` | Editor menu **Project → Tools → Draft: Import mental events** (import + Rebuild game.db). Enable it in Project Settings → Plugins |

## Rules
- **Ids are stable**: text ids are `<event>_L<seq>` · `<event>_C<n>` · `<event>_C<n>_S<seq>` (as before Draft) and the
  alias is `mental.<event lower>.<id lower>`, so an unchanged event re-imports with 0 edits and keeps its `tx_` keys.
- A Flow is an event only when it has a memo (Comment) with a `kind` attr; other flows are skipped with a warning.
  Rows are sorted by kind (`KINDS` order), then id. Duplicate event ids: the later flow is dropped (warning).
- Line markers come from the speaker's wiki name (`SPEAKER_MARKERS`: 감독 `>`, 파트너 `&`, 태그 `@`; no speaker /
  stage line `*`; anyone else plain). Translations whose line count differs from the source leave `en` empty (warning).
- Removing an event in Draft removes its `mental.<event>.*` l10n rows on the next import (data alias rule only;
  `mental.ui.*` code keys are never touched). Translations are written as `draft`; approval stays manual.
- `--dry` prints the counts without writing anything — run it first after big Draft edits.
