# awakening/ — 깨달음 (awakening) + pilot card loadouts (§15 C)

Contract: `docs/outgame_dev_plan.md` §15 (decisions §15.0 C, state §15.1, interfaces §15.2).
Display text = l10n keys of the **`awakening` domain** (`data/l10n/src/awakening.csv`: `awakening.view.*` ·
`awakening.option.*` · `awakening.upgrade|swap|preset.*` · `awakening.preset_tab.*` · `awakening.detail.*` ·
`awakening.picker.*`); shared buttons `ui.button.confirm|cancel|back|tap_to_continue`. Tuning = const.csv
`AWAKEN_*` / `LOADOUT_*` (no numbers in this doc).

| File | Role |
|---|---|
| `Awakening.gd` | `class_name Awakening` (static). Gauge per pilot, queue of pending awakenings, training / match sources, the 1-of-3 options, deterministic candidate draws, `resolve_*` (writes the outcome). |
| `PilotLoadout.gd` | `class_name PilotLoadout` (static). Card presets per pilot (base + extras), active preset, edits (upgrade / swap / add), roster-copy `apply_to`, card-table helpers (`upgrade_of`, `base_of`, `candidate_pool`). |
| `UI_View_Awakening.tscn` / `AwakeningView.gd` | `class_name AwakeningView` (CanvasLayer 25). The awakening event screen: intro FX → choose 1 of 3 → sub-page → confirm. `create()` · `open(pid)` · `signal closed` · `is_open()` · static `preset_label(idx)`. |
| `AwakeningBurst.gd` | `class_name AwakeningBurst` — `_draw` widget placed in the view scene: amber rays / glow / expanding ring; `progress` (tweened) · `spin`. |
| `UI_Comp_AwakeningCardCell.tscn` / `AwakeningCardCell.gd` | One pilot card: the real hand card (`scenes/Card.tscn`) in a `SelectableCard` frame + tap button + caption ("강화됨" under a "+" card). `create()` · `set_card_scale(k)` · `fill(card_id)` · `set_selected` · `set_locked` · `set_caption` · `signal tapped(card_id)`. Also used by the ban/pick preset picker. |
| `UI_Comp_AwakeningPilotBlock.tscn` / `AwakeningPilotBlock.gd` | Gauge bar + "pending" line + the pilot's presets (name, "출전" chip on the active one, card-name chips; "+" cards on the accent chip). `SeasonPilotDetail` mounts it into its `%AwakeningSlot` (`AwakeningPilotBlock.mount(holder, state, pid)`). |

The pre-match preset picker lives in `features/match_flow/ban_pick/` (`BanPickLoadoutPicker`, see that README).

## State (`season_state`, JSON-round-tripped — string keys, `int()` reads)
```
awakening         = {"<pid>": int gauge}            # my pilots only, 0 .. AWAKEN_THRESHOLD-1 after queueing
awakening_pending = [pid, …]                        # queue; a pid may appear twice (gauge jumped 2 thresholds)
awakening_count   = {"<pid>": int}                  # resolved awakenings this run (seeds the draws)
loadouts          = {"<pid>": {"presets": [[card_id ×3], …], "active": int}}
```
`init_run` (from `GameManager.start_run`) writes all four. Every read is lazy-safe: a run without the keys
(old save, editor test run, `UiPreview.ensure_run`) gets the base preset / an empty queue on first use.
Only my pilots (`MentalSystem.my_pilot_ids`) have a gauge or a loadout; anyone else reads 0 / [] and is ignored.

## Gauge rules (`Awakening`)
- `add_gauge(state, pid, amount, source := "")` — the only way in (training, match, and agent D's
  story / incident / focus-training clauses). Gauge + amount; **every time it reaches AWAKEN_THRESHOLD one
  awakening is queued and the threshold is taken off** (130 → queue + 30). A negative amount lowers it (≥ 0).
- Training day (`on_training_day(state, rows)`, `TrainingBoard.apply_day_training` hook): sum of the row's
  `exp` values × AWAKEN_TRAIN_PER_EXP, rounded, clamped AWAKEN_TRAIN_MIN..MAX (0 on a day without EXP).
  The gain is written back on the row as **`row["awaken"]`** (the week screen may show it).
- Match (`on_match(state, pending_match)`, `SeasonHub._consume_pending_match_result` hook): every pilot of
  mine AWAKEN_MATCH_BASE, + AWAKEN_MATCH_RANK_BONUS scaled by the `RunStats.mvp_score` rank among my five
  (best = full, worst = 0, linear, rounded), + AWAKEN_MATCH_MVP for `pending_match.mvp_pilot_id`. Once per
  match (`pending_match.awakening_recorded`); gains land in `pending_match.awakening_gains` (`{"<pid>": n}`).
- `next_pending(state) -> int` (first queued pid, -1 none) · `pending_count(state, pid)` · `count(state, pid)` ·
  `gauge(state, pid)` · `threshold()`.

## The awakening (1 of 3)
`options(state, pid) -> {upgrade, swap, preset: bool, preset_reason: "" | "level" | "max"}`:
- **upgrade** — some preset holds a card with an upgrade (`cards.upgrade_id >= 0`). `upgradable(state, pid, idx)`.
- **swap** — `swap_candidates(state, pid, idx)`: AWAKEN_SWAP_CANDIDATES cards from `PilotLoadout.candidate_pool`
  (`pool = 1`, `scope` allows the pilot's position, **no family already in that preset** — a base card and its
  "+" row are one family —, held `excl_group`s blocked).
- **add preset** — `PilotLoadout.can_add_preset`: `TrainingLevel.level >= LOADOUT_PRESET_MIN_TLEVEL` and fewer
  than LOADOUT_EXTRA_MAX extra presets. `preset_candidates(state, pid)`: AWAKEN_PRESET_CANDIDATES presets of 3,
  consecutive cards of one shuffled pool (candidates do not share cards while the pool is big enough).
- **Draws are deterministic** — `RandomNumberGenerator` seeded with `"run_seed:pid:awakening_count:kind:preset"`.
  Reopening the same awakening shows the same candidates; the next awakening of that pilot draws anew.
- `resolve_upgrade(state, pid, idx, card_id)` · `resolve_swap(state, pid, idx, out_id, in_id)` ·
  `resolve_preset(state, pid, cand)` · `resolve_skip(state, pid)` (nothing available — spends it without an
  effect, so the queue never sticks). Each validates (the pilot must be queued, the pick must be one of the
  shown candidates), writes the loadout, **pops one queue entry and counts it**; returns `{ok, kind, …}`.
- Run-only, that pilot, that preset only. A swapped-out "+" card is lost as such (its base is not restored).

## Loadouts (`PilotLoadout`)
- Base preset = `GameManager.pilot_card_ids_for(pd)` of the run copy at `init_run` (after rank rows applied).
- `presets(state, pid) -> Array[Array[int]]` (copies) · `preset(state, pid, idx)` · `active` · `set_active` ·
  `extra_count` · `can_add_preset` · `upgrade_card` · `swap_card` · `add_preset` (→ index, -1 at the cap).
- `apply_to(state, pd)` — `MatchFlow._finalize_rosters` hook, my pilots only: `pd.pilot_cards = active preset`
  on the **roster copy**. The battle deck then reads it through `GameManager.pilot_card_ids_for` like any
  `players.pilot_cards` value ("+" ids are ordinary `cards.csv` rows with the same `scope`, so they pass).
- Card helpers: `upgrade_of(id)` (-1 none), `base_of(id)` (via `GameManager.card_upgrade_base`), `is_upgraded`,
  `base_ids(state, pid)`, `candidate_pool(state, pid, held)`.

## Upgraded "+" cards (`data/csv/cards.csv`)
- Every `pool = 1` card has a "+" row: **id = base id + 100**, `pool = 0` (never rolled as a pilot card),
  same scope / cat / keywords, name key `card.pilot.<id>.name` = base name + "+", own description key
  `card.pilot.<id>.desc` (copy of the base text unless a clause was added). The base row's `upgrade_id`
  points at it; the "+" row's is -1 (one upgrade step).
- Upgrades are drafts for the designer: mostly cost −1, else a number up (draw / search / strategy / shield /
  growth / ambush search …), or an extra clause (복귀+ `;draw:1`, 재고+ `;draw:1`). 자신감+ / 맑은 정신+ (hand
  passives whose amount is a const) carry their own amount on the clause (`hand_passive:confidence|hit_pct:25`,
  `hand_passive:clear_mind|cut:2`, read by `CardPhaseManager._hand_passive_mod`).
- A "+" card wears its base card's art and nameplate type (`CardImages.base_uid`).

## AwakeningView flow (`UI_View_Awakening.tscn`)
```
AwakeningView (CanvasLayer 25)
└ %Root (full rect, STOP — blocks the week screen; intro tap on release)
  ├ Dim · DimDeep (DimPanel ×2)
  ├ %Burst (AwakeningBurst, centre = portrait centre)
  ├ %Intro ─ %IntroPortrait (340², round portrait) · IntroTitle "깨달음" · %IntroLine · IntroHint
  └ %SafeArea (device insets, code)
    └ %Panel (PopupCard, full width − 28 margins, height = content, centred)
      └ Body ─ Head (%Title · %Sub) · %Tabs (%TabTemplate) ·
               %PageChoose (ChooseHead · %OptUpgrade · %OptSwap · %OptPreset [Pad/Lines: Name · Desc · Lock] · %SkipNote) ·
               %PageUpgrade (UpPreview: %UpBig · %UpDesc · %UpHint · UpGap · %UpCards) ·
               %PageSwap (SwapHint · SwapCandsTitle · %SwapCands · %SwapDesc · SwapHeldTitle · %SwapHeld) ·
               %PagePreset (%PresetHint · %PresetRows/%PresetRowTemplate [RowHit · RowPad/Line: Label · Cards] · %PresetDesc) ·
               Footer (%Back · FooterGap · %Confirm)
```
1. `open(pid)` — fade in, burst + portrait pop, "{name}이 무언가를 깨달았습니다". Taps count after
   `INTRO_TAP_DELAY`. A pid with nothing queued closes right away (`closed` next frame).
2. Choice page — three option buttons; a locked one stays visible, faded, with its reason (`Lock` line:
   no upgradable card / no candidate / training level / extras full). None available → `%SkipNote` + 확인.
3. Upgrade: preset tabs; the preset's 3 cards at the bottom (already "+" = locked); tap → the "+" card
   (scale 1.3) with the current card's description (faded) above the "+" one. Swap: tabs; candidates on
   top, the preset's cards below, the last tapped card's description between; 확인 needs one of each.
   Add preset: candidate rows (selectable card frames), the tapped card's description below.
4. 확인 → `Awakening.resolve_*` (state written) → fade out → `closed`. 뒤로 returns to the choice page.

**Week screen contract (agent D):** poll `Awakening.next_pending(state)` after each state change; when it is
`>= 0`, stop advancing the day and
```gdscript
var v := AwakeningView.create()
add_child(v)
v.closed.connect(func(): v.queue_free(); _save("awakening"); refresh())   # then poll again
v.open(pid)
```
The view never saves; the host saves after `closed` (the outcome is already in `season_state`). If the app
closes before that save, the awakening is still queued in the last save and simply reopens.

## Detail sheet (`SeasonPilotDetail`)
`UI_View_SeasonPilotDetail.tscn` has an `%AwakeningSlot` VBox before `Tail`; `_bind` calls
`AwakeningPilotBlock.mount(%AwakeningSlot, state, pid)`. The small `SeasonPilotCard` has no gauge (no room
under the ring / pill / stress lines at 256 tall).

## F6 previews
`AwakeningView` (in-memory run, one awakening queued for my first pilot) · `AwakeningCardCell` ([교전 개시+],
selected) · `AwakeningPilotBlock` (gauge 70, one "+" card, one extra preset). Nothing is saved.

## Verification (2026-10-09, headless + windowed harnesses, deleted)
Logic: base presets, 130 → 30 + queue, non-my pilot ignored, training / match gains (MVP > others,
idempotent), options (preset locked by level), deterministic candidates, all three resolves + skip refusal
without a queue, extra cap, JSON round trip, `apply_to` → `pilot_card_ids_for` → BattleSim `starter_cards`
holds the "+" ids, hand-passive overrides, every card's `CardDescBox` builds. Screens: intro, choice,
upgrade, swap, add preset, detail sheet block, ban/pick picker (810×1440).
