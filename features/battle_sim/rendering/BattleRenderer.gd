class_name BattleRenderer
extends Node2D

@onready var _bs: BattleSim = get_parent() as BattleSim

# 강조된(타겟 가능) 파일럿 마커가 약간 펄스로 커지는 애니메이션의 시간 누적값.
# Targeting overlay가 visualizing 중일 때만 _process에서 누적/재draw 한다.
var _emphasis_time: float = 0.0
const EMPHASIS_PULSE_HZ: float       = 1.4    # 1초당 펄스 횟수
const EMPHASIS_SCALE_MIN: float      = 1.06   # 최소 확대 배율
const EMPHASIS_SCALE_MAX: float      = 1.14   # 최대 확대 배율


# ─── 피해 수치 팝업 (공격 카드 전용) ─────────────────────────────────────────
# 공격 카드가 대상 파일럿 위에 남기는 짧은 플로팅 텍스트. 각 항목은
#   {"pos": Vector2, "text": String, "color": Color, "t": float, "delay": float}
# 이고 `pos` 는 **띄운 순간의 마커 좌표를 그대로 고정**한다 — 대상이 그 사이
# 쓰러지거나 밀려나도 숫자가 따라다니지 않게 하기 위함.
var _popups: Array = []

const POPUP_MISS_COLOR   := Color(0.78, 0.80, 0.86)
const POPUP_DAMAGE_COLOR := Color(1.00, 0.42, 0.36)
const POPUP_SHIELD_COLOR := Color(0.45, 0.85, 1.00)
const POPUP_FONT_SIZE_BASE := 26


func _process(delta: float) -> void:
	# Targeting/Selection-preview 중 강조 마커가 살아있는 동안만 펄스가 돌도록
	# 시간을 누적하고 매 프레임 재draw 한다. 비활성 상태에서는 시간을 0으로
	# 리셋해 다음 강조 시 처음부터 펄스가 시작되게 한다.
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to != null and to.is_visualizing():
		_emphasis_time += delta
		queue_redraw()
	else:
		_emphasis_time = 0.0
	if _advance_popups(delta):
		queue_redraw()


## Ticks every live popup and drops the expired ones. Returns true while at
## least one is still on screen so the caller keeps redrawing.
func _advance_popups(delta: float) -> bool:
	if _popups.is_empty():
		return false
	var keep: Array = []
	for raw in _popups:
		var e: Dictionary = raw
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < float(e["delay"]) + _bs.DMG_POPUP_DUR:
			keep.append(e)
	_popups = keep
	return true


## Floats `text` above `p`'s currently-drawn marker. `delay` staggers the
## members of a 연속 공격 chain so several numbers off the same swing don't
## stack on one pixel.
func spawn_pilot_popup(p: PilotData, text: String, color: Color,
		delay: float = 0.0) -> void:
	if p == null:
		return
	var markers: Dictionary = _build_pilot_render_layout()
	var pos: Vector2 = markers[p] as Vector2 if markers.has(p) \
			else _bs.pilot_marker_pos_solo(p)
	_popups.append({
		"pos":   pos,
		"text":  text,
		"color": color,
		"t":     0.0,
		"delay": max(0.0, delay),
	})
	queue_redraw()


## Drops every in-flight popup. Called on restart so numbers from the previous
## match don't float over the fresh board.
func clear_popups() -> void:
	_popups.clear()
	queue_redraw()


func _draw_pilot_popups() -> void:
	if _popups.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fsz: int = int(round(POPUP_FONT_SIZE_BASE * HexGrid.DISPLAY_SCALE))
	for raw in _popups:
		var e: Dictionary = raw
		var local_t: float = float(e["t"]) - float(e["delay"])
		if local_t < 0.0:
			continue
		var k: float = clampf(local_t / _bs.DMG_POPUP_DUR, 0.0, 1.0)
		# 위로 갈수록 감속하며 떠오르고, 뒷부분에서만 흐려진다.
		var rise: float = _bs.DMG_POPUP_RISE_PX * (1.0 - pow(1.0 - k, 2.0))
		var alpha: float = 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
		var txt: String = String(e["text"])
		var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
		var base: Vector2 = (e["pos"] as Vector2) \
				+ Vector2(-tsz.x * 0.5, -PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE - rise)
		# 검은 외곽선 먼저 — 전장 타일 위에서도 숫자가 읽히도록.
		var outline := _alpha_mul(Color(0.0, 0.0, 0.0), alpha * 0.85)
		for ox in [-2.0, 2.0]:
			for oy in [-2.0, 2.0]:
				draw_string(font, base + Vector2(ox, oy), txt,
						HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, outline)
		draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
				_alpha_mul(e["color"] as Color, alpha))


func _draw() -> void:
	if _bs.game_phase == GameEnums.BattlePhase.GAMBIT:
		return
	# Recompute the per-cell pilot grouping once so _draw_pilot_groups and the
	# targeting dim overlay agree on where each pilot's marker landed within
	# its team's offset row above / below the tile.
	_pilot_render_layout = _build_pilot_render_layout()
	_draw_captured_tile_overlays()
	_draw_targeting_underlays()
	# Out-of-range tile dim is drawn BEFORE HQ/turret/pilot graphics so a
	# pilot marker that visually overlaps an adjacent out-of-range tile (the
	# marker is offset above/below its own tile) is not obscured by the dim.
	# The dim now goes up the moment a card is lifted in hand — selecting IS
	# targeting. is_visualizing() is false for INSTANT cards (no range to show),
	# so a 드로우 / 전략 점수 card leaves the battlefield untouched.
	var draw_dim: bool = _bs.targeting_overlay != null \
			and _bs.targeting_overlay.is_visualizing()
	var range_set: Dictionary = {}
	if draw_dim:
		range_set = _build_range_set()
		_draw_targeting_tile_dim(range_set)
	_draw_hq_hp_bars()
	_draw_turret_hp_bars()
	_draw_pilot_groups()
	# Pending-pick highlight (cyan ring/outline on the clicked-but-not-yet-
	# confirmed target) draws AFTER pilot circles so the ring sits on top of
	# the marker, but BEFORE per-pilot dim so it is not greyed out.
	_draw_pending_pick_highlight()
	# Per-pilot dim is the only dim drawn ON TOP of pilot markers — only
	# applied to pilots whose own cell is INSIDE the in-range set (so they're
	# not already covered by tile dim). This prevents the double-dim where an
	# invalid pilot in an out-of-range cell got a tile dim hex AND a per-
	# marker disc stacked on each other.
	if draw_dim:
		_draw_targeting_pilot_dim()
	# 피해 수치 / MISS 는 무엇에도 가려지면 안 되므로 맨 마지막.
	_draw_pilot_popups()


# ─── Per-frame pilot render layout cache ─────────────────────────────────────
# Built once per _draw() call so the per-pilot dim overlay can ask "where on
# screen is this pilot's marker?" without redoing the team-stack solve.
# Schema:
#   _pilot_render_layout = {
#     PilotData → Vector2 marker_pos (tile centre when solo, else offset)
#   }
var _pilot_render_layout: Dictionary = {}


# Captured jungle/neutral tiles use saturated team-coloured atlas tiles. We
# overlay a translucent white polygon on owned cells so the team identity
# still reads but the tile no longer competes with pilot markers / HP bars.
func _draw_captured_tile_overlays() -> void:
	var hg: HexGrid = _bs.hex_grid
	for raw_cell in _bs.neutral_zone_cells.keys():
		var cell := raw_cell as Vector2i
		var owner_id: int = int(_bs.neutral_zone_cells[cell])
		if owner_id < 0:
			continue
		var center := _bs.cell_center(cell)
		var pts := hg.hex_corners(center)
		draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.55))


func _draw_pilot_groups() -> void:
	var groups := _group_pilots_by_render_cell()
	var cell_team0: Dictionary = groups[0]
	var cell_team1: Dictionary = groups[1]
	var all_cells: Dictionary = {}
	for pos in cell_team0.keys(): all_cells[pos] = true
	for pos in cell_team1.keys(): all_cells[pos] = true

	for pos in all_cells.keys():
		var pv := pos as Vector2i
		var t0: Array = cell_team0.get(pv, []) as Array
		var t1: Array = cell_team1.get(pv, []) as Array
		var total := t0.size() + t1.size()
		if not t1.is_empty():
			_draw_pilot_team(pv, t1, true)
		if not t0.is_empty():
			_draw_pilot_team(pv, t0, false)
		# Skip the cross-team collision badge (1v1, 2v2 …) — it added noise on
		# top of the pilot stacks. Keep the single-team multi-pilot tag (x2, x3).
		if total > 1 and (t0.is_empty() or t1.is_empty()):
			_draw_cell_badge(pv, t0.size(), t1.size())


# Group renderable pilots by their *render* cell (not grid_pos): a pilot in
# recall fade-out is drawn at the cell they came from, so they don't crowd the
# HQ layout until the fade-in phase starts. Returns [team0_dict, team1_dict].
func _group_pilots_by_render_cell() -> Array:
	var cell_team0: Dictionary = {}
	var cell_team1: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not _is_renderable(p):
			continue
		var rcell := _render_cell(p)
		if p.team == 0:
			if not cell_team0.has(rcell):
				cell_team0[rcell] = []
			(cell_team0[rcell] as Array).append(p)
		else:
			if not cell_team1.has(rcell):
				cell_team1[rcell] = []
			(cell_team1[rcell] as Array).append(p)
	return [cell_team0, cell_team1]


# Builds the PilotData → Vector2 marker_pos lookup used by the dim overlay.
# Mirrors _layout_team_positions for small stacks (n ≤ 5); the
# overflow circle case (n > 5) doesn't have a per-pilot slot for the
# overflow group, so those pilots fall back to their team-direction offset.
func _build_pilot_render_layout() -> Dictionary:
	var out: Dictionary = {}
	var groups := _group_pilots_by_render_cell()
	var cell_team0: Dictionary = groups[0]
	var cell_team1: Dictionary = groups[1]
	var all_cells: Dictionary = {}
	for pos in cell_team0.keys(): all_cells[pos] = true
	for pos in cell_team1.keys(): all_cells[pos] = true
	for pos in all_cells.keys():
		var pv := pos as Vector2i
		var t0: Array = cell_team0.get(pv, []) as Array
		var t1: Array = cell_team1.get(pv, []) as Array
		var tile_center := _bs.cell_center(pv)
		var radius := _radius_for_count(t0.size() + t1.size())
		_apply_team_layout_to_lookup(out, t0, tile_center, false, radius)
		_apply_team_layout_to_lookup(out, t1, tile_center, true,  radius)
	return out


func _apply_team_layout_to_lookup(out: Dictionary, pilots: Array,
		tile_center: Vector2, is_enemy: bool, radius: float) -> void:
	if pilots.is_empty():
		return
	var n := pilots.size()
	var positions := _layout_team_positions(n, tile_center, is_enemy, radius)
	var visible_count: int = mini(n, 5)
	# n > 5 fills positions[0..3] for the first 4 pilots and reserves
	# positions[4] for the +N overflow circle; remaining pilots have no
	# screen slot. Map only the on-screen pilots so the dim overlay matches
	# what's actually drawn.
	var slot_count: int = visible_count - 1 if n > 5 else visible_count
	for i in range(slot_count):
		out[pilots[i]] = positions[i] as Vector2


func _draw_hq_hp_bars() -> void:
	var enemy_locked  := not _bs.sim_core.any_t2_destroyed(1)
	var player_locked := not _bs.sim_core.any_t2_destroyed(0)
	if not player_locked:
		_draw_hq_hp_bar(_bs.PLAYER_HQ_POS, _bs.player_hq_hp)
	if not enemy_locked:
		_draw_hq_hp_bar(_bs.ENEMY_HQ_POS, _bs.enemy_hq_hp)


func _draw_hq_hp_bar(pos: Vector2i, hp: int) -> void:
	var center := _bs.cell_center(pos)
	var s: float = HexGrid.DISPLAY_SCALE
	var bw := 60.0 * s; var bh := 8.0 * s
	var bx := center.x - bw * 0.5; var by_ := center.y + 16.0 * s
	draw_rect(Rect2(bx, by_, bw, bh), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(bx, by_, bw * float(hp) / float(_bs.HQ_MAX_HP), bh), Color(0.2, 0.9, 0.2))


func _draw_turret_hp_bars() -> void:
	for t in _bs.turrets:
		_draw_turret_hp_bar(t as TurretData)


func _draw_turret_hp_bar(td: TurretData) -> void:
	if not td.alive:
		return
	if td.tier == 2 and _bs.sim_core.t1_alive_in_lane(td.team, td.lane):
		return
	# 피격 중에는 HP 바도 스프라이트와 **같은 오프셋**으로 흔들린다 — 둘이
	# 어긋나면 바만 제자리에 붙어 있어 연출이 겉돈다.
	var center := _bs.cell_center(td.grid_pos) + _bs.turret_hit_offset(td)
	var hg: HexGrid = _bs.hex_grid
	var bw: float = hg.hex_size * 1.1; var bh: float = 6.0 * HexGrid.DISPLAY_SCALE
	var bx: float = center.x - bw * 0.5; var by_: float = center.y - hg.hex_height * 0.38
	draw_rect(Rect2(bx, by_, bw, bh), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(bx, by_, bw * float(td.hp) / float(td.max_hp), bh),
			Color(0.92, 0.68, 0.1))


# ─── Pilot rendering ─────────────────────────────────────────────────────────
# All pilot circles are offset OUTSIDE their tile (enemy ABOVE, ally BELOW)
# with a small team-coloured triangle behind them whose apex points to the
# tile centre — like a speech-bubble tail.

# Pilot dimensions track HexGrid.DISPLAY_SCALE so they stay proportional to
# tile size. Base values are calibrated against the unscaled (1.0x) hex.
const PILOT_RADIUS_BASE := 31.5
const PILOT_FONT_SIZE_BASE := 16


func _radius_for_count(_n: int) -> float:
	return PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE


func _font_size_for_count(_n: int) -> int:
	return int(round(PILOT_FONT_SIZE_BASE * HexGrid.DISPLAY_SCALE))


# Returns up to 5 Vector2 positions, ordered:
#   [close-row left, close-row mid, close-row right, far-row …]
# Pilots are ALWAYS offset outside the tile toward their own side (enemy above,
# ally below), even when alone in the cell — the speech-bubble arrow then
# always marks which tile the pilot occupies.
func _layout_team_positions(n: int, tile_center: Vector2,
		is_enemy: bool, radius: float) -> Array:
	var dir: float = -1.0 if is_enemy else 1.0
	var hex_h: float = (_bs.hex_grid as HexGrid).hex_height
	var close_off: float = hex_h * 0.45 + radius * 0.4
	var far_off: float   = close_off + radius * 1.85 + 6.0
	var close_y: float = tile_center.y + dir * close_off
	var far_y: float   = tile_center.y + dir * far_off
	var dx_3: float    = radius * 2.4
	var dx_2: float    = radius * 1.2
	var visible_count: int = mini(n, 5)
	var positions: Array = []
	if visible_count == 1:
		positions.append(Vector2(tile_center.x, close_y))
	elif visible_count == 2:
		positions.append(Vector2(tile_center.x - dx_2, close_y))
		positions.append(Vector2(tile_center.x + dx_2, close_y))
	elif visible_count == 3:
		positions.append(Vector2(tile_center.x - dx_3, close_y))
		positions.append(Vector2(tile_center.x,        close_y))
		positions.append(Vector2(tile_center.x + dx_3, close_y))
	elif visible_count == 4:
		positions.append(Vector2(tile_center.x - dx_3, close_y))
		positions.append(Vector2(tile_center.x,        close_y))
		positions.append(Vector2(tile_center.x + dx_3, close_y))
		positions.append(Vector2(tile_center.x,        far_y))
	else:
		positions.append(Vector2(tile_center.x - dx_3, close_y))
		positions.append(Vector2(tile_center.x,        close_y))
		positions.append(Vector2(tile_center.x + dx_3, close_y))
		positions.append(Vector2(tile_center.x - dx_2, far_y))
		positions.append(Vector2(tile_center.x + dx_2, far_y))
	return positions


func _draw_pilot_team(cell: Vector2i, pilots: Array, is_enemy: bool) -> void:
	var tile_center := _bs.cell_center(cell)
	var n := pilots.size()
	var radius := _radius_for_count(n)
	var fsize := _font_size_for_count(n)
	var team_color := Color(0.9, 0.2, 0.2) if is_enemy else Color(0.2, 0.5, 0.9)
	var positions := _layout_team_positions(n, tile_center, is_enemy, radius)
	var visible_count: int = mini(n, 5)
	for i in range(visible_count):
		var base_pos: Vector2 = positions[i]
		var is_overflow: bool = (n > 5 and i == 4)
		if is_overflow:
			_draw_arrow_to_tile(base_pos, tile_center, radius, team_color, 1.0)
			_draw_overflow_circle(base_pos, n - 4, radius, team_color)
		else:
			var pilot := pilots[i] as PilotData
			var off := _pilot_anim_offset(pilot)
			var alpha := _pilot_anim_alpha(pilot)
			var pos := base_pos + off
			# 쓰러진 파일럿은 팀 색까지 함께 죽여 딤드로 읽히게 한다. 초상 자체의
			# 딤은 _draw_pilot_circle 이 같은 배율로 건다.
			var marker_color: Color = team_color
			if pilot.anim_death_phase != 0:
				marker_color = team_color * _bs.ANIM_DEATH_TINT
			_draw_arrow_to_tile(pos, tile_center, radius, marker_color, alpha)
			_draw_pilot_circle(pilot, pos, radius, fsize,
					marker_color, is_enemy, alpha)


# ─── Animation helpers ───────────────────────────────────────────────────────

## A pilot is drawn while they are alive **or** while the 전사 연출 (dim → fade
## + rise at the cell they fell on) is still playing. That animation runs after
## `alive` has already flipped to false, which is exactly why this is not a
## plain `p.alive` test — without it a killed pilot vanished on the same frame
## the damage landed. 복귀 연출은 여기 걸릴 일이 없다: 복귀한 파일럿은 전장을
## 뜨지 않으므로 계속 `alive` 다.
func _is_renderable(p: PilotData) -> bool:
	return p.alive or p.anim_death_phase != 0


# Render cell: where this pilot should be drawn this frame. During recall
# phase 1 (fade-out) the pilot still appears at the cell they came from even
# though grid_pos has already been snapped to HQ. During phase 2 (fade-in)
# the pilot is drawn at their HQ even if the sim has already advanced them
# away — phase 2 is the "arrive at HQ" descent and must visually anchor there.
# A pilot playing the 전사 연출 stays on the cell they fell on.
func _render_cell(p: PilotData) -> Vector2i:
	if p.anim_recall_phase == 1:
		return p.anim_recall_orig
	if p.anim_recall_phase == 2:
		return _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	if p.anim_death_phase != 0:
		return p.anim_death_cell
	return p.grid_pos


# Per-pilot pixel offset combining move tween, recall rise/descend and
# damage shake. Applied on top of the per-cell layout position.
func _pilot_anim_offset(p: PilotData) -> Vector2:
	var off := Vector2.ZERO
	if p.anim_death_phase == 2:
		# 전사 2단계 — 시신이 투명해지며 위로 떠오른다.
		var td: float = clamp(p.anim_death_t / p.anim_death_dur, 0.0, 1.0)
		off.y -= _bs.ANIM_DEATH_RISE_PX * td
		return off
	if p.anim_death_phase == 1:
		return off   # 딤드 대기 중에는 제자리
	if p.anim_recall_phase == 1:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		off.y -= _bs.ANIM_RECALL_RISE_PX * t
	elif p.anim_recall_phase == 2:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		off.y -= _bs.ANIM_RECALL_RISE_PX * (1.0 - t)
	elif p.anim_move_dur > 0.0:
		var t_raw: float = clamp(p.anim_move_t / p.anim_move_dur, 0.0, 1.0)
		var t_eased: float = 1.0 - pow(1.0 - t_raw, 3.0)
		var from_screen := _bs.cell_center(p.anim_prev_grid_pos)
		var to_screen := _bs.cell_center(p.grid_pos)
		off += from_screen.lerp(to_screen, t_eased) - to_screen
	if p.anim_shake_dur > 0.0:
		var t: float = clamp(p.anim_shake_t / p.anim_shake_dur, 0.0, 1.0)
		var amp: float = _bs.ANIM_SHAKE_AMP_PX * (1.0 - t)
		off.x += sin(t * TAU * 4.0) * amp
	return off


func _pilot_anim_alpha(p: PilotData) -> float:
	var alpha: float = 1.0
	if p.anim_death_phase == 1:
		return 1.0
	if p.anim_death_phase == 2:
		return 1.0 - clamp(p.anim_death_t / p.anim_death_dur, 0.0, 1.0)
	if p.anim_recall_phase == 1:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		alpha = 1.0 - t
	elif p.anim_recall_phase == 2:
		var t: float = clamp(p.anim_recall_t / p.anim_recall_dur, 0.0, 1.0)
		alpha = t
	# Targeting overlay dim is now applied as a separate black overlay in
	# _draw_targeting_dim_overlay (RGB darken instead of alpha fade), so the
	# pilot drawing itself uses only the recall-fade alpha here.
	return alpha


# Targeting underlays — soft yellow fill on every in-range cell so the
# player sees the cast radius, plus a green outline on LOCATION-mode legal
# pick cells (subset of in-range, e.g. 약탈's enemy-jungle filter). PILOT
# mode no longer draws per-cell rings — the visible pilot markers are the
# click target, and the range fill provides the visual cue.
func _draw_targeting_underlays() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or not to.is_visualizing():
		return
	var hg: HexGrid = _bs.hex_grid
	var range_set: Dictionary = {}
	if to.mode == CardTargetingOverlay.Mode.PREVIEW:
		for raw in to.area_cells.keys():
			range_set[raw as Vector2i] = true
	elif to.range_unlimited:
		# 사거리 제한 없음(복귀 / 보호 / 약탈) — 전장 전체를 노랗게 덮으면
		# 유효 대상 표시가 묻히므로 채움 자체를 생략한다. 딤도 없다
		# (_build_range_set 이 전 셀을 in-range 로 돌려준다).
		pass
	elif to.range_caster != null and to.range_radius > 0:
		# Same shape as CardTargetingOverlay.is_in_range_cell — duplicated here
		# so the renderer doesn't need to call into the overlay per cell.
		var caster_cell: Vector2i = to.range_caster.grid_pos
		var max_r: int = to.range_radius
		for raw in _bs.tiles_layer.get_used_cells():
			var c := raw as Vector2i
			var d: int = hg.hex_distance(caster_cell, c)
			if d == 0 or d <= max_r:
				range_set[c] = true
	for raw in range_set.keys():
		var c := raw as Vector2i
		var ctr := _bs.cell_center(c)
		var pts := hg.hex_corners(ctr)
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.30, 0.22))
		draw_polyline(_close_polygon(pts),
				Color(1.0, 0.85, 0.30, 0.85), 3.0, true)
	# LOCATION valid cells — green outline on top of the range fill.
	if to.mode == CardTargetingOverlay.Mode.LOCATION:
		for raw in to.valid_cells.keys():
			var c := raw as Vector2i
			var ctr := _bs.cell_center(c)
			var pts := hg.hex_corners(ctr)
			draw_colored_polygon(pts, Color(0.30, 0.85, 0.45, 0.25))
			draw_polyline(_close_polygon(pts),
					Color(0.30, 0.85, 0.45, 0.95), 3.0, true)


# Cyan ring / outline on the clicked-but-not-yet-confirmed target so the
# player can see what 확인 will commit. Drawn between pilot circles and the
# dim overlay so it sits on top of the marker.
func _draw_pending_pick_highlight() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or to.pending_pick == null:
		return
	var hg: HexGrid = _bs.hex_grid
	if to.mode == CardTargetingOverlay.Mode.PILOT:
		var picked := to.pending_pick as PilotData
		if picked != null and picked.alive:
			var pos := _pilot_marker_pos(picked)
			var radius: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE + 10.0
			draw_arc(pos, radius, 0.0, TAU, 36,
					Color(0.30, 0.95, 1.0, 0.95), 4.0)
	elif to.mode == CardTargetingOverlay.Mode.LOCATION:
		var c := to.pending_pick as Vector2i
		var ctr := _bs.cell_center(c)
		var pts := hg.hex_corners(ctr)
		draw_polyline(_close_polygon(pts),
				Color(0.30, 0.95, 1.0, 0.95), 5.0, true)


# Build the in-range cell set used by both the tile dim and the pilot dim.
# Mirrors the logic in _draw_targeting_underlays; kept identical so the
# yellow range fill and the out-of-range black dim never disagree.
func _build_range_set() -> Dictionary:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	var range_set: Dictionary = {}
	if to == null:
		return range_set
	var hg: HexGrid = _bs.hex_grid
	if to.mode == CardTargetingOverlay.Mode.PREVIEW:
		for raw in to.area_cells.keys():
			range_set[raw as Vector2i] = true
	elif to.range_unlimited:
		# 전장 전체가 사거리 — 딤이 하나도 올라가지 않도록 전 셀을 넣는다.
		for raw in _bs.tiles_layer.get_used_cells():
			range_set[raw as Vector2i] = true
	elif to.range_caster != null and to.range_radius > 0:
		var caster_cell: Vector2i = to.range_caster.grid_pos
		var max_r: int = to.range_radius
		for raw in _bs.tiles_layer.get_used_cells():
			var c := raw as Vector2i
			var d: int = hg.hex_distance(caster_cell, c)
			if d == 0 or d <= max_r:
				range_set[c] = true
	return range_set


# Out-of-range tile dim. Drawn BEFORE pilots / HQ bars so an offset pilot
# marker that visually intrudes into an adjacent out-of-range tile is not
# covered by the dim of that neighbour cell.
func _draw_targeting_tile_dim(range_set: Dictionary) -> void:
	var hg: HexGrid = _bs.hex_grid
	var dim_color := Color(0.0, 0.0, 0.0, 0.60)
	for raw in _bs.tiles_layer.get_used_cells():
		var c := raw as Vector2i
		if range_set.has(c):
			continue
		var ctr := _bs.cell_center(c)
		var pts := hg.hex_corners(ctr)
		draw_colored_polygon(pts, dim_color)


# Per-pilot marker dim. Drawn AFTER pilot circles so the dim sits on top of
# the marker. Applied to every invalid pilot regardless of whether their tile
# is in-range — pilot markers are offset above/below their tile, so a marker
# whose own cell is dimmed can still bleed onto an adjacent in-range tile and
# read as "bright" without this per-marker disc. The marker is drawn ON TOP
# of the tile dim, so the disc dims only the marker; the underlying tile dim
# already darkens the tile area beneath it without doubling up on the marker.
func _draw_targeting_pilot_dim() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null:
		return
	var dim_color := Color(0.0, 0.0, 0.0, 0.60)
	var radius: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if not to.should_dim_pilot(p):
			continue
		var marker_pos := _pilot_marker_pos(p)
		# Cover the HP ring outside the portrait too — slightly larger than
		# the portrait radius.
		draw_circle(marker_pos, radius + 4.0, dim_color)


# Rendered marker position for the pilot — reads the cached layout built in
# _draw(). Falls back to BattleSim.pilot_marker_pos_solo (the team-direction
# offset) when the pilot was not laid out this frame (overflow circle slot
# or off-screen states).
func _pilot_marker_pos(p: PilotData) -> Vector2:
	if _pilot_render_layout.has(p):
		return _pilot_render_layout[p] as Vector2
	return _bs.pilot_marker_pos_solo(p)


## Fresh `PilotData → Vector2` marker map — the same per-cell stack solve
## `_draw()` runs. Public because CardTargetingOverlay's PILOT hit test needs
## the *drawn* marker of each pilot: several pilots sharing a cell each get
## their own slot, and aiming at the tile centre instead can only ever resolve
## to one of them. Rebuilt on call (10 pilots) so a click never reads a layout
## from before the last move.
func pilot_marker_positions() -> Dictionary:
	return _build_pilot_render_layout()


# 타겟 가능한 파일럿(=강조)에는 약간 커지는 펄스 배율을 반환한다. 대상이
# 아니면 1.0. PILOT 모드는 valid_pilots, PREVIEW 는 preview_participants 가
# 강조 대상이다. Pending pick(이미 찍은 대상)은 별도의 시안 링으로 강조되므로
# 펄스에서 제외해 시각이 겹치지 않게 한다.
func _pilot_emphasis_scale(p: PilotData) -> float:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or not to.is_visualizing():
		return 1.0
	if to.pending_pick != null and to.pending_pick is PilotData and to.pending_pick == p:
		return 1.0
	var emphasized: bool = false
	match to.mode:
		CardTargetingOverlay.Mode.PILOT:
			emphasized = to.valid_pilots.has(p)
		CardTargetingOverlay.Mode.PREVIEW:
			emphasized = p in to.preview_participants
	if not emphasized:
		return 1.0
	# sin 펄스를 0..1 정규화 후 [MIN, MAX] 사이로 매핑.
	var t: float = (sin(_emphasis_time * TAU * EMPHASIS_PULSE_HZ) + 1.0) * 0.5
	return EMPHASIS_SCALE_MIN + (EMPHASIS_SCALE_MAX - EMPHASIS_SCALE_MIN) * t


func _close_polygon(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out := PackedVector2Array()
	for v in pts:
		out.append(v)
	out.append(pts[0])
	return out


func _alpha_mul(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)


func _draw_arrow_to_tile(circle_pos: Vector2, tile_center: Vector2,
		radius: float, color: Color, alpha: float = 1.0) -> void:
	var to_tile := tile_center - circle_pos
	if to_tile.length_squared() < 1.0:
		return
	var dir := to_tile.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var apex_out: float = clamp(radius * 0.84, 10.0, 24.0)
	var base_half: float = clamp(radius * 0.9, 10.0, 18.0)
	var apex := circle_pos + dir * (radius + apex_out)
	var base := circle_pos + dir * (radius * 0.6)
	var pts := PackedVector2Array([
		apex,
		base + perp * base_half,
		base - perp * base_half,
	])
	draw_colored_polygon(pts, _alpha_mul(color.darkened(0.1), alpha))
	# White outline so the arrow stays distinguishable against captured tiles.
	draw_polyline(_close_polygon(pts),
			_alpha_mul(Color(1.0, 1.0, 1.0), alpha), 2.5, true)


func _draw_pilot_circle(pilot: PilotData, pos: Vector2, radius: float,
		_fsize: int, color: Color, _is_enemy: bool,
		alpha: float = 1.0) -> void:
	# 강조(=타겟 가능) 마커는 베이스 반지름에 펄스 배율을 곱해 약간 커진다.
	# Pending pick(이미 클릭한 대상)은 별도의 시안 링이 강조를 대신하므로 펄스
	# 적용에서 제외한다.
	var draw_radius: float = radius * _pilot_emphasis_scale(pilot)
	# Pilot portrait fills the slot. The team-colour HP ring (drawn outside the
	# portrait) is now the sole faction marker — the previous ring directly on
	# the portrait edge has been removed to avoid the double outline.
	var portrait: Texture2D = PilotImages.circle_for(pilot.pilot_id)
	# 쓰러진 파일럿의 초상은 마커 색과 같은 배율로 어두워진다.
	var portrait_tint: Color = _bs.ANIM_DEATH_TINT if pilot.anim_death_phase != 0 \
			else Color.WHITE
	if portrait != null:
		var rect := Rect2(pos.x - draw_radius, pos.y - draw_radius,
				draw_radius * 2.0, draw_radius * 2.0)
		draw_texture_rect(portrait, rect, false, _alpha_mul(portrait_tint, alpha))
	else:
		draw_circle(pos, draw_radius, _alpha_mul(color, alpha))
	# Circular HP ring hugging the outside of the pilot circle. Width is
	# doubled vs. the old marker; colour now matches faction (was green).
	var hp_ring_w := 8.0
	var hp_ring_r := draw_radius + hp_ring_w * 0.5 + 1.0
	draw_arc(pos, hp_ring_r, 0.0, TAU, 36,
			_alpha_mul(Color(0.15, 0.15, 0.15), alpha), hp_ring_w)
	var hp_frac: float = clamp(float(pilot.hp) / float(pilot.max_hp), 0.0, 1.0)
	var start_a: float = -PI * 0.5
	if hp_frac > 0.0:
		var end_a: float = start_a + TAU * hp_frac
		var seg: int = max(8, int(36.0 * hp_frac))
		draw_arc(pos, hp_ring_r, start_a, end_a, seg,
				_alpha_mul(color, alpha), hp_ring_w)
	# Tick marks every 25 HP — so a 110-HP bar shows 4 dividers and the final
	# stub reads as 10/25 of a full segment.
	if pilot.max_hp > 25:
		var tick_inner: float = hp_ring_r - hp_ring_w * 0.5
		var tick_outer: float = hp_ring_r + hp_ring_w * 0.5
		var tick_col: Color = _alpha_mul(Color(0.05, 0.05, 0.05), alpha)
		var ticks: int = int(floor(float(pilot.max_hp - 1) / 25.0))
		for i in range(1, ticks + 1):
			var frac: float = float(i * 25) / float(pilot.max_hp)
			if frac >= 1.0:
				break
			var ang: float = start_a + TAU * frac
			var dirv := Vector2(cos(ang), sin(ang))
			draw_line(pos + dirv * tick_inner, pos + dirv * tick_outer,
					tick_col, 1.5)
	# 보호막 ring — cyan band stacked just outside the HP ring, length = shield / max_hp.
	if pilot.shield > 0:
		var sh_frac: float = clamp(float(pilot.shield) / float(pilot.max_hp), 0.0, 1.0)
		var sh_ring_r: float = hp_ring_r + hp_ring_w * 0.5 + 2.0
		var sh_start: float = -PI * 0.5
		var sh_end: float = sh_start + TAU * sh_frac
		var sh_seg: int = max(8, int(36.0 * sh_frac))
		draw_arc(pos, sh_ring_r, sh_start, sh_end, sh_seg,
				_alpha_mul(Color(0.45, 0.85, 1.0), alpha), 3.0)


func _draw_overflow_circle(pos: Vector2, overflow_n: int, radius: float,
		color: Color) -> void:
	draw_circle(pos, radius, color.darkened(0.3))
	draw_arc(pos, radius, 0.0, TAU, 20, color.lightened(0.3), 1.5)
	var fsz: int = int(round(10.0 * HexGrid.DISPLAY_SCALE))
	var txt := "+%d" % overflow_n
	var tsz := ThemeDB.fallback_font.get_string_size(txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	draw_string(ThemeDB.fallback_font,
			pos - tsz * 0.5 + Vector2(0.0, 5.0 * HexGrid.DISPLAY_SCALE),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color.WHITE)


func _draw_cell_badge(cell: Vector2i, c0: int, c1: int) -> void:
	var text:   String
	var bg_col: Color
	if c0 > 0 and c1 > 0:
		text   = "%dv%d" % [c0, c1]
		bg_col = Color(0.72, 0.1, 0.1, 0.92)
	elif c0 > 1:
		text   = "x%d" % c0
		bg_col = Color(0.1, 0.22, 0.65, 0.88)
	else:
		text   = "x%d" % c1
		bg_col = Color(0.55, 0.1, 0.1, 0.88)
	# Pilots now render outside the tile, so the tile centre is free for the badge.
	var center := _bs.cell_center(cell)
	var s: float = HexGrid.DISPLAY_SCALE
	var bsize  := Vector2(36.0, 20.0) * s
	var bpos   := center - bsize * 0.5
	draw_rect(Rect2(bpos, bsize), bg_col)
	var fsz: int = int(round(13.0 * s))
	var tsz := ThemeDB.fallback_font.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	draw_string(ThemeDB.fallback_font, center + Vector2(-tsz.x * 0.5, 5.0 * s),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color.WHITE)
