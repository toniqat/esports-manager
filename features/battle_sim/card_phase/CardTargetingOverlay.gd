class_name CardTargetingOverlay
extends Node

# 카드를 **끌어내는 순간** 켜지는 대상 지정 오버레이.
#
# 예전에는 카드를 고른 뒤 설명 상자의 "카드 내기"를 눌러야 비로소 모달 대상
# 지정이 열렸고, 그 다음에는 **카드를 클릭해 선택하는 것**이 곧 대상 지정
# 단계였다. 선택 상태 자체가 사라진 지금은 **드래그가 그 자리를 이어받았다** —
# 카드를 손에서 끌어내는 순간 놓을 수 없는 곳이 전부 딤드되고, 손을 떼면 사라진다
# (`CardPhaseManager._begin_drag` / `_end_drag`).
#
#   • PILOT    — 타일은 전부 딤드(타일은 대상이 아니다). 유효 대상만
#                TARGET_EMPHASIS_SCALE 만큼 커진 채 밝게 남는다.
#   • LOCATION — 유효 셀만 초록으로 남고 나머지 셀과 파일럿 전원이 딤드된다.
#   • PREVIEW  — 전투 개시류. 시전자 셀 + 인접 6칸이 영역으로 밝아지고 그 안의
#                참여 파일럿이 강조된다. **참가자 명단은 여기 없다** — 카드를
#                제출한 뒤 `engage/EngageIntro.gd` 의 VS 화면이 보여 준다.
#                (예전에는 화면 좌/우에 세로 팀 패널 두 개가 떴다. 아직 낼지도
#                정하지 않은 카드를 집기만 해도 화면 절반이 표로 덮였고, 세로로
#                나란히 선 목록 둘은 어느 쪽이 내 팀인지를 위치로 말해 주지도
#                못했다.)
#   • INSTANT  — 대상이 없는 카드. 전장 표시가 하나도 없다.
#
# **확정 경로는 드래그 드롭 하나뿐이다.** 카드를 대상 위(또는 무대상 카드라면
# 드롭 존)에 놓는 것만이 카드를 내는 방법이고, 빗나간 드롭은 그냥 카드를 손패로
# 돌려보낸다. 확정 전까지는 비용도 카드도 그대로이므로 되돌릴 상태가 애초에 없다.
# (버리기 / 찾기 카드의 스냅샷 환불 경로는 CardSelectOverlay 쪽에 그대로 남아
# 있다.)
#
# `pending_pick` 은 **드래그 중 미리보기 전용**이다 — `preview_drag_target` 이
# 커서 아래의 대상을 찍어 시안 링을 붙인다.

enum Mode { NONE, INSTANT, PILOT, LOCATION, PREVIEW }

# ─── State ────────────────────────────────────────────────────────────────────
var mode: int = Mode.NONE

# Public read-only state read by BattleRenderer.
var valid_pilots: Dictionary = {}    # PilotData    → true
var valid_cells:  Dictionary = {}    # Vector2i     → true
var area_cells:   Dictionary = {}    # Vector2i     → true (PREVIEW area)
var preview_caster: PilotData = null
var preview_participants: Array = []  # PilotData (engage participants)
# 들려 있는 카드의 시전자. **모드와 무관하게** 채워지며, 하는 일은 하나뿐이다 —
# 시전자는 어느 모드에서도 딤드되지 않는다(should_dim_pilot). 지금 이 카드를 쏘는
# 사람이 어두워져 있으면 "쓸 수 없는 파일럿"으로 읽히기 때문이다. 대신 **강조
# 대상은 아니다**: 커지는 것은 놓을 수 있는 곳이라는 신호이므로, 시전자가 그 카드의
# 유효 대상일 때(보호 / 복귀 같은 target=ally 카드)만 valid_pilots 를 통해 커진다.
var card_caster: PilotData = null
# Range info for PILOT / LOCATION modes — drives the in-range tile highlight
# and the out-of-range black dim drawn by BattleRenderer.
var range_caster: PilotData = null
var range_radius: int = 0
# 사거리 제한이 사실상 없는 카드(복귀 / 보호 / 약탈 — cast_range ≥
# UNLIMITED_RANGE)는 전장 전체가 사거리다. 노란 사거리 채움으로 전장을 통째로
# 덮으면 유효 대상 표시만 묻히므로, 이 플래그가 켜지면 채움도 딤도 그리지
# 않는다 (LOCATION 의 초록 유효 셀 외곽선은 그대로).
var range_unlimited: bool = false

# 이 값 이상의 cast_range 는 "제한 없음"으로 읽는다. cards.csv 가 무제한을
# 99 로 적어 두는 관례를 한 곳에 모아 둔 것.
const UNLIMITED_RANGE: int = 99

# PILOT / LOCATION pending pick — 드래그 중 커서 아래에 들어온 유효 대상.
# 시안 링(BattleRenderer._draw_pending_pick_highlight)의 유일한 입력이다.
# Holds either PilotData or Vector2i.
var pending_pick: Variant = null

var _bs: BattleSim = null
var _on_confirm: Callable = Callable()
# CardPhaseManager 가 "비용/시전자 생존/유효 대상"을 판정해 내려주는 값.
# 드롭 확정(confirm_with)은 이 값 AND 대상 지정 완료일 때만 통과한다.
var _play_allowed: bool = false

# ─── UI consts ───────────────────────────────────────────────────────────────
# 확인 / 취소 버튼은 사라졌지만 그 자리는 **빈 띠로 남긴다** — HudBuilder 가 이
# 두 상수로 전략 포인트 도넛의 세로 위치를 잡고, 도넛이 핸드 행에 바로 붙어
# 앉으면 카드 윗단과 겹친다. 이름과 값을 그대로 두는 이유가 그것뿐이라는 뜻이다.
const BTN_H            := 56.0
const BTN_HAND_GAP     := 10.0


# Bind step so the overlay does not need to know its parent type at construction.
func bind(bs: BattleSim) -> void:
	_bs = bs


# ─── State accessors (read by renderer / play path) ──────────────────────────
# There is no modal state any more: selecting a card never blocks the hand or
# 턴 넘기기. BattleRenderer asks is_visualizing() to decide whether to paint
# the range fill and the out-of-range dim — INSTANT cards have neither.
func is_visualizing() -> bool:
	return mode == Mode.PILOT or mode == Mode.LOCATION or mode == Mode.PREVIEW


## True while a card is lifted in hand with this overlay live (any kind).
func is_selecting() -> bool:
	return mode != Mode.NONE


# Non-valid pilots are dimmed in PILOT mode; ALL pilots are dimmed in LOCATION.
# In PREVIEW, participating pilots stay bright and others dim.
#
# **시전자만은 어느 모드에서도 딤드되지 않는다.** 딤은 "여기엔 놓을 수 없다"는
# 말인데, 카드를 쏘는 당사자에게 그 말은 성립하지 않는다 — LOCATION 카드를 들면
# 전원 딤 규칙에 시전자까지 걸려, 지금 움직이려는 파일럿이 가장 어둡게 보였다.
func should_dim_pilot(p: PilotData) -> bool:
	if p != null and p == card_caster:
		return false
	match mode:
		Mode.PILOT:
			return not valid_pilots.has(p)
		Mode.LOCATION:
			return true
		Mode.PREVIEW:
			return not (p in preview_participants)
		_:
			return false


# Cells inside the highlighted "range" area (LOCATION / PILOT use the caster's
# cast_range; PREVIEW uses the engage area). Used by BattleRenderer to:
#  • highlight in-range cells with a soft yellow fill, and
#  • black-dim every other valid grid cell.
func is_in_range_cell(cell: Vector2i) -> bool:
	if mode == Mode.PREVIEW:
		return area_cells.has(cell)
	if range_unlimited:
		return true
	if range_caster == null or range_radius <= 0:
		return false
	if cell == range_caster.grid_pos:
		return true
	var d: int = _bs.hex_grid.hex_distance(range_caster.grid_pos, cell)
	return d > 0 and d <= range_radius


# A valid target cell? — used by BattleRenderer to draw the cell outline.
func is_valid_cell(cell: Vector2i) -> bool:
	return mode == Mode.LOCATION and valid_cells.has(cell)


# A cell inside the engage preview area? — drawn with a softer fill.
func is_area_cell(cell: Vector2i) -> bool:
	return mode == Mode.PREVIEW and area_cells.has(cell)


## 대상 지정이 끝났는가. PILOT / LOCATION 만 실제로 찍어야 하고, PREVIEW 와
## INSTANT 는 고른 즉시 확정 가능하다.
func has_required_pick() -> bool:
	if mode == Mode.PILOT or mode == Mode.LOCATION:
		return pending_pick != null
	return mode != Mode.NONE


# ─── Entry point ─────────────────────────────────────────────────────────────
## 핸드에서 카드를 고른 순간 CardPhaseManager._select_card 가 호출한다.
## `on_confirm` 은 드롭 확정 시 `Variant`(PilotData / Vector2i / null) 하나를
## 받는다. 오버레이가 스스로 정리된 뒤에 불리므로 콜백 안에서 다시 선택을
## 걸어도 안전하다. (취소 콜백은 없다 — 빗나간 드롭은 호출 측이
## `deselect_current_card` 로 직접 걷는다.)
func start_card_selection(cd: CardData, on_confirm: Callable) -> void:
	_clear_visual_state()
	if cd == null:
		return
	var caster: PilotData = cd.owner_pilot
	card_caster = caster
	var kind: String = ""
	if _bs.card_phase != null:
		kind = _bs.card_phase.targeting_kind(cd)
	# 시전자가 없는 레거시 카드는 대상 지정 자체가 성립하지 않으므로 INSTANT
	# 취급 — 확인 버튼만 뜬다.
	if caster == null:
		kind = "none"
	match kind:
		"pilot":
			mode = Mode.PILOT
			range_caster = caster
			range_radius = max(0, cd.cast_range)
			range_unlimited = cd.cast_range >= UNLIMITED_RANGE
			var team_filter: int = 1 if cd.target == "enemy" else 0
			for raw in _bs.card_phase.compute_valid_pilot_targets(cd, caster, team_filter):
				valid_pilots[raw as PilotData] = true
		"location":
			mode = Mode.LOCATION
			range_caster = caster
			range_radius = max(1, cd.cast_range)
			range_unlimited = cd.cast_range >= UNLIMITED_RANGE
			for c in _bs.card_phase.compute_valid_location_targets(cd, caster):
				valid_cells[c as Vector2i] = true
		"preview":
			mode = Mode.PREVIEW
			preview_caster = caster
			var area := _bs.card_phase.compute_engage_area(caster)
			for c in area:
				area_cells[c as Vector2i] = true
			var exclude_lane: bool = _bs.card_phase.has_clause_flag(
					cd.effect, "engage", "exclude_lane")
			preview_participants = _bs.card_phase.compute_engage_participants(
					caster, area, exclude_lane)
		_:
			mode = Mode.INSTANT
	_on_confirm = on_confirm
	_play_allowed = false
	_request_redraw()


## 대상 지정 해제 — 아직 비용도 카드도 건드리지 않았으므로 되돌릴 상태가 없다.
## 콜백은 부르지 않는다(호출 측이 이미 정리 중일 때 재진입하지 않도록).
## 이미 꺼져 있으면 no-op.
func clear_selection() -> void:
	if mode == Mode.NONE:
		return
	_teardown()


## CardPhaseManager 가 "비용 / 시전자 생존 / 유효 대상" 판정 결과를 내려준다.
## 드롭 확정은 이 값과 has_required_pick() 이 둘 다 참일 때만 통과한다.
func set_play_allowed(allowed: bool) -> void:
	_play_allowed = allowed


# ─── 드래그 앤 드롭 진입점 ────────────────────────────────────────────────────
# 카드를 손에서 끌어다 놓는 것이 **카드를 내는 유일한 조작**이다. 비용 차감 /
# 카드 소비 / effect chain 은 전부 CardPhaseManager._on_selection_confirm 뒤에
# 있으므로, 드롭은 대상만 손에 들고 와서 confirm_with 로 들어온다.

## 드롭 지점의 파일럿(PILOT 모드 한정). 유효 대상이 아니면 null.
func hit_test_pilot_at(pos: Vector2) -> PilotData:
	if mode != Mode.PILOT:
		return null
	return _hit_test_pilot(pos)


## 드롭 지점의 유효 셀(LOCATION 모드 한정). 없으면 null.
func hit_test_cell_at(pos: Vector2) -> Variant:
	if mode != Mode.LOCATION:
		return null
	var cell := _hit_test_cell(pos)
	if cell == Vector2i(-2147483648, -2147483648) or not valid_cells.has(cell):
		return null
	return cell


## 드래그 중 커서 아래의 대상을 미리 찍어 둔다(시안 링 피드백). 놓지 않고 손을
## 떼면 그대로 pending_pick 으로 남아 확인 버튼으로도 확정할 수 있다.
func preview_drag_target(target: Variant) -> void:
	if target == null:
		if pending_pick == null:
			return
		pending_pick = null
		_request_redraw()
		return
	if pending_pick == target:
		return
	_set_pending_pick(target)


## 드롭으로 확정한다. 버튼과 같은 게이트(`_play_allowed`)를 지나며, 통과하면
## 오버레이를 정리하고 확인 콜백을 부른다. 반환값은 "정말 카드를 냈는가" — false
## 면 호출 측이 카드를 손으로 되돌려야 한다.
func confirm_with(target: Variant) -> bool:
	if mode == Mode.NONE or not _play_allowed:
		return false
	pending_pick = target
	if not has_required_pick():
		return false
	var cb := _on_confirm
	_teardown()
	if not cb.is_valid():
		return false
	cb.call(target)
	return true


# **전장 클릭은 삼키기만 한다.** PILOT / LOCATION 카드가 들려 있는 동안 전장
# 어디를 눌러도 아무 일도 일어나지 않는다 — 카드를 내는 조작은 끌어다 놓기
# 하나뿐이기 때문이다. 그래도 이벤트를 소비하는 이유는 그대로다:
# CardPhaseManager._unhandled_input 이 전장 탭을 "바깥 클릭"으로 읽어 선택을
# 통째로 떨어뜨리기 때문. 나가는 길은 빗나간 드롭, 카드 재클릭, 다른 카드 선택.
#
# (예전에는 여기서 대상을 찍어 pending_pick 에 넣고 우하단 확인으로 확정했다.
#  확인 / 취소 버튼과 함께 그 경로가 사라졌다.)
func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PILOT and mode != Mode.LOCATION:
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()


# 드래그 중 커서 아래에 들어온 대상을 기록하고 시안 링을 새로 그린다.
func _set_pending_pick(target: Variant) -> void:
	pending_pick = target
	_request_redraw()


# Closest cell whose centre is within hex_size of `pos`. Returns a sentinel
# value when nothing is close enough. Used by LOCATION mode only.
func _hit_test_cell(pos: Vector2) -> Vector2i:
	var best: Vector2i = Vector2i(-2147483648, -2147483648)
	var best_d: float = INF
	var hex_size: float = (_bs.hex_grid as HexGrid).hex_size
	for c_raw in valid_cells.keys():
		var c := c_raw as Vector2i
		var centre := _bs.cell_center(c)
		var d := centre.distance_to(pos)
		if d < best_d and d <= hex_size:
			best_d = d
			best = c
	return best


# PILOT mode hit test — picks the valid pilot whose **drawn** marker is closest
# to the click position.
#
# The marker position comes from `BattleRenderer.pilot_marker_positions()`, the
# same per-cell stack solve `_draw()` uses, so a cell holding several pilots
# resolves to the one actually under the finger. Probing
# `BattleSim.pilot_marker_pos_solo` instead (as this used to) gave *every*
# pilot in a shared cell the identical probe point, so the first key in
# `valid_pilots` — the leftmost drawn marker — always won no matter which
# portrait was tapped. Pilots with no drawn slot (the >5 overflow circle) still
# fall back to the solo offset.
#
# A click that lands on no marker but inside a pilot's own tile still resolves,
# ranked by marker distance — that keeps taps on the tile itself working while
# leaving a stacked cell unambiguous.
func _hit_test_pilot(pos: Vector2) -> PilotData:
	var markers: Dictionary = {}
	if _bs.renderer != null:
		markers = _bs.renderer.pilot_marker_positions()
	var best: PilotData = null
	var best_d: float = INF
	var tile_best: PilotData = null
	var tile_best_d: float = INF
	var hex_size: float = (_bs.hex_grid as HexGrid).hex_size
	# Slightly looser than half a tile so the click area covers the visible
	# marker circle (~31.5 px radius at default scale).
	var base_r: float = hex_size * 0.85
	for raw in valid_pilots.keys():
		var p := raw as PilotData
		if not p.alive:
			continue
		var marker: Vector2 = _bs.pilot_marker_pos_solo(p)
		if markers.has(p):
			marker = markers[p] as Vector2
		# 대상 지정 중 유효 파일럿의 초상은 TARGET_EMPHASIS_SCALE 만큼 커져
		# 타일 반지름을 넘어선다 — 그리는 반지름을 렌더러에서 그대로 받아
		# 얼굴 바깥 테두리를 눌러도 잡히게 한다.
		var max_r: float = base_r
		if _bs.renderer != null:
			max_r = maxf(base_r, _bs.renderer.pilot_marker_radius(p))
		var d: float = marker.distance_to(pos)
		if d <= max_r:
			if d < best_d:
				best_d = d
				best = p
			continue
		# 타일 폴백은 강조와 무관하게 **타일 크기** 기준이다 — 커진 초상만큼
		# 넓히면 옆 칸을 누른 클릭까지 이 파일럿으로 빨려 들어간다.
		var tile_d: float = _bs.cell_center(p.grid_pos).distance_to(pos)
		if tile_d <= base_r and d < tile_best_d:
			tile_best_d = d
			tile_best = p
	return best if best != null else tile_best


# ─── Teardown ────────────────────────────────────────────────────────────────
# Common reset helper used by start_card_selection / _teardown before stamping
# new state. Does NOT touch button refs — the entry point rebuilds them.
func _clear_visual_state() -> void:
	mode = Mode.NONE
	valid_pilots.clear()
	valid_cells.clear()
	area_cells.clear()
	preview_caster = null
	card_caster = null
	preview_participants.clear()
	range_caster = null
	range_radius = 0
	range_unlimited = false
	pending_pick = null
	_play_allowed = false


func _teardown() -> void:
	_clear_visual_state()
	_on_confirm = Callable()
	_request_redraw()


# Force tile + battlefield redraws so dim state takes effect immediately.
# The tilemap modulate stays at the default (WHITE) — per-cell black dim is
# drawn by BattleRenderer for cells outside the cast range.
func _request_redraw() -> void:
	if _bs.tiles_layer != null:
		_bs.tiles_layer.modulate = Color.WHITE
	if _bs.renderer != null:
		_bs.renderer.queue_redraw()
