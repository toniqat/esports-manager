# narrative/ — Draft project for the mental events

The **source of truth** for every mental event text and its rules (interview · outing · incident · press ·
morning talk · joint-training talk). It is a [Draft](../../../Draft) project directory (`project.json` +
`flows/<flowId>.json`); open this folder in Draft. `.gdignore` keeps Godot from importing it.

```
Draft (narrative/)  ──save (runtime preset, auto-sync)──▶  data/draft/EsportsManager[.<event>].json
        ▲                                                         │
        │ one-time seed from the old csv (2026-10)                 ▼  Project → Tools → "Draft: Import mental events"
        │                                                         │  (or addons/draft_import/cli.gd)
                                     data/csv/mental_events.csv · mental_texts.csv · data/l10n/src/mental.csv → game.db
```

**Do not hand-edit** `data/csv/mental_events.csv`, `mental_texts.csv` or the `mental.<event>.<id>` rows of
`data/l10n/src/mental.csv` any more: the next import overwrites them. Code keys `mental.ui.*` are not touched.
Importer details: `addons/draft_import/README.md`. Grammar of `cond` / `effects`: `features/season/mental/README.md`.

## Runtime preset (project.json `exportPresets`)
`EsportsManager 런타임` — engine godot, `godot.projectDir` = this repo, `godot.dataDir` = `data/draft`,
scope = all flows, auto-sync on save. The Godot project has **no** `draft_dialogue` addon (the game does not run
Draft graphs; the importer converts them), so Draft's link status shows the addon as missing: that is expected.
`projectDir` is an absolute path of this PC; on another PC re-pick it in the preset editor.

## One event = one top-level Flow

| Part | Convention |
|---|---|
| Flow name | **Event id** (`I01`, `O1F`, `X03`, `P05`, `T02`, `J01` …) — ASCII letters · digits · `_`. It is also the runtime file slug and the l10n alias segment. Folder = kind (면담 · 외출 · 사건 · 기자회견 · 오전 만남 · 합동 훈련), organisational only |
| Event settings | A **memo (Comment) attached to the first line**, attrs `kind` (enum) · `manager_type` (-1 any · 0 운영형 · 1 실전형) · `stage` (outing stage, else 0) · `cond` · `weight`. The editor cannot wire Start into a Destination and memos only attach to Dialogs, hence the memo |
| Opening lines | Start → Dialog → Dialog … in order |
| Answers | One **Select**; option text = the manager's answer, option attr `effects` = clause string (`trust:+2;ok>pmod:all:+1:-1`) |
| Replies | Each option → Dialog … → **End**. Dialog attr `branch` = `ok` / `ng` (only on a passed / failed mental check), empty = always |
| Speakers (wiki 인물) | `선수` = the target pilot (`{name}`) · `파트너` = joint-training partner (`{name2}`, `talk_pair` only) · `감독` = manager · `기자` = press reporter · `태그` = header tag (press outlet / incident name, not a bubble) · **no speaker** = narration. A `!` stage line is narration too |
| Text | `{name}` / `{name2}` placeholders; Korean josa tags `{i}` `{eun}` `{eul}` `{wa}` after them (`{name}{i}`), ko only. Several lines in one Dialog = several lines in the game. `#` script lines are dropped |
| Translation | Draft language `En` → l10n `en` (always imported as draft; approval stays in the l10n tool) |

Attributes are defined **per flow** in Draft (no project-wide definitions): duplicate an existing event flow to
start a new one so the memo, attribute definitions and speaker picker come along.

## Kinds
`interview` · `outing` (picked by `stage`) · `incident` (evening, forced) · `press` (weekly conference) ·
`talk` (morning talk right after training) · `talk_pair` (morning talk with the pilot who trained in the same
tile — both appear, single-pilot clauses hit both). Morning-talk conds: `train=<colour>[,<colour>…]`,
`ups>=N` / `ups<N` (stat points gained today), `stress>=N` / `stress<N`.
