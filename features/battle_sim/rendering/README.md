# Rendering Module

## BattleRenderer.gd
`extends Node2D` — child of BattleSim at position (0,0).

Owns all `_draw()` logic. BattleSim calls `_renderer.queue_redraw()` whenever state changes.
Reads all state from `_bs` (the BattleSim parent).

### Draw pipeline (called from `_draw()`)
1. `_draw_grid()` — cells with neutral zone coloring
2. `_draw_lane_dividers()` — vertical white lines at columns 3 and 6
3. `_draw_lane_lines()` — structural reference polylines + faction minion progress lines
4. `_draw_lane_midpoints()` — gold circles at row-7 midpoints
5. `_draw_hqs()` — colored HQ cells with HP bar
6. `_draw_turrets()` — diamond shape per turret, HP bar, tier label
7. `_draw_minions()` — solo (green/orange rect) or combat (M badge + counts)
8. Per-cell pilot rendering via `_draw_pilot_zoned()` — top/bottom zone split for combat/siege

### Coordinate helpers
All drawing uses `_bs.cell_center(pos)` and `_bs.cell_rect(pos)` which incorporate
`GRID_ORIGIN` and `CELL_SIZE` from BattleSim.
