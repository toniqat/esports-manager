# Autoloads

Godot singletons registered in `project.godot`. Available globally via `/root/<Name>`.

Display text is l10n keys (`ui` domain) — the error strings `start_run` / `level_up_pilot` return are
already translated (`Loc.t`) at the moment they are made; callers show them as-is, never compare them.

## Files

### GameManager.gd
**Game state singleton** — owns the BattleSim card pool and the **match
context** that flows from MatchFlow into BattleSim. No `class_name` (Godot 4.5
quirk) — access at runtime via `get_node("/root/GameManager")`.

---

#### Fixed pilot cards — `pilot_card_ids_for(pd)`
Each player has **3 fixed** pilot (파일럿) cards. This is the only function that answers
"which ones", and both the in-game deck (`CardPhaseManager._pilot_cards_for`) and the
draft detail popup call it.

- `pilot_card_ids_for(pd) -> Array[int]` — priority: `pd.pilot_cards` (CSV / save)
  → the DB row with the same id (cache `_db_pilot_cards`, used to restore old saves) → seeded roll.
  Ids that don't exist or are blocked by the position are dropped, and only the missing
  slots are filled by the seeded roll.
- `roll_pilot_card_ids(pos, seed, keep = [])` — rolls deterministically from `pilot_card_slots`
  (three slots per position, a category list per slot). The seed is `7919 + id` for a player;
  in a standalone run it is team · role.
- `card_def(id)` — one row of `card_pool_bs`. `parse_card_ids("12|36|41")` — CSV cell parser.
- **Card / skill / passive text is l10n keys — `Loc.t`.** `card_pool_bs` · `mech_card_defs` ·
  `pilot_skills` · `mech_passives` rows carry `name_key` · `description_key` (no `name` /
  `description`); display sites call `Loc.t(def["name_key"])`. The old name-based
  `card_costs_by_name()` is gone (D3) — `[card]` references in descriptions resolve by key
  (`CardData.ref_entries`, `resources/README.md`).
- `pilot_card_slots: Dictionary` — read from the `pilot_card_slots` table in `_ready`.

#### game.db path — `db_path()`

**Every path handed to SQLite at runtime must come from this function.** A hardcoded
`"res://data/game.db"` works only in the editor and fails to open in an exported build —
`res://` lives inside the `.pck`, and SQLite needs a real file on disk.

**The path logic moved to `resources/GameDb.gd`** (static class) — `ConstTable` must open the
DB while other scripts' `static var` initialisers run, i.e. possibly before autoloads exist.
`GameManager.db_path()` is kept and now simply returns `GameDb.path()`.

- `GameDb.path() -> String` — `res://data/game.db` in the editor, otherwise
  `user://data/game.db`. Computed once per run and cached.
- `GameDb._extract_to_user() -> String` — copies the DB inside the pck out to `user://`.
  **It overwrites on every run**: the DB is read-only and 96KB, so there is no reason
  for cache invalidation, and this makes it impossible for an old build's DB to survive
  into a new build. On failure it returns the original path unchanged — the `open_db()`
  failure path at each call site reports the error instead.

External consumers: `features/battle_sim/data/DataLoader.gd` (via `GameManager.db_path()`,
reached with `get_node_or_null("/root/GameManager")`) and `resources/ConstTable.gd` (calls
`GameDb.path()` directly). Only the editor tool
`addons/csv_to_db/csv_to_db.gd` still **writes** to `res://data/game.db` — because that is
the source copy. Full background: `docs/ios_testbuild.md`.

---

#### BattleSim card pool
- `card_pool_bs: Array` — loaded once on `_ready()` from the `cards` table via
  `_load_card_pool_bs()`. CardPhaseManager copies entries into starter decks.
  `scope` and `pool` are read with `row.get(…, default)` so a game.db built
  before those columns existed still loads (every card reads as `any` / in
  pool). `pool = 0` rows are dropped from the random deal;
  `scope` restricts which pilots may own a card — see
  `features/battle_sim/card_phase/README.md`.

---

#### Match Context (MatchFlow → BattleSim)
Populated by `features/match_flow/MatchFlow.gd` and consumed by
`features/battle_sim/combat/SimulationCore.spawn_pilots_with_lanes()`.

```gdscript
var match_ctx: Dictionary = {
    "active": bool,                 # false when running BattleSim standalone
    "player_roster": Array[PlayerData],   # 5 players sorted by role 0..4
    "enemy_roster":  Array[PlayerData],
    "jungle_start_dir": int (GameEnums.JungleStartDir),
    "player_side":   int (GameEnums.DraftSide),
    "banned_mech_ids": Array[int],
    "all_mechs":      Array[MechData],
}
```

API:
- `reset_match_ctx()` — clears all keys back to defaults (active = false)
- `load_match_data()` → `{"players": Array[PlayerData], "mechs": Array[MechData]}`
  or `{"error": String}`. Reads the `players` and `mechs` SQLite tables — names as
  l10n keys (`name_key`; `PlayerData.name` / `MechData.name` are `Loc.t` getters).

#### Names (l10n, D7) — `team_name(id)`, `team_short_name(id)`, `pilot_name(id)`
`season_state.team_meta` / `intl_team_meta` hold `{id, name_key, short_name_key}` only (no
display text — saves keep keys). `team_name` / `team_short_name` resolve league (0..7) and INTL
(100..) teams with `Loc.t`; outside a run (empty meta) they fall back to `RunRules.team_packages()`;
an unknown id / empty key (DB-less fallback meta) shows the id. `LeagueManager` /
`InternationalTournament` / `MatchFlow` team-name helpers delegate here. `pilot_name(id)` finds a
pilot in `all_pilots` / `intl_pilots` (for saved records that keep only `pilot_id`, e.g.
`week_day_log`). The DB-less fallbacks (`_load_team_meta`, `_synth_intl_pool`) use empty keys —
no synthesized display names.

When `match_ctx.active == false`, BattleSim falls back to `ROLE_STATS` defaults
(loaded from `pilots.csv`).

#### Run start — `start_run(run_setup) -> String`, `init_season()`, `default_run_setup()`
`start_run` is the only run entry (rank / level the pool via `RunRules.apply_progress` — every
named pilot at its stars, **my five at their profile rank + level** (`run_setup.pilot_levels` is
ignored for a real run; a test run reads `pilot_ranks` / `pilot_levels` from `run_setup`) → validate
→ season skeleton → `run_seed` → AI rosters via `RunRoster` → `team_rosters` →
`season_state.run_setup` with `pilot_levels` / `pilot_ranks` of my five).
`init_season(team_id := 0)` = `start_run(default_run_setup(team_id))` (editor
direct-run default). Test runs (`use_test_run`) skip the profile ownership check.
Errors come back as translated text (`ui.run.*`, `ui.lineup.*` from `RunRules.validate_lineup`).
Full contract → `features/season/README.md` "Entry point".

#### Run save target — `use_test_run`
`var use_test_run: bool = true`. `SaveSystem.run_path()` reads it: `true` →
`user://run_test.save` (hidden test run, used when Season / MatchFlow is run directly
from the editor), `false` → `user://run.save`. The lobby sets it to `false` in `_ready`.
(Replaces the old `active_save_slot`.) → `features/save_load/README.md`

### ProfileManager.gd
**Account (profile) state** — permanent progress that outlives a run. One JSON file,
`user://profile.save` (schema: `docs/outgame_dev_plan.md` §4). No `class_name`;
access via `get_node("/root/ProfileManager").profile`. Run state is **not** here
(that is `season_state` → `user://run.save`).

- `profile: Dictionary`, `default_profile()`, `load_profile() -> String` (called in `_ready`),
  `save_profile() -> String`.
- Missing file → default profile written. Corrupt file → warning, original copied to
  `user://profile.save.bak`, default written.
- Loaded data is laid over the defaults: missing top-level keys, and missing keys one level
  down in `manager` (+ `manager.alloc`) / `currency` / `traits` / `pass`, get default values;
  a top-level value of the wrong type is dropped. JSON floats are cast back to int for
  `version`, `active_preset`, manager ints, alloc, currency and `pass.exp`.
- M0 only creates / loads it; later milestones write to it (M1 collection, M2 run results …).
- **Collection (B — stars · rank · breakthrough · level, profile v3)** — `profile.collection`:
  `"<pilot_id>" → {owned, rank, breakthrough, level, exp, dupes}` (rules: `resources/README.md` → RunRules).
  - `ensure_starter_collection() -> bool` — on an empty collection grants every
    `players.starter = 1` pilot at rank = stars, Lv0 (called in `_ready`, saved if it granted).
  - Reads: `owned_pilot_ids()`, **`owns_pilot(pid)`** (the ownership test — Lv0 is a real level),
    `stars_of(pid)` (1..3, 0 unknown), `rank_of` (0 = not owned), `max_rank_of` (= stars + breakthrough),
    `breakthrough_of`, `breakthrough_cap_of` (= RANK_MAX − stars), `level_of`, `level_cap_of` (= 10 × rank),
    `pilot_exp_of` (EXP inside the current rank), `pilot_exp_progress(pid) -> {into, need}` (`need` 0 at the
    cap), `owned_ranks()` / `owned_levels()` (`{"<pid>": int}` — run setup pool, `start_run`, lineup owner set).
  - `grant_pilot(pid) -> {result: new|breakthrough|shard, stage, shards, rank_stone}` — new = rank = stars, Lv0;
    dupe → breakthrough +1 up to the cap; past the cap → `SHARD_PER_EXTRA_DUPE` × stars shards **and**
    `RANK_STONE_PER_EXTRA_DUPE` × stars rank stones.
  - `add_pilot_exp(pid, n) -> {from, to}` — EXP (capped at the cap level's threshold) raises the level along
    `RunRules.exp_required`, never past the cap (`from = to = -1` when not owned).
  - `level_up_cost(pid)` (-1 at the cap) · `level_up_pilot(pid)` (levelup currency, +`PILOT_MAX_LEVEL_GAIN`
    levels, EXP raised to the new level's threshold) · `rank_up_cost(pid)` (-1 at RANK_MAX) ·
    `rank_up_block_reason(pid)` ("" or translated: not owned / rank max / need breakthrough / below level cap /
    not enough 승급석) · `rank_up_pilot(pid)` (spends `rank_stone`, rank + 1, level 0, exp 0).
  - Deprecated aliases: `max_level_of` (= `level_of`, not an ownership test), `pilot_rarity` (= `stars_of`).
  - **Migration (v2 → v3, `_normalize_entry` in `_merge_over_defaults`)**: an entry without `rank` is the old
    `{max_level, breakthrough 0..5}` shape → rank = stars, breakthrough = min(old, RANK_MAX − stars),
    level = clamp(old max_level, 0, 10 × rank), exp clamped into [exp_required(level), exp_required(cap)]
    (level then follows that exp up to the cap); `max_level` is dropped. Non-dictionary entries are removed.
    Currency `rank_stone` defaults to 0.
- `apply_run_result(result) -> String` (M2, called only by `RunResult.settle_current_run`
  for non-test runs; shape `docs/outgame_dev_plan.md` §10.3): adds `currency.outgame` and
  `manager.exp` (no level-ups until M9), adds this run's `mvp` / `pom` into
  `achievements[pid]` for my pilots (new entries `{pom, mvp, true_ending: false}`; all-zero
  pilots skipped), appends `{id, scenario, team, score, result: "clear"|"fail", phase_reached, at}`
  to `runs` (abandon is recorded as `"fail"`; oldest dropped past `RUNS_HISTORY_MAX`), then saves.
  Idempotent: a `result.id` already in `runs` is a no-op.
- **v2 (M8~M10, `docs/outgame_dev_plan.md` §12.1)** — presets (`ManagerProgress`), `manager.removed`,
  owned traits (`ensure_default_traits` in `_ready`, `grant_trait`), currencies (`currency_of` /
  `add_currency` / `spend_currency`; keys = `default_profile().currency`, incl. `rank_stone`), pilot growth
  (collection API above), weekly pass
  (`PassSystem`). **These mutators do not save** — the screen calls `save_profile()` once per action.
  `apply_run_result` also pays every `result.currency` key, manager exp (→ level-ups), `pilot_exp`,
  `pass_exp`, grants `unlocked_traits` (+ `traits.unlocked_pending`) and writes `result.profile_delta`.
- **Locale (l10n M5, `docs/localization_design.md` D10 · D11 · §10.4)** — `profile.locale`: the chosen
  locale code (one of `L.LOCALES`), `""` = never chosen (old profiles load as `""`).
  - **Boot**: `_init()` (not `_ready`) peeks only the `locale` field of `profile.save` (`_peek_saved_locale`,
    missing / corrupt → `""`) and calls `Loc.set_locale(Loc.pick_initial_locale(saved))` — saved value if
    supported → device locale (`OS.get_locale()`, then the language part) → `L.FALLBACK_LOCALE`. The engine
    instantiates every autoload (`_init`) before adding any to the tree (`_ready`), so this runs before
    `GameManager._ready` (listed earlier in `project.godot`) and before any scene builds text. The full
    profile load stays in `_ready` (it needs `ConstTable` / game.db). `""` is kept until the player picks,
    so a later device-language change still applies.
  - `saved_locale() -> String`; `set_locale(code) -> String` — rejects codes outside `L.LOCALES`, applies
    `Loc.set_locale`, writes `profile.locale` and **saves immediately** (one settings action). The caller
    reloads the current scene (`HomeTab._on_locale_chosen`, `features/meta/lobby/README.md`).

### Haptics.gd
**iOS / Android haptic feedback** — the GDScript wrapper of a `godot-haptics` fork that is
maintained in a separate repository. **This project is not the source, so do not edit it here**:
edit `autoload/godot_4/Haptics.gd` in the fork repo and copy it over.

Unlike `GameManager`, **it is registered with `*`** (`project.godot`) — the whole plugin API
is written assuming the global name `Haptics`. So calls are plain `Haptics.play(...)`, not
`get_node("/root/Haptics")`.

There are two layers, and **game code calls only the upper one**:

```gdscript
Haptics.play(Haptics.Kind.SELECT)    # a value changed under the finger
Haptics.play(Haptics.Kind.MEDIUM)    # confirm action
Haptics.play(Haptics.Kind.SUCCESS)   # the result went our way
```

The upper layer **fully absorbs the `enabled` toggle · platform check · missing-plugin
fallback**, so call sites have no branches. The lower layer (`selection()` / `rigid()` /
`impact(style, intensity)`) is only for directly specifying iOS-specific styles or
intensities that have no cross-platform meaning.

- **On desktop everything is a silent no-op**, so editor runs need no guards.
- **`enabled` is a settings-screen toggle and must be stored in the save** — Godot cannot
  read the haptics switch in iOS system settings, so this is the only way to turn it off in-game.
- **`prepare()`** wakes the Taptic Engine ahead of time. Otherwise the first haptic of a
  session arrives noticeably late — call it one beat early, e.g. when opening a screen
  (no-op on Android).
- **Overuse turns it into background noise.** Attach it to events that fire every turn and
  the one big event gets buried — the same reason the front-line (전선) dwell growth points
  (성장치) popup is not shown.

**CI builds the native binary** — `.github/workflows/ios-testbuild.yml` recompiles it on every
iOS build against that Godot version's headers, places it in `ios/plugins/haptics/`, and
uses three layers of gates to verify it was actually linked
(`ios/plugins/README.md`). Therefore **the fallback never runs in CI artifacts**.
A build exported locally on Windows has no plugin, so only then does the
`Input.vibrate_handheld` fallback run, and a warning is printed once.


### HapticUi.gd
**Wires button haptics in one place** — this repo's own layer on top of `Haptics`; unlike
that one, **it may be edited here** (it is not a file copied from the fork).
For the same reason as `Haptics`, it is registered with `*` under the global name `HapticUi`.

#### Invert the rule — write only the exceptions
There are over a hundred pressable things (screen buttons · transparent hit buttons over
portraits · filter chips · dim backplates), and writing `Haptics.play(...)` by hand on all of
them means **every new button is one more place to forget it**. So a single
`get_tree().node_added` attaches feel to **every `BaseButton` that enters the tree**. Writing the
exceptions is shorter than writing the rule.

```gdscript
HapticUi.mute(btn)                           # another place already fires for the same press
HapticUi.kind(btn, Haptics.Kind.MEDIUM)      # different release feel for this button only
HapticUi.down_kind_for(btn, HapticUi.NONE)   # drop the press beat for this button only
```

#### One press gives two beats

| Event | Default feel | What it says |
|---|---|---|
| `button_down` (finger touches) | `SOFT` | **blunt** — touched |
| `pressed` (finger lifts = activation) | `RIGID` | **crisp** — pressed |

- **It used to be a single `pressed` beat.** But if feel only comes on release, **nothing
  happens at the moment of pressing** — there is no way to confirm the press until the
  screen changes. Now a soft layer comes first on touch, and a crisp tap closes it on release.
- **The order of the two beats was flipped once.** Previously touch was `LIGHT` and release
  was `SOFT` (light tap → blunt close). Now it is the reverse: **the soft one comes first and
  the hard one closes** — like a clicky physical button, the sharp-ended beat must own
  activation for the fact of the press to stay in the hand.
- **The press beat can be cancelled.** Press, then slide the finger off, and `pressed` never
  fires, so there is no release beat — only the soft layer remains with no hard close, and that
  itself means "nothing happened". That is why **the sharp beat goes on release.**
- **The intensity table was retired.** At one point each button had a different release
  intensity (primary buttons `MEDIUM` · tabs `SELECT` …), but now every kind gets the same two
  beats. Whether it is a confirm or a tab switch is the screen's job to say; feel that wobbled
  from screen to screen was itself noise. The `kind()` calls on `OutgameTheme`'s four button
  styles · ban/pick (밴픽) filter chips · confirm buttons were all removed at that time.
- **Defaults are `down_kind` / `up_kind`** (filled in `_ready` — `Haptics` is an autoload and
  does not yet exist at `const` initialization time).
- **The kind is read at press time.** So calling `kind()` before or after `add_child` is the
  same. Auto-wiring is applied only once, when the node enters the tree
  (`haptic_bound` meta stamp — prevents a node that is removed and re-added from being wired
  twice and buzzing twice per press).
- **`mute()` turns off both beats.** Use it when another place already fires for the same
  press, like the lobby's `새 런` with a run, or a danger `ConfirmPopup` confirm (`meta/lobby/`).
- **`button_down` also gets `Haptics.prepare()`**: the time from finger touch to finger lift
  is exactly the slack needed to wake the Taptic Engine, and that slack **makes the crisp close
  arrive on time**.
- `enabled` turns off **this layer only** (`Haptics.enabled` is game-wide).

#### Places auto-wiring does not reach
Things that are not `BaseButton` — card drag, the strategy point donut (`_input`), training
tile drag (pick up · snap per cell · drop), the jungler marker drag in jungle start (정글 시작),
the mech (메크) slot drag in ban/pick, and **events unrelated to buttons**
(hit · kill · turret destroyed · engage result · objective captured · win/loss). Those places
call `Haptics.play(...)` directly — the table is in the "Haptics (feel)" section below
(moved here from root `CLAUDE.md`).

---

## Note
Do NOT add `class_name` to autoload scripts in Godot 4.5 — causes parse errors in other scripts.


## Detail moved from root CLAUDE.md

### L10nKeyMode.gd
**Dev-only l10n key mode** (debug builds; release frees it at start). **Ctrl+Alt+K**, or the run
argument `--l10n-keys` (Debug → Customize Run Instances → Main Run Args), swaps the current locale's
`Translation` for one mapping every key to its **alias**, so each text on screen reads like
`battle.pile_viewer.title` — search it in the L10n sheet (editor main screen `L10n` tab). Both text paths
(`Loc.t` and scene auto-translate) go through `TranslationServer`, so nothing else is touched; toggling
off puts the original translations back. Scene texts redraw at once (`set_locale` to the same locale);
texts code already set refresh only when that UI is rebuilt — turn it on before opening a screen. A
yellow "L10N KEYS" badge (CanvasLayer 128) shows while on. Aliases come from
`data/l10n/generated/index.json` (local, gitignored — l10n scan / build writes it); without it the raw
`tx_` keys show. API: `set_enabled(on)`, `is_enabled()`. Listed in l10n `config.json`
`scan.ignore_paths` (its badge text is a dev label).

### Haptics (feel) — shared by outgame and in-game
**There is one table that decides what reaches the hand.** Wiring has two layers, and neither
writes intensities by hand per screen.

1. **Buttons are wired automatically by `autoloads/HapticUi.gd`, and one press gives two
   beats** — a single `node_added` attaches feel to **both** `button_down` and `pressed` of
   **every `BaseButton`** entering the tree: **`SOFT` on press (touch), `RIGID` on release
   (activation)**. If feel only comes on release, nothing happens at the moment of pressing,
   and there is no way to confirm the press until the screen changes — so a soft layer comes
   first on touch and a crisp tap closes it. **The order of the two beats was flipped once**
   (previously `LIGHT` → `SOFT`) — like a clicky physical button, **the sharp-ended beat owns
   activation** so the fact of the press stays in the hand. Press and slide the finger off, and
   `pressed` never fires, so **the absence of the closing beat itself means "nothing
   happened"** — that is why the sharp beat goes on release. **The button intensity table was
   retired** — previously `OutgameTheme`'s button style was the intensity
   (primary · dark = `MEDIUM`, ghost = `LIGHT`, text = `SELECT`); now every kind gets the same
   two beats (whether it is a confirm or a tab switch is for the screen to say). Only exceptions
   are written, via `HapticUi.mute(btn)` (both beats off) / `kind(btn, …)` (release) /
   `down_kind_for(btn, …)` (press). `button_down` also gets
   `Haptics.prepare()`, so the Taptic Engine wakes between press and activation.
2. **Non-buttons call it directly where the event happens** (`Haptics.play`).

| Event | Where | Feel |
|---|---|---|
| Card dragged out of the hand (손패) | `CardPhaseManager._begin_drag` | `SELECT` |
| Dragged card **just entered a valid target / drop zone** | `CardPhaseManager._update_drag` (`_drag_hot_last` transition) | `SELECT` |
| Card actually played / moved to discard | `CardPhaseManager._end_drag` | `MEDIUM` |
| Attack card **single hit** | `CardPhaseManager._effect_attack` | `MEDIUM` |
| Attack card **miss** | 〃 | `LIGHT` |
| Pilot kill (both teams) | `BattleSim.mark_pilot_dead` | `HEAVY` |
| Turret (포탑) destroyed | `BattleSim.score_turret_kill` | `HEAVY` |
| My operation phase (작전 단계) opening | `CardPhaseManager.start_card_phase` | `MEDIUM` |
| End turn / flip donut | `ui/CostDonut._input` | `MEDIUM` / `SELECT` |
| Engage (교전) result (win / loss / draw) | `EngagePhaseManager` dashboard entry | `SUCCESS` / `ERROR` / `MEDIUM` |
| Objective captured (ally / enemy) | `ObjectiveSystem._grant_reward` | `SUCCESS` / `WARNING` |
| Match win / loss | `SimulationCore.check_win_condition` | `SUCCESS` / `ERROR` |
| Battlefield (전장) portrait press / **long-press for detail panel** | `battle_sim/ui/MarkerTouch` | `SELECT` / `MEDIUM` |
| Jungle start — pick up marker / **snap per droppable cell** / cell chosen | `gambit/JungleStartOverlay` | `SELECT` / `LIGHT` / `MEDIUM` |
| Training tile — pick up / **snap per droppable cell** / place | `season/training/TrainingView` | `SELECT` / `LIGHT` / `SOFT` |
| Training tile — tap on board to remove | `season/training/TrainingView._on_grid_input` | `LIGHT` |
| Ban/pick mech slot — lift / swap | `ban_pick/BanPickController` | `SELECT` / `MEDIUM` |
| Abandon run — open confirm / delete | `meta/lobby/LobbyScreen` (`새 런` / `_on_abandon_confirmed`) | `WARNING` / `ERROR` |
| Campaign over / championship | `GameOverView` / `EndingView.ensure_view` | `ERROR` / `SUCCESS` |

**Three rules.**
- **Don't attach to events that fire every turn** — a single hit of auto-combat on the
  battlefield, front-line dwell growth points, camp (캠프) capture. Overuse makes feel
  background and buries the one big event
  (same reason the growth points popup doesn't show front-line income).
- **One event buzzes once.** A hit that ends in a kill skips `MEDIUM` —
  `mark_pilot_dead` already fired `HEAVY`, and overlapping would blur the kill into a normal
  hit. For the same reason, the two-press delete button `mute`s auto-wiring.
- **Drag buzzes only on "enter" — except on boards that snap per cell, where it buzzes per
  cell.** Leaving is silent everywhere (becoming droppable is the signal), and buzzing every
  **frame** is still forbidden (that is vibration, not a signal). The training board fires
  `LIGHT` per cell because that screen's preview moves **locked to cells**, not free
  coordinates — one tap means "crossed one cell", so dragging across the board gives a
  ratcheting click feel. Places with a continuous target, like card drag (`_drag_hot_last`),
  still buzz once per transition.
- **Drag-and-drop also closes with a heavier layer.** The moment a training tile locks onto
  the board is `SOFT` — a layer heavier than pick up (`SELECT`) · cell crossing (`LIGHT`) is
  needed for the three to read as the start · middle · end of one gesture.

**On desktop everything is a silent no-op**, so editor runs need no guards.
However, **`--check-only --script` doesn't know autoload identifiers** — files that call
`Haptics` / `HapticUi` show `Identifier not found` in that check, but actual runs are fine.
Verify by running a scene.

### `res://data/game.db` → `user://data/game.db`

**SQLite must open a real file on disk.** In the editor `res://` is a real folder, so it just
opens, but in an exported build `res://` lives inside the `.pck` and SQLite cannot open that
path — left untouched, the iPhone build would have stopped at the title screen with a DB
error. So all runtime DB access goes through one place, **`GameDb.path()`** (`resources/GameDb.gd`;
`GameManager.db_path()` delegates to it) — in the
editor it returns `res://data/game.db` as-is (CSV→DB rebuilds must take effect immediately);
on device it returns a copy of the pck's DB extracted to `user://data/game.db`. **It
overwrites on every run** — the DB is read-only at runtime (saves are
`user://saves/*.save`) and only 96KB, so simply copying is always better than a cache
invalidation mechanism that compares what changed (it becomes structurally impossible for an
old build's game.db to survive after installing a new build). Only the editor tool
`addons/csv_to_db/csv_to_db.gd` still **writes** to `res://data/game.db` — because that is
the source copy.

`data/game.db` is **not a resource**, so by default it is not packed into the pck.
`include_filter="data/game.db"` in `export_presets.cfg` is what includes it, and the
workflow's packaging step actually searches for that string inside the pck to confirm — if
the filter silently misses, you get a combination where the build is green but the game dies.

---
