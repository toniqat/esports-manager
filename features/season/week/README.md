# Week progress (시간 경과) (week)

The screen where the week passes **one day at a time, Monday to Sunday**. `Screen.WEEK` in
`SeasonHub`.

| File | Role |
|---|---|
| `WeekProgressView.gd` | `class_name WeekProgressView extends Control` — the whole screen |

## Screen

```
┌──────────────────────────────────────────┐
│ 1주  월  화  수  목 [금]  토  일            │  ← top horizontal weekday rail
└──────────────────────────────────────────┘
  프리시즌 · 3주차                  1년 12월
  금요일                                5
 ──────────────────────────────────────────
  ▌(○) Evelyn      전명 전회 교명 …          ← vertical scroll
  ▌    탱커         86   87   83
  ▌(○) Seed  …
        [               확인               ]
```

(Mockup uses in-game Korean text: `1주` = Week 1, 월화수목금토일 = Mon–Sun, "프리시즌 · 3주차" =
Preseason · Week 3, "1년 12월" = Year 1, December, "금요일" = Friday, 탱커 = tank, stat
abbreviations such as 전명 / 전회 / 교명, `확인` = OK.)

* **Top horizontal rail** — on a dark pill spanning the full screen width, `N주` (Week N) at the
  left end, then seven weekday (요일) chips spaced evenly **left → right**. **Only the current
  weekday's chip is filled amber.** Past days have white text, remaining days dim text — that
  contrast lets you read "how many days left" from the rail alone. It used to be a **left vertical
  column** (exactly as in the reference design), but the rail took 152 px of width, squeezing the
  card's six stat cells, and weekdays flowing top-to-bottom clashed with how calendars are read.
* **Header** (below the rail) — on the left, phase · week number and a large weekday name; on the
  right, `1년 12월` (Year 1, December) and a large number for that day's **day of month (日)**. The
  date is built by adding the weekday offset to that week's Monday
  (`season_state.year/month/day`) (`_date_of_day`; it can cross a month, so it goes through
  `CalendarSystem.DAYS_IN_MONTH`).
* **Body** — the card list, vertical scroll (`OutgameTheme.add_vscroll` → drag-scrolled by `DragScroll`).
* **Bottom button** — normally `확인` (OK) (amber); on Sunday `주 마감 →` (End of week); if the
  player still has a match that day, **`경기 시작`** (Start match) (dark fill — meaning "you are
  leaving this screen").

## What each weekday does

| Weekday | What happens |
|---|---|
| 월~금 (Mon–Fri) | **Training days.** On first reaching that weekday, `TrainingBoard.apply_day_training(day)` settles that row of the board and actually raises player stats. |
| 토 · 일 (Sat · Sun) | **Match days (경기일)** (`CalendarSystem.MATCH_DAYS` — Sat = match day 0, Sun = match day 1). That day's scheduled matches show up as cards. |

### Training card

One card per player (선수). On the left a role-colour strip (`OutgameTheme.lead_bar_style`), a
round portrait, name · role; on the right six stats, each in three lines:
`name / current value / today's result`.

The third line is **`+N` (green) if points were gained, otherwise `carry/EXP_PER_POINT`** (EXP accumulated toward
the next point; `EXP_PER_POINT` = const.csv `TRAINING_EXP_PER_POINT`). On a board with only basic courses, daily EXP falls short of `EXP_PER_POINT`,
so a points-only line would show `—` Mon–Thu and everything would rise at once on Friday — then for four days this screen would have no answer to the question it must answer every day,
"what improved today?".

### Match card

Lists every match of that match day, with **the player's match on top** in a dark fill
(the rest are white cards at half height). Two sources — the bracket if a tournament is running,
otherwise the league schedule (`_matches_on_day`). The status cell is `예정` (Scheduled) /
`승` (Win) / `패` (Loss) / `<팀> 승` (<team> wins).

### Mon–Fri: incident card + 오늘 저녁 (evening) card — M7

Rules and state are in `features/season/mental/README.md` (`MentalSystem`); this screen only draws
records and forwards taps. On a training day the list order is **incident → evening → training cards**.

* **Incident** — `refresh()` calls `MentalSystem.ensure_incident(state, day)` right after the
  training settle (rolled once per weekday, seeded). A pending incident opens its dialog **by
  itself** (`_open_incident`, deferred); the card (red lead bar) shows `사건 — <name> · <pilot>` and
  either `눌러서 대응하기` (reopens the dialog) or the effect notes once resolved.
* **오늘 저녁** — five portrait slots (seat order; tap to select, amber highlight; trust is amber
  once the outing is unlocked) + `면담` / `외출` / `패스`. The header shows the remaining weekly
  `면담 n/N · 외출 n/M`. Disabled buttons say why (`면담 (이번 주 끝)`, `외출 (신뢰 N↑)` with N =
  `TRUST_OUTING_MIN`). After the action the card collapses to a one-line
  summary with the effect notes. Pressing the bottom `확인` without choosing records a **pass**.
* **Dialog overlay** — interview / outing / incident open a `MessengerView`
  (`features/season/press/MessengerView.gd`) as the last child of this screen (`_overlay`); its
  STOP root blocks the list and the bottom bar until it closes, then the screen `refresh()`es.
  An evening dialog left open by a reload (record with `choice = -1`) reopens itself with the same event.

## Never settle twice

A weekday's result is kept in `season_state["week_day_log"][day]`, and **if it already exists it is
not settled again** (`_settle_day_if_needed`). There really is a path that returns to the same
weekday after playing a match —

```
WEEK Sat  →  경기 시작  →  MatchFlow → BattleSim  →  re-enter Season
        →  SeasonHub applies the result + settles that match day's AI matches  →  STANDINGS
        →  확인  →  WEEK Sat (that match is now played, so the button is "확인" again)
        →  확인  →  WEEK Sun
```

There are three pieces of week-progress state (all in `season_state`, all saved).

| Key | Meaning |
|---|---|
| `week_day` | The weekday currently shown, 0..6. **-1 means the week has not been opened yet** — the hub · press conference (기자회견) · training plan stretch is all -1, and that value decides whether the standings' "확인" returns to the week or to the hub (`SeasonHub.on_standings_confirmed`). |
| `week_day_log` | `day(int) → Array[row]`. Integer keys, so on load it goes through `_int_keyed_dict_in` — otherwise `log[3]` returns an empty array forever and the same weekday's training is applied twice. |
| `training_exp_carry` | The leftover-EXP bank. See the `TrainingBoard` entry. |

All three are cleared by `TrainingBoard.reset_week_progress()`, which runs in two places:
**training confirm** (`SeasonHub.on_training_confirmed`) and **week end** (`reset_for_new_week`).

The M7 evening action and incident follow the same rule with their own record,
`season_state.mental.days["<day>"]` (`MentalSystem`): the incident is rolled once and the evening
dialog's event is stored before it opens, so re-entering the weekday (after a match, after load)
redraws from the record and never rerolls or re-applies. `MentalSystem.end_week` clears it.

## Exchanges with SeasonHub

| Direction | Functions |
|---|---|
| Screen → hub | `has_player_match_on_day(day)` · `opponent_name_on_day(day)` · `on_week_day_match_start()` · `on_week_day_confirmed()` |
| Hub → screen | `ensure_view()` (on every routing) |

`on_week_day_confirmed()` sweeps up that day's AI matches **before moving on**
(`_resolve_ai_for_matchday`) — even when the player has no match that day and just moves on, that
day's league must still run, so the next standings shown match the date.
