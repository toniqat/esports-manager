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


# ─── 마커 글라이드 (초상화는 절대 순간이동하지 않는다) ───────────────────────
# **화면 위의 마커 좌표 하나가 통째로 보간된다.** 예전에는 칸 이동만 트윈하고
# (`PilotData.anim_move_t/dur`, 셀 중심끼리의 lerp) 슬롯 변화는 즉시 반영했는데,
# 슬롯 하나가 91px 이고 반대편으로 옮겨 앉으면 182px 라 **칸 사이 거리(140px)보다
# 큰 순간이동**이 매 턴 섞여 들어왔다. 옆 사람이 와서 비켜 앉는 파일럿은 아예
# 트윈이 걸리지 않아 그냥 튀었다.
#
# 지금은 마커 좌표를 **중심 + 슬롯 벡터**로 갈라 놓고 둘을 따로 민다:
#
#   center — 지나간 칸의 중심을 이은 **폴리라인**을 따라 간다. 그래서 2칸 이동
#            (정글러 move_range 2, 전진 카드 advance:N)이 중간 칸을 스쳐 지나가지
#             않고 실제로 밟은 대로 꺾인다. 경로는 `PilotData.anim_move_path`.
#   vec    — 타일 중심에서 슬롯까지의 변위. **각도는 중심 이동과 같은 박자로**
#            돌고(= 화살표 방향이 칸 이동과 동시에 바뀐다), **길이는 도착한 뒤에**
#            따라온다 — 붐비는 칸에 들어가느라 바깥 링으로 밀려날 때 이동 중에
#            화살표까지 늘어나면 무엇이 움직였는지가 흐려진다.
#
# 말풍선 꼬리는 이제 **언제나 `center` 를 가리킨다**. 초상이 실제로 미끄러지므로
# 꼬리도 같이 미끄러지면 되고, 예전의 관성 장치(`_arrow_hold` / `_arrow_settle_t` /
# `_arrow_vec_now` / `_lerp_polar`)는 통째로 삭제됐다 — 그것은 "초상은 출발 칸에
# 있는데 꼬리만 도착 칸을 가리킨다"를 가리려고 있던 것이다.

## 링(반지름)이 바뀔 때, 이동이 끝난 **뒤에** 길이가 따라오는 데 걸리는 시간(s).
## `BattleSim.ANIM_MOVE_DUR`(0.30) 과 합쳐도 턴 간격(0.5초)을 넘지 않아야 한다.
const MARKER_RADIUS_SETTLE_SEC: float = 0.15

## PilotData → 글라이드 상태. 스키마는 `_settled_glide` 참조.
var _glide: Dictionary = {}


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
	# 상시 갱신이 필요한 것은 셋이다 — 피해 수치 팝업, 켜지거나 꺼지는 중인 대상
	# 강조, 그리고 미끄러지는 중인 마커. 전부 멈춰 있으면 재draw 하지 않는다
	# (대상 지정 상태가 **바뀌는** 순간은 CardTargetingOverlay._request_redraw()
	#  가 따로 걷어찬다).
	var dirty: bool = _advance_popups(delta)
	if _advance_emphasis(delta):
		dirty = true
	# 목표 자리를 먼저 훑어 새 글라이드를 띄운 다음 시간을 민다. BattleSim 은
	# 이동 타이머를 더 이상 들고 있지 않으므로 이 구간의 프레임은 여기서 만든다.
	_sync_glide(_solve_slots())
	if _advance_glide(delta):
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
	_draw_front_line_overlays()
	_draw_captured_tile_overlays()
	_draw_jungle_camps()
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


# ─── 전선 / 정글 캠프 (성장치 수입이 나오는 자리) ────────────────────────────
## 전선 = 그 레인에서 양 팀의 살아 있는 최전방 포탑 **사이**. 레인 파일럿은 이
## 안에 살아서 서 있는 턴에만 성장치를 번다(`SimulationCore.award_frontline_income`).
##
## 화면에 그리는 이유는 하나다 — 수입이 위치에서 나오는데 그 위치가 안 보이면
## 플레이어는 자기가 왜 뒤처지는지 알 수 없다. 얇은 테두리로만 표시해 타일 색
## (정글 점령)과 경쟁하지 않게 한다.
const FRONT_LINE_COLOR: Color = Color(0.98, 0.86, 0.42, 0.30)
const FRONT_LINE_WIDTH: float = 2.0
## 캠프 마름모의 반지름 — hex_size 배율.
const CAMP_MARK_RATIO: float = 0.20
const CAMP_MARK_COLOR: Color = Color(0.65, 1.0, 0.55, 0.92)
## 적 소유 칸에 차 있는 캠프 — 같은 자리 · 같은 크기의 **속 빈** 마름모.
## 채우지 않는 것이 "있지만 지금은 못 먹는다"를 말한다. 색은 채운 쪽보다 **어둡다**
## — 타일이 흰색·연분홍이라 밝은 초록 외곽선은 면에 먹혀 사라진다(실측 확인).
const CAMP_MARK_ENEMY_COLOR: Color = Color(0.18, 0.48, 0.24, 0.90)
const CAMP_MARK_ENEMY_WIDTH: float = 2.5

func _draw_front_line_overlays() -> void:
	if _bs.sim_core == null or _bs.turrets.is_empty():
		return
	var hg: HexGrid = _bs.hex_grid
	for lane in _bs.sim_core.lane_corridor_count():
		for raw in _bs.sim_core.front_line_cells(lane).keys():
			var pts := hg.hex_corners(_bs.cell_center(raw as Vector2i))
			pts.append(pts[0])
			draw_polyline(pts, FRONT_LINE_COLOR, FRONT_LINE_WIDTH)


## 차 있는 정글 캠프에 작은 마름모를 하나 찍는다. **두 가지로 갈라 그린다.**
##   • 우리가 지금 먹을 수 있는 캠프 → 꽉 찬 초록 마름모.
##   • 적 소유 칸에 차 있는 캠프 → 같은 자리 · 같은 크기의 **속 빈** 마름모.
## 뺏을 값어치가 지금 있는지(= 그 칸의 캠프가 차 있는지)가 안 보이면 정글 점령이
## 판단의 대상이 되지 못한다. 채움 여부가 "우리 것 / 적 것"을 가르므로 둘을
## 헷갈릴 여지가 없다.
##
## 판정은 시뮬레이터와 같은 함수(`camp_harvestable` / `camp_charged`)를 지나므로
## 보이는 캠프와 먹히는 캠프가 어긋날 수 없다.
func _draw_jungle_camps() -> void:
	if _bs.sim_core == null:
		return
	var r: float = _bs.hex_grid.hex_size * CAMP_MARK_RATIO
	var foe: int = 1 - _bs.blue_team
	for raw in _bs.jungle_camps.keys():
		var cell := raw as Vector2i
		var c := _bs.cell_center(cell)
		var pts := PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r, 0),
				c + Vector2(0, r),  c + Vector2(-r, 0)])
		if _bs.sim_core.camp_harvestable(cell, _bs.blue_team):
			draw_colored_polygon(pts, CAMP_MARK_COLOR)
		elif _bs.sim_core.camp_charged(cell) 				and int(_bs.neutral_zone_cells.get(cell, -2)) == foe:
			var loop := PackedVector2Array(pts)
			loop.append(pts[0])
			draw_polyline(loop, CAMP_MARK_ENEMY_COLOR, CAMP_MARK_ENEMY_WIDTH)




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
# 공유하기 때문이다 — 기본 방향은 팀마다 반대쪽(팀0 S / 팀1 N)이라 출발점은
# 부딪히지 않지만, 겹침을 피해 **시계방향으로 도는 순간** 한 팀의 블록이 다른
# 팀의 슬롯 위로 넘어갈 수 있다. 한 표에서 같이 풀어야 그 자리를 서로 안다.
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
# the dim overlay and the targeting hit test.
#
# 세 걸음이다 — **자리를 푼다**(`_solve_slots`, 순수) → **글라이드를 맞춘다**
# (`_sync_glide`, 목표가 바뀐 파일럿에게 새 보간을 띄운다) → **지금 프레임의
# 좌표를 낸다**(`_compose_positions`, 강조 배율과 화면 클램프를 얹는다).
# 시간을 미는 것은 `_process` 의 `_advance_glide` 뿐이므로, 이 함수를 한 프레임에
# 여러 번 불러도(그리기 · 히트 테스트 · 돌진 기하) 답이 흔들리지 않는다.
func _build_pilot_render_layout() -> Dictionary:
	var solution := _solve_slots()
	_sync_glide(solution)
	return _compose_positions(solution)


# PilotData → {"cell": Vector2i, "slot": int}. 모든 렌더 가능한 파일럿이 자기
# 슬롯을 받는다 — `+N` 오버플로 원은 사라졌고, 7명째부터는 바깥 링으로 나간다.
#
# 배정은 **전장 전체를 한 번에 훑는 그리디**이되, 낱개가 아니라 **블록 단위**다:
# 같은 칸에서 기본 방향이 같은 파일럿들(= 같은 팀)은 한 덩어리로 묶여 자리표의
# **연속된 창(window)** 을 통째로 차지하고, 막히면 창째 한 칸 옆으로 미끄러진다
# (`_pick_block_slots`). 낱개 그리디였을 때는 A·B 가 나란히 선 칸에서 A 의 자리만
# 막히면 A 가 B 를 뛰어넘어 반대쪽에 앉아, 두 얼굴의 좌우가 뒤바뀌었다.
#
# 겹침 판정이 **다른 칸의 마커까지** 본다는 것은 그대로다 — 위아래로 붙은 두 칸이
# 서로를 향한 슬롯을 고르는 일(= 초상화가 겹치는 유일한 구조적 원인)이 없다.
func _solve_slots() -> Dictionary:
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
		var tile_center := _bs.cell_center(cell)
		var used: Dictionary = {}
		for raw_block in _slot_blocks(by_cell[cell] as Array):
			var block: Dictionary = raw_block
			var members: Array = block["pilots"] as Array
			var slots: Array = _pick_block_slots(tile_center, int(block["dir"]),
					_block_seat_bias(members), members.size(), base_r, used, placed)
			for i in range(members.size()):
				var slot: int = int(slots[i])
				used[slot] = true
				placed.append(tile_center + _slot_offset(slot, base_r))
				out[members[i]] = {"cell": cell, "slot": slot}
	return out


## 한 칸의 파일럿을 **기본 방향이 같은 블록**으로 묶는다. 블록은 한 덩어리로
## 자리를 받는 단위다 — 구성원은 자리표 위의 연속된 창에 왼쪽부터 순서대로
## 앉으므로(`_pick_block_slots`), 창이 어디로 밀려도 좌우 순서가 유지된다.
##
## 블록 순서는 **첫 등장 순**(= `_bs.pilots` 스폰 순서)이라 프레임마다 흔들리지
## 않는다. 기본 방향은 팀이 정하므로(팀0 S / 팀1 N) **한 칸의 블록은 최대 둘**,
## 곧 팀별로 하나씩이다 — 같은 팀은 언제나 한 덩어리로 나란히 앉는다.
func _slot_blocks(pilots: Array) -> Array:
	var order: Array = []
	var by_dir: Dictionary = {}
	for raw in pilots:
		var p := raw as PilotData
		var d: int = pilot_display_dir_index(p)
		if not by_dir.has(d):
			by_dir[d] = []
			order.append(d)
		(by_dir[d] as Array).append(p)
	var out: Array = []
	for d in order:
		out.append({"dir": int(d), "pilots": by_dir[d] as Array})
	return out


## 블록 `n` 명이 앉을 슬롯들(**자리표 왼쪽부터** 순서대로). 블록은 자리표
## (`SEAT_ROW_*`)의 **연속된 `n` 칸 = 창(window)** 을 통째로 차지한다. 그 창이
## 막혀 있으면 **창을 통째로 한 칸 옆으로 밀어** 다시 본다 — 그래서 나란히 선
## A·B 는 왼쪽이 막히면 **둘 다 오른쪽으로**, 오른쪽이 막히면 **둘 다 왼쪽으로**
## 비켜 앉고, 좌우 순서가 뒤집히지 않는다.
##
## 창 후보의 순서는 `_seat_windows`(자기 절반을 지키는 창 → 기본 방향에 가까운 창
## → 왼쪽 창)이고, 한 링의 창이 전부 막히면 **블록째** 바깥 링으로 나간다 — 링
## 경계에서 갈라져 두 겹에 걸쳐 앉지 않게 하기 위함이다.
##
## **예전에는 우선순위 순으로 빈자리를 하나씩 주웠다.** 막힌 자리를 건너뛰기만
## 하므로 블록이 끊기는 것은 물론, A 의 자리만 막히면 A 가 B 를 뛰어넘어 반대쪽
## 끝에 앉아 두 얼굴의 좌우가 뒤바뀌었다(그 앞은 각도 기준 시계방향 회전이었고,
## 그것은 아래 진영을 타일 위로 끌고 갔다 — `SEAT_ROW_DOWN` 주석).
##
## 세 링의 창이 다 막히거나 `n` 이 자리표보다 크면 한 명씩 따로 찾기(`_pick_slot`)로
## 떨어진다 — 나란히 서는 것보다 그려지는 것이 먼저다.
func _pick_block_slots(tile_center: Vector2, base_dir: int, bias: int, n: int,
		r: float, used: Dictionary, placed: Array) -> Array:
	var row: Array = _seat_row(base_dir)
	if n <= row.size():
		for ring in range(SLOT_RINGS):
			for raw_win in _seat_windows(n, bias):
				var start: int = int(raw_win)
				var cand: Array = []
				var ok: bool = true
				for k in range(n):
					var slot: int = ring * 6 + int(row[start + k])
					if used.has(slot) \
							or _slot_collides(tile_center + _slot_offset(slot, r), r, placed):
						ok = false
						break
					cand.append(slot)
				if ok:
					return cand
	var fallback: Array = []
	var local_used: Dictionary = used.duplicate()
	var local_placed: Array = placed.duplicate()
	for _k in range(n):
		var slot: int = _pick_slot(tile_center, base_dir, bias, r, local_used, local_placed)
		local_used[slot] = true
		local_placed.append(tile_center + _slot_offset(slot, r))
		fallback.append(slot)
	return fallback


## 이 블록이 자리표에서 **어느 쪽으로 쏠려 앉는가**: 오른쪽 +1 / 왼쪽 -1 / 없음 0.
##
## 기본 방향(= 팀)만으로는 좌우가 안 갈린다 — 자리표의 동률은 언제나 왼쪽 창이
## 가져갔고, 그래서 **모든 블록이 왼쪽으로 쏠렸다**. 우측 레인은 서포터 + 스나이퍼
## 둘이 한 칸에 서는 일이 잦은데, 그 2인 창이 왼쪽(팀0 이면 `SW S`)에 앉는 바람에
## 왼쪽 이웃 칸을 지나는 정글러 마커와 부딪혀 블록이 통째로 밀려나곤 했다 —
## 화면에서는 두 초상화가 이유 없이 돌아 앉는 것으로 보인다.
##
## 그래서 **레인이 곧 쏠리는 방향**이다: 우측 레인은 오른쪽(팀0 `S SE` / 팀1
## `N NE`), 좌측 레인은 왼쪽(`S SW` / `N NW`), 가운데 레인과 정글러는 쏠림 없음.
## 레인이 서로 다른 파일럿이 한 블록에 섞이면(같은 팀 정글러 + 라이너처럼)
## 방향을 정할 근거가 없으므로 0 으로 떨어진다.
##
## 쏠림은 **동률을 가르는 자리에만** 들어간다(`_compare_seat_windows`) — 자기
## 절반을 지키는 것도, 기본 방향에서 덜 비켜나는 것도 여전히 먼저다. 그래서
## 혼자 선 파일럿은 레인과 무관하게 한가운데(팀0 `S`)에 앉고, 그 자리가 막혔을
## 때 어느 쪽으로 비켜 앉는지만 레인이 정한다.
func _block_seat_bias(members: Array) -> int:
	var bias: int = 0
	for raw in members:
		var b: int = _lane_seat_bias((raw as PilotData).lane)
		if b == 0 or (bias != 0 and b != bias):
			return 0
		bias = b
	return bias


func _lane_seat_bias(lane: int) -> int:
	match lane:
		GameEnums.LanePosition.RIGHT: return 1
		GameEnums.LanePosition.LEFT:  return -1
		_:                            return 0


## 이 기본 방향(= 팀)의 자리표. 팀0 은 타일 아래를, 팀1 은 타일 위를 지난다.
func _seat_row(base_dir: int) -> Array:
	return SEAT_ROW_UP if base_dir == 0 else SEAT_ROW_DOWN


## `n` 명짜리 블록이 앉을 **창의 시작 칸** 후보를 좋은 순서대로. 창은 자리표의
## 연속된 `n` 칸이므로 어느 창을 골라도 구성원의 좌우 순서는 그대로다.
##
## 순서를 매기는 기준은 셋이다:
## 1. **자기 절반(가운데 세 자리)을 벗어난 인원이 적을수록** — 아래 진영이 타일
##    위에 앉는 것보다 나쁜 것은 없다.
## 2. **창의 중심이 기본 방향에 가까울수록** — 같은 조건이면 한가운데에서 덜
##    비켜난 쪽. 이것이 "한 칸씩 미끄러진다"를 만드는 항이다.
## 3. **블록이 쏠리는 쪽 창일수록**(`bias`) — 우측 레인이면 오른쪽 창, 좌측 레인
##    이면 왼쪽 창. 쏠림이 없는 블록(가운데 레인 · 정글러)은 예전처럼 왼쪽 창이
##    남은 동률을 가져간다. 자세한 이유는 `_block_seat_bias`.
func _seat_windows(n: int, bias: int = 0) -> Array:
	var scored: Array = []
	for start in range(0, 7 - n):
		var off: int = 0
		for k in range(n):
			var seat: int = start + k
			if seat < SEAT_HALF_MIN or seat > SEAT_HALF_MAX:
				off += 1
		var center: float = float(start) + float(n - 1) * 0.5
		scored.append({"start": start, "off": off, "d": absf(center - float(SEAT_BASE))})
	scored.sort_custom(_compare_seat_windows.bind(bias))
	var out: Array = []
	for raw in scored:
		out.append(int((raw as Dictionary)["start"]))
	return out


func _compare_seat_windows(a: Dictionary, b: Dictionary, bias: int) -> bool:
	if int(a["off"]) != int(b["off"]):
		return int(a["off"]) < int(b["off"])
	if not is_equal_approx(float(a["d"]), float(b["d"])):
		return float(a["d"]) < float(b["d"])
	if bias > 0:
		return int(a["start"]) > int(b["start"])
	return int(a["start"]) < int(b["start"])


# 지금 프레임의 마커 좌표 표. 글라이드가 낸 **중심 + 슬롯 벡터**에 그 칸의 강조
# 배율을 곱하고(= 무리가 함께 벌어진다) 화면 밖으로 나간 무리를 통째로 밀어 넣는다.
#
# 배율을 타일 중심이 아니라 **글라이드 중심**에 걸어야 한다는 것이 요점이다 —
# 칸을 건너는 중인 파일럿을 도착 타일 기준으로 부풀리면 아직 도착하지도 않은
# 지점을 축으로 튕겨 나간다.
func _compose_positions(solution: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var by_cell: Dictionary = {}
	for raw in solution.keys():
		var cell := (solution[raw] as Dictionary)["cell"] as Vector2i
		if not by_cell.has(cell):
			by_cell[cell] = []
		(by_cell[cell] as Array).append(raw)
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	for raw_cell in by_cell.keys():
		var pilots: Array = by_cell[raw_cell] as Array
		var em: float = _group_emphasis(pilots)
		var positions: Array = []
		for raw in pilots:
			var g: Dictionary = _glide[raw]
			positions.append((g["center"] as Vector2) + (g["vec"] as Vector2) * em)
		positions = _clamp_group_on_screen(positions, base_r * em)
		for i in range(pilots.size()):
			out[pilots[i]] = positions[i] as Vector2
	return out


func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


# ─── 마커 글라이드 ───────────────────────────────────────────────────────────

## 목표(칸 + 슬롯)가 바뀐 파일럿에게 새 보간을 띄운다. **시간은 여기서 흐르지
## 않는다** — 미는 것은 `_advance_glide` 하나뿐이라, 한 프레임에 이 함수가 몇 번
## 불려도(그리기 · 히트 테스트 · 팝업) 연출이 되감기지 않는다.
func _sync_glide(solution: Dictionary) -> void:
	var base_r: float = PILOT_RADIUS_BASE * HexGrid.DISPLAY_SCALE
	for raw in solution.keys():
		var p := raw as PilotData
		var e: Dictionary = solution[p]
		var cell := e["cell"] as Vector2i
		var slot: int = int(e["slot"])
		var center := _bs.cell_center(cell)
		var vec := _slot_offset(slot, base_r)
		if not _glide.has(p):
			_glide[p] = _settled_glide(cell, slot, center, vec)
			continue
		var g: Dictionary = _glide[p]
		if (g["cell"] as Vector2i) == cell and int(g["slot"]) == slot:
			continue
		# 순간이동이 **맞는** 경우 — 복귀 / 부활은 페이드가 자리 이동을 덮고,
		# 시신은 쓰러진 칸에 붙박여 있어야 한다. 미끄러뜨리면 사라지는 몸이
		# 화면을 가로지른다.
		if p.anim_recall_phase != 0 or p.anim_death_phase != 0:
			_glide[p] = _settled_glide(cell, slot, center, vec)
			continue
		var from_center: Vector2 = g["center"] as Vector2
		var from_vec: Vector2 = g["vec"] as Vector2
		var path := PackedVector2Array()
		if (g["cell"] as Vector2i) != cell:
			path = _screen_path(p, cell)
		if path.is_empty():
			path.append(center)
		# 출발점은 **지금 실제로 그려지고 있는 중심**이다 — 이전 글라이드가 아직
		# 안 끝났으면 기록된 출발 칸으로 되감기는 대신 그 자리에서 이어 간다.
		path[0] = from_center
		# 길이(= 링)가 바뀌는 경우에만 도착 후 정착 구간을 단다.
		var settle: float = 0.0
		if not is_equal_approx(from_vec.length(), vec.length()):
			settle = MARKER_RADIUS_SETTLE_SEC
		var ng: Dictionary = {
			"cell":     cell,
			"slot":     slot,
			"path":     path,
			"from_vec": from_vec,
			"to_vec":   vec,
			"t":        0.0,
			"move_dur": _bs.ANIM_MOVE_DUR,
			"total":    _bs.ANIM_MOVE_DUR + settle,
			"center":   from_center,
			"vec":      from_vec,
		}
		_eval_glide(ng)
		_glide[p] = ng
	# 전장을 뜬 파일럿(사망 퇴장, 재시작으로 갈린 로스터)의 상태는 버린다.
	for raw in _glide.keys():
		if not solution.has(raw):
			_glide.erase(raw)


## 아무 데도 가지 않는(= 이미 도착해 있는) 상태.
func _settled_glide(cell: Vector2i, slot: int, center: Vector2,
		vec: Vector2) -> Dictionary:
	return {
		"cell":     cell,
		"slot":     slot,
		"path":     PackedVector2Array([center]),
		"from_vec": vec,
		"to_vec":   vec,
		"t":        0.0,
		"move_dur": _bs.ANIM_MOVE_DUR,
		"total":    0.0,
		"center":   center,
		"vec":      vec,
	}


## `p` 가 이번에 실제로 밟은 칸들의 화면 좌표. `PilotData.anim_move_path` 가
## 도착 칸까지 이어져 있으면 그대로 쓰고(2칸 이동이 꺾여서 간다), 아니면
## 출발 → 도착 두 점짜리 직선으로 떨어진다(카드 순간이동, 밀림 등).
##
## **읽으면서 비운다.** 그래야 같은 프레임의 뒤이은 걸음은 이어 붙고(전진 카드의
## N틱), 다음 턴의 이동은 빈 배열에서 새 경로로 시작한다.
func _screen_path(p: PilotData, to_cell: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cells: Array[Vector2i] = p.anim_move_path
	if cells.size() >= 2 and cells[cells.size() - 1] == to_cell:
		for c in cells:
			out.append(_bs.cell_center(c))
	p.anim_move_path.clear()
	if out.is_empty():
		out.append(_bs.cell_center(to_cell))
	return out


## 모든 글라이드의 시계를 민다. 아직 움직이는 것이 하나라도 있으면 true.
func _advance_glide(delta: float) -> bool:
	var moving: bool = false
	for raw in _glide.keys():
		var g: Dictionary = _glide[raw]
		var total: float = float(g["total"])
		if float(g["t"]) >= total:
			continue
		g["t"] = minf(float(g["t"]) + delta, total)
		_eval_glide(g)
		moving = true
	return moving


## 지금 시각의 중심 · 슬롯 벡터를 `g` 에 적어 넣는다.
##
## **중심과 각도는 같은 박자, 길이만 뒤에 온다.** 링이 그대로면 길이 보간은
## 항등이라 화살표 길이가 이동 내내 한 픽셀도 변하지 않고(꼬리가 초상에 매달려
## 통째로 미끄러진다), 붐비는 칸으로 들어가 바깥 링으로 밀려날 때만 도착 후
## `MARKER_RADIUS_SETTLE_SEC` 동안 늘어난다.
func _eval_glide(g: Dictionary) -> void:
	var move_dur: float = maxf(0.0001, float(g["move_dur"]))
	var t: float = float(g["t"])
	var te: float = clampf(t / move_dur, 0.0, 1.0)
	# **smoothstep — 양 끝에서 정지한다.** 예전 이동 트윈은 ease-out cubic 이었고
	# (슬롯은 어차피 튀었으니 출발이 급해도 티가 덜 났다) 그 곡선은 60fps 첫
	# 프레임에 이미 거리의 15%(≈25px)를 지나간다 — 순간이동을 없애려는 연출이
	# 출발할 때마다 한 번 튀는 셈이었다. 실측: 첫 프레임 24.98px → 1.1px.
	te = te * te * (3.0 - 2.0 * te)
	g["center"] = _polyline_lerp(g["path"] as PackedVector2Array, te)
	var a: Vector2 = g["from_vec"] as Vector2
	var b: Vector2 = g["to_vec"] as Vector2
	# 각도는 **짧은 쪽으로** 돈다. 끝점을 직선 lerp 하면 두 벡터 사이를 가로지르며
	# 마커가 타일 중심 쪽으로 파고들었다 나와, 회전이 아니라 흔들림으로 읽힌다.
	var ang: float = a.angle() + wrapf(b.angle() - a.angle(), -PI, PI) * te
	var tr: float = 1.0
	if float(g["total"]) > float(g["move_dur"]):
		tr = clampf((t - float(g["move_dur"])) / MARKER_RADIUS_SETTLE_SEC, 0.0, 1.0)
		tr = 1.0 - pow(1.0 - tr, 3.0)
	g["vec"] = Vector2.from_angle(ang) * lerpf(a.length(), b.length(), tr)


## 폴리라인 위를 **호 길이 비율**로 훑는다. 구간 개수로 나누면 칸마다 속도가
## 달라지지는 않지만(육각 이웃 간 거리는 모두 같다) 출발점만 바꿔 끼운 경로에서
## 첫 구간이 짧아지므로, 거리로 재는 편이 어느 경우에도 등속이다.
func _polyline_lerp(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1 or t <= 0.0:
		return pts[0]
	if t >= 1.0:
		return pts[pts.size() - 1]
	var total: float = 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total < 0.001:
		return pts[0]
	var want: float = total * t
	var acc: float = 0.0
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if acc + seg >= want:
			return pts[i - 1].lerp(pts[i], (want - acc) / maxf(0.0001, seg))
		acc += seg
	return pts[pts.size() - 1]


## 이 파일럿의 말풍선 꼬리가 가리킬 점 — 글라이드 중인 **타일 중심**이다. 이동
## 중에는 아직 출발 칸 근처에 있으므로, 꼬리가 도착 칸을 먼저 가리키며 늘어나는
## 일이 없다(초상과 함께 미끄러진다).
func _marker_center(p: PilotData) -> Vector2:
	if _glide.has(p):
		return (_glide[p] as Dictionary)["center"] as Vector2
	return _bs.cell_center(_render_cell(p))


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
## **시계방향**(화면 기준 y 아래)이다.
## 인덱스: 0=N 1=NE 2=SE 3=S 4=SW 5=NW.
const HEX_DIRS: Array[Vector2] = [
	Vector2( 0.0,       -1.0),   # N
	Vector2( 0.8660254, -0.5),   # NE
	Vector2( 0.8660254,  0.5),   # SE
	Vector2( 0.0,        1.0),   # S
	Vector2(-0.8660254,  0.5),   # SW
	Vector2(-0.8660254, -0.5),   # NW
]

## 한 링의 여섯 자리를 **왼쪽에서 오른쪽으로** 늘어놓은 자리표(HEX_DIRS 인덱스).
## 가운데 세 자리(인덱스 1·2·3)가 그 팀의 **절반**이고, 한가운데(`SEAT_BASE` = 2)가
## 기본 방향이다. 팀0 은 타일 **아래**를, 팀1 은 타일 **위**를 지나며 왼쪽에서
## 오른쪽으로 훑는 순서다:
##
##     팀0(아래 진영)   NW   SW  [S]  SE   NE   N
##     팀1(위 진영)     SW   NW  [N]  NE   SE   S
##
## 두 표 모두 육각 링을 한 방향으로 감은 것이라(팀0 은 반시계, 팀1 은 시계),
## **자리표에서 연속인 칸은 링에서도 연속인 자리**다 — 블록이 창(window) 하나로
## 앉으면 화면에서도 끊김 없이 나란히 선다.
##
## 링을 좌우가 아니라 **각도**로 도는 방식(기본 방향에서 시계방향 회전, 또는
## 좌우 번갈아 벌리기)은 전부 삭제됐다. 그 순서로는 자리가 하나 막혔을 때 블록의
## 한 명만 반대편으로 건너뛰어, 비켜 앉은 것이 아니라 **자리를 맞바꾼 것**으로
## 읽혔다 — 지금은 블록이 통째로 한 칸 미끄러진다(`_pick_block_slots`).
const SEAT_ROW_DOWN: Array[int] = [5, 4, 3, 2, 1, 0]   # 팀0: NW SW [S] SE NE N
const SEAT_ROW_UP:   Array[int] = [4, 5, 0, 1, 2, 3]   # 팀1: SW NW [N] NE SE S

## 자리표에서 기본 방향이 앉는 칸. 좌우 각 2칸이 여기서 뻗어 나간다.
const SEAT_BASE := 2

## 자리표에서 **자기 절반**인 구간(둘 다 포함). 이 밖은 위/아래가 뒤집히는 자리라
## 창을 고를 때 감점된다.
const SEAT_HALF_MIN := 1
const SEAT_HALF_MAX := 3

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


## 이 파일럿이 앉을 슬롯. 혼자 앉는 것은 **1인짜리 창**이므로 블록과 같은 표를
## 쓴다 — `_seat_windows(1, bias)` 가 자리표를 기본 방향부터 좌우로 번갈아 훑는
## 순서를 돌려준다(팀0 · 쏠림 없음이면 S → SW → SE → NW → NE → N, 우측 레인이면
## 좌우가 뒤집혀 S → SE → SW → NE → NW → N). 거기서 (1) 같은 칸에서 아직 안 쓴
## 자리이고 (2) 이미 놓인 어떤 마커와도 겹치지 않는 첫 자리를 잡는다. 안쪽 링 6자리를
## 다 돌면 그대로 바깥 링으로 나간다 — 그만큼 타일에서 멀어지고 화살표가 길어져,
## 붐비는 칸일수록 "어느 타일인지"가 화살표로 읽힌다.
##
## 겹침 판정이 **다른 칸의 마커까지** 본다는 것이 요점이다: 위아래로 붙은 두 칸이
## 서로를 향한 슬롯(위 칸의 S, 아래 칸의 N)을 고르면 초상화 두 개가 그 사이에서
## 정면으로 겹치는데, 이것이 전장에서 얼굴이 가려지는 유일한 구조적 원인이었다.
## 그 자리를 피해 **어디로 비켜 앉는가**를 정하는 것이 위 순서다.
func _pick_slot(tile_center: Vector2, base_dir: int, bias: int, r: float,
		used: Dictionary, placed: Array) -> int:
	var row: Array = _seat_row(base_dir)
	var seats: Array = _seat_windows(1, bias)
	for ring in range(SLOT_RINGS):
		for raw_seat in seats:
			var slot: int = ring * 6 + int(row[int(raw_seat)])
			if used.has(slot):
				continue
			if _slot_collides(tile_center + _slot_offset(slot, r), r, placed):
				continue
			return slot
	# 사방이 막혔으면 겹치더라도 빈 슬롯을 준다 — 그리지 않는 것보다 낫다.
	for ring in range(SLOT_RINGS):
		for raw_seat in seats:
			var slot: int = ring * 6 + int(row[int(raw_seat)])
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
# **팀이 정한다** — 아래 진영(팀0)은 타일 아래(S), 위 진영(팀1)은 타일 위(N).
# 화면에서 자기 HQ 가 있는 쪽이 곧 자기 자리라, 어느 칸을 보든 아래줄이 내 팀이고
# 윗줄이 상대 팀이다. 여기서 겹치는 경우는 배정 쪽이 자리표(`SEAT_ROW_*`)를
# **좌우로 미끄러뜨려** 푼다(`_pick_block_slots` / `_pick_slot`) — 기본 방향은
# 자리표 한가운데이고, 그 **절반**(팀0 이면 아래 SW·S·SE, 팀1 이면 위 NW·N·NE)이
# 다 막히기 전에는 반대쪽으로 넘어가지 않는다.
#
# **삭제된 것 — 이동 방향 기반 배치.** 예전에는 "가려는 쪽을 비우고 지나온 쪽에
# 선다"며 레인 파일럿은 다음 웨이포인트 방향의 반대, 정글러는 `prev_grid_pos` 에서
# 온 방향의 반대에 앉혔다(`_pilot_travel_dir` / `_peek_waypoint` /
# `_nearest_dir_index`, 커밋 64bec06). 같은 레인 같은 구간이면 정렬은 맞았지만
# **같은 팀이 구간마다 다른 쪽에 앉아**(1차 포탑 전 왼쪽 아래 → 그 뒤 아래 →
# 적 포탑 뒤 오른쪽 아래) 화면에서 팀을 위/아래로 읽는 기준이 사라졌다.
# 되살리지 말 것. `PilotData.prev_grid_pos` 도 그때 함께 삭제됐다.

## `p` 의 기본 슬롯 방향(HEX_DIRS 인덱스). 공개 — BattleSim 의 대체 좌표 계산이
## 같은 답을 써야 한다.
func pilot_display_dir_index(p: PilotData) -> int:
	return 3 if p.team == 0 else 0   # 팀0 = S(아래), 팀1 = N(위)


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
func _draw_pilot_cell(_cell: Vector2i, pilots: Array) -> void:
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
		# 끝점은 **글라이드 중인 타일 중심**이다 — 초상이 실제로 미끄러지므로
		# 꼬리도 같은 박자로 따라간다. 링이 그대로면 이동 내내 길이가 한 픽셀도
		# 변하지 않고, 바깥 링으로 밀려날 때만 도착 후에 늘어난다(`_eval_glide`).
		_draw_arrow_to_tile(pos, _marker_center(pilot),
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


# Per-pilot pixel offset combining recall rise/descend, 전사 상승, 돌진, 그리고
# 피격 흔들림. **칸 이동은 여기 없다** — 마커 좌표 자체가 글라이드로 미끄러지므로
# (`_sync_glide` / `_eval_glide`) 여기서 한 번 더 얹으면 두 벌이 된다.
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
	# 공격 카드 돌진은 다른 무엇에도 얹힌다 — 이동/복귀와 배타적인 elif 사슬에
	# 넣지 않는 이유는, 돌진 중에도 대상이 흔들리듯 시전자가 흔들릴 수 있고 오프셋은
	# 서로 독립이기 때문이다. 계산 자체는 BattleSim 이 소유한다(연출 상수와
	# 단계 전환이 거기 모여 있다).
	off += _bs.pilot_lunge_offset(p)
	if p.anim_shake_dur > 0.0:
		var t: float = clamp(p.anim_shake_t / p.anim_shake_dur, 0.0, 1.0)
		# 진폭은 흔들림을 건 쪽이 정한다(전장 교전 6px / 공격 카드 20px).
		# 0 은 `anim_shake_amp` 가 붙기 전에 만들어진 상태이므로 기본값으로 읽는다.
		var base_amp: float = p.anim_shake_amp
		if base_amp <= 0.0:
			base_amp = _bs.ANIM_SHAKE_AMP_PX
		var amp: float = base_amp * (1.0 - t)
		# **주파수는 고정, 진동 수가 지속시간을 따라간다.** 진동 수를 4회로
		# 고정하면 길게 흔들라는 지시가 "느리게 흔들라"가 되어 격렬함이 사라진다.
		var cycles: float = 4.0 * (p.anim_shake_dur / _bs.ANIM_SHAKE_DUR)
		off.x += sin(t * TAU * cycles) * amp
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
## 기본 방향(팀0 = 아래 / 팀1 = 위)의 첫 링에 앉힌다. 공개인 이유는 `BattleSim` 과
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


# 마커에서 자기 타일을 가리키는 말풍선 꼬리. `aim_point` 는 **글라이드 중인 타일
# 중심**(`_marker_center`)이다 — 이동 중에는 초상과 함께 미끄러지므로 꼬리가
# 초상보다 먼저 도착 칸을 가리키며 늘어나는 일이 없다.
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
