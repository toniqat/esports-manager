class_name BattleRenderer
extends Node2D

@onready var _bs: BattleSim = get_parent() as BattleSim

# 대상 지정 카드를 끌고 있을 때, **찍을 수 있는 파일럿**의 마커가 도달하는 배율.
# 예전에는 1.06~1.14 사이를 오가는 펄스(EMPHASIS_PULSE_HZ)였는데, 드래그해서
# 얼굴 위에 놓는 조작에서는 크기가 계속 변하는 대상이 오히려 겨누기 어려웠다 —
# 지금은 **고정 목표값**이고, 거기에 닿기까지 `EMPHASIS_TWEEN_SEC` 동안 부드럽게
# 자란다(도달 후에는 미동도 없다). 나머지는 전부 딤드되므로 커진 얼굴만 남는다.
# 2.0 에서 **1.5** 로 낮췄다: 2배는 한 칸에 두세 명이 선 무리를 화면 밖까지
# 밀어낼 만큼 벌려 놓았고, 얼굴 하나가 옆 레인까지 침범해 어느 타일 이야기인지가
# 흐려졌다.
#
# **이 배율은 초상만이 아니라 배치도 탄다.** 한 칸에 두세 명이 서 있으면 커진
# 얼굴들이 서로를 덮어 어느 쪽을 눌렀는지 알 수 없게 되므로,
# `_build_pilot_render_layout` 이 육각 링의 반지름을 같은 배율로 벌린다
# (그리고 `_draw_arrow_to_tile` 이 그만큼 긴 화살표를 그린다).
const TARGET_EMPHASIS_SCALE: float = 1.5

## 강조가 켜지고 꺼지는 데 걸리는 시간(s). 1.0 ↔ TARGET_EMPHASIS_SCALE 전 구간을
## 이 시간에 선형으로 지난다.
##
## **왜 애니메이션인가.** 예전에는 배율이 즉시 튀었다 — 카드를 집는 순간 전장의
## 얼굴 서넛이 한 프레임 만에 1.5배로 부풀고 무리가 좌우로 벌어졌으므로, 무엇이
## 대상인지보다 화면이 흔들렸다는 인상이 먼저 왔다. 배치(육각 링의 반지름)
## 와 히트 반경(`pilot_marker_radius`)이 전부 이 한 값에서 나오므로, 여기를
## 보간하면 초상 · 간격 · 화살표 길이 · 클릭 반경이 **함께** 자란다.
##
## 0.15 → **0.05** 로 줄였다. 0.15초는 "즉시 튄다"는 인상은 지웠지만, 카드를 든
## 손이 이미 대상 위로 가 있는데 얼굴이 아직 자라는 중인 구간이 남았다 — 강조는
## 겨누기 **전에** 끝나 있어야 하는 신호다.
const EMPHASIS_TWEEN_SEC: float = 0.05

## PilotData → 지금 프레임의 강조 배율(1.0 ~ TARGET_EMPHASIS_SCALE). `_process`
## 가 매 프레임 목표값 쪽으로 밀고, 그리기 · 배치 · 히트 테스트가 전부 이 값을
## 읽는다. 살아 있는 파일럿만 담기므로 재시작으로 로스터가 바뀌어도 남지 않는다.
var _emphasis_now: Dictionary = {}

## 강조로 벌어진 무리를 화면 안에 넣을 때 가장자리에서 남기는 여백.
const SCREEN_EDGE_PAD: float = 6.0


# ─── 말풍선 꼬리(화살표)의 관성 ───────────────────────────────────────────────
# **이동 트윈이 도는 동안 화살표는 크기도 방향도 바꾸지 않는다.** 예전에는 끝점을
# 언제나 "지금 프레임의 타일 중심"으로 잡았는데, `_render_cell` 이 이동이 시작된
# 프레임부터 곧장 **도착 칸**을 돌려주므로 화살표가 초상보다 먼저 목적지를 가리키며
# 0.3초 내내 회전하고 늘어났다 — 파일럿은 아직 출발 칸에 있는데 꼬리만 다음 칸에
# 가 있는 그림이다. 지금은 이동이 시작되는 프레임에 **직전 프레임의 화살표 벡터**를
# 붙들어(`_arrow_hold`) 초상에 강체로 매달고, **도착한 뒤에야** 회전 + 신축으로
# 제 칸을 다시 가리킨다.
#
# 상태는 셋으로 갈린다:
#   `_arrow_hold`     — 붙들고 있는(그리고 정착의 출발점이 되는) 벡터
#   `_arrow_settle_t` — 도착 후 경과 시간. `_process` 가 민다
#   `_arrow_vec_now`  — 이번 프레임에 실제로 그린 벡터(= 다음 이동이 붙들 값)
#
## 도착 후 화살표가 제 타일을 다시 가리키기까지 걸리는 시간(s). 이동 트윈
## (`BattleSim.ANIM_MOVE_DUR` 0.30) 과 합쳐도 턴 간격(0.5초)을 넘지 않아야
## 한다 — 넘으면 다음 이동이 아직 정착 중인 화살표를 붙들어, 어긋난 각도가
## 턴을 넘어 누적된다.
const ARROW_SETTLE_SEC: float = 0.15

var _arrow_hold: Dictionary = {}
var _arrow_settle_t: Dictionary = {}
var _arrow_vec_now: Dictionary = {}


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
	# 상시 갱신이 필요한 것은 둘뿐이다 — 피해 수치 팝업과, 켜지거나 꺼지는 중인
	# 대상 강조. 둘 다 멈춰 있으면 재draw 하지 않는다(대상 지정 상태가 **바뀌는**
	# 순간은 CardTargetingOverlay._request_redraw() 가 따로 걷어찬다).
	var dirty: bool = _advance_popups(delta)
	if _advance_emphasis(delta):
		dirty = true
	# 도착 후의 화살표 정착. 이동 트윈이 끝나면 BattleSim 은 더 이상 재draw 를
	# 걷어차지 않으므로, 이 구간의 프레임은 여기서 만들어야 한다.
	if _advance_arrow_settle(delta):
		dirty = true
	if dirty:
		queue_redraw()


## 각 파일럿의 강조 배율을 목표값 쪽으로 `EMPHASIS_TWEEN_SEC` 페이스로 민다.
## 아직 움직이는 중이면 true(= 계속 다시 그려야 한다).
##
## 목표에 닿은 1.0 은 dict 에서 지운다 — 기본값이 1.0 이므로 남겨 둘 이유가 없고,
## 매 판 새 PilotData 가 들어오는 자리에 죽은 키가 쌓이지 않는다.
func _advance_emphasis(delta: float) -> bool:
	var step: float = (TARGET_EMPHASIS_SCALE - 1.0) \
			* (delta / maxf(0.0001, EMPHASIS_TWEEN_SEC))
	var moving: bool = false
	for raw in _bs.pilots:
		var p := raw as PilotData
		var want: float = _pilot_emphasis_target(p)
		var have: float = float(_emphasis_now.get(p, 1.0))
		if is_equal_approx(have, want):
			continue
		have = move_toward(have, want, step)
		moving = true
		if is_equal_approx(have, 1.0):
			_emphasis_now.erase(p)
		else:
			_emphasis_now[p] = have
	return moving


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
	# 전장을 뜬 파일럿이 붙들고 있던 화살표 기하를 버린다.
	_prune_arrow_state()
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
	if draw_dim:
		_draw_targeting_tile_dim(_undimmed_cells())
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
	var by_cell := _group_pilots_by_render_cell()

	# 돌진 중인 시전자가 있는 칸을 **맨 마지막에** 그린다. 돌진은 대상 초상과
	# 절반쯤 겹치는 것이 연출의 전부라, 대상 칸이 나중에 그려지면 파고든 얼굴이
	# 그 뒤로 숨어 버린다(칸 순회는 Dictionary 순서라 그때그때 다르다).
	for pos in _lunging_cells_last(by_cell.keys()):
		var pv := pos as Vector2i
		var pilots: Array = by_cell[pv] as Array
		var c0: int = 0
		for raw in pilots:
			if (raw as PilotData).team == 0:
				c0 += 1
		var c1: int = pilots.size() - c0
		_draw_pilot_cell(pv, pilots)
		# Skip the cross-team collision badge (1v1, 2v2 …) — it added noise on
		# top of the pilot stacks. Keep the single-team multi-pilot tag (x2, x3).
		if pilots.size() > 1 and (c0 == 0 or c1 == 0):
			_draw_cell_badge(pv, c0, c1)


# 셀 순회 순서 — 돌진 중인 파일럿이 서 있는 칸만 뒤로 미룬다. 나머지 순서는
# 건드리지 않으므로 평소 그림은 한 픽셀도 달라지지 않는다.
func _lunging_cells_last(cells: Array) -> Array:
	var lunging: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.anim_lunge_phase != 0:
			lunging[_render_cell(p)] = true
	if lunging.is_empty():
		return cells
	var normal: Array = []
	var late: Array = []
	for c in cells:
		if lunging.has(c as Vector2i):
			late.append(c)
		else:
			normal.append(c)
	return normal + late


# Group renderable pilots by their *render* cell (not grid_pos): a pilot in
# recall fade-out is drawn at the cell they came from, so they don't crowd the
# HQ layout until the fade-in phase starts.
#
# **두 팀이 한 배열에 담긴다.** 초상화가 앉는 6슬롯은 셀 하나가 팀 구분 없이
# 공유하기 때문이다 — 예전에는 "적은 타일 위 / 아군은 타일 아래" 라 팀마다 따로
# 풀어도 서로 부딪힐 일이 없었지만, 지금은 방향이 **각자의 이동 방향**에서 나오
# 므로 같은 칸의 두 팀이 같은 슬롯을 노릴 수 있다.
#
# 배열 순서는 `_bs.pilots` 순서(= 스폰 순서)다. 슬롯 배정이 순서에 의존하는
# 그리디라, 여기가 프레임마다 흔들리면 배치가 통째로 떨린다.
func _group_pilots_by_render_cell() -> Dictionary:
	var by_cell: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not _is_renderable(p):
			continue
		var rcell := _render_cell(p)
		if not by_cell.has(rcell):
			by_cell[rcell] = []
		(by_cell[rcell] as Array).append(p)
	return by_cell


# Builds the PilotData → Vector2 marker_pos lookup shared by the drawing pass,
# the dim overlay and the targeting hit test. 모든 렌더 가능한 파일럿이 자기
# 슬롯을 받는다 — `+N` 오버플로 원은 사라졌고, 7명째부터는 바깥 링으로 나간다.
#
# 배정은 **전장 전체를 한 번에 훑는 그리디**다: 앞서 자리를 잡은 마커와 겹치는
# 슬롯은 건너뛰고 시계방향으로 다음 슬롯을 찾는다. 그래서 위아래로 붙은 두 칸이
# 서로를 향한 슬롯을 고르는 일(= 초상화가 겹치는 유일한 구조적 원인)이 없다.
func _build_pilot_render_layout() -> Dictionary:
	var out: Dictionary = {}
	var by_cell := _group_pilots_by_render_cell()
	var cells: Array = by_cell.keys()
	# 순회 순서가 곧 우선순위(먼저 도는 칸이 자기 기본 방향을 지킨다)이므로
	# 좌표로 정렬한다 — Dictionary 순서에 맡기면 같은 상황에서 프레임마다 다른
	# 칸이 양보하게 되어 배치가 떨린다.
	cells.sort_custom(_compare_cells)
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	# 이미 자리를 잡은 마커의 **강조 이전** 좌표. 슬롯 배정을 강조 배율과 무관하게
	# 두기 위한 것이다 — 강조까지 반영하면 카드를 집을 때마다 전장의 슬롯이 새로
	# 풀려 배치가 통째로 다시 섞인 것처럼 보인다.
	var placed: Array = []
	for raw_cell in cells:
		var cell := raw_cell as Vector2i
		var pilots: Array = by_cell[cell] as Array
		var tile_center := _bs.cell_center(cell)
		var em: float = _group_emphasis(pilots)
		var used: Dictionary = {}
		var slots: Array = []
		for raw in pilots:
			var slot: int = _pick_slot(tile_center,
					pilot_display_dir_index(raw as PilotData), base_r, used, placed)
			used[slot] = true
			placed.append(tile_center + _slot_offset(slot, base_r))
			slots.append(slot)
		var positions: Array = []
		for raw_slot in slots:
			positions.append(tile_center + _slot_offset(raw_slot as int, base_r * em))
		positions = _clamp_group_on_screen(positions, base_r * em)
		for i in range(pilots.size()):
			out[pilots[i]] = positions[i] as Vector2
	return out


func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


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
# 초상화는 언제나 타일 **바깥**에 앉고, 뒤에서 타일 중심을 가리키는 팀 색 삼각형
# (말풍선 꼬리)이 어느 칸 이야기인지를 말한다. 앉을 자리는 타일을 둘러싼 육각
# 6슬롯이고, 그 중 어느 슬롯을 고르는지는 아래 두 절이 정한다.

# Pilot dimensions track HexGrid.DISPLAY_SCALE so they stay proportional to
# tile size. Base values are calibrated against the unscaled (1.0x) hex.
const PILOT_RADIUS_BASE := 31.5

## 초상화가 앉을 수 있는 6방향 — 육각 이웃과 정확히 같은 방향이고, 배열 순서가
## **시계방향**(화면 기준 y 아래)이다. 슬롯이 막히면 이 배열의 다음 칸으로 돈다.
## 인덱스: 0=N 1=NE 2=SE 3=S 4=SW 5=NW.
const HEX_DIRS: Array[Vector2] = [
	Vector2( 0.0,       -1.0),   # N
	Vector2( 0.8660254, -0.5),   # NE
	Vector2( 0.8660254,  0.5),   # SE
	Vector2( 0.0,        1.0),   # S
	Vector2(-0.8660254,  0.5),   # SW
	Vector2(-0.8660254, -0.5),   # NW
]

## 초상화 사이에 남기는 최소 여백(px). 링 반지름과 충돌 판정이 같은 값에서
## 나오므로 둘이 어긋날 수 없다.
const MARKER_GAP := 6.0

## 몇 겹까지 링을 만들 것인가. 한 링이 6자리이므로 3겹 = 18자리 — 5v5 전원이 한
## 칸에 몰려도(10명) 남는다. 이 위로는 겹치더라도 자리를 준다.
const SLOT_RINGS := 3


# 이 무리(= 같은 셀에 선 **양 팀 전원**)의 배치에 곱해지는 배율. 강조된 파일럿이
# 한 명이라도 있으면 무리 전체가 그 배율로 벌어진다 — 슬롯은 셀 단위로 풀리므로
# 사람마다 다른 간격을 줄 수 없고, 겹치지 않으려면 가장 큰 쪽에 맞춰야 한다.
func _group_emphasis(pilots: Array) -> float:
	var em: float = 1.0
	for raw in pilots:
		em = maxf(em, _pilot_emphasis_scale(raw as PilotData))
	return em


## 링 `ring`(0부터)의 반지름. **이웃 슬롯이 60° 간격이므로 반지름 d 인 링에서
## 이웃 슬롯 사이 거리는 정확히 d 다** — 그래서 지름 + 여백을 그대로 반지름으로
## 쓰면 한 링 안의 초상화가 서로 닿지 않는다. 바깥 링은 그 배수라 반지름 방향
## 으로도 같은 간격이 확보된다.
func _ring_radius(ring: int, r: float) -> float:
	return (r * 2.0 + MARKER_GAP) * float(ring + 1)


## 슬롯 번호(= ring * 6 + 방향 인덱스) → 타일 중심에서의 변위.
func _slot_offset(slot: int, r: float) -> Vector2:
	@warning_ignore("integer_division")
	var ring: int = slot / 6
	return HEX_DIRS[slot % 6] * _ring_radius(ring, r)


## 이 파일럿이 앉을 슬롯. **기본 방향에서 시계방향으로** 돌며 (1) 같은 칸에서
## 아직 안 쓴 자리이고 (2) 이미 놓인 어떤 마커와도 겹치지 않는 첫 자리를 잡는다.
## 안쪽 링 6자리를 다 돌면 그대로 바깥 링으로 나간다 — 그만큼 타일에서 멀어지고
## 화살표가 길어져, 붐비는 칸일수록 "어느 타일인지"가 화살표로 읽힌다.
##
## 겹침 판정이 **다른 칸의 마커까지** 본다는 것이 요점이다: 위아래로 붙은 두 칸이
## 서로를 향한 슬롯(위 칸의 S, 아래 칸의 N)을 고르면 초상화 두 개가 그 사이에서
## 정면으로 겹치는데, 이것이 전장에서 얼굴이 가려지는 유일한 구조적 원인이었다.
func _pick_slot(tile_center: Vector2, base_dir: int, r: float,
		used: Dictionary, placed: Array) -> int:
	for ring in range(SLOT_RINGS):
		for step in range(6):
			var slot: int = ring * 6 + (base_dir + step) % 6
			if used.has(slot):
				continue
			if _slot_collides(tile_center + _slot_offset(slot, r), r, placed):
				continue
			return slot
	# 사방이 막혔으면 겹치더라도 빈 슬롯을 준다 — 그리지 않는 것보다 낫다.
	for ring in range(SLOT_RINGS):
		for step in range(6):
			var slot: int = ring * 6 + (base_dir + step) % 6
			if not used.has(slot):
				return slot
	return base_dir


func _slot_collides(pos: Vector2, r: float, placed: Array) -> bool:
	# 링 간격(지름 + MARKER_GAP)보다 살짝 관대하게 잡는다 — 같은 링의 이웃 슬롯이
	# 정확히 그 거리라, 판정을 같은 값으로 두면 부동소수 오차 하나로 멀쩡한 자리가
	# 반려된다.
	var min_d: float = r * 2.0 + MARKER_GAP * 0.5
	for raw in placed:
		if pos.distance_to(raw as Vector2) < min_d:
			return true
	return false


# ─── 초상화가 앉는 기본 방향 ─────────────────────────────────────────────────
# **이동 방향의 정반대**다. 파일럿은 자기가 가려는 쪽을 비워 두고 지나온 쪽에
# 선다 — 오른쪽 레인을 NE 로 밀고 올라가는 팀0 은 타일 왼쪽 아래(SW)에, 그 구간을
# 반대로 내려오는 팀1 은 오른쪽 위(NE)에 선다. 미드는 위/아래라 예전 규칙(적 위 /
# 아군 아래)과 그림이 같고, 왼쪽 레인은 오른쪽 레인의 좌우 반전이 저절로 나온다.
#
# 방향의 출처는 둘로 갈린다:
#   • 레인 파일럿 — **레인 경로**(다음 웨이포인트)를 향하는 방향. 교전으로 멈춰
#     서 있거나 한 턴 밀려나도 표시가 뒤집히지 않고, 같은 구간의 팀원이 늘 같은
#     쪽으로 정렬된다.
#   • 정글러 — **직전에 서 있던 칸**에서 지금 칸으로 온 방향. 정글에는 경로가
#     없고 로밍 목적지가 수시로 바뀌므로 지나온 자취가 유일하게 안정적인 신호다.

## `p` 의 기본 슬롯 방향(HEX_DIRS 인덱스). 공개 — BattleSim 의 대체 좌표 계산이
## 같은 답을 써야 한다.
func pilot_display_dir_index(p: PilotData) -> int:
	return _nearest_dir_index(-_pilot_travel_dir(p))


## 이 파일럿이 향하고 있는 방향(픽셀, 정규화 전). 아무 신호도 없으면 적 HQ 쪽을
## 본다 — 개시 직후처럼 아직 한 칸도 움직이지 않았을 때의 답이다.
func _pilot_travel_dir(p: PilotData) -> Vector2:
	var here := _render_cell(p)
	var here_px := _bs.cell_center(here)
	if p.is_guerrilla:
		if p.prev_grid_pos != here:
			return here_px - _bs.cell_center(p.prev_grid_pos)
	else:
		var wp := _peek_waypoint(p, here)
		if wp != here:
			return _bs.cell_center(wp) - here_px
	var hq: Vector2i = _bs.ENEMY_HQ_POS if p.team == 0 else _bs.PLAYER_HQ_POS
	if hq != here:
		return _bs.cell_center(hq) - here_px
	# 적 HQ 칸 위에 선 파일럿 — 더 갈 곳이 없으니 팀의 진행 방향을 그대로 쓴다.
	return Vector2(0.0, -1.0) if p.team == 0 else Vector2(0.0, 1.0)


## `SimulationCore.current_waypoint` 의 **부작용 없는** 사본. 원본은 지나친
## 웨이포인트를 만나면 `waypoint_idx` 를 밀어 올리는데, 그리기 중에 시뮬 상태를
## 건드리면 화면이 게임을 바꾸는 셈이 된다.
func _peek_waypoint(p: PilotData, here: Vector2i) -> Vector2i:
	var paths: Array = _bs.LANE_PATHS_TEAM0 if p.team == 0 else _bs.LANE_PATHS_TEAM1
	if p.lane < 0 or p.lane >= paths.size():
		return here
	var path: Array = paths[p.lane] as Array
	if path.is_empty():
		return here
	var idx: int = clampi(p.waypoint_idx, 0, path.size() - 1)
	while idx < path.size() - 1 and (path[idx] as Vector2i) == here:
		idx += 1
	return path[idx] as Vector2i


func _nearest_dir_index(v: Vector2) -> int:
	if v.length_squared() < 0.0001:
		return 3   # S — 팀0 의 평소 방향
	var n := v.normalized()
	var best: int = 0
	var best_dot: float = -INF
	for i in range(HEX_DIRS.size()):
		var d: float = n.dot(HEX_DIRS[i])
		if d > best_dot:
			best_dot = d
			best = i
	return best


# 무리 **전체를 통째로 밀어** 화면 안에 넣는다.
#
# 강조로 벌어진 가장자리 레인의 2~3인 무리는 그대로 두면 화면 밖으로 잘려 나가는
# 데, 잘린 얼굴은 볼 수도 누를 수도 놓을 수도 없다. 마커를 하나씩 따로 밀면
# 애써 벌려 놓은 간격이 도로 무너져 다시 겹치므로 **평행 이동**이어야 한다.
# 화살표는 여전히 각자 자기 타일을 가리키므로 누가 어느 칸에 있는지는 유지된다.
# 무리가 화면보다 넓은 극단에서는 왼쪽/위쪽 가장자리에 붙인다.
func _clamp_group_on_screen(positions: Array, draw_r: float) -> Array:
	if positions.is_empty():
		return positions
	var vp: Vector2 = get_viewport_rect().size
	var pad: float = draw_r + SCREEN_EDGE_PAD
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for raw in positions:
		var v := raw as Vector2
		min_p = Vector2(minf(min_p.x, v.x), minf(min_p.y, v.y))
		max_p = Vector2(maxf(max_p.x, v.x), maxf(max_p.y, v.y))
	var shift := Vector2.ZERO
	if max_p.x + pad > vp.x:
		shift.x = vp.x - pad - max_p.x
	if min_p.x + shift.x - pad < 0.0:
		shift.x = pad - min_p.x
	if max_p.y + pad > vp.y:
		shift.y = vp.y - pad - max_p.y
	if min_p.y + shift.y - pad < 0.0:
		shift.y = pad - min_p.y
	if shift == Vector2.ZERO:
		return positions
	var out: Array = []
	for raw in positions:
		out.append((raw as Vector2) + shift)
	return out


# 한 칸의 파일럿 전원(양 팀)을 그린다. **자리는 여기서 풀지 않는다** —
# `_draw()` 가 프레임 앞머리에 `_build_pilot_render_layout()` 으로 이미 배정해
# 두었고, 딤 오버레이와 히트 테스트도 같은 표를 읽는다.
func _draw_pilot_cell(cell: Vector2i, pilots: Array) -> void:
	var tile_center := _bs.cell_center(cell)
	var radius: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	for raw in pilots:
		var pilot := raw as PilotData
		var is_enemy: bool = pilot.team == 1
		var team_color := Color(0.9, 0.2, 0.2) if is_enemy else Color(0.2, 0.5, 0.9)
		var pos := _pilot_marker_pos(pilot) + _pilot_anim_offset(pilot)
		var alpha := _pilot_anim_alpha(pilot)
		# 쓰러진 파일럿은 팀 색까지 함께 죽여 딤드로 읽히게 한다. 초상 자체의
		# 딤은 _draw_pilot_circle 이 같은 배율로 건다.
		var marker_color: Color = team_color
		if pilot.anim_death_phase != 0:
			marker_color = team_color * _bs.ANIM_DEATH_TINT
		# 화살표 배율은 **그 파일럿 자신의** 강조다(무리 전체가 아니라):
		# 한 무리 안에 강조 대상과 아닌 사람이 섞이면 초상 크기가 서로
		# 다르고, 화살표는 자기 초상 바깥에서 시작해야 한다.
		# 끝점은 타일 중심이 아니라 `_arrow_aim_point` 가 정한다 — 이동 중에는
		# 꼬리가 크기 · 방향을 그대로 유지한 채 초상을 따라가고, 도착한 뒤에야
		# 회전 + 신축으로 제 타일을 다시 가리킨다.
		_draw_arrow_to_tile(pos, _arrow_aim_point(pilot, pos, tile_center),
				radius, marker_color, alpha, _pilot_emphasis_scale(pilot))
		_draw_pilot_circle(pilot, pos, radius, marker_color, alpha)


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
	# 공격 카드 돌진은 다른 무엇에도 얹힌다 — 이동/복귀와 배타적인 elif 사슬에
	# 넣지 않는 이유는, 돌진 중에도 대상이 흔들리듯 시전자가 흔들릴 수 있고 오프셋은
	# 서로 독립이기 때문이다. 계산 자체는 BattleSim 이 소유한다(연출 상수와
	# 단계 전환이 거기 모여 있다).
	off += _bs.pilot_lunge_offset(p)
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


# Targeting underlays — the paint that marks **what can be dropped on**.
#
# 딤과 강조의 규칙이 모드마다 다르고, 그 규칙의 한쪽 절반이 여기다
# (나머지 절반은 _undimmed_cells / _draw_targeting_pilot_dim /
#  _pilot_emphasis_scale).
#
#   • PILOT    — 타일은 대상이 아니므로 **하나도 칠하지 않고 전부 딤드**한다.
#                남는 것은 2배로 커진 유효 파일럿뿐. 예전에는 사거리 안 타일을
#                노랗게 칠했는데, 어차피 그 타일에는 놓을 수 없으니 겨눌 곳을
#                가리는 노이즈였다.
#   • LOCATION — 유효 셀만 초록으로 칠하고 나머지는 전부 딤드. 사거리 노란 채움은
#                사라졌다 — 유효 셀 집합이 이미 사거리의 부분집합이고, 사거리
#                무제한 카드(약탈 / 정글 파밍)에서는 사거리 표시 자체가 전장
#                전체라 아무것도 말해 주지 않았다.
#   • PREVIEW  — 교전 영역(시전자 셀 + 인접 6칸)을 노랗게. 여기서는 영역 자체가
#                카드가 말하는 내용이다.
func _draw_targeting_underlays() -> void:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or not to.is_visualizing():
		return
	var hg: HexGrid = _bs.hex_grid
	if to.mode == CardTargetingOverlay.Mode.PREVIEW:
		for raw in to.area_cells.keys():
			var c := raw as Vector2i
			var pts := hg.hex_corners(_bs.cell_center(c))
			draw_colored_polygon(pts, Color(1.0, 0.85, 0.30, 0.22))
			draw_polyline(_close_polygon(pts),
					Color(1.0, 0.85, 0.30, 0.85), 3.0, true)
	elif to.mode == CardTargetingOverlay.Mode.LOCATION:
		for raw in to.valid_cells.keys():
			var c := raw as Vector2i
			var pts := hg.hex_corners(_bs.cell_center(c))
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
			# 강조 배율만큼 커진 마커 **바깥**에 링이 걸리도록 같은 배율을 탄다.
			var radius: float = pilot_marker_radius(picked) + 10.0
			draw_arc(pos, radius, 0.0, TAU, 36,
					Color(0.30, 0.95, 1.0, 0.95), 4.0)
	elif to.mode == CardTargetingOverlay.Mode.LOCATION:
		var c := to.pending_pick as Vector2i
		var ctr := _bs.cell_center(c)
		var pts := hg.hex_corners(ctr)
		draw_polyline(_close_polygon(pts),
				Color(0.30, 0.95, 1.0, 0.95), 5.0, true)


# The cells that stay bright while a 대상 지정 카드 is lifted — everything else
# takes the black dim. The mirror image of _draw_targeting_underlays: whatever
# gets painted there is exactly what is spared here.
#
# **PILOT 은 빈 집합**이다 — 타일은 그 카드의 대상이 아니므로 전부 어두워지고,
# 밝게 남는 것은 마커(파일럿)뿐이다.
func _undimmed_cells() -> Dictionary:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	var out: Dictionary = {}
	if to == null:
		return out
	match to.mode:
		CardTargetingOverlay.Mode.PREVIEW:
			for raw in to.area_cells.keys():
				out[raw as Vector2i] = true
		CardTargetingOverlay.Mode.LOCATION:
			for raw in to.valid_cells.keys():
				out[raw as Vector2i] = true
	return out


# Tile dim. Drawn BEFORE pilots / HQ bars so an offset pilot marker that
# visually intrudes into an adjacent dimmed tile is not covered by that
# neighbour's dim — the marker's own dim (if any) is a separate disc drawn
# after the pilots.
func _draw_targeting_tile_dim(bright_cells: Dictionary) -> void:
	var hg: HexGrid = _bs.hex_grid
	var dim_color := Color(0.0, 0.0, 0.0, 0.60)
	for raw in _bs.tiles_layer.get_used_cells():
		var c := raw as Vector2i
		if bright_cells.has(c):
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
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if not to.should_dim_pilot(p):
			continue
		var marker_pos := _pilot_marker_pos(p)
		# Cover the HP ring outside the portrait too — slightly larger than
		# the portrait radius. 딤드 대상은 강조 대상이 아니므로 배율은 사실상
		# 1.0 이지만, 반지름은 그리는 쪽과 같은 한 곳에서 받아 온다.
		draw_circle(marker_pos, pilot_marker_radius(p) + 4.0, dim_color)


# Rendered marker position for the pilot — reads the cached layout built in
# _draw(). 지금은 렌더 가능한 파일럿이 모두 슬롯을 받으므로 이 폴백은 레이아웃이
# 아직 한 번도 안 돌았을 때(첫 프레임 이전)나 렌더 대상이 아닌 파일럿을 물었을
# 때만 걸린다.
func _pilot_marker_pos(p: PilotData) -> Vector2:
	if _pilot_render_layout.has(p):
		return _pilot_render_layout[p] as Vector2
	return pilot_marker_pos_fallback(p)


## 레이아웃 표에 없는 파일럿의 **대체** 마커 좌표 — 자기 칸에 혼자 선 것으로 치고
## 기본 방향(= 이동 방향의 반대)의 첫 링에 앉힌다. 공개인 이유는 `BattleSim` 과
## `CardTargetingOverlay` 의 폴백 경로가 같은 답을 써야 하기 때문이다.
func pilot_marker_pos_fallback(p: PilotData) -> Vector2:
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	return _bs.cell_center(_render_cell(p)) \
			+ _slot_offset(pilot_display_dir_index(p), base_r)


## Fresh `PilotData → Vector2` marker map — the same per-cell stack solve
## `_draw()` runs. Public because CardTargetingOverlay's PILOT hit test needs
## the *drawn* marker of each pilot: several pilots sharing a cell each get
## their own slot, and aiming at the tile centre instead can only ever resolve
## to one of them. Rebuilt on call (10 pilots) so a click never reads a layout
## from before the last move.
func pilot_marker_positions() -> Dictionary:
	return _build_pilot_render_layout()


## 지금 실제로 그려지는 마커 반지름 — 대상 지정 강조 배율이 반영된 값.
## `CardTargetingOverlay._hit_test_pilot` 이 클릭 반경을 여기서 받는다: 강조로
## 2배가 된 초상은 타일 반지름보다 커서, 고정 상수로 재면 얼굴 바깥 테두리를
## 눌렀을 때 대상이 잡히지 않는다.
func pilot_marker_radius(p: PilotData) -> float:
	return PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE * _pilot_emphasis_scale(p)


# 지금 프레임의 강조 배율 — `_advance_emphasis` 가 목표값으로 밀고 있는 값이다.
# 그리기 · 배치 · 히트 반경이 전부 여기를 읽으므로 셋이 어긋날 수 없다.
func _pilot_emphasis_scale(p: PilotData) -> float:
	return float(_emphasis_now.get(p, 1.0))


# 이 파일럿이 **지금 찍을 수 있는 대상인가** — 보간의 목표값(1.0 또는
# TARGET_EMPHASIS_SCALE). PILOT 모드는 valid_pilots, PREVIEW 는
# preview_participants 가 강조 대상이다.
#
# 이미 찍어 둔 대상(pending_pick)도 **같이 커진 채로 둔다** — 시안 링이 그 위에
# 따로 붙으므로 구분은 되고, 여기서만 1.0 으로 되돌리면 카드를 끌고 지나갈 때
# 얼굴이 커졌다 작아졌다 하며 도로 펄스처럼 보인다.
func _pilot_emphasis_target(p: PilotData) -> float:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or not to.is_visualizing():
		return 1.0
	var emphasized: bool = false
	match to.mode:
		CardTargetingOverlay.Mode.PILOT:
			emphasized = to.valid_pilots.has(p)
		CardTargetingOverlay.Mode.PREVIEW:
			emphasized = p in to.preview_participants
	return TARGET_EMPHASIS_SCALE if emphasized else 1.0


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


# ─── 화살표 관성 (이동 중 고정 → 도착 후 정착) ───────────────────────────────

## 이 파일럿의 화살표가 지금 **붙들려 있는가**. 이동 트윈이 도는 동안만 참이다 —
## 복귀 / 부활 / 전사는 `anim_move_dur` 를 0 으로 밀고 들어오므로 저절로 빠진다
## (순간이동에는 "따라가는 꼬리"라는 개념이 없다).
func _arrow_frozen(p: PilotData) -> bool:
	return p.anim_move_dur > 0.0


## 이번 프레임에 화살표가 가리킬 점. 셋 중 하나다 —
##   이동 중        → 붙든 벡터 그대로(크기 · 방향 불변, 초상만 따라 움직인다)
##   도착 직후      → 붙든 벡터에서 참값으로 회전 + 신축하는 중
##   그 밖(정지 중) → 참값(= 타일 중심)
##
## 부작용으로 `_arrow_vec_now` 에 이번 프레임의 벡터를 남긴다. 다음 이동이
## 붙드는 것이 바로 이 값이다 — 직전 프레임에 **실제로 보이던** 기하라야
## 이동이 시작되는 프레임에 화살표가 한 번도 튀지 않는다.
func _arrow_aim_point(p: PilotData, marker_pos: Vector2,
		tile_center: Vector2) -> Vector2:
	var want: Vector2 = tile_center - marker_pos
	var vec: Vector2 = want
	if _arrow_frozen(p):
		# 붙들 값을 새로 잡아야 하는 두 경우 — (1) 붙든 것이 아예 없다,
		# (2) **정착 중에 다음 이동이 시작됐다**(`_arrow_settle_t > 0`). (2)에서
		# 옛 hold 를 그대로 쓰면 정착으로 이미 돌아간 만큼 화살표가 되감긴다.
		if not _arrow_hold.has(p) or float(_arrow_settle_t.get(p, 0.0)) > 0.0:
			var prev: Vector2 = want
			if _arrow_vec_now.has(p):
				prev = _arrow_vec_now[p]
			_arrow_hold[p] = prev
			_arrow_settle_t[p] = 0.0
		vec = _arrow_hold[p]
	elif _arrow_hold.has(p):
		var t: float = clampf(
				float(_arrow_settle_t.get(p, 0.0)) / ARROW_SETTLE_SEC, 0.0, 1.0)
		var from_vec: Vector2 = _arrow_hold[p]
		# 감속(ease-out cubic) — 도착하자마자 크게 돌아 두고 마지막에 살며시 맞춘다.
		vec = _lerp_polar(from_vec, want, 1.0 - pow(1.0 - t, 3.0))
	_arrow_vec_now[p] = vec
	return marker_pos + vec


## **각도와 길이를 따로** 보간한다 — 끝점을 직선으로 lerp 하면 화살표가 도중에
## 짧아졌다 길어지고(두 벡터 사이를 가로지르므로) 회전으로 읽히지 않는다.
## 사용자에게 보여야 하는 것은 "돌면서 늘어난다" 두 가지다.
func _lerp_polar(a: Vector2, b: Vector2, t: float) -> Vector2:
	var la: float = a.length()
	var lb: float = b.length()
	if la < 0.001 or lb < 0.001:
		return a.lerp(b, t)
	# 각 차이는 ±PI 로 감아 짧은 쪽으로 돈다.
	var ang: float = a.angle() + wrapf(b.angle() - a.angle(), -PI, PI) * t
	return Vector2.from_angle(ang) * lerpf(la, lb, t)


## 정착 타이머를 민다. 아직 정착 중인 화살표가 하나라도 있으면 true(= 계속
## 다시 그려야 한다). 이동 중인 파일럿은 시간이 흐르지 않는다 — 붙든 벡터는
## 이동이 **끝나는** 순간부터 풀리기 시작해야 한다.
func _advance_arrow_settle(delta: float) -> bool:
	if _arrow_hold.is_empty():
		return false
	var moving: bool = false
	for raw in _arrow_hold.keys():
		var p := raw as PilotData
		if _arrow_frozen(p):
			continue
		var t: float = float(_arrow_settle_t.get(p, 0.0)) + delta
		if t >= ARROW_SETTLE_SEC:
			_arrow_hold.erase(p)
			_arrow_settle_t.erase(p)
		else:
			_arrow_settle_t[p] = t
		moving = true
	return moving


## 화면에서 사라진 파일럿의 화살표 상태를 버린다(사망 후 퇴장, 재시작으로 로스터
## 자체가 갈리는 경우). 그리기 표에 없는 파일럿은 다음에 나타날 때 어차피
## 순간이동이므로 붙들 기하가 없다.
func _prune_arrow_state() -> void:
	for raw in _arrow_vec_now.keys():
		if not _pilot_render_layout.has(raw):
			_arrow_vec_now.erase(raw)
			_arrow_hold.erase(raw)
			_arrow_settle_t.erase(raw)


# 마커에서 자기 타일을 가리키는 말풍선 꼬리. `aim_point` 는 **보통은 타일
# 중심이지만 이동 중에는 아니다** — 이동 트윈이 도는 동안 꼬리는 크기도 방향도
# 바꾸지 않고 초상에 매달려 따라가므로, 그때의 끝점은 `_arrow_aim_point` 가
# 붙들어 둔 벡터가 정한다.
#
# `em` 은 그 파일럿의 강조 배율이다. 초상이 커지면 화살표는 **더 바깥에서
# 시작해서 더 길게** 뻗어야 한다 — 시작점을 base 반지름에 두면 2배로 커진 초상이
# 화살표를 통째로 덮어 버린다(강조 대상, 즉 지금 겨누고 있는 파일럿에서만
# 사라지므로 하필 가장 필요한 순간에 사라진다). 길이도 같은 배율을 타되 타일
# 중심은 넘지 않는다.
func _draw_arrow_to_tile(circle_pos: Vector2, aim_point: Vector2,
		radius: float, color: Color, alpha: float = 1.0,
		em: float = 1.0) -> void:
	var to_tile := aim_point - circle_pos
	var dist: float = to_tile.length()
	if dist < 1.0:
		return
	var dir := to_tile / dist
	var perp := Vector2(-dir.y, dir.x)
	var draw_radius: float = radius * em
	var base_half: float = clamp(radius * 0.9, 10.0, 18.0) * em
	# **끝은 언제나 타일 중심 바로 앞이다.** 예전에는 마커 반지름에서 길이를
	# 뽑았는데(반지름 + 24px), 7명째부터 바깥 링에 앉는 마커는 타일에서 두 배로
	# 멀어져 그 길이로는 허공에 짧은 삼각형만 남고 어느 칸 이야기인지가 사라진다.
	# 거리에서 역산하면 멀어진 만큼 화살표가 길어져 "약간 멀어져 앉되 가리키는
	# 칸은 분명하다"가 성립한다. 중심을 찔러 넘어가지는 않는다 — 넘어가면 옆 칸을
	# 가리키는 것처럼 읽힌다.
	var tip_inset: float = clamp(radius * 0.55, 10.0, 26.0)
	var apex_len: float = dist - tip_inset
	if apex_len <= draw_radius * 0.75:
		return
	var apex := circle_pos + dir * apex_len
	var base := circle_pos + dir * (draw_radius * 0.6)
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
		color: Color, alpha: float = 1.0) -> void:
	# 찍을 수 있는 대상은 베이스 반지름에 TARGET_EMPHASIS_SCALE 을 곱해 크게
	# 그린다 — 나머지는 전부 딤드되므로 커진 얼굴만 남는다.
	var draw_radius: float = radius * _pilot_emphasis_scale(pilot)
	# Pilot portrait fills the slot. The team-colour HP ring (drawn outside the
	# portrait) is now the sole faction marker — the previous ring directly on
	# the portrait edge has been removed to avoid the double outline.
	var portrait: Texture2D = PilotImages.circle_for(pilot.pilot_id)
	# 쓰러진 파일럿의 초상은 마커 색과 같은 배율로 어두워진다.
	var portrait_tint: Color = _bs.ANIM_DEATH_TINT if pilot.anim_death_phase != 0 \
			else Color.WHITE
	# **초상 뒤의 흰 원.** `*_circle.png` 는 원 안쪽에도 투명한 부분이 있는 것이
	# 섞여 있어(실측: 40장 중 일부), 그대로 그리면 뒤의 타일 색이 얼굴을 뚫고
	# 비친다 — 특히 점령된 정글 타일 위에서 파일럿이 타일과 같은 색으로 물든다.
	# 원 그림 자체가 정사각형에 내접해 있으므로 같은 반지름의 원이 정확히 맞고,
	# 1px 줄여 안티에일리어싱된 가장자리 바깥으로 흰 테가 삐져나오지 않게 한다.
	# 딤/페이드는 초상과 같은 tint·alpha 를 타므로 배경만 밝게 남는 일은 없다.
	draw_circle(pos, maxf(1.0, draw_radius - 1.0), _alpha_mul(portrait_tint, alpha))
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
