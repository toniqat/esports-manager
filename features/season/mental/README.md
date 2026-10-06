# mental/ — trust · interviews · outings · incidents (M7)

Contract: `docs/outgame_dev_plan.md` §11. State `season_state.trust` / `outings` / `mental` / `pilot_mods`.

| File | Role |
|---|---|
| `MentalSystem.gd` | `class_name MentalSystem` (static). STUB in the base commit — M7 fills the bodies. |
| `PilotMods.gd` | `class_name PilotMods` (static, complete). Temporary per-pilot stat mods `[{pilot_id, stat, delta, weeks_left, source}]`; `weeks_left = -1` lasts until the next own match. `apply_to` is only ever called on a **roster copy** (MatchFlow). |

`data/csv/mental_events.csv` grammar (filled by M7): `kind` = `interview` / `outing` / `incident` / `press`;
`manager_type` -1 = any; `stage` = outing stage (1..5) or 0; `lines` / `choices` / `effects` joined with `|`,
one `effects` entry per choice, clauses inside an entry joined with `;`.
