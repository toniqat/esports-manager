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
  death rise (`ANIM_DEATH_RISE_PX`, phase 2 only) and damage shake (decaying
  `sin` jitter capped at `ANIM_SHAKE_AMP_PX`).
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
- 연속 공격(`repeat`)은 타수마다 `DMG_POPUP_STAGGER`(0.18s)씩 늦게 떠서 한
  픽셀에 겹치지 않는다.
- `_advance_popups(delta)` 가 `_process` 에서 돌며 만료분을 버리고, 살아 있는
  동안 `queue_redraw()` 를 계속 건다. 재시작은 `clear_popups()`.

### Targeting dim + emphasis pulse
**딤은 카드를 드는 순간 올라간다.** 예전에는 모달 대상 지정이 열려야
(`is_active()`) 사거리 밖 타일이 어두워졌지만, 이제 카드 선택 자체가 대상
지정이므로 `_draw()` 의 `draw_dim` 조건은 `targeting_overlay.is_visualizing()`
하나뿐이다. `is_visualizing()` 은 PILOT / LOCATION / PREVIEW 에서만 참이라
사거리 개념이 없는 INSTANT 카드(드로우 / 전략 점수 등)를 들었을 때는 전장이
전혀 어두워지지 않는다.

**사거리 무제한 카드는 노란 채움도 딤도 없다.** `cast_range ≥ 99`
(`CardTargetingOverlay.UNLIMITED_RANGE` — 복귀 / 보호 / 약탈)면 오버레이가
`range_unlimited` 을 켜고, `_draw_targeting_underlays` 는 사거리 채움을
건너뛰며 `_build_range_set` 은 전 셀을 in-range 로 돌려준다(=딤 없음).
전장을 통째로 노랗게 덮으면 정작 읽어야 할 표시(LOCATION 의 초록 유효 셀,
딤되지 않은 파일럿 마커)가 묻히기 때문이다.

### 파일럿 마커 위치 — `pilot_marker_positions()`
`_draw()` 는 매 프레임 `_build_pilot_render_layout()` 으로
`PilotData → Vector2` 마커 위치 표를 만들어 딤 오버레이와 공유한다. 같은
solve 를 즉석에서 한 번 더 돌려 돌려주는 **공개** 래퍼가
`pilot_marker_positions()` 이고, `CardTargetingOverlay._hit_test_pilot` 이
이걸 쓴다 — 한 셀에 여러 명이 서 있으면 각자 다른 슬롯에 그려지므로,
`grid_pos` 만 보고 계산하는 위치(타일 중심 / `pilot_marker_pos_solo`)로는
누구를 눌렀는지 구분할 수 없다(항상 맨 왼쪽 파일럿이 잡혔다).

타겟 가능한 파일럿 마커는 `_pilot_emphasis_scale(p)`가 반환하는 펄스 배율
(`EMPHASIS_SCALE_MIN..MAX`, 기본 1.06..1.14)로 약간 커진다. `_process(delta)`
가 visualizing 동안 `_emphasis_time` 을 누적하고 매 프레임 `queue_redraw()`
를 호출해 sin 펄스가 돌아간다. 강조 대상은 모드별로 다음과 같다:
- **PILOT**: `valid_pilots` 의 모든 파일럿
- **PREVIEW**: `preview_participants`
- 클릭하여 `pending_pick` 으로 잠긴 파일럿은 시안 링이 별도 강조이므로
  펄스에서 제외된다.
