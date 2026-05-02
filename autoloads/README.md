# Autoloads

Godot singletons registered in `project.godot`. Available globally via `/root/<Name>`.

## Files

### GameManager.gd
**Game state singleton** — owns Card Draw state, the BattleSim card pool, and
the **match context** that flows from MatchFlow into BattleSim.
No `class_name` (Godot 4.5 quirk) — access at runtime via `get_node("/root/GameManager")`.

---

#### Card Draw state
- Owns both decks (`player_deck`, `ai_deck`), hands, and discard piles
- Tracks `current_phase` (DRAW / PLAYER_ACTION / AI_ACTION) using `GameEnums.Phase`
- Manages mana pools (`player_mana`, `ai_mana`, `max_cost`)
- Emits signals for all state changes; scene scripts connect to these

Key signals: `phase_changed`, `card_drawn`, `card_played`, `mana_changed`, `game_log`, `ai_turn_finished`, `card_overflow_discarded`

Key methods:
- `start_draw_phase()` — resets draw alternation, emits `phase_changed`
- `execute_draw()` — draws one card for the current player, checks initiative (threshold = 7)
- `player_play_card(card)` → bool — deducts mana, emits `card_played`
- `ai_play_card()` → CardData — picks random affordable card
- `end_player_turn()` / `end_ai_turn()` — transitions back to draw phase

---

#### BattleSim card pool
- `card_pool_bs: Array` — loaded once from the `cards` table via `_load_card_pool()`

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
  or `{"error": String}`. Reads the `players` and `mechs` SQLite tables.

When `match_ctx.active == false`, BattleSim falls back to `ROLE_STATS` defaults
(loaded from `pilots.csv`) and `move_range = 1`.

---

#### Battle state mirror
Cross-scene mirror of the in-battle phase/turn for any future UI that needs it
without depending on BattleSim being instanced:
- `battle_phase`, `battle_turn`, `player_hq_hp`, `enemy_hq_hp`, `battle_over`
- Signals: `battle_phase_changed`, `battle_turn_advanced`
- API: `set_battle_phase(p)`, `advance_battle_turn()`, `reset_battle_state()`

## Note
Do NOT add `class_name` to autoload scripts in Godot 4.5 — causes parse errors in other scripts.
