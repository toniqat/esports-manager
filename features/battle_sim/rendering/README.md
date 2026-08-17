# Rendering Module

## BattleRenderer.gd
`extends Node2D` — child of BattleSim at position (0,0).

Owns all `_draw()` logic. BattleSim calls `renderer.queue_redraw()` whenever state changes.
Reads all state from `_bs` (the BattleSim parent).

### Draw pipeline (called from `_draw()`)
1. `_draw_hq_hp_bars()` — green HP bar under each HQ once any T2 in their team is destroyed
2. `_draw_turret_hp_bars()` — yellow HP bar above each living turret (T2 hidden while own-lane T1 alive). 피격 중에는 `BattleSim.turret_hit_offset(td)` 만큼 함께 흔들린다 — 포탑 스프라이트(`Building` 노드)는 렌더러가 그리지 않고 BattleSim 이 직접 흔들므로, 바만 제자리에 두면 둘이 어긋난다.
3. Per-cell pilot rendering via `_draw_pilot_team()` — pilots render OUTSIDE the tile (enemy above, ally below) with a small team-coloured triangle behind them whose apex points to the tile centre (speech-bubble tail)
4. `_draw_cell_badge()` — `NvN` / `xN` count badge centred ON the tile (the tile centre is now empty, since pilots are offset outward)
5. `_draw_pilot_popups()` — 공격 카드의 피해 수치 / MISS 플로팅 텍스트, **맨 마지막**에 그려 무엇에도 가려지지 않는다

The minion / lane-line / minion-progress visualizations were removed alongside
the minion concept. Tile background colouring (lane vs jungle vs neutral) is
owned by the TileMapLayer in `BattleField.tscn`, not by the renderer.

### Pilot layout per team in a single cell
Built by `_layout_team_positions()`. Direction sign: enemy = above tile, ally = below.

| Count | Layout |
|---|---|
| 1 | one circle, offset toward team side (also when alone in the cell) |
| 2–3 | one horizontal row, offset toward team side |
| 4 | row of 3 close to tile + 1 farther out |
| 5 | row of 3 close to tile + 2 farther out |
| 6+ | 5-slot layout; the last slot becomes a `+N` overflow circle |

**No solo exception**: a pilot alone in a cell is laid out exactly like a
stacked one — offset toward its own side (enemy above, ally below) with the
speech-bubble arrow pointing back at the tile. The arrow is therefore always
present, so the tile a pilot occupies reads the same whether the cell is
contested or not. (The earlier `is_solo` centring + `_has_crowded_neighbor`
override were removed.)

Each pilot draws its own arrow (`_draw_arrow_to_tile`) — direction is computed from the circle's
position to the tile centre, so side circles in a 3-wide row point diagonally inward.

#### 대상 지정 강조는 배치도 탄다 (`em`)
`_layout_team_positions` 는 마지막 인자로 **그 무리의 강조 배율**
(`_group_emphasis` = 무리 안 최대 `_pilot_emphasis_scale`, 즉 1.0 또는
`TARGET_EMPHASIS_SCALE` **1.5**)을 받는다. 초상만 키우면 두 가지가 동시에
무너지기 때문이다:

1. **좌우로 겹친다.** 간격은 그대로인데 지름만 커지면 한 칸에 선 두세 명의
   얼굴이 서로를 덮어, 정작 겨눠야 할 순간에 누가 누구인지 읽을 수 없다.
2. **화살표가 사라진다.** 마커가 커지면 초상이 타일 중심까지 삼켜서 화살표가
   초상 뒤에 완전히 깔린다 — 하필 강조된(=지금 겨누는) 파일럿에서만.

그래서 좌우 간격(`dx_2` / `dx_3`)은 `em` 에 비례해 벌어지고, 타일에서의 거리는
`maxf(hex_h * 0.45 + draw_r * 0.4, draw_r * 1.75)` 로 반지름 기준 하한이 이겨
무리가 더 **바깥으로 물러난다** — 그 물러난 만큼이 곧 화살표가 길어질 자리다.
`em = 1` 에서는 언제나 앞 항이 이기므로 평소 배치는 한 픽셀도 바뀌지 않는다.

`_draw_arrow_to_tile` 도 같은 배율을 받아 **커진 초상 바깥에서 시작해 더 길게**
뻗는다(`apex_out` × `em`). 다만 `dist - 8px` 로 잘라 타일 중심을 넘지 않는다 —
넘어가면 옆 칸을 가리키는 것처럼 읽힌다. 오버플로 `+N` 원은 대상이 아니므로
`em = 1` 로 그린다(자리만 무리를 따라 벌어진다).

**화면 밖으로 나가면 무리째 밀어 넣는다** (`_clamp_group_on_screen`). 강조로
벌어진 가장자리 레인의 2~3인 무리는 그냥 두면 화면 밖으로 잘리는데, 잘린 얼굴은
누를 수도 놓을 수도 없다. 마커를 하나씩 따로 밀면 애써 벌린 간격이 도로 무너져
다시 겹치므로 **평행 이동**이다. 화살표는 여전히 각자 자기 타일을 가리키므로
누가 어느 칸인지도 유지된다. 실측(1080×1920, `SCREEN_EDGE_PAD` 6, 배율이 2.0
이던 시절): 타일 중심 x=950 의 3인 무리가 `em=2` 에서 자연 폭 617..1283 →
**495.6..1074** 로 접히고, x=120 의 무리는 왼쪽 가장자리 6px 에 붙는다. 배율이
1.5 로 내려간 지금은 접히는 일 자체가 훨씬 드물다 — 이 절이 존재하는 이유의
절반이 그 접힘을 없애자는 것이었다.

Radius and role-text font are FIXED per pilot (base values `PILOT_RADIUS_BASE = 31.5`,
`PILOT_FONT_SIZE_BASE = 16`, both multiplied by `HexGrid.DISPLAY_SCALE` at draw time so
they track tile size) regardless of how many pilots share the cell — circles do not shrink
for multi-pilot stacks. As a consequence, 3-wide rows extend past the hex's flat-to-flat
width and may visually overlap adjacent tiles' pilot displays; this is intentional. HQ HP
bars and cell badges are also scaled by `HexGrid.DISPLAY_SCALE` to stay proportional to
the bigger tiles.

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
- `_pilot_anim_offset(p)` — sums move-tween offset (ease-out cubic from
  `anim_prev_grid_pos` → `grid_pos`), recall rise/descend (`ANIM_RECALL_RISE_PX`),
  death rise (`ANIM_DEATH_RISE_PX`, phase 2 only), **공격 카드 돌진**
  (`BattleSim.pilot_lunge_offset`) and damage shake (decaying `sin` jitter
  capped at `ANIM_SHAKE_AMP_PX`).
- `_pilot_anim_alpha(p)` — 1.0 → 0 during recall phase 1 **and** death phase 2,
  0 → 1.0 during recall phase 2 (and respawn fade-in). Multiplied into every
  per-pilot draw call (circle, ring, role text, HP ring, speech-bubble arrow)
  via `_alpha_mul`.
- **Death tint** — while `anim_death_phase != 0` the team colour and the
  portrait are both multiplied by `BattleSim.ANIM_DEATH_TINT`, so the fallen
  pilot reads as dimmed rather than merely faded. Phase 1 holds at full alpha
  (딤드된 채 대기), phase 2 fades it out while it rises.

The 5+ overflow circle and the cell badge (`NvN` / `xN`) are drawn at full
alpha — they're aggregate visuals, not per-pilot. Note that a pilot mid-death
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
- `BattleSim.DMG_POPUP_DUR`(0.95s) 동안 `DMG_POPUP_RISE_PX`(46px) 만큼 감속하며
  떠오르고 마지막 40% 구간에서만 흐려진다.
- **`DMG_POPUP_STAGGER`(0.18s)는 이제 거의 쓰이지 않는다.** 한 타격이
  파고들기 → 타격 → 복귀 세 박자(1.12초)를 다 도는 연출이 붙으면서 연속 공격의
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
`PilotData → Vector2` 마커 위치 표를 만들어 딤 오버레이와 공유한다. 같은
solve 를 즉석에서 한 번 더 돌려 돌려주는 **공개** 래퍼가
`pilot_marker_positions()` 이고, `CardTargetingOverlay._hit_test_pilot` 이
이걸 쓴다 — 한 셀에 여러 명이 서 있으면 각자 다른 슬롯에 그려지므로,
`grid_pos` 만 보고 계산하는 위치(타일 중심 / `pilot_marker_pos_solo`)로는
누구를 눌렀는지 구분할 수 없다(항상 맨 왼쪽 파일럿이 잡혔다).


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

`_process` 의 상시 재draw 는 **피해 수치 팝업과, 켜지거나 꺼지는 중인 강조**
두 가지뿐이다. 둘 다 멈춰 있으면 `queue_redraw()` 를 부르지 않는다 — 대상 지정
상태가 **바뀌는** 순간은 `CardTargetingOverlay._request_redraw()` 가 따로
걷어찬다.
