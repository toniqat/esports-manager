# League Manager

Owns the regular-league round-robin schedule, AI-vs-AI auto resolution,
standings table, and the playoff cut-line check (top 4 of 8 = playoffs).
The campaign progresses 1 week at a time, and **each league week holds two
rounds** — one round on Saturday (`matchday = 0`), one round on Sunday (`matchday = 1`).

## Schedule shape
- **PRESEASON** — single round-robin (7 rounds, 28 matches, each team
  plays every other once). **4 league weeks** — the round count is odd, so the last week
  ends with a single Saturday round and Sunday is empty.
- **MIDSEASON / REGULAR** — double round-robin (14 rounds, 56 matches,
  home-and-away). **7 league weeks**.
- **\*\_INTL** phases — no league schedule. INTL bracket lives in
  `features/season/tournament/` (3-week 8-team SE).
- **2 rounds = 1 week.** Round `r_idx` → `phase_week = r_idx / 2 + 1`,
  `matchday = r_idx % 2`. Each match is stamped with the Monday of its
  phase_week so save metadata stays coherent — `weekday` stays 0 and the
  day the match actually lands on is what `matchday` says.
- Schedule is generated lazily and idempotently:
  - `SeasonHub._show_hub()` calls `LeagueManager.ensure_phase_scheduled()`
    on every hub entry — covers the initial PRESEASON post-draft.
  - `LeagueManager._on_phase_changed()` does the same on every league
    phase transition (MIDSEASON, REGULAR). INTL transitions are no-ops.

## Match-day flow
- The player enters by pressing "경기 시작" (Start match) on **Sat / Sun of the week-progress
  screen (시간 경과 화면)** (`SeasonHub.on_week_day_match_start` → MatchFlow → BattleSim). On return,
  SeasonHub records the result and settles only **that match day's (경기일)** AI matches
  (`_resolve_ai_for_matchday`).
- `resolve_matchday(md)` does that work — it runs `simulate_ai_match()` on matches with
  `phase == current_phase && phase_week == current_phase_week && matchday == md` that do not
  involve the player team, and records the results.
  `md < 0` means the whole week (the sweep-up path of end of week (주 마감)). No-op when not a
  league week (`is_league_match_week()`).
- `resolve_current_week()` remains as another name for `resolve_matchday(-1)`.
- **Running per match day is the point** — running the whole week at once would put Sunday
  results that haven't been played yet into the standings shown after Saturday's match.

## Standings
- `season_state["league_standings"]` — `team_id (int) → {wins, losses}`.
  Reset to all-zeros at the start of every league phase
  (`generate_phase_schedule` clears it).
- `standings_ranked()` returns rows `{team_id, wins, losses}` sorted by
  wins desc, losses asc, team_id asc.
- `player_made_playoffs()` checks whether the player team is in the top
  `GameManager.PLAYOFF_TEAMS` (default 4). Used by Phase 7 at phase end.

## Public API
| Method | Caller |
|---|---|
| `ensure_phase_scheduled()` | SeasonHub on hub entry, self on phase_changed |
| `generate_phase_schedule(phase)` | Internal (called by ensure) |
| `resolve_matchday(md)` | SeasonHub — settles that match day's AI matches |
| `resolve_current_week()` | `resolve_matchday(-1)` — end-of-week sweep-up |
| `record_result(a, b, winner)` | SeasonHub after BattleSim returns |
| `simulate_ai_match(a, b)` | resolve_current_week (and tournaments reuse it) |
| `standings_ranked()` | LeagueView, tournament managers |
| `player_made_playoffs()` | Phase 7 cut |
| `next_unplayed_player_match()` | LeagueView next-match header, HubView |
| `player_match_on_day(md)` | SeasonHub (is there a match on that weekday?) |
| `player_match_this_week()` | `player_match_on_day(-1)` — HubView header |
| `matches_this_week()` | LeagueView "this week's matches" |
| `team_name(id)` / `team_short_name(id)` | LeagueView, draft, future UIs |

## Match-schedule entry shape
Each entry in `season_state["match_schedule"]` is a Dictionary:
```
{
  "phase":      GameEnums.SeasonPhase,
  "phase_week": int,                  # 1-indexed week within the phase
  "matchday":   int,                  # 0 = Sat, 1 = Sun
  "round":      int,                  # round-robin round index
  "year":       int, "month": int, "day": int, "weekday": int,
  "team_a":     int, "team_b": int,
  "played":     bool,
  "winner":     int,                  # team_id or -1 if not played
}
```

`year/month/day` are stamped to the Monday of the phase_week — used only
for save metadata and the lobby run card, never for match-day filtering.

## Files
- `LeagueManager.gd` — orchestrator (this README's contract).
- `LeagueView.gd` + `LeagueView.tscn` — standings screen. 8 ranked rows + next-match header
  + **a single "확인" (OK) button**. Routed via `SeasonHub.Screen.LEAGUE`, built with
  `LeagueView.create()` (never `.new()`). Advancing the week
  moved to the Sunday close on the week-progress screen, and where to return is decided by the
  week-progress state, not by a button (`SeasonHub.on_standings_confirmed`). Colours come from
  `OutgameTheme` — a card list on white paper.
  **Tapping a row opens the team detail** (`open_team_detail(team_id, rank)` → `HubSheet`): rank ·
  record, then the five pilots under the analysis reveal rule — the same `OpponentIntel` /
  `IntelView` pair MatchFlow PREP uses (`features/match_flow/match_prep/README.md`). The own team
  is always fully visible; other teams follow `StaffSystem.analysis_tier`, with an analyst note
  when analysis is delegated.
- `LeagueRow.gd` + `LeagueRow.tscn` — one standings row (item scene). `fill(rank, team_text, wins,
  losses, made_po, is_player)` / `clear()`; emits `tapped` from its full-row flat `%Hit` button.
  The card style is built in code (`card_style(14)`) because it is data: own team = `ACCENT_DIM` +
  `ACCENT` 2px border, playoff cut = green 6px left bar, empty slot = `SURFACE_SUNK`. The rank
  colour (own team = `TEXT`) is data too.

### LeagueView scene tree
```
LeagueView (Control, full rect, mouse PASS, theme OutgameTheme)
├ %Background   ColorRect BG — code stretches it into the notch (`extend_background`)
├ Content       Control, anchored top-centre, 1000 wide
│ ├ %Phase (CaptionLabel 24) · Title (HeadingLabel) · %NextMatch (AccentLabel 24)
│ ├ Header      column captions (순위 · 팀 · 승-패 · 승률 · PO, CaptionLabel 20) + Divider
│ └ Body        VBox ─ %Rows (VBox, sep 10, LeagueRow ×8 — scene holds one preview row,
│                       `_ensure_rows` reuses it and instantiates the rest) · HintGap · Hint
└ %OkButton     PrimaryButton, anchored bottom-wide (code: `style_bottom_button` + bottom inset)
```
Scene owns: positions, column widths, font sizes / variations, the PO mark colour. Code owns: text,
row card colours, rank colour, safe-area top indent, bottom-bar styling / inset.
