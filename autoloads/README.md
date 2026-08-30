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

### Haptics.gd
**iOS / Android 햅틱 피드백** — 별도 저장소로 굴리는 `godot-haptics` 포크의
GDScript 래퍼다. **이 프로젝트가 원본이 아니므로 여기서 고치지 말 것**:
포크 저장소의 `autoload/godot_4/Haptics.gd` 를 고치고 이리로 복사한다.

`GameManager` 와 달리 **`*` 를 달아 등록한다**(`project.godot`) — 플러그인 API
전체가 전역 이름 `Haptics` 를 전제로 쓰여 있어서다. 그래서 호출은
`get_node("/root/Haptics")` 가 아니라 그냥 `Haptics.play(...)` 다.

두 층이 있고 **게임 코드는 위층만 부른다**:

```gdscript
Haptics.play(Haptics.Kind.SELECT)    # 손가락 밑에서 값이 바뀌었다
Haptics.play(Haptics.Kind.MEDIUM)    # 확정 동작
Haptics.play(Haptics.Kind.SUCCESS)   # 결과가 이쪽에 유리하게 났다
```

위층이 **`enabled` 토글 · 플랫폼 검사 · 플러그인 부재 폴백을 통째로 흡수**하므로
호출부에 분기가 없다. 아래층(`selection()` / `rigid()` /
`impact(style, intensity)`)은 크로스 플랫폼 의미가 없는 iOS 고유 스타일이나
세기를 직접 지정할 때만 쓴다.

- **데스크톱에서는 전부 조용한 no-op** 이라 에디터 실행에 가드가 필요 없다.
- **`enabled` 는 설정 화면 토글이고 세이브에 실어야 한다** — iOS 시스템 설정의
  햅틱 스위치는 Godot 에서 읽을 수 없어서, 게임 안에서 끄는 길이 이것뿐이다.
- **`prepare()`** 는 탭틱 엔진을 미리 깨운다. 세션 첫 햅틱은 안 그러면 눈에 띄게
  늦게 온다 — 화면을 열 때처럼 한 박자 앞서 부른다(Android 에서는 no-op).
- **남발하면 배경이 된다.** 매 턴 도는 사건에 붙이면 정작 큰 한 건이 묻힌다 —
  전선 체류 성장치 팝업을 안 띄우는 것과 같은 이유다.

**네이티브 바이너리는 CI 가 굽는다** — `.github/workflows/ios-testbuild.yml` 이
매 iOS 빌드에서 그 Godot 버전의 헤더로 다시 컴파일해 `ios/plugins/haptics/` 에
놓고, 세 겹의 게이트로 그것이 실제로 링크됐는지까지 확인한다
(`ios/plugins/README.md`). 그러므로 **CI 아티팩트에서는 폴백이 돌지 않는다**.
윈도우에서 로컬로 익스포트한 빌드에는 플러그인이 없으므로 그때만
`Input.vibrate_handheld` 폴백이 돌고 경고가 한 번 찍힌다.


### HapticUi.gd
**버튼 햅틱을 한 곳에서 배선한다** — `Haptics` 위에 얹은 이 저장소 쪽 층이고,
그쪽과 달리 **여기서 고쳐도 된다**(포크에서 복사해 오는 파일이 아니다).
`Haptics` 와 같은 이유로 `*` 를 달아 전역 이름 `HapticUi` 로 등록한다.

#### 규칙을 뒤집는다 — 예외만 적는다
눌리는 것이 백 개가 넘고(화면 버튼 · 초상화 위의 투명 히트 버튼 · 필터 칩 ·
딤 뒤판) 그 전부에 손으로 `Haptics.play(...)` 를 적으면 **새로 만드는 버튼마다
빠뜨릴 자리가 하나씩 생긴다**. 그래서 `get_tree().node_added` 하나가
**트리에 들어오는 모든 `BaseButton`** 에 감촉을 물린다. 예외를 적는 쪽이
규칙을 적는 쪽보다 짧다.

```gdscript
HapticUi.mute(btn)                           # 같은 누름에 다른 자리가 이미 낸다
HapticUi.kind(btn, Haptics.Kind.MEDIUM)      # 이 버튼만 뗄 때를 다르게
HapticUi.down_kind_for(btn, HapticUi.NONE)   # 이 버튼만 누름 박자를 뺀다
```

#### 한 번 누르면 두 박자가 온다

| 사건 | 기본 감촉 | 무엇을 말하는가 |
|---|---|---|
| `button_down` (손가락이 닿음) | `LIGHT` | **가볍게** — 닿았다 |
| `pressed` (손가락을 뗌 = 활성화) | `SOFT` | **뭉툭하게** — 눌렸다 |

- **예전에는 `pressed` 한 박자뿐이었다.** 그런데 감촉이 뗄 때만 오면 **누른
  순간에는 아무 일도 안 일어난다** — 화면이 바뀌기 전까지 눌렸는지 확인할
  길이 없다. 지금은 닿는 순간 가벼운 톡이 먼저 오고, 손을 뗄 때 뭉툭한 한 겹이
  그것을 닫는다.
- **누름 박자는 취소될 수 있다.** 눌렀다가 손가락을 밖으로 빼면 `pressed` 가
  안 오므로 뗌 박자가 없다 — 가벼운 톡만 남고 뭉툭한 닫음이 없는 것이 곧
  "아무 일도 일어나지 않았다"이다. 그래서 **무거운 쪽을 뗄 때에 둔다.**
- **세기 표는 폐기됐다.** 한때는 버튼마다 뗄 때의 세기가 달랐지만(주요 버튼
  `MEDIUM` · 탭 `SELECT` …) 지금은 종류와 무관하게 같은 두 박자다. 확정인지
  탭 전환인지는 화면이 말하는 것이고, 손에 오는 감촉이 화면마다 흔들리면
  그것이 도리어 잡음이었다. `OutgameTheme` 의 버튼 스타일 넷 · 밴픽 필터 칩 ·
  확정 버튼들에 있던 `kind()` 호출이 그때 전부 사라졌다.
- **기본값은 `down_kind` / `up_kind`**(`_ready` 에서 채운다 — `Haptics` 는
  오토로드라 `const` 초기화 시점에는 아직 없다).
- **종류는 누를 때 읽는다.** 그래서 `kind()` 를 `add_child` 앞에 부르든 뒤에
  부르든 같다. 자동 배선은 노드가 트리에 들어오는 순간 한 번만 걸린다
  (`haptic_bound` 메타 도장 — 떼었다 다시 붙이는 노드가 두 번 물려 한 번
  눌러 두 번 울리는 것을 막는다).
- **`mute()` 는 두 박자를 다 끈다.** 두 번 눌러야 지워지는 삭제 버튼처럼 같은
  누름에 대해 다른 자리가 이미 내고 있을 때다(`save_load/SlotCard`).
- **`button_down` 에는 `Haptics.prepare()` 도 함께 붙는다**: 손가락이 닿는
  순간부터 손을 떼는 순간까지가 정확히 탭틱 엔진을 깨울 여유이고, 그 여유가
  **뭉툭한 닫음을 제때 오게 한다**.
- `enabled` 는 **이 층만** 끈다(`Haptics.enabled` 는 게임 전체).

#### 자동 배선이 닿지 않는 자리
`BaseButton` 이 아닌 것 — 카드 드래그, 전략 포인트 도넛(`_input`), 훈련 타일
드래그(집기 · 미리보기 · 놓기 세 박자), 정글 시작 초상화, 밴픽의 메크 칸
드래그, 그리고 **버튼과 무관한 사건**
(명중 · 처치 · 포탑 철거 · 교전 결과 · 오브젝트 획득 · 승패). 그 자리들은
`Haptics.play(...)` 를 직접 부른다 — 표는 루트 `CLAUDE.md` 의 "햅틱 (감촉)" 항목.

---

## Note
Do NOT add `class_name` to autoload scripts in Godot 4.5 — causes parse errors in other scripts.
