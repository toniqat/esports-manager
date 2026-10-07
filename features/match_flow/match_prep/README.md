# match_prep/ — PREP screen + opponent intel (M5 analysis)

MatchFlow's first step (`LOAD → PREP → BAN_PICK`). Contract: `docs/outgame_dev_plan.md` §3 M5 · §11.

| File | Role |
|---|---|
| `MatchPrepController.gd` | PREP step. `enter(player_roster, enemy_roster, player_name, enemy_name)` creates `MatchPrepView` under `_mf.canvas`, fills it; its `start_pressed` → frees the view → `phase_finished` (pre-ban-pick autosave in `MatchFlow`) |
| `MatchPrepView.gd` · `.tscn` | `class_name MatchPrepView` — the PREP screen. **Layout is owned by the scene** (tree below). White outgame paper, title centred (the editor-only cheat button sits top-left), a vertical scroll with **opponent on top** (same side as ban/pick) and own team below, bottom bar `경기 시작`. `create()` · `fill(state, player_roster, enemy_roster, player_name, enemy_name)` · signal `start_pressed` |
| `OpponentIntel.gd` | `class_name OpponentIntel` (static). **The single reveal rule** — `build(state, roster, is_own)` returns rows + analyst notes as data; `tier_for`, `threshold_of`, `team_roster(state, team_id)` (league `all_pilots` / INTL `intl_pilots`), `mech_name` |
| `IntelView.gd` | `class_name IntelView` (static). Draws a `build()` result: `add_tier_header`, `add_analyst_note`, `add_rows` / `add_pilot_row`. Shared with the league team detail (`features/season/league/LeagueView.gd`) |

**F6 standalone run** of `MatchPrepView.tscn` shows dummy data: in-memory run (`UiPreview.ensure_run`)
vs its next league opponent (`UiPreview.ensure_league`), the run's real analysis tier; `경기 시작` only
prints — `_fill_preview()` at the bottom of the script, helper `resources/UiPreview.gd`.

## PREP screen scene (`MatchPrepView.tscn`)
```
MatchPrepView (Control full rect, OutgameTheme.tres)
├ Paper (ColorRect BG, full viewport — also covers the notch strip)
└ %Safe (full rect; code: offset_top = top inset, offset_bottom = −bottom inset)
  ├ Title "경기 준비" (HeadingLabel 48) · %Matchup (SubLabel)
  ├ %Scroll (40 side margin, top 136, bottom = bar + 12) → Body (VBox)
  │   EnemyHead/%EnemyTitle · %EnemyIntel · Gap · OwnHead/%OwnTitle · %OwnIntel · BottomPad
  └ %Start (bottom-anchored, 128 high, BarPrimaryButton)
```
- Code-owned: the top safe-area offset, the bottom inset via `OutgameTheme.fit_bottom_bar(%Start, %Safe)`
  (`%Safe` ends at the safe line; the bar reaches the screen bottom with its text kept above the inset —
  the square corners are the `BarPrimaryButton` variation), and the two `*Intel` holders — `IntelView` (shared with the league team detail, absolute
  coordinates) draws into them and their minimum height is the height it used. Row width =
  scroll width − 16 (`SCROLLBAR_ROOM`).
- The scroll bar now sits at the scroll's own right edge (inside the 40px margin); the old code-built
  body was 1000 wide, which pushed the bar ~8px further right.

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
