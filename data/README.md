# data/ — CSV tables, game.db and the SQLite addon


## Detail moved from root CLAUDE.md

## Godot-SQLite Addon

**Addon**: `addons/godot-sqlite/` — GDNative SQLite3 wrapper for Godot 4.0+
**Platforms**: Windows, Linux, Mac, Android, iOS, HTML5

### Core API (class `SQLite`)
```gdscript
var db := SQLite.new()
db.path = "res://data/game.db"       # read-only (packaged)
db.path = "user://data/game.db"      # read-write (runtime)
db.open_db()
db.close_db()
db.query("SELECT * FROM pilots")
db.query_with_bindings("SELECT * FROM pilots WHERE role = ?", [role_id])
db.create_table("pilots", { "id": {"data_type":"int","primary_key":true}, ... })
db.insert_row("pilots", {"id":1, "role":"Tank", "hp":200, "atk":8})
db.select_rows("pilots", "hp > 100", ["role","hp"])  # returns Array of Dicts
db.update_rows("pilots", "id = 1", {"hp": 210})
db.delete_rows("pilots", "id = 1")
```

### Data Types
`int` → INTEGER, `real` → REAL, `text`/`char(n)` → TEXT, `blob` → BLOB (PackedByteArray)

### Important Constraints
- Column/table **names cannot be bound** — interpolate them directly into query strings
- **No encryption** support
- Read-only DBs: package inside `.pck` at `res://`; Read-write DBs: copy to `user://` at runtime
- Foreign keys must be enabled **before** `open_db()`

### Import / Export
```gdscript
db.export_to_json("user://backup.json")
db.import_from_json("res://data/seed.json")
db.backup_to("user://save.db")
db.restore_from("user://save.db")
```

### CSV → DB Workflow Pattern
CSV files live in `data/csv/`. The conversion logic lives in
`addons/csv_to_db/csv_to_db.gd` (a plain `RefCounted`); `addons/csv_to_db/plugin.gd`
is a thin **EditorPlugin** that only registers the menu item
(**Project → Tools → Rebuild game.db**). It reads each CSV, validates required
columns + duplicate PKs, then writes `res://data/game.db` with
`create_table` + `insert_row`. Adding a new table = add a CSV under `data/csv/`
and add an entry to both `SCHEMAS` and `TABLE_DEFS` **in `csv_to_db.gd`**.

The logic sits outside the EditorPlugin because `EditorPlugin` cannot be
instantiated headlessly, so the DB can also be rebuilt from the CLI:
```gdscript
# a throwaway `extends SceneTree` script, run with --headless --script
func _initialize() -> void:
    var err: String = load("res://addons/csv_to_db/csv_to_db.gd").new().call("rebuild")
    if err != "": printerr(err)
    quit()
```

### Tables (current)
| Table | CSV | Read at | Purpose |
|---|---|---|---|
| `pilots` | `pilots.csv` | BattleSim startup | Per-role baseline stats (used as fallback when match_ctx is inactive) |
| `cards` | `cards.csv` | GameManager startup | **파일럿 카드 표 (43행) — 전부 `card_type = pilot`.** 예전의 "공용 메크 카드"(mech 행)는 없어졌고 메크 카드는 `mech_cards` 에만 산다. `scope` 는 **포지션 목록**이다 — `any` 단독 = 전부, `lane` 단독 = 탑/미드/원딜/서폿, 그 밖에는 `jungle`/`top`/`mid`/`carry`/`support` 를 `\|` 로 잇는다. `card_cat` 은 `\|` 로 여러 개를 다는 **분류**(growth/engage/ambush/attack/defense/utility/draw/jungle/lane, 지급 전용은 `-`)이고 `pilot_card_slots` 의 칸이 이 값으로 후보를 고른다. `pool` (1/0) — 0 이면 파일럿 카드 후보가 아니다(결투 · 전령 제압 · 용 보상 · 핫핸드 · 이동). `keyword` 는 `\|` 목록(`exhaust` / `preserve` / `volatile` / `charge` / **`reposition`** = 재배치, 손패 맨 왼쪽으로 이동) — **키워드는 설명문에 다시 적지 않는다**(설명판이 키워드 줄과 풀이를 따로 그린다). **`charge_max`** 컬럼이 더해졌다(충전 상한, 성장 가속 5). `excl_group` 은 지금 쓰는 카드가 없다. 설명문의 용어: **손**(← 손패 · 핸드) · **소지 중**(← 손에 있는 동안) · **찾기**(← 탐색) · **버린 더미**(← 묘지) · **뽑기**(← 드로우) · **턴**(← 라운드) · **토큰**(충전으로 채워지는 것) · **작전 단계** · **교전**. 표기 규칙은 `features/battle_sim/card_phase/README.md` 의 "설명문 표기" 절, 카드 목록과 이름 변경 이력은 같은 README 의 cards.csv 컬럼 절. |
| `game_config` | `game_config.csv` | BattleSim startup | Tunable knobs (HP, turns, thresholds). `MAX_HAND_SIZE` 는 **10**, `BLUE_COST_HEAD_START`(1) 은 블루 진영이 선점하는 전략 포인트다. **`INITIAL_HAND_SIZE` 는 삭제됐다** — 개시 손패가 없어졌고 양 팀은 빈 손으로 시작한다. `ECONOMY_START_TURN`(**10**)은 전략 점수 회복 / 자동 드로우가 처음 도는 턴이다. **`GROWTH_PER_TURN` 은 삭제됐다** — 성장이 시간이 아니라 성장치에서 파생되면서 턴당 성장률이라는 개념이 사라졌다(위 "성장" 항목). 대신 `PILOT_STRUCTURE_DMG`(**2**) 가 들어왔다 — 파일럿이 포탑/HQ 에 한 번에 넣는 **고정** 피해이며 `atk` 와 무관하다. `BATTLE_PILOT_DMG_MULT`(**0.35**) 는 **전장 교전이 파일럿에게 넣는 피해**에만 곱해진다 — 포탑/HQ 피해·공격 카드·교전 무대는 제외. `TURRET_HP` 는 **24**(예전 16 에서 ×1.5), `HQ_MAX_HP` 는 **40** — 고정 피해 2 에 맞춰 잡은 값이라 셋을 따로 만지면 공성 속도가 어긋난다(무방비 포탑 12턴). 포탑 한 기의 성장치 값어치(`SCORE_TURRET_FULL` 1.0k)는 그대로이므로 한 점당 값만 0.0625k → 0.042k 로 내려갔다. `TURRET_SPEED` 는 **삭제됐다** — 교전이 라운드 턴제가 되면서 가담 포탑도 라운드마다 한 번 쏘므로 속도 개념이 없다. 복귀는 이제 즉시 만피 + 1턴 대기라 회복/대기 관련 키가 없다 — `RECALL_HEAL_RATIO` 와 `RECALL_RETURN_TURNS` 둘 다 제거됐다. 오브젝트 노브 여덟 개(`OBJ_HERALD_FIRST_TURN` **35** / `OBJ_DRAGON_FIRST_TURN` **25** — 용이 먼저다 / `OBJ_RESPAWN_TURNS` **20** / `OBJ_RETRY_TURNS` **15** / `OBJ_ENGAGE_ROUNDS` 4 / `OBJ_HERALD_TURRET_DMG` 8 / `OBJ_DRAGON_CARD_COUNT` **3** / `OBJ_DRAGON_GROWTH_PCT` **5** — 예전 5장 × 10%p 에서 내려왔다. 용은 세 번 넘게 열리므로 옛 값은 후반 성장치 곡선을 통째로 지배했다)는 `objective/README.md` 참조. |
| `lane_config` | `lane_config.csv` | BattleSim startup | LANE_NAMES, LANE_MAX, midpoints |
| `pilot_skills` | `pilot_skills.csv` | GameManager startup | **파일럿 스킬 25행** — 역할당 5개. `key` 가 런타임 분기 키(`PilotSkillSystem.KEY_*` 와 1:1), `type` 이 `cooldown`/`charge`/`passive`, `p1` 이 쿨타임 턴 수 또는 활성화 충전 비용, `p2` 가 최대 충전. 배율(몇 %인가)은 CSV 가 아니라 `PilotSkillSystem` 의 상수다 — 스킬마다 의미가 다른 숫자 칸을 대여섯 개 만들지 않기 위해서다. `description` 은 카드처럼 줄바꿈을 두 글자 `\n` 으로, 카드 이름을 `[카드명]` 으로 쓰고 조사는 꼬리표(`{eul}` 을/를 · `{eun}` · `{i}` · `{wa}`)로 둔다 — `StrategyIcon.resolve_josa` 가 푼다. 자세한 목록과 표기 규칙은 `features/battle_sim/skill/README.md`. |
| `players` | `players.csv` | Season + MatchFlow startup | 40 pilots (8 teams × 5 roles), `PlayerData` fields. **스탯 컬럼은 여섯이다** — `field_hit` / `field_eva` / `engage_hit` / `engage_eva` / `atk_growth` / `hp_growth`(위 "선수 스탯" 항목). 예전 다섯(`laning`/`mechanics`/`gamesense`/`teamfight`/`mental`)은 삭제됐다. **서포터(role 3)는 `field_eva` 쪽, 원딜(role 4)은 `field_hit` 쪽으로 치우쳐 있다**(둘 다 합계는 그대로 두고 ±10 씩 옮겼다) — 바텀 결속 묶음이 전장 명중 / 회피를 평균으로 공유하므로(`combat/README.md` "Lane bond") 함께 서면 솔로 라이너처럼 균형이 잡히고, 한쪽이 빠지면 남은 쪽의 치우침이 드러난다. `intl_players` 도 같다. **`skill_id`** 가 `pilot_skills.id` 를 가리키고(-1 = 없음), **`is_mob`** 이 실루엣 초상화 · 스킬 없음 · 드래프트 제외를 한꺼번에 뜻한다 — 네임드 25명은 8팀에 고르게 흩어져 있고(팀 0 이 5명, 나머지 20명이 7팀에 2~3명씩) 모브 15명의 스탯은 CSV 값 자체가 이미 10% 낮다. Player drafts 5 from this pool in Season. **`name` 은 그 id 의 초상화에 묶여 있다** — pilot id `N` 이 쓰는 `resources/images/pilot/*/N+1_*.png` 가 어떤 젠레스 존 제로 에이전트인지가 곧 이름이다(40장 전부 공식 아이콘 아트와 대조). 행 순서·id 를 바꾸면 이름과 얼굴이 어긋난다 — 자세한 규칙과 대체 코스튬 4건은 `resources/README.md` 의 `PilotImages.gd` 절. **`pilot_cards`** 컬럼이 더해졌다 — 이 선수의 **고정 파일럿 카드 3장**(`cards.id` 를 `\|` 로 이은 것). 지금 값은 `pilot_card_slots` 로 한 번 굴려 채운 것이고, 칸을 비우면 `GameManager.pilot_card_ids_for` 가 선수 id 를 씨앗 삼아 결정적으로 뽑는다. 포지션이 막는 id 나 없는 id 는 빠지고 모자란 칸이 씨앗 뽑기로 채워진다. |
| `mechs` | `mechs.csv` | MatchFlow startup | **21 mech pool** (원딜 5 · 전사 4 · 탱커 3 · 지원 5 · 암살 4). 예전 30대에서 9대를 지웠고 **살아남은 id 는 그대로 두었다** — `resources/images/mech/{id}_full.png` 가 id 에 묶여 있어 번호를 다시 매기면 그림과 스탯이 통째로 어긋나므로, id 에 구멍이 있다(3·4·5 / 10·11 / 16·17 / 23 / 29 가 빠진 자리). **`role` 컬럼이 생겼다**(GameEnums.Role) — 메크마다 고유 카드 셋이 붙으면서 그 카드들이 역할군을 전제하게 됐기 때문이며, 배정이 어느 슬롯에 어느 기체를 앉힐지는 여전히 막지 않는다. Barrage(id 27)만 공격력이 25 → **12** 로 내려갔다(전탄 발사 패시브의 대가). Drives PilotData stats when picked. **`id` 는 전신 아트에 묶여 있다** — `resources/images/mech/{id}_full.png` 가 그 id 의 스탯 아키타입(탱커 0–5 / 격투 6–11 / 암살 12–17 / 서포터 18–23 / 스나이퍼 24–29)에 맞춰 배치돼 있으므로, 행 순서나 스탯 구간을 바꾸면 그림과 스탯이 어긋난다 — `resources/README.md` 의 대응표 참조. `name` 은 아트와 무관한 자체 명명이고 **21대가 전부 고유한 영단어 코드명**이다(Juggernaut · Overdrive · Barrage …) — 예전의 `계열-A1` / `-A2` 식 접미사 이름(Bulwark-A1 / Bulwark-A2 처럼 같은 계열이 번호만 다른 것)은 바꿨다. 이름은 런타임 키가 아니라 표시값이라(짝은 언제나 `id`) 세이브 호환에 영향이 없다. `presence`(타겟 어그로)는 **교전 무대 전용** — 전장은 읽지 않는다. **`speed` 컬럼은 삭제됐다** — 교전이 라운드 턴제가 되면서 행동 빈도 개념이 사라졌고, `csv_to_db.gd` 스키마와 `GameManager` 로더에서도 함께 빠졌다. |
| `mech_passives` | `mech_passives.csv` | GameManager startup | **메크 패시브 15행** — 21대 중 15대만 갖는다. `mech_id` 가 짝이고 `key` 가 런타임 분기 키(`MechSkillSystem.KEY_*` 와 1:1), `p1`/`p2` 는 패시브마다 뜻이 다른 두 숫자(시작 충전 · 최대 충전 · 취약 수치 · 피해 비율). 배율(몇 %인가)은 CSV 가 아니라 `MechSkillSystem` 의 상수다 — 파일럿 스킬과 같은 이유. |
| `mech_cards` | `mech_cards.csv` | GameManager startup | **메크 카드 64행** — 파일럿이 받는 "메크 카드 3장"을 통째로 대체한다. `count` 가 채용 시 덱에 들어가는 장수이고 **`count = 0` 인 여섯 장**(승전보 · 철거 · 처형 · 락온 · 고통과 쾌감 · 단계 B/C)은 패시브나 다른 카드가 만들어 줄 때만 세상에 나온다(그래도 배분 표에는 적는다 — 상세 패널의 메크 탭이 기체를 반만 보여 주지 않게). **`cost = -1` 은 사용 불가**를 뜻한다. `keyword` 에 **`charge`** 가, 컬럼에 **`charge_max`**(충전 상한, 충전 카드가 아니면 0)가 더해졌고, `target` 에 셋이 더해졌다 — `foe`(적 파일럿 **또는** 포탑 → 대상 지정은 **칸**을 고르게 하고 그 칸의 무엇을 때리는지는 공격 절이 정한다. 포탑에는 초상화가 없어 PILOT 오버레이를 쓸 수 없다) / `turret_outer` / `turret_any`. `effect` 의 engage 절에는 **`|drop_in`** 이 더해졌다 — 시전자가 지정한 대상의 칸으로 이동해 교전에 참가하고(선공권), 무대에서는 적 진형 한가운데에 낙하한다([강습] id 30 하나가 쓴다). `trigger` 는 **그 카드**가 존재를 얻는 조건이라 패시브가 아니라 카드 쪽에 산다 — `turret_kill_deck`(꿰뚫는 번개) / `death_hand`(공격 명령 — 누가 쓰러질 때마다 그 카드를 손패에 한 장 만든다). 덱 슬롯 컬럼(card_type / card_cat / excl_group)과 시전자 제약(scope)이 없는 것은 메크 카드의 임자를 기체가 정하기 때문. **설명문은 키워드 머리말을 걷었다**("소멸." · "충전. 내 핸드에 들어올 때 충전 +1 (최대 3)." — 설명판이 키워드 줄과 풀이를 따로 그린다) — 그리고 충전으로 쌓이는 수는 **토큰**, 교전 길이는 **턴**, 뽑는 것은 **뽑기**로 적는다. |
| `training_tiles` | `training_tiles.csv` | GameManager startup | **일상 훈련판에 올리는 코스 타일 15행.** `shape` 는 `/` 로 줄을 나눈 색 문자열(**한 줄 = 하루, 한 글자 = 선수 한 명**), `exp` 는 `\|` 로 이은 `스탯:값`(`all` = 여섯 전부, **한 칸이 주는 값**), `effect` 는 `;` 로 이은 절(`mult:<scope>:<pct>` / `flat:<scope>:<stat>:<n>`). `id` 가 **텍스트 PK**(`T01` …)인 유일한 표다 — 등급 체인을 나중에 끼워 넣어도 번호가 밀리지 않게. **`description` 컬럼은 삭제됐다** — 그 문장은 `effect` 절을 사람이 손으로 옮겨 적은 것이라 절의 숫자를 고치면 설명만 조용히 거짓말이 됐다. 지금 정보 팝오버가 읽는 두 줄은 둘 다 데이터에서 만들어진다(`TrainingTile.exp_summary()` / `effect_summary()`, 후자는 `SCOPE_LABELS` 표 하나만 지난다). 색 표 · 스코프 표 · 등급별 배치 상한은 `features/season/training/README.md`. |
| `teams` | `teams.csv` | Season `init_season()` | 8 teams (id/name/short_name) → `season_state["team_meta"]`. Falls back to synthesized `Team N` rows if the table is missing. 팀명은 젠레스 존 제로 **진영(faction)** 에서 땄다 — 다만 **로스터는 진영과 맞지 않는다**(초상화가 진영을 섞어 뽑혀 있어서), 팀명은 순수한 간판이다. |
| `intl_teams` | `intl_teams.csv` | Season `init_season()` | 4 INTL teams (ids 100..103) → `season_state["intl_team_meta"]`. Synthesized fallback `Intl Alpha/Bravo/Charlie/Delta` rows when the table is missing. 국내 8팀이 쓰지 않은 진영 4개를 쓴다. |
| `intl_players` | `intl_players.csv` | Season `init_season()` | 20 INTL pilots (ids 100..119, 4 teams × 5 roles). 스탯 컬럼은 `players` 와 같은 여섯이다. → `season_state["intl_pilots"]`. Used by `MatchFlow._team_roster` and `InternationalTournament.simulate_ai_match` when `team_id >= 100`. **초상화가 없으므로**(`PilotImages.has_image` 는 id ≥ 100 에 false) 이름은 `players.csv` 40명이 쓰고 남은 에이전트 중에서 자유롭게 붙였다. `pilot_cards` 컬럼은 `players` 와 같은 뜻이다. |
| `pilot_card_slots` | `pilot_card_slots.csv` | GameManager startup | **포지션별 파일럿 카드 슬롯 3칸.** `position`(top/jungle/mid/carry/support) + `slot1..3`, 각 칸은 `cards.card_cat` 분류의 `\|` 목록이다 — 그 칸은 분류가 하나라도 겹치고 `scope` 가 그 포지션을 허락하는 `pool = 1` 카드 중 하나로 채운다. `players.pilot_cards` 가 빈 선수(와 단독 실행 · 합성 INTL 선수)만 이 표로 뽑히므로, 표를 바꿔도 이미 채워진 선수의 카드는 그대로다 — 다시 굴리려면 그 선수의 `pilot_cards` 칸을 비운다. 지금은 세 칸이 같은 목록이다(정글 = 성장/교전/매복/유틸리티/뽑기/정글). |

At runtime, `GameManager` and BattleSim's `DataLoader` open the DB once, load
tables into Dictionaries / Arrays keyed by ID, then close the DB. All in-game
access goes through those structures — not live DB queries.
