# Autoloads

Godot singletons registered in `project.godot`. Available globally via `/root/<Name>`.

## Files

### GameManager.gd
**Game state singleton** — owns the BattleSim card pool and the **match
context** that flows from MatchFlow into BattleSim. No `class_name` (Godot 4.5
quirk) — access at runtime via `get_node("/root/GameManager")`.

---

#### game.db 경로 — `db_path()`

**런타임에 SQLite 에 넘기는 경로는 반드시 이 함수에서 나온다.** 하드코딩한
`"res://data/game.db"` 를 쓰면 에디터에서만 돌고 익스포트 빌드에서는 열리지
않는다 — `res://` 가 `.pck` 안으로 들어가는데 SQLite 는 디스크 위의 진짜
파일을 요구하기 때문이다.

- `db_path() -> String` — 에디터면 `res://data/game.db`, 아니면
  `user://data/game.db`. 한 실행에 한 번만 계산해 `_db_path` 에 물고 있는다.
- `_extract_db_to_user() -> String` — pck 안의 DB 를 `user://` 로 꺼낸다.
  **매 실행마다 덮어쓴다**: DB 는 읽기 전용이고 96KB 라 캐시 무효화를
  둘 이유가 없고, 그래야 새 빌드에 옫 빌드의 DB 가 남는 사고가 불가능해진다.
  실패하면 원본 경로를 그대로 돌려준다 — 호출부마다 있는 `open_db()` 실패
  경로가 에러를 대신 말해 준다.

외부 소비자는 `features/battle_sim/data/DataLoader.gd` 하나이고
`get_node_or_null("/root/GameManager")` 로 받아 쓴다. 편집 도구인
`addons/csv_to_db/csv_to_db.gd` 만 여전히 `res://data/game.db` 에 **쓴다** —
그것이 원본이기 때문이다. 자세한 배경은 `docs/ios_testbuild.md`.

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
  or `{"error": String}`. Reads the `players` and `mechs` SQLite tables.

When `match_ctx.active == false`, BattleSim falls back to `ROLE_STATS` defaults
(loaded from `pilots.csv`).

## Note
Do NOT add `class_name` to autoload scripts in Godot 4.5 — causes parse errors in other scripts.
