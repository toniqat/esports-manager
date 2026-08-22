# Rendering Module

## BattleRenderer.gd
`extends Node2D` — child of BattleSim at position (0,0).

Owns all `_draw()` logic. BattleSim calls `renderer.queue_redraw()` whenever state changes.
Reads all state from `_bs` (the BattleSim parent).

### Draw pipeline (called from `_draw()`)
0. `_draw_front_line_overlays()` + `_draw_captured_tile_overlays()` +
   `_draw_jungle_camps()` — **성장치 수입이 나오는 자리**를 타일 위에 얹는다.
   전선은 얇은 금색 **테두리**(레인마다 양 팀의 살아 있는 최전방 포탑 사이;
   `SimulationCore.front_line_cells`), 캠프는 칸 한가운데의 작은 초록 **마름모**.
   수입이 위치에서 나오는데 그 위치가 안 보이면 왜 뒤처지는지 알 수 없으므로
   그린다. 정글 점령 타일이 이미 면을 칠하고 있어 전선은 테두리로만 표시해
   색이 경쟁하지 않게 하고, 캠프 판정은 시뮬레이터와 **같은 함수**
   (`camp_harvestable(cell, team)` / `camp_charged(cell)`)를 지나므로 보이는
   캠프와 먹히는 캠프가 어긋날 수 없다. 팀 인자는 `_bs.blue_team`.
   **캠프는 두 가지로 갈라 그린다**: 우리가 지금 먹을 수 있으면 **꽉 찬** 초록
   마름모, 적 소유 칸에 차 있으면 같은 자리 · 같은 크기의 **속 빈** 마름모
   (`CAMP_MARK_ENEMY_COLOR`, 외곽선만). 채움 여부가 "우리 것 / 적 것"을 가르므로
   둘을 헷갈릴 여지가 없고, 적 정글을 **지금 뺏을 값어치가 있는지**가 화면에
   있어야 정글 점령이 판단의 대상이 된다.
1. `_draw_hq_hp_bars()` — green HP bar under each HQ once any T2 in their team is destroyed
2. `_draw_turret_hp_bars()` — yellow HP bar above each living turret (T2 hidden while own-lane T1 alive). 피격 중에는 `BattleSim.turret_hit_offset(td)` 만큼 함께 흔들린다 — 포탑 스프라이트(`Building` 노드)는 렌더러가 그리지 않고 BattleSim 이 직접 흔들므로, 바만 제자리에 두면 둘이 어긋난다.
3. Per-cell pilot rendering via `_draw_pilot_cell()` — pilots render OUTSIDE the tile, on a hex ring of 6 slots around it, with a team-coloured triangle behind them whose apex points to the tile centre (speech-bubble tail). **자리는 여기서 풀지 않는다** — `_draw()` 앞머리의 `_build_pilot_render_layout()` 이 전장 전체를 한 번에 배정하고, 딤 오버레이 · 히트 테스트 · 돌진 기하가 같은 표를 읽는다
4. `_draw_cell_badge()` — `NvN` / `xN` count badge centred ON the tile (the tile centre is now empty, since pilots are offset outward)
5. `_draw_pilot_popups()` — 공격 카드의 피해 수치 / MISS 플로팅 텍스트, **맨 마지막**에 그려 무엇에도 가려지지 않는다

The minion / lane-line / minion-progress visualizations were removed alongside
the minion concept. Tile background colouring (lane vs jungle vs neutral) is
owned by the TileMapLayer in `BattleField.tscn`, not by the renderer.

### 초상화가 앉는 자리 — 타일을 둘러싼 육각 6슬롯
`_build_pilot_render_layout()` 이 **전장 전체를 한 번에** 배정한다. 자리는
타일 중심에서 6방향(`HEX_DIRS` = 육각 이웃과 같은 방향, 배열 순서가 화면 기준
**시계방향** N→NE→SE→S→SW→NW)으로 뻗은 링 위이고, 반지름은 `_ring_radius()`:

```
ring_radius(ring) = (지름 + MARKER_GAP) × (ring + 1)      # 91px, 182px, 273px
```

**이웃 슬롯이 60° 간격이므로 반지름 d 인 링에서 이웃 슬롯 사이 거리는 정확히
d 다** — 그래서 지름 + 여백을 그대로 반지름으로 쓰면 한 링 안의 초상화가 절대
닿지 않고, 바깥 링은 그 배수라 반지름 방향으로도 같은 간격이 확보된다.
`SLOT_RINGS`(3) = 18자리라 5v5 전원이 한 칸에 몰려도(10명) 남는다.

배정은 파일럿마다:
1. **기본 방향**을 잡는다 — 아래 *기본 방향* 절. 이동 방향의 정반대다.
2. 거기서 **시계방향으로** 돌며 (a) 같은 칸에서 아직 안 쓴 자리이고
   (b) **이미 놓인 어떤 마커와도 겹치지 않는** 첫 자리를 잡는다(`_pick_slot`).
3. 안쪽 링 6자리를 다 돌면 그대로 **바깥 링**으로 나간다. 그만큼 타일에서
   멀어지고 화살표가 길어져, 붐비는 칸일수록 "어느 타일인지"를 화살표가 말한다.

(b)가 **다른 칸의 마커까지 본다**는 것이 요점이다. 이웃 타일 중심은 140px 밖에
안 떨어져 있는데 초상화 지름이 85px 라, 위아래로 붙은 두 칸이 서로를 향한
슬롯(위 칸의 S, 아래 칸의 N)을 고르면 두 얼굴이 그 사이에서 정면으로 겹친다 —
레인이 맞붙는 순간마다 벌어지던, 전장에서 얼굴이 가려지는 유일한 구조적
원인이었다. 지금은 뒤에 오는 칸이 시계방향으로 한 칸 비껴 앉는다.

순회 순서가 곧 우선순위(먼저 도는 칸이 자기 기본 방향을 지킨다)이므로 셀은
**좌표로 정렬**하고(`_compare_cells`), 한 칸 안에서는 `_bs.pilots` 순서(스폰
순서)를 쓴다 — Dictionary 순서에 맡기면 같은 상황에서 프레임마다 다른 칸이
양보해 배치가 떨린다.

**한 칸의 6슬롯은 양 팀이 공유한다.** `_group_pilots_by_render_cell()` 이
두 팀을 한 배열에 담는 이유다 — 예전에는 "적은 타일 위 / 아군은 타일 아래" 라
팀마다 따로 풀어도 부딪힐 일이 없었지만, 지금은 방향이 각자의 이동 방향에서
나오므로 같은 칸의 두 팀이 같은 슬롯을 노릴 수 있다.

**`+N` 오버플로 원은 삭제됐다.** 렌더 가능한 파일럿은 전원이 자기 슬롯을 받고,
7명째부터는 바깥 링에 앉는다(`_draw_overflow_circle` 과 함께 제거).

**No solo exception**: a pilot alone in a cell is laid out exactly like a
stacked one — offset outward with the speech-bubble arrow pointing back at the
tile. The arrow is therefore always present, so the tile a pilot occupies reads
the same whether the cell is contested or not. (The earlier `is_solo` centring +
`_has_crowded_neighbor` override were removed.)

#### 기본 방향 — 이동 방향의 정반대
파일럿은 **자기가 가려는 쪽을 비워 두고 지나온 쪽에 선다**
(`pilot_display_dir_index`). 오른쪽 레인을 NE 로 밀고 올라가는 팀0 은 타일
왼쪽 아래(SW)에, 같은 구간을 반대로 내려오는 팀1 은 오른쪽 위(NE)에 앉는다.
미드는 위/아래라 예전 규칙(적 위 / 아군 아래)과 그림이 같고, 왼쪽 레인은
오른쪽 레인의 좌우 반전이 계산에서 저절로 나온다.

| 이동 | 표시 |
|---|---|
| N | S |
| NE | SW |
| SE | NW |
| S | N |
| SW | NE |
| NW | SE |

방향의 출처는 둘로 갈린다(`_pilot_travel_dir`):

- **레인 파일럿 — 레인 경로.** 지금 칸에서 다음 웨이포인트를 향하는 방향을
  6방향으로 스냅한다. 교전으로 멈춰 서 있거나 한 턴 밀려나도 표시가 뒤집히지
  않고, 같은 레인 같은 구간의 팀원이 늘 같은 쪽으로 정렬된다. 웨이포인트 조회는
  `_peek_waypoint` — `SimulationCore.current_waypoint` 의 **부작용 없는** 사본
  이다(원본은 `waypoint_idx` 를 밀어 올린다. 그리기 중에 시뮬 상태를 건드리면
  화면이 게임을 바꾸는 셈이 된다).
- **정글러 — `PilotData.prev_grid_pos`.** 정글에는 경로가 없고 로밍 목적지는
  수시로 바뀌므로 지나온 자취가 유일하게 안정적인 신호다. 왼쪽 위(NW)로
  움직였으면 오른쪽 아래(SE)에, 오른쪽 위(NE)로 움직였으면 왼쪽 아래(SW)에 선다.
Each pilot draws its own arrow (`_draw_arrow_to_tile`) — the tip is the
**glide-interpolated tile centre** (`_marker_center`), so the tail slides with
the portrait instead of pointing at the destination first (다음 절).

둘 다 답이 없으면(개시 직후, 아직 한 칸도 안 움직인 정글러) **적 HQ 쪽**을
보고, 적 HQ 칸 위에 서 있으면 팀의 진행 방향(팀0 = N)을 그대로 쓴다.
### 마커 글라이드 — 초상화는 순간이동하지 않는다
**화면 위의 마커 좌표 하나가 통째로 보간된다.** 예전에는 칸 이동만 트윈하고
(`PilotData.anim_move_t/dur`, 셀 중심끼리의 lerp) **슬롯 변화는 즉시 반영**했다.
슬롯 하나가 91px, 반대편으로 옮겨 앉으면 182px 라 **칸 사이 거리(140px)보다 큰
순간이동**이 매 턴 섞여 들어왔고, 옆 사람이 와서 비켜 앉기만 하는 파일럿은 아예
트윈이 걸리지 않아 그냥 튀었다.

지금은 마커 좌표를 **중심 + 슬롯 벡터**로 갈라 놓고 둘을 따로 민다
(`_sync_glide` → `_eval_glide`, 상태는 `_glide` dict):

| 성분 | 무엇 | 언제 |
|---|---|---|
| `center` | 지나간 칸 중심을 이은 **폴리라인**을 호 길이 비율로 훑는다 | `BattleSim.ANIM_MOVE_DUR` (0.30초), smoothstep |
| `vec` 의 **각도** | 슬롯 방향. 짧은 쪽으로 돈다 | 위와 **같은 박자** |
| `vec` 의 **길이** | 링(반지름) | **도착한 뒤** `MARKER_RADIUS_SETTLE_SEC` (0.15초), ease-out cubic |

- **경로를 따라 꺾인다.** `PilotData.anim_move_path` 가 이번에 실제로 밟은 칸을
  들고 온다(`SimulationCore.resolve_movement` 이 락스텝 라운드마다 붙이고, 전진
  카드는 `anim_pilot_move` 가 같은 프레임의 걸음을 이어 붙인다). 그래서
  `move_range` 2 짜리 이동과 `advance:3` 이 중간 칸을 스쳐 지나가지 않는다 —
  실측: 3칸 경로의 중점이 직선 중점에서 **121.5px** 벗어난다. 렌더러는 경로를
  읽는 즉시 **비운다**(`_screen_path`); 그래야 다음 턴 이동이 옛 출발점으로
  되감기지 않는다.
- **각도가 중심과 같은 박자로 도는 것이 곧 "화살표가 칸 이동과 동시에 돈다"**
  이다. 링이 그대로면 길이 보간이 항등이라 화살표 길이가 이동 내내 한 픽셀도
  변하지 않고 꼬리가 초상에 매달려 통째로 미끄러진다. 붐비는 칸에 들어가느라
  **바깥 링으로 밀려날 때만** 도착 후에 늘어난다 — 이동 중에 길이까지 변하면
  무엇이 움직였는지가 흐려진다.
- **곡선은 smoothstep** — 양 끝에서 정지한다. 예전 이동 트윈의 ease-out cubic 은
  슬롯이 어차피 튀던 시절의 선택이라 출발이 급해도 티가 덜 났는데, 그 곡선은
  60fps 첫 프레임에 이미 거리의 15%(실측 **24.98px**)를 지나간다 — 순간이동을
  없애려는 연출이 출발할 때마다 한 번 튀는 셈이었다. smoothstep 으로 바꾼 뒤
  첫 프레임 변위는 **0.5~0.7px**, 한 번의 이동이 40프레임에 걸쳐 흐른다.
- **순간이동이 맞는 경우는 스냅한다** — 복귀 / 부활(`anim_recall_phase != 0`)은
  페이드가 자리 이동을 덮고, 전사(`anim_death_phase != 0`)는 시신이 쓰러진 칸에
  붙박여 있어야 한다. 미끄러뜨리면 사라지는 몸이 화면을 가로지른다.
- 레이아웃에서 빠진 파일럿(사망 퇴장, 재시작으로 갈린 로스터)의 상태는
  `_sync_glide` 가 버린다.

시간을 미는 것은 `_process` 의 `_advance_glide` **하나뿐**이다. 그래서
`_build_pilot_render_layout()` 을 한 프레임에 몇 번 불러도(그리기 · 히트 테스트 ·
돌진 기하 · 팝업) 연출이 되감기지 않는다. `BattleSim` 은 이동 타이머를 더 이상
들고 있지 않으므로 이 구간의 재draw 도 렌더러가 걷어찬다.

**삭제된 것 — 화살표 관성 장치.** `_arrow_hold` / `_arrow_settle_t` /
`_arrow_vec_now` / `_arrow_frozen` / `_arrow_aim_point` / `_advance_arrow_settle` /
`_prune_arrow_state` / `_lerp_polar` / `ARROW_SETTLE_SEC` 는 전부 사라졌다. 그것은
"초상은 출발 칸에 있는데 꼬리만 도착 칸을 가리킨다"를 가리려고 이동 중 꼬리를
얼려 두던 장치인데, 지금은 초상이 실제로 미끄러지므로 꼬리가 그냥 따라가면 된다.

#### 화살표 길이는 거리에서 역산한다
`_draw_arrow_to_tile` 의 끝점은 **언제나 타일 중심 바로 앞**
(`dist - tip_inset`)이다. 예전에는 마커 반지름에서 뽑았는데(반지름 + 24px),
바깥 링에 앉는 마커는 타일에서 두 배로 멀어져 그 길이로는 허공에 짧은 삼각형만
남고 어느 칸 이야기인지가 사라진다. 거리에서 역산하면 멀어진 만큼 화살표가
길어져 "약간 멀어져 앉되 가리키는 칸은 분명하다"가 성립한다. 중심을 찔러
넘어가지는 않는다 — 넘어가면 옆 칸을 가리키는 것처럼 읽힌다.

#### 대상 지정 강조는 배치도 탄다 (`em`)
`_compose_positions` 는 **그 칸의 강조 배율**(`_group_emphasis` = 그 칸에
선 양 팀 전원 중 최대 `_pilot_emphasis_scale`, 즉 1.0 또는
`TARGET_EMPHASIS_SCALE` **1.5**)을 링 반지름에 곱한다. 초상만 키우면 두 가지가
동시에 무너지기 때문이다:

1. **좌우로 겹친다.** 간격은 그대로인데 지름만 커지면 한 칸에 선 두세 명의
   얼굴이 서로를 덮어, 정작 겨눠야 할 순간에 누가 누구인지 읽을 수 없다.
2. **화살표가 사라진다.** 마커가 커지면 초상이 타일 중심까지 삼켜서 화살표가
   초상 뒤에 완전히 깔린다 — 하필 강조된(=지금 겨누는) 파일럿에서만.

링 반지름이 통째로 `em` 배가 되므로 **간격과 거리가 한 번에 같이 벌어진다** —
링 정의(`지름 + 여백`)가 곧 비겹침 조건이라 `em` 을 곱해도 그 조건이 그대로
유지되고(85.05 × 1.5 = 127.6 필요 vs 91 × 1.5 = 136.5 확보), 무리가 바깥으로
물러난 만큼이 곧 화살표가 길어질 자리다. 화살표 끝은 어차피 거리에서 역산하므로
(위 절) 따로 배율을 태울 것이 없다.

**슬롯 배정 자체는 `em` 을 보지 않는다.** 겹침 판정은 강조 이전 좌표로 돌리고,
`em` 은 배정이 끝난 뒤 반지름에만 곱한다 — 강조까지 반영하면 카드를 집을 때마다
전장의 슬롯이 새로 풀려 배치가 통째로 다시 섞인 것처럼 보인다.

**글라이드도 `em` 을 보지 않는다.** 보간되는 것은 강조 이전의 중심 + 슬롯
벡터이고, `em` 은 그 위에 매 프레임 곱해진다 — 그래서 강조가 `EMPHASIS_TWEEN_SEC`
(0.05초)에 다 자라는 동안 0.30초짜리 글라이드가 끼어들어 굼떠지지 않는다.
곱하는 축은 타일 중심이 아니라 **글라이드 중심**이다: 칸을 건너는 중인 파일럿을
도착 타일 기준으로 부풀리면 아직 도착하지도 않은 지점을 축으로 튕겨 나간다.

**화면 밖으로 나가면 칸째 밀어 넣는다** (`_clamp_group_on_screen`, 한 칸의 양 팀
전원이 한 무리다). 강조로 벌어진 가장자리 레인의 2~3인 무리는 그냥 두면 화면 밖으로 잘리는데, 잘린 얼굴은
누를 수도 놓을 수도 없다. 마커를 하나씩 따로 밀면 애써 벌린 간격이 도로 무너져
다시 겹치므로 **평행 이동**이다. 화살표는 여전히 각자 자기 타일을 가리키므로
누가 어느 칸인지도 유지된다. 실측(1080×1920, `SCREEN_EDGE_PAD` 6, 배율이 2.0
이던 시절): 타일 중심 x=950 의 3인 무리가 `em=2` 에서 자연 폭 617..1283 →
**495.6..1074** 로 접히고, x=120 의 무리는 왼쪽 가장자리 6px 에 붙는다. 배율이
1.5 로 내려간 지금은 접히는 일 자체가 훨씬 드물다 — 이 절이 존재하는 이유의
절반이 그 접힘을 없애자는 것이었다.

Radius is FIXED per pilot (`PILOT_RADIUS_BASE = 31.5` × `HexGrid.DISPLAY_SCALE`
= 42.5px at draw time, so it tracks tile size) regardless of how many pilots
share the cell — circles do not shrink for multi-pilot stacks. 붐비는 칸이
감당하는 것은 크기가 아니라 **거리**다: 6명을 넘으면 바깥 링으로 나가고, 그만큼
화살표가 길어진다. HQ HP bars and cell badges are also scaled by
`HexGrid.DISPLAY_SCALE` to stay proportional to the bigger tiles.

(`PILOT_FONT_SIZE_BASE` 는 슬롯 안에 역할 글자를 찍던 시절의 잔재라 초상화가
슬롯을 통째로 채우게 되면서 **삭제됐다**.)

HP is shown as a circular progress ring hugging the outside of every pilot's
circle (radius + 3 px, 4 px wide). The dark backing ring traces the full
circumference; the green fill ring sweeps clockwise from the top
(`-PI/2`) by `hp / max_hp`. Because each ring sits on its owner's circle, the
old "solo only" gate is gone — every drawn pilot has its own HP ring. The
guerrilla dash ring is pushed out to radius + 9 px so it stays clear of the HP
ring.

### Coordinate helpers
All drawing uses `_bs.cell_center(pos)` which dispatches to `hex_grid.hex_to_screen()`.

### Pilot animation rendering
`BattleSim` mutates per-pilot animation timers on `PilotData`
(`anim_move_*`, `anim_shake_*`, `anim_recall_*`); the renderer just reads
them each `_draw()`:

- **`_is_renderable(p)`** — the grouping gate. A pilot is drawn while `alive`
  **or** while an off-field animation is still playing: the 전사 연출
  (`anim_death_phase != 0`) and the fade-out half of a 저HP 귀환
  (`anim_recall_phase == 1`). This is deliberately not a plain `p.alive` test —
  both states flip `alive` to false *before* their animation runs, and the old
  gate made a killed pilot vanish on the same frame the damage landed.
- `_render_cell(p)` — returns `anim_recall_orig` while a pilot is in recall
  fade-out, `anim_death_cell` while the 전사 연출 plays, otherwise `grid_pos`.
  Pilots are grouped/team-laid-out by this so a recalling pilot is drawn at the
  cell they came from until they fully fade out, then "appears" at HQ for the
  descent fade-in, and a fallen pilot stays on the cell they fell on.
- `_pilot_anim_offset(p)` — sums recall rise/descend (`ANIM_RECALL_RISE_PX`),
  death rise (`ANIM_DEATH_RISE_PX`, phase 2 only), **공격 카드 돌진**
  (`BattleSim.pilot_lunge_offset`) and damage shake (decaying `sin` jitter).
  **칸 이동은 여기 없다** — 마커 좌표 자체가 글라이드로 미끄러지므로(위
  *마커 글라이드* 절) 여기서 한 번 더 얹으면 두 벌이 된다.
- **피격 흔들림의 세기는 흔든 쪽이 정한다** — `PilotData.anim_shake_amp` 에
  실려 온다(전장 자동 교전 `ANIM_SHAKE_AMP_PX` **6px** / 공격 카드 명중
  `ANIM_SHAKE_CARD_AMP_PX` **20px**). 렌더러가 상수 하나를 읽던 시절에는 둘 중
  하나만 맞출 수 있었다. **주파수는 고정이고 진동 수가 지속시간을 따라간다**
  (`cycles = 4 × dur / ANIM_SHAKE_DUR`) — 진동 수를 4회로 고정하면 길게 흔들라는
  지시가 "느리게 흔들라"가 되어 격렬함이 오히려 사라진다. 실측: 전장 6px 기준
  최대 5.63px · 4주기, 카드 20px 기준 최대 19.13px · 5.8주기.
- `_pilot_anim_alpha(p)` — 1.0 → 0 during recall phase 1 **and** death phase 2,
  0 → 1.0 during recall phase 2 (and respawn fade-in). Multiplied into every
  per-pilot draw call (circle, ring, role text, HP ring, speech-bubble arrow)
  via `_alpha_mul`.
- **Death tint** — while `anim_death_phase != 0` the team colour and the
  portrait are both multiplied by `BattleSim.ANIM_DEATH_TINT`, so the fallen
  pilot reads as dimmed rather than merely faded. Phase 1 holds at full alpha
  (딤드된 채 대기), phase 2 fades it out while it rises.

The cell badge (`NvN` / `xN`) is drawn at full
alpha — it's an aggregate visual, not per-pilot. Note that a pilot mid-death
still occupies a layout slot, so a fallen body shifts the living pilots in its
cell for the ~1.45s the animation runs; `pilot_marker_positions()` reads the
same solve, so hit-testing never disagrees with what is on screen.

**초상 뒤에는 흰 원이 깔린다** (`_draw_pilot_circle`). `*_circle.png` 는 원
안쪽까지 투명한 것이 섞여 있어(실측: 40장 중 일부는 원 내부에도 알파 구멍이
있다) 그냥 그리면 뒤의 타일 색이 얼굴을 뚫고 비친다 — 점령된 정글 타일 위에서는
파일럿이 타일과 같은 색으로 물들었다. 원 그림 자체가 정사각형에 **내접**해 있어
같은 반지름의 `draw_circle` 이 정확히 맞고, 1px 줄여 안티에일리어싱된 가장자리
바깥으로 흰 테가 삐져나오지 않게 한다. 색은 초상과 **같은** tint·alpha 를
타므로(사망 딤 / 복귀 페이드) 배경만 밝게 남는 일이 없다.

**돌진 중인 파일럿의 칸은 맨 마지막에 그린다** (`_lunging_cells_last`). 돌진은
대상 초상과 절반쯤 겹치는 것이 연출의 전부인데, 셀 순회가 `Dictionary` 순서라
대상 칸이 나중에 그려지면 파고든 얼굴이 그 뒤로 숨는다. 돌진이 없으면 순회
배열을 그대로 돌려주므로 평소 그림은 달라지지 않는다.

### 피해 수치 팝업 (`spawn_pilot_popup`)
공격 카드(`attack:N`) 전용 플로팅 텍스트. `CardPhaseManager._effect_attack` 이
판정마다 한 번씩 호출한다 — 빗나가면 **MISS**, 명중하면 **-N**, 보호막이 전부
흡수했으면 **흡수**. 색은 `POPUP_MISS_COLOR` / `POPUP_DAMAGE_COLOR` /
`POPUP_SHIELD_COLOR`.

- 좌표는 **띄운 순간의 마커 위치를 그대로 고정**한다. 대상이 그 사이에
  쓰러지거나 밀려나도 숫자가 따라다니지 않는다(그리고 대상이 사라진 뒤에도
  숫자가 끝까지 재생된다).
- `BattleSim.DMG_POPUP_DUR`(**0.30s**) 동안 `DMG_POPUP_RISE_PX`(46px) 만큼 감속하며
  떠오르고 마지막 40% 구간에서만 흐려진다. 이 값은 **한 타격의 돌진 연출 길이
  (0.32초)보다 짧아야 한다** — 길면 연속 공격의 숫자가 같은 자리에 겹쳐 쌓인다.
- **`DMG_POPUP_STAGGER`(0.18s)는 이제 거의 쓰이지 않는다.** 한 타격이
  파고들기 → 타격 → 복귀 세 박자(0.32초)를 다 도는 연출이 붙으면서 연속 공격의
  팝업이 애초에 서로 겹칠 수 없게 됐다. 지연이 남는 것은 연출이 붙지 않는
  경우(시전자가 없는 레거시 카드)뿐이다.
- `_advance_popups(delta)` 가 `_process` 에서 돌며 만료분을 버리고, 살아 있는
  동안 `queue_redraw()` 를 계속 건다. 재시작은 `clear_popups()`.

### Targeting dim + 강조 (놓을 수 있는 곳만 밝게)
**딤은 카드를 손에서 끌어내는 순간 올라간다.** 예전에는 모달 대상 지정이 열려야
(`is_active()`) 사거리 밖 타일이 어두워졌지만, 이제 드래그 자체가 대상
지정이므로 `_draw()` 의 `draw_dim` 조건은 `targeting_overlay.is_visualizing()`
하나뿐이다. `is_visualizing()` 은 PILOT / LOCATION / PREVIEW 에서만 참이라
사거리 개념이 없는 INSTANT 카드(드로우 / 전략 점수 등)를 들었을 때는 전장이
전혀 어두워지지 않는다.

**규칙은 하나다 — "이 카드를 놓을 수 있는 곳"만 밝다.** 카드를 끌어다 대상 위에
놓는 조작이 들어오면서, 딤은 "사거리를 보여 주는 장치"에서 "드롭 지점을 남기는
장치"로 바뀌었다. 칠하는 쪽(`_draw_targeting_underlays`)과 딤을 면제하는 쪽
(`_undimmed_cells`)이 서로의 거울이라 둘이 어긋날 수 없다:

| 모드 | 밝게 남는 것 | 칠 |
|---|---|---|
| PILOT | **파일럿 마커만** — 타일은 전부 딤 | 없음 |
| LOCATION | `valid_cells` | 초록 채움 + 외곽선 |
| PREVIEW | `area_cells` (시전자 셀 + 인접 6칸) | 노란 채움 + 외곽선 |
| INSTANT | 전부 (딤 자체가 없다) | 없음 |

파일럿 딤은 그대로 `should_dim_pilot` 이 가른다 — PILOT 은 유효 대상이 아닌
파일럿, LOCATION 은 전원, PREVIEW 는 비참여자. **단 시전자(`card_caster`)는
어느 모드에서도 딤드되지 않는다** — 딤은 "여기엔 놓을 수 없다"는 말인데 카드를
쏘는 당사자에게 그 말은 성립하지 않고, 특히 LOCATION 의 "파일럿 전원 딤" 규칙에
걸리면 지금 움직이려는 그 파일럿이 화면에서 가장 어두웠다. **대신 강조 대상도
아니다**: 커지는 것은 "놓을 수 있는 곳"이라는 신호이므로, 시전자는 자기가 그
카드의 유효 대상일 때(보호 / 복귀 같은 `target=ally` 카드)만 `valid_pilots` 를
통해 커진다.

사라진 것 둘: **PILOT 의 노란 사거리 채움**(어차피 그 타일에는 놓을 수 없으니
겨눌 곳을 가리는 노이즈였다)과 **`range_unlimited` 특례**(사거리 무제한 카드는
사거리 표시가 전장 전체라 아무것도 말해 주지 않았는데, 이제 유효 셀 기준으로
딤이 걸려 약탈 / 정글 파밍도 갈 수 있는 칸만 남는다). 오버레이의
`range_caster` / `range_radius` / `range_unlimited` 는 남아 있지만 렌더러는
더 이상 읽지 않는다.

### 파일럿 마커 위치 — `pilot_marker_positions()`
`_draw()` 는 매 프레임 `_build_pilot_render_layout()` 으로
`PilotData → Vector2` 마커 위치 표를 만들어 딤 오버레이와 공유한다. 그 함수는
세 걸음이다 — **자리를 푼다**(`_solve_slots`, 순수) → **글라이드를 맞춘다**
(`_sync_glide`) → **지금 프레임의 좌표를 낸다**(`_compose_positions`, 강조 배율과
화면 클램프를 얹는다). 시간은 여기서 흐르지 않으므로 한 프레임에 여러 번 불려도
답이 흔들리지 않는다. 같은 것을 그대로 돌려주는 **공개** 래퍼가
`pilot_marker_positions()` 이고, `CardTargetingOverlay._hit_test_pilot` 이
이걸 쓴다 — 한 셀에 여러 명이 서 있으면 각자 다른 슬롯에 그려지므로,
`grid_pos` 만 보고 계산하는 위치(타일 중심 / `pilot_marker_pos_solo`)로는
누구를 눌렀는지 구분할 수 없다(항상 맨 왼쪽 파일럿이 잡혔다). 게다가 슬롯은
전장 전체를 훑는 그리디로 정해지므로, **한 칸만 따로 풀어서는 같은 답이 나오지
않는다** — 이 표 하나가 유일한 답이다.

표에 없는 파일럿(레이아웃이 아직 한 번도 안 돌았거나 렌더 대상이 아닌 경우)의
폴백은 **`pilot_marker_pos_fallback(p)`** — 자기 칸에 혼자 선 것으로 치고 기본
방향의 첫 링에 앉힌다. `BattleSim.pilot_marker_pos_solo` 는 이제 이 함수로
그대로 넘긴다(예전에는 거기에 "적 위 / 아군 아래" 규칙이 한 벌 더 적혀 있었고,
방향 규칙이 바뀌면 두 답이 갈라졌다).

타겟 가능한 파일럿 마커는 `_pilot_emphasis_scale(p)` 가 돌려주는 배율만큼
커진다 — 목표값은 **`TARGET_EMPHASIS_SCALE`(1.5)** 이고, 거기에 **곧바로 튀지
않고 `EMPHASIS_TWEEN_SEC`(0.05초) 동안 자란다**(그리고 같은 칸의 무리가 겹치지
않도록 배치까지 함께 벌어진다 — 위 *대상 지정 강조는 배치도 탄다* 절).
강조 대상은 모드별로:
- **PILOT**: `valid_pilots` 의 모든 파일럿
- **PREVIEW**: `preview_participants`
- **`pending_pick` 도 예외가 아니다** — 시안 링이 그 위에 따로 붙어 구분되고,
  여기서만 1.0 으로 되돌리면 카드를 끌고 지나갈 때 얼굴이 커졌다 작아졌다
  한다. 시안 링의 반지름도 같은 배율을 타서 커진 마커 바깥에 걸린다.

그리는 반지름은 **`pilot_marker_radius(p)`** 한 곳에서만 나온다(공개 —
`CardTargetingOverlay._hit_test_pilot` 이 클릭 반경으로 쓰고, 시안 링과 딤 디스크도
같은 값을 읽는다). 강조된 초상(31.5 × 1.35 × 1.5 = **63.8px**)은 타일
반지름(`hex_size * 0.85` = 68.9px)에 가까우므로, 히트 테스트가 고정 상수로 재면
얼굴 바깥 테두리를 눌렀을 때 대상이 잡히지 않을 수 있다(배율이 2.0 이던 시절엔
85px 로 확실히 넘겼다). 단 "마커에 안 맞았지만 자기 타일 안"이라는 폴백은 강조와
무관하게 타일 크기 기준이다 — 커진 초상만큼 넓히면 옆 칸을 누른 클릭까지 빨려
들어간다.

#### 강조의 보간 (`EMPHASIS_TWEEN_SEC` 0.05초)
질문은 둘로 갈라져 있다:
- **`_pilot_emphasis_target(p)`** — 이 파일럿이 *지금* 찍을 수 있는 대상인가.
  1.0 아니면 `TARGET_EMPHASIS_SCALE`, 즉 계단 함수다.
- **`_pilot_emphasis_scale(p)`** — 지금 프레임에 실제로 쓰는 배율.
  `_emphasis_now` dict 에서 읽고, `_advance_emphasis(delta)` 가 매 프레임 목표값
  쪽으로 `move_toward` 로 민다(전 구간 0.05초 페이스 — 0.15초는 카드를 든 손이
  이미 대상 위에 가 있는데 얼굴이 아직 자라는 중인 구간을 남겼다). 목표에 닿으면 그 프레임에
  멈추고, 값이 1.0 으로 돌아온 항목은 dict 에서 지운다 — 기본값이 1.0 이라
  남겨 둘 이유가 없고, 매 판 새 `PilotData` 가 들어오는 자리에 죽은 키가 쌓이지
  않는다.

**그리기 · 배치 · 히트 반경이 전부 `_pilot_emphasis_scale` 한 곳을 읽으므로**
보간 중에도 셋이 어긋나지 않는다 — 얼굴이 자라는 만큼 무리 간격이 벌어지고,
타일을 가리키는 화살표가 길어지고, 클릭 반경이 함께 커진다. 실측(합성 입력):
드래그 시작 후 반지름이 42.53 → 63.79px 로 매끄럽게 오르고, 손을 떼면 같은
페이스로 되돌아온다.

> **왜 즉시 튀면 안 되나.** 카드를 집는 순간 전장의 얼굴 서넛이 한 프레임 만에
> 1.5배로 부풀고 무리가 좌우로 벌어졌다. 무엇이 대상인지보다 "화면이 흔들렸다"는
> 인상이 먼저 왔다.

> **그렇다고 펄스는 아니다.** 1.06~1.14 사이를 오가던 sin 확대는 삭제됐고
> 되살리지 말 것 — 드래그해서 얼굴 위에 놓는 조작에서는 크기가 *계속* 변하는
> 대상이 오히려 겨누기 어려웠다. 지금 값은 **도달하면 미동도 없다**. 그와 함께
> `_emphasis_time` / `EMPHASIS_PULSE_*` 상수도 사라졌다.

`_process` 의 상시 재draw 는 셋이다 — **피해 수치 팝업**, **켜지거나 꺼지는 중인
강조**, 그리고 **미끄러지는 중인 마커**(`_advance_glide`). 전부 멈춰 있으면
`queue_redraw()` 를 부르지 않는다 — 대상 지정 상태가 **바뀌는** 순간은
`CardTargetingOverlay._request_redraw()` 가 따로 걷어찬다.
