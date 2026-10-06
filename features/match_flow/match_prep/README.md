# match_prep/ — PREP screen + opponent intel (M5 analysis)

MatchFlow's first step (`LOAD → PREP → BAN_PICK`). Contract: `docs/outgame_dev_plan.md` §3 M5 · §11.

| File | Role |
|---|---|
| `MatchPrepController.gd` | PREP screen. White outgame paper (`OutgameTheme`), title centred (the editor-only cheat button sits top-left), a vertical scroll with **opponent on top** (same side as ban/pick) and own team below, bottom bar `경기 시작` → `phase_finished` (pre-ban-pick autosave in `MatchFlow`). `enter(player_roster, enemy_roster, player_name, enemy_name)` is unchanged |
| `OpponentIntel.gd` | `class_name OpponentIntel` (static). **The single reveal rule** — `build(state, roster, is_own)` returns rows + analyst notes as data; `tier_for`, `threshold_of`, `team_roster(state, team_id)` (league `all_pilots` / INTL `intl_pilots`), `mech_name` |
| `IntelView.gd` | `class_name IntelView` (static). Draws a `build()` result: `add_tier_header`, `add_analyst_note`, `add_rows` / `add_pilot_row`. Shared with the league team detail (`features/season/league/LeagueView.gd`) |

## Reveal tiers
`StaffSystem.analysis_tier(state)` (thresholds `ANALYSIS_TIER_1..3`, const.csv):

| Tier | Opponent rows show |
|---|---|
| 0 | portrait, role, name; stats `?` |
| 1 | stats as ranges `ANALYSIS_APPROX_STEP` wide (`60~69`), total `≈` |
| 2 | exact stats + top `ANALYSIS_TOP_MECHS` mechs (`MechMastery.top_mechs` with grade; falls back to `PlayerData.main_mechs` labelled `주력` while there is no mastery data) |
| 3 | + the three fixed pilot cards (`GameManager.pilot_card_ids_for` → `card_def.name`) |

- **Own team is always tier 3.** Outside a season (`season_state.active == false`, MatchFlow run straight from the editor) everything is tier 3 too.
- The header chip shows the tier and, below full, `내 분석 v · 다음 단계 n 필요`.
- PREP shows whatever rosters `MatchFlow` passes in — if those are match copies with mastery / mods applied, the numbers shown are the match numbers.

## Auto vs manual (analyst note)
- `StaffSystem.is_delegated(state, "analysis")` → an amber note `분석 · <name> (<job>)` with up to two lines from `OpponentIntel.interpret`: the strongest lane by visible stat total (+ its highest stat), then a suggested ban (top-mastery mech on their side — ties go to the stronger pilot) from tier 2, else the weakest lane. Tier 0 says the data is too thin. Deliberately a simple heuristic, not optimal.
- Manager owns analysis → one faint line `분석 담당 없음 — 데이터만 보입니다. 해석은 감독이 직접.`; the player reads the raw data.
- Separate from `enemy_misjudge_chance` (that is the opponent's ability, not our information).
