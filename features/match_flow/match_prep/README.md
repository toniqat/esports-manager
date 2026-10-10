# match_prep/ — PREP screen + opponent intel (M5 analysis)

**표시 텍스트는 l10n key (`match` 도메인, `match.intel.*` · `match.prep.*` (card: `match.prep.overall` · `warn_badge`) · scene keys `match.intel_*` / `match.match_prep_view.*`).** `OpponentIntel.build()` returns already-translated strings (tier label, analyst notes) — built when drawn, never saved. **텍스트는 l10n key — `Loc.t`** — `OpponentIntel._card_names_for` shows pilot cards via `Loc.t(def["name_key"])`.

MatchFlow's first step (`LOAD → PREP → BAN_PICK`). Contract: `docs/outgame_dev_plan.md` §3 M5 · §11.

| File | Role |
|---|---|
| `MatchPrepController.gd` | PREP step. `enter(player_roster, enemy_roster, player_name, enemy_name, enemy_team_id)` (MatchFlow passes its `enemy_team_id`) creates `MatchPrepView` under `_mf.canvas`, fills it; its `start_pressed` → frees the view → `phase_finished` (pre-ban-pick autosave in `MatchFlow`) |
| `MatchPrepView.gd` · `.tscn` | `class_name MatchPrepView` — the PREP screen. **Layout is owned by the scene** (tree below). White outgame paper, title centred (the editor-only cheat button sits top-left), a vertical scroll: the analyst note on top, then **opponent cards** (same side as ban/pick) · the centred **versus block** (own logo + short name · `VS` · opponent short name + logo) · own cards, bottom bar `경기 시작`. No team-name line, no section titles, no tier chip (2026-10). `create()` · `fill(state, player_roster, enemy_roster, player_name, enemy_name, enemy_team_id = -1)` (-1 = the roster's `team_id`) · signal `start_pressed`. Card tap → detail sheet (my run pilot = `SeasonPilotDetail.open`, opponent / my pilot outside a run = `MatchPrepPilotDetail.open`) |
| `TeamBanner.gd` | `class_name TeamBanner` — `_draw` widget behind one card row, borderless: draws `texture` (the team's banner image, `TeamLogos.banner` = `teams.csv` `banner_path`) scaled to cover (aspect kept, centred, overflow cropped); without one, a procedural band in `color` (`TeamLogos.color`) with lighter horizontal stripes (`STRIPE_PITCH` 12, 3 thick) and a darker band along the top / bottom edge. Placed as `%OwnBanner` / `%EnemyBanner` in the PREP scene |
| `UI_Comp_MatchPrepPilotCard.tscn` / `MatchPrepPilotCard.gd` | `class_name MatchPrepPilotCard` — one pilot card (section below). `create()` · `fill(row, own, trust, warn)` · signal `pressed(pilot_id)` |
| `UI_View_MatchPrepPilotDetail.tscn` / `MatchPrepPilotDetail.gd` | `class_name MatchPrepPilotDetail` — `HubSheet` body for an opponent pilot: tier line + one `IntelPilotRow` (six stats / mech line / card line exactly as the reveal tier allows). `open(host, intel, row)` (sheet title = pilot name) |
| `OpponentIntel.gd` | `class_name OpponentIntel` (static). **The single reveal rule** — `build(state, roster, is_own, team_id = -1)` returns rows + analyst notes + `analyst_who` + `threat_pilot_id` as data (`team_id` -1 = `roster_team(roster)`); `strongest_row(rows)` (the "경계 대상" lane), `tier_for(state, team_id, is_own = false)` (also read by ban/pick), `roster_team(roster)`, `team_roster(state, team_id)` (league `all_pilots` / INTL `intl_pilots`), `mech_name` (caches `mechs.name_key`, resolves with `Loc.t`) |
| `UI_Comp_IntelView.tscn` / `.gd` | `class_name IntelView` — one team's `build()` result as a **container scene** (VBox: parent width, content height): tier header · analyst note / "no analyst" line · five `IntelPilotRow`. `create()` · `show_intel(intel)`. `@export show_rows` (default true) — PREP sets it false (header + note only, the pilots are cards). Shared with the league team detail (`features/season/league/LeagueTeamDetail`, a `HubSheet` body, rows on) |
| `UI_Comp_IntelPilotRow.tscn` / `.gd` | `class_name IntelPilotRow` — one pilot row (item scene, `fill(row)`): portrait slot · role / name / total · six stat cells · mech line · card line |

**F6 standalone run** of `UI_View_MatchPrepView.tscn` shows dummy data: in-memory run (`UiPreview.ensure_run`)
vs its next league opponent (`UiPreview.ensure_league`) at that team's real analysis rank; `경기 시작` only
prints, card taps open the real sheets — `_fill_preview()` at the bottom of the script, helper `resources/UiPreview.gd`.
`UI_Comp_MatchPrepPilotCard.tscn` alone = a hand-written tier-2 opponent mid flagged `경계 대상`;
`UI_View_MatchPrepPilotDetail.tscn` alone = the body (no sheet) for the first pilot of another team at its rank.
`UI_Comp_IntelView.tscn` alone = another team of the in-memory run at its rank; `UI_Comp_IntelPilotRow.tscn` alone =
a hand-written tier-2 mid row.

## PREP screen scene (`UI_View_MatchPrepView.tscn`)
```
MatchPrepView (Control full rect, OutgameTheme.tres)
├ Paper (ColorRect BG, full viewport — also covers the notch strip)
└ %Safe (full rect; code: offset_top = top inset, offset_bottom = −bottom inset)
  ├ Title "경기 준비" (HeadingLabel 48)
  ├ %Scroll (full screen width — no side margin, top 104, bottom = bar + 12) → Body (VBox, expand = fills the scroll height)
  │   (page gutter per row: EnemyIntelPad / VersusPad / *BandPad = left 40 · right 48 (40 + scroll bar 8))
  │   EnemyIntelPad/%IntelView_EnemyIntel (show_rows = false, show_header = false: analyst note only) ·
  │   TopSpace (expand) · EnemyCardsGap 20 (room for the `경계 대상` chip sticking 16 above a card) ·
  │   EnemyCardsPad (no margin) [%EnemyBanner (TeamBanner, full screen width x 0..1080) + EnemyBandPad (40 · 48 sides, 22 top/bottom) /
  │     %EnemyCards (HBox sep 10: MatchPrepPilotCard_Enemy0..4, expand)] · VersusGap 28 ·
  │   VersusPad/Versus (HBox centred, sep 40): OwnSide (240: %OwnLogo 128² · %OwnAbbr HeadingLabel 40) ·
  │     VsText `VS` (AccentLabel 64) · EnemySide (%EnemyLogo · %EnemyAbbr) · VersusGap2 28 ·
  │   OwnCardsPad [%OwnBanner + OwnBandPad / %OwnCards (MatchPrepPilotCard_Own0..4)] · BottomSpace (expand) · BottomPad 16
  │   (five cards = (1080 − 88 − 4 × 10) / 5 ≈ 190 wide on the 1080 design width; the banners run edge to edge)
  └ %Start (bottom-anchored, 128 high, BarPrimaryButton)
```
- The two expand spacers centre the enemy cards · versus · own cards block in the space under the
  analyst note (both card rows are the same height, so `VS` sits at the block's middle — about the
  screen centre on a 1080×1920 screen); they collapse to 0 when the content is taller than the scroll.
- Code-owned: the top safe-area offset, the bottom inset via `OutgameTheme.fit_bottom_bar(%Start, %Safe)`
  (`%Safe` ends at the safe line; the start capsule floats 32 px above it, 40 px in from the sides —
  the capsule look is the `BarPrimaryButton` variation), filling the enemy `IntelView` note
  (`show_intel`), the ten cards from `OpponentIntel.build()` rows (seat order; a missing pilot hides
  its card) and the versus block (`_fill_versus`: `TeamLogos.texture(team_id)` + `GameManager.team_short_name`
  = `teams.csv` `short_name_key`, team ids = the two `build()` results' `team_id`; no team id → no logo and
  the team name `fill` got). The two banners get `TeamLogos.banner(team_id)` + `TeamLogos.color(team_id)` (`_fill_banner`; no team id → the scene's colour band). Own cards get `MentalSystem.trust`; the enemy card whose
  `pilot_id == threat_pilot_id` gets the warn chip.
- The scroll spans the full screen width, so its bar sits at the screen's right edge (over the banners);
  every other row keeps the 40 / 48 page gutter itself.

## Pilot card (`UI_Comp_MatchPrepPilotCard.tscn`)
```
MatchPrepPilotCard (PanelContainer `MatchPrepPilotCard` = Card look, no padding; width from the row)
├ Box (VBox)
│ ├ %SeasonPilotCard_Own   own team: `UI_Comp_SeasonPilotCard.tscn` instance (bare, `SeasonPilotCardBare`):
│ │   (164 high)           portrait in the trust ring, level / trust pills; gauges off
│ │                        (`set_gauges_visible(false)` in `_ready`) and the instance's min height cut
│ │                        from 244 to 164 — filled with `show_pilot(pid, trust_points, 0)`, its own tap
│ │                        off (`set_tappable(false)`)
│ ├ %EnemyTop (164)        opponent: %Portrait 116 @24 (role-coloured rim, `OutgameTheme.add_round_portrait`)
│ │                        — the season card's portrait spot inside its ring, so both rows line up
│ ├ OverallKey `종합` (CaptionLabel 18) · %Overall (HeadingLabel 46 ↔ FaintLabel when hidden)
│ └ BottomPad 14
├ Overlay / %Warn          `MatchPrepWarnChip` (red) `경계 대상`, top-right, 16 above the card's edge
└ %Hit                     flat Button over the card (PASS — keeps drag scroll) → pressed(pilot_id)
```
- Total = the row's `total_text`: tier 0 `?` (faint), tier 1 `≈n`, tier 2+ exact; own always exact.
- No name, position badge, mech chips, stress / trust / awakening gauges (removed 2026-10 — the seat
  order says the role); six stats, mechs and pilot cards are in the detail sheet.
- Own and enemy cards are the same height (256 + card margins); portraits at the same y.

## IntelView scene (`UI_Comp_IntelView.tscn`)
```
IntelView (VBox, sep 0 — parent width, content height)
├ %Header (opponents only, `show_header`): HeaderRow (40, sep 14) ─ %TierChip (AccentChip, fits its text) / %TierText (20)
│                           · %Need (CaptionLabel 18) ; HeaderGap 12
├ %NoAnalyst (manager owns analysis): Line (SubLabel 20, 30) · Gap 10
├ %Note (delegated): Card (IntelAnalystNote) / Pad 20·12·20·10 / Row (HBox sep 16):
│                    ThumbFrame (SunkPanel mask, 96², top) / %AnalystPortrait (`StaffImages.portrait(intel.analyst_who)`)
│                    · VBox: %Analyst (AccentLabel 20, 28) · 6 · %Lines (sep 3, BodyLabel 22 wrapped,
│                    one per note) · Tail 3 ; Gap 10
├ %Rows (sep 10) — IntelPilotRow ×5 (scene sample replaced at runtime)
└ RowsTail 10
IntelPilotRow (MarginContainer): %Back (Card preview → code lead_bar_style(role)) + Content VBox:
  Top 100 (%Portrait 76 @18,14 · NameCol 108 → 40 % − 8: %PositionBadge_Role (PositionBadge)/%Name/%Total · %Stats HBox 40 % → −14, six cells)
  · %MechLine 34 · %CardLine 34 · BasePad 4 · %ExtraPad 8 (when a line shows)
```
- `@export show_rows` / `show_header` (both default true): PREP turns both off (analyst note only); the league
  team detail keeps them.
- Code-owned (data / state): role colour (card bar, role text, portrait ring), stat value font size and
  `BodyLabel` ↔ `FaintLabel`, tier chip fill below full (`SURFACE_SUNK` copy of the `AccentChip` box) and
  `AccentLabel` ↔ `BodyLabel`, which blocks / lines are visible.
- Look vs. the old code-drawn version: the tier chip now fits its text (was `36 + 16 × length` wide), the
  analyst note card is the `IntelAnalystNote` variation (amber `ACCENT_DIM`, radius 14, as before). Stat cells are whole-pixel widths (≤ 1px text shift).

## Reveal tiers
**Per opponent team (§16)**: `OpponentIntel.tier_for(state, team_id)` = the team's analysis rank
`IntelResearch.rank(state, team_id)` (0..3, all teams 0 at run start, +1 per completed 전력 분석실 research on
that team — `features/season/facility/README.md` → IntelResearch) + the `analysis_tier` manager traits
(`TraitSystem.run_mod`, clamped 0..3; a rank-3 team stays 3). The old analyst-stat tier
(`StaffSystem.analysis_tier`, `ANALYSIS_TIER_1..3`) is gone. Callers pass the team id: PREP (`MatchFlow.enemy_team_id`),
the league team detail (`LeagueView.open_team_detail` tid), ban/pick (`OpponentIntel.roster_team` of the enemy
roster — enemy likely picks / mastery tags need tier >= 2).

| Tier | Opponent rows show |
|---|---|
| 0 | portrait, role, name; stats `?` |
| 1 | stats as ranges `ANALYSIS_APPROX_STEP` wide (`60~69`), total `≈` |
| 2 | exact stats + top `ANALYSIS_TOP_MECHS` mechs (`MechMastery.top_mechs` with grade; falls back to `PlayerData.main_mechs` labelled `주력` while there is no mastery data) |
| 3 | + the three fixed pilot cards (`GameManager.pilot_card_ids_for` → `card_def.name`) |

- **Own team is always tier 3.** Outside a season (`season_state.active == false`, MatchFlow run straight from the editor) everything is tier 3 too.
- The header chip (league team detail, opponent detail sheet — not on the PREP screen since 2026-10) shows `분석 단계 n · <label>` and, below full, how to raise it (`match.intel.need`:
  research the team in the 전력 분석실).
- PREP shows whatever rosters `MatchFlow` passes in — if those are match copies with mastery / mods applied, the numbers shown are the match numbers.

## Auto vs manual (analyst note)
- Staff seated in the intel facility (`FacilitySystem.is_delegated_fid(state, "intel")`) → an amber note with the occupant's thumbnail on the left (`build()["analyst_who"]` = `FacilitySystem.occupant`, `StaffImages.portrait`) and `분석 · <name> (<job>)` (`analyst_label` = the intel occupant) with up to two lines from `OpponentIntel.interpret`: the strongest lane by visible stat total (+ its highest stat), then a suggested ban (top-mastery mech on their side — ties go to the stronger pilot) from tier 2, else the weakest lane. Tier 0 says the data is too thin. Deliberately a simple heuristic, not optimal.
- The strongest-lane pilot is also data: `build()["threat_pilot_id"]` (`strongest_row`), set only when that line is shown (delegated, tier >= 1, opponent) — PREP marks that card with the red `경계 대상` chip.
- Nobody / the manager in the intel facility → one faint line `분석 담당 없음 — 데이터만 보입니다. 해석은 감독이 직접.`; the player reads the raw data.
- Separate from `enemy_misjudge_chance` (that is the opponent's ability, not our information).
