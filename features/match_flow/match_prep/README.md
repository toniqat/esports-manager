# match_prep/ — PREP screen + opponent intel (M5 analysis)

**표시 텍스트는 l10n key (`match` 도메인, `match.intel.*` · `match.prep.*` (card: `match.prep.overall` · `warn_badge` · `no_mech`) · scene keys `match.intel_*` / `match.match_prep_view.*`).** `OpponentIntel.build()` returns already-translated strings (tier label, analyst notes) — built when drawn, never saved. **텍스트는 l10n key — `Loc.t`** — `OpponentIntel._card_names_for` shows pilot cards via `Loc.t(def["name_key"])`.

MatchFlow's first step (`LOAD → PREP → BAN_PICK`). Contract: `docs/outgame_dev_plan.md` §3 M5 · §11.

| File | Role |
|---|---|
| `MatchPrepController.gd` | PREP step. `enter(player_roster, enemy_roster, player_name, enemy_name)` creates `MatchPrepView` under `_mf.canvas`, fills it; its `start_pressed` → frees the view → `phase_finished` (pre-ban-pick autosave in `MatchFlow`) |
| `MatchPrepView.gd` · `.tscn` | `class_name MatchPrepView` — the PREP screen. **Layout is owned by the scene** (tree below). White outgame paper, title centred (the editor-only cheat button sits top-left), a vertical scroll with **opponent on top** (same side as ban/pick: analysis header + five pilot cards) and own team below (five cards), bottom bar `경기 시작`. `create()` · `fill(state, player_roster, enemy_roster, player_name, enemy_name)` · signal `start_pressed`. Card tap → detail sheet (my run pilot = `SeasonPilotDetail.open`, opponent / my pilot outside a run = `MatchPrepPilotDetail.open`) |
| `UI_Comp_MatchPrepPilotCard.tscn` / `MatchPrepPilotCard.gd` | `class_name MatchPrepPilotCard` — one pilot card (section below). `create()` · `fill(row, own, trust, stress, warn)` · signal `pressed(pilot_id)` |
| `UI_View_MatchPrepPilotDetail.tscn` / `MatchPrepPilotDetail.gd` | `class_name MatchPrepPilotDetail` — `HubSheet` body for an opponent pilot: tier line + one `IntelPilotRow` (six stats / mech line / card line exactly as the reveal tier allows). `open(host, intel, row)` (sheet title = pilot name) |
| `OpponentIntel.gd` | `class_name OpponentIntel` (static). **The single reveal rule** — `build(state, roster, is_own)` returns rows + analyst notes + `threat_pilot_id` as data; `strongest_row(rows)` (the "경계 대상" lane), `tier_for`, `threshold_of`, `team_roster(state, team_id)` (league `all_pilots` / INTL `intl_pilots`), `mech_name` (caches `mechs.name_key`, resolves with `Loc.t`) |
| `UI_Comp_IntelView.tscn` / `.gd` | `class_name IntelView` — one team's `build()` result as a **container scene** (VBox: parent width, content height): tier header · analyst note / "no analyst" line · five `IntelPilotRow`. `create()` · `show_intel(intel)`. `@export show_rows` (default true) — PREP sets it false (header + note only, the pilots are cards). Shared with the league team detail (`features/season/league/LeagueTeamDetail`, a `HubSheet` body, rows on) |
| `UI_Comp_IntelPilotRow.tscn` / `.gd` | `class_name IntelPilotRow` — one pilot row (item scene, `fill(row)`): portrait slot · role / name / total · six stat cells · mech line · card line |

**F6 standalone run** of `UI_View_MatchPrepView.tscn` shows dummy data: in-memory run (`UiPreview.ensure_run`)
vs its next league opponent (`UiPreview.ensure_league`), the run's real analysis tier; `경기 시작` only
prints, card taps open the real sheets — `_fill_preview()` at the bottom of the script, helper `resources/UiPreview.gd`.
`UI_Comp_MatchPrepPilotCard.tscn` alone = a hand-written tier-2 opponent mid flagged `경계 대상`;
`UI_View_MatchPrepPilotDetail.tscn` alone = the body (no sheet) for the first pilot of another team at the run's tier.
`UI_Comp_IntelView.tscn` alone = another team of the in-memory run at the run's tier; `UI_Comp_IntelPilotRow.tscn` alone =
a hand-written tier-2 mid row.

## PREP screen scene (`UI_View_MatchPrepView.tscn`)
```
MatchPrepView (Control full rect, OutgameTheme.tres)
├ Paper (ColorRect BG, full viewport — also covers the notch strip)
└ %Safe (full rect; code: offset_top = top inset, offset_bottom = −bottom inset)
  ├ Title "경기 준비" (HeadingLabel 48) · %Matchup (SubLabel)
  ├ %Scroll (40 side margin, top 136, bottom = bar + 12) → Body (VBox)
  │   EnemyHead/%EnemyTitle · EnemyIntelPad/%IntelView_EnemyIntel (show_rows = false: tier chip + note) ·
  │   EnemyCardsGap 20 (room for the `경계 대상` chip sticking 16 above a card) ·
  │   EnemyCardsPad/%EnemyCards (HBox sep 10: MatchPrepPilotCard_Enemy0..4, expand) · Gap2 28 ·
  │   OwnHead/%OwnTitle · OwnCardsPad/%OwnCards (MatchPrepPilotCard_Own0..4) · BottomPad
  │   (*Pad right 8 → with the scroll bar the rows end 16 short of the scroll's right edge;
  │    five cards = (992 − 4 × 10) / 5 ≈ 190 wide on the 1080 design width)
  └ %Start (bottom-anchored, 128 high, BarPrimaryButton)
```
- Code-owned: the top safe-area offset, the bottom inset via `OutgameTheme.fit_bottom_bar(%Start, %Safe)`
  (`%Safe` ends at the safe line; the bar reaches the screen bottom with its text kept above the inset —
  the square corners are the `BarPrimaryButton` variation), filling the enemy `IntelView` header
  (`show_intel`) and the ten cards from `OpponentIntel.build()` rows (seat order; a missing pilot hides
  its card). Own cards get `MentalSystem.trust` / `StressSystem.value`; the enemy card whose
  `pilot_id == threat_pilot_id` gets the warn chip.
- The scroll bar now sits at the scroll's own right edge (inside the 40px margin); the old code-built
  body was 1000 wide, which pushed the bar ~8px further right.

## Pilot card (`UI_Comp_MatchPrepPilotCard.tscn`)
```
MatchPrepPilotCard (PanelContainer `MatchPrepPilotCard` = Card look, no padding; width from the row)
├ Box (VBox)
│ ├ %SeasonPilotCard_Own   own team: `UI_Comp_SeasonPilotCard.tscn` instance drawn without its card
│ │                        (`MatchPrepCardInner` = empty box): badge, portrait in the trust ring, level
│ │                        pill, stress, note — filled with `show_pilot(pid, role, trust_points, stress)`,
│ │                        its own tap off (`set_tappable(false)`)
│ ├ %EnemyTop (196)        opponent: BadgeSlot/%PositionBadge_Role (12..42) · %Portrait 116 @62
│ │                        (role-coloured rim, `OutgameTheme.add_round_portrait`) — the season card's spots
│ ├ OverallKey `종합` (CaptionLabel 18) · %Overall (HeadingLabel 46 ↔ FaintLabel when hidden)
│ ├ MechGap 6 · MechPad (8 sides) / %Mechs (HBox sep 6, centred): MechChip0..1 (`MatchPrepMechChip`, Text 15, clipped)
│ └ BottomPad 14
├ Overlay / %Warn          `MatchPrepWarnChip` (red) `경계 대상`, top-right, 16 above the card's edge
└ %Hit                     flat Button over the card (PASS — keeps drag scroll) → pressed(pilot_id)
```
- Total = the row's `total_text`: tier 0 `?` (faint), tier 1 `≈n`, tier 2+ exact; own always exact.
- Mech chips = the row's `mechs` (first two names: `MechMastery.top_mechs`, fallback `main_mechs`);
  opponent below tier 2 → one faint `?` chip; no mech at all → one faint `주력 메크 없음`.
- No six stats and no pilot cards on the card — they are in the detail sheet.
- Own cards are ~60px taller (stress + note lines of the season card).

## IntelView scene (`UI_Comp_IntelView.tscn`)
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
  Top 100 (%Portrait 76 @18,14 · NameCol 108 → 40 % − 8: %PositionBadge_Role (PositionBadge)/%Name/%Total · %Stats HBox 40 % → −14, six cells)
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
- The strongest-lane pilot is also data: `build()["threat_pilot_id"]` (`strongest_row`), set only when that line is shown (delegated, tier >= 1, opponent) — PREP marks that card with the red `경계 대상` chip.
- Manager owns analysis → one faint line `분석 담당 없음 — 데이터만 보입니다. 해석은 감독이 직접.`; the player reads the raw data.
- Separate from `enemy_misjudge_chance` (that is the opponent's ability, not our information).
