# match_prep/ — PREP screen + opponent intel (M5 analysis)

MatchFlow's first step (`LOAD → PREP → BAN_PICK`). Contract: `docs/outgame_dev_plan.md` §3 M5 · §11.

| File | Role |
|---|---|
| `MatchPrepController.gd` | PREP step. `enter(player_roster, enemy_roster, player_name, enemy_name)` creates `MatchPrepView` under `_mf.canvas`, fills it; its `start_pressed` → frees the view → `phase_finished` (pre-ban-pick autosave in `MatchFlow`) |
| `MatchPrepView.gd` · `.tscn` | `class_name MatchPrepView` — the PREP screen. **Layout is owned by the scene** (tree below). White outgame paper, title centred (the editor-only cheat button sits top-left), a vertical scroll with **opponent on top** (same side as ban/pick) and own team below, bottom bar `경기 시작`. `create()` · `fill(state, player_roster, enemy_roster, player_name, enemy_name)` · signal `start_pressed` |
| `OpponentIntel.gd` | `class_name OpponentIntel` (static). **The single reveal rule** — `build(state, roster, is_own)` returns rows + analyst notes as data; `tier_for`, `threshold_of`, `team_roster(state, team_id)` (league `all_pilots` / INTL `intl_pilots`), `mech_name` |
| `IntelView.tscn` / `.gd` | `class_name IntelView` — one team's `build()` result as a **container scene** (VBox: parent width, content height): tier header · analyst note / "no analyst" line · five `IntelPilotRow`. `create()` · `show_intel(intel)`. Shared with the league team detail (`features/season/league/LeagueTeamDetail`, a `HubSheet` body) |
| `IntelPilotRow.tscn` / `.gd` | `class_name IntelPilotRow` — one pilot row (item scene, `fill(row)`): portrait slot · role / name / total · six stat cells · mech line · card line |

**F6 standalone run** of `MatchPrepView.tscn` shows dummy data: in-memory run (`UiPreview.ensure_run`)
vs its next league opponent (`UiPreview.ensure_league`), the run's real analysis tier; `경기 시작` only
prints — `_fill_preview()` at the bottom of the script, helper `resources/UiPreview.gd`.
`IntelView.tscn` alone = another team of the in-memory run at the run's tier; `IntelPilotRow.tscn` alone =
a hand-written tier-2 mid row.

## PREP screen scene (`MatchPrepView.tscn`)
```
MatchPrepView (Control full rect, OutgameTheme.tres)
├ Paper (ColorRect BG, full viewport — also covers the notch strip)
└ %Safe (full rect; code: offset_top = top inset, offset_bottom = −bottom inset)
  ├ Title "경기 준비" (HeadingLabel 48) · %Matchup (SubLabel)
  ├ %Scroll (40 side margin, top 136, bottom = bar + 12) → Body (VBox)
  │   EnemyHead/%EnemyTitle · EnemyIntelPad/%EnemyIntel · Gap · OwnHead/%OwnTitle ·
  │   OwnIntelPad/%OwnIntel · BottomPad   (*Intel = IntelView.tscn instances; *Pad right 8)
  └ %Start (bottom-anchored, 128 high, BarPrimaryButton)
```
- Code-owned: the top safe-area offset, the bottom inset via `OutgameTheme.fit_bottom_bar(%Start, %Safe)`
  (`%Safe` ends at the safe line; the bar reaches the screen bottom with its text kept above the inset —
  the square corners are the `BarPrimaryButton` variation), and filling the two `IntelView` instances
  (`show_intel`). Their height is their content (containers). Row width = body width − the `*Pad` right
  margin 8; with the scroll bar (8) the rows end 16 short of the scroll's right edge, as before.
- The scroll bar now sits at the scroll's own right edge (inside the 40px margin); the old code-built
  body was 1000 wide, which pushed the bar ~8px further right.

## IntelView scene (`IntelView.tscn`)
```
IntelView (VBox, sep 0 — parent width, content height)
├ %Header (opponents only): HeaderRow (40, sep 14) ─ %TierChip (AccentChip, fits its text) / %TierText (20)
│                           · %Need (CaptionLabel 18) ; HeaderGap 12
├ %NoAnalyst (manager owns analysis): Line (SubLabel 20, 30) · Gap 10
├ %Note (delegated): Card (IntelAnalystNote) / Pad 20·12·20·10 / %Analyst (AccentLabel 20, 28)
│                    · 6 · %Lines (sep 3, BodyLabel 22 wrapped, one per note) · Tail 3 ; Gap 10
├ %Rows (sep 10) — IntelPilotRow ×5 (scene sample replaced at runtime)
└ RowsTail 10
IntelPilotRow (MarginContainer): %Back (Card preview → code lead_bar_style(role)) + Content VBox:
  Top 100 (%Portrait 76 @18,14 · NameCol 108 → 40 % − 8: %Role (PositionBadge)/%Name/%Total · %Stats HBox 40 % → −14, six cells)
  · %MechLine 34 · %CardLine 34 · BasePad 4 · %ExtraPad 8 (when a line shows)
```
- Code-owned (data / state): role colour (card bar, role text, portrait ring), stat value font size and
  `BodyLabel` ↔ `FaintLabel`, tier chip fill below full (`SURFACE_SUNK` copy of the `AccentChip` box) and
  `AccentLabel` ↔ `BodyLabel`, which blocks / lines are visible.
- Look vs. the old code-drawn version: the tier chip now fits its text (was `36 + 16 × length` wide), the
  analyst note card is the `IntelAnalystNote` variation (amber `ACCENT_DIM`, radius 14, as before). Stat cells are whole-pixel widths (≤ 1px text shift).

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
