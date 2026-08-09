# Rendering Module

## BattleRenderer.gd
`extends Node2D` — child of BattleSim at position (0,0).

Owns all `_draw()` logic. BattleSim calls `renderer.queue_redraw()` whenever state changes.
Reads all state from `_bs` (the BattleSim parent).

### Draw pipeline (called from `_draw()`)
1. `_draw_hq_hp_bars()` — green HP bar under each HQ once any T2 in their team is destroyed
2. `_draw_turret_hp_bars()` — yellow HP bar above each living turret (T2 hidden while own-lane T1 alive)
3. Per-cell pilot rendering via `_draw_pilot_team()` — pilots render OUTSIDE the tile (enemy above, ally below) with a small team-coloured triangle behind them whose apex points to the tile centre (speech-bubble tail)
4. `_draw_cell_badge()` — `NvN` / `xN` count badge centred ON the tile (the tile centre is now empty, since pilots are offset outward)

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

- `_render_cell(p)` — returns `anim_recall_orig` while a pilot is in recall
  fade-out, otherwise `grid_pos`. Pilots are grouped/team-laid-out by this so
  a recalling pilot is drawn at the cell they came from until they fully
  fade out, then "appears" at HQ for the descent fade-in.
- `_pilot_anim_offset(p)` — sums move-tween offset (ease-out cubic from
  `anim_prev_grid_pos` → `grid_pos`), recall rise/descend (`ANIM_RECALL_RISE_PX`),
  and damage shake (decaying `sin` jitter capped at `ANIM_SHAKE_AMP_PX`).
- `_pilot_anim_alpha(p)` — 1.0 → 0 during recall phase 1, 0 → 1.0 during
  recall phase 2 (and respawn fade-in). Multiplied into every per-pilot draw
  call (circle, ring, role text, HP ring, speech-bubble arrow) via
  `_alpha_mul`.

The 5+ overflow circle and the cell badge (`NvN` / `xN`) are drawn at full
alpha — they're aggregate visuals, not per-pilot.

### Targeting dim + emphasis pulse
**딤은 카드를 드는 순간 올라간다.** 예전에는 모달 대상 지정이 열려야
(`is_active()`) 사거리 밖 타일이 어두워졌지만, 이제 카드 선택 자체가 대상
지정이므로 `_draw()` 의 `draw_dim` 조건은 `targeting_overlay.is_visualizing()`
하나뿐이다. `is_visualizing()` 은 PILOT / LOCATION / PREVIEW 에서만 참이라
사거리 개념이 없는 INSTANT 카드(드로우 / 전략 점수 등)를 들었을 때는 전장이
전혀 어두워지지 않는다.

타겟 가능한 파일럿 마커는 `_pilot_emphasis_scale(p)`가 반환하는 펄스 배율
(`EMPHASIS_SCALE_MIN..MAX`, 기본 1.06..1.14)로 약간 커진다. `_process(delta)`
가 visualizing 동안 `_emphasis_time` 을 누적하고 매 프레임 `queue_redraw()`
를 호출해 sin 펄스가 돌아간다. 강조 대상은 모드별로 다음과 같다:
- **PILOT**: `valid_pilots` 의 모든 파일럿
- **PREVIEW**: `preview_participants`
- 클릭하여 `pending_pick` 으로 잠긴 파일럿은 시안 링이 별도 강조이므로
  펄스에서 제외된다.
