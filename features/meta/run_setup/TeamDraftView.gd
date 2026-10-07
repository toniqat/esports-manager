class_name TeamDraftView
extends Control

# 런 준비의 **5인 편성** 화면 — 우마무스메식 인물 고르기.
#
#   맨 위: 단계 머리글(`RunSetupScreen` 이 그린다 — 이 화면은 그 아래부터)
#   상단: **샐러리 게이지** — 합계 / 캡, 넘치면 빨강. 그 아래 규칙 한 줄
#         (`RunRules.validate_lineup` 의 오류 문장 그대로)
#   상: 선택한 5인의 **상체 일러스트** (탑 · 정글 · 미드 · 원딜 · 서폿).
#       일러스트를 누르면 `DraftDetailPanel` 이 열린다. 칸 아래에 **레벨 스테퍼**
#       (− Lv +, 1 ~ 달성 최대)와 그 레벨의 샐러리 · 종합 스탯
#   중: 전체 / 탑 / 정글 / 미드 / 원딜 / 서폿 필터 버튼 한 줄
#   하: 보유 선수 썸네일 격자 (세로 스크롤, 3.5줄이 보인다, 칸마다 샐러리 꼬리표)
#   맨 아래: 하단 바 `뒤로` / `다음`
#
# **모양의 정본은 `UI_View_TeamDraftView.tscn`** (게이지 · 다섯 칸 `DraftSlot` · 필터 · 격자 뒤판 ·
# 격자 · 하단 바의 자리 · 크기 · 변형). 이 스크립트는 `%` 노드에 데이터를 넣고 시그널을
# 잇고, 선택 5인 블록의 y(PICK / CONFIRM)와 픽창의 빠짐만 계산한다. 생성은
# `TeamDraftView.create()` (`TeamDraft.ensure_view`).
#
# 블록은 **아래에서 위로** 쌓는다 — 격자를 하단 바 위에 매달고, 필터와 선택
# 5인이 그 위에 차례로 앉는다. 게이지는 머리글 바로 아래에 붙는다.
#
# **화면은 두 모드를 오간다.** PICK 은 위와 같고, `다음`을 누르면 CONFIRM 으로
# 넘어가 **픽창(필터 + 격자)이 화면 아래로 빠지고 선택 5인이 화면 가운데로
# 내려온다**(`_apply_mode`). 거기서 **`게임 시작`**이 `TeamDraft.start_requested`
# 를 올리고, `RunSetupScreen` 이 암전 → 가짜 로딩 → 밝아짐 뒤에서 런을 연다.
# `뒤로`는 PICK 에서는 팀 단계로(`back_requested`), CONFIRM 에서는 PICK 으로.
#
# **규칙은 고를 때 보인다** — 샐러리캡을 넘기는 선택도 막지 않고 게이지를 빨갛게
# 칠한 뒤 `다음` / `게임 시작`을 잠근다. 시작 버튼에서 처음 거절당하는 조합은 없다.
#
# **다섯 칸은 역할 고정**이다(`TeamDraft.SLOT_ROLES`) — `validate_lineup` 이
# "포지션당 1명"을 강제하므로 자유 순서로 두면 화면에서만 가능한 조합이 생긴다.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_View_TeamDraftView.tscn"

const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

# ─── 세로 배치 — 코드가 정하는 것은 선택 5인 블록의 y 둘뿐 ─────────────────────
# 게이지 · 필터 · 격자 · 뒤판 · 하단 바의 자리와 크기는 씬(`UI_View_TeamDraftView.tscn`)이 정한다.
# 블록의 y 는 PICK / CONFIRM 사이를 오가며 트윈되므로 그 두 값만 여기서 낸다 —
# 씬 노드의 실제 자리(`%Gauge` 아랫변, `%Filters` 윗변, 바 윗변)에서 읽어 오므로
# 에디터에서 블록을 옮겨도 따라간다.
## 게이지 아랫변 ↔ 선택 5인(CONFIRM 모드에서 위로 붙을 수 있는 한계).
const GAUGE_ROW_GAP: float = 24.0
## 블록 아랫변 ↔ 필터 줄 (PICK).
const SLOT_FILTER_GAP: float = 32.0
## 블록 아랫변 ↔ 하단 바 (CONFIRM 의 아래 한계).
const SLOT_BAR_GAP: float = 20.0
## CONFIRM 에서 픽창이 빠지는 거리 — 필터 줄 윗변이 화면 아래끝을 이만큼 넘는다.
const PICK_EXIT_PAD: float = 40.0

# 칸 크기의 정본은 `UI_Comp_DraftSlot.tscn` — 일러스트 비율(204 : 412 = 0.495)은
# `PilotImages.BUST_ASPECT`(0.496)와 같다. 둘 중 하나만 바꾸면 얼굴이 찌그러진다.
const SLOT_COUNT: int = 5

# ─── 연출 ────────────────────────────────────────────────────────────────────
const MODE_ANIM_SEC: float = 0.38


static func create() -> TeamDraftView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TeamDraftView


@onready var _draft: TeamDraft = get_parent() as TeamDraft
@onready var _safe: Control = %Safe
@onready var _gauge: Control = $Safe/Gauge
@onready var _slot_row: Control = %SlotRow
@onready var _pick_root: Control = %PickPane
@onready var _filters: Control = %Filters
@onready var _grid: GridContainer = %Grid
@onready var _back_btn: Button = %Back
@onready var _next_btn: Button = %Next
@onready var _confirm_btn: Button = %Start

var _picks: Array = [-1, -1, -1, -1, -1]   # 슬롯 인덱스 → pilot id (-1 = 빈 칸)
var _thumbs_by_id: Dictionary = {}         # pilot_id(int) → PilotThumb
var _filter_role: int = -1                 # -1 = 전체

var _confirm_mode: bool = false
## 모드 전환 연출 / 게임 시작 전환이 도는 중 — 그 사이의 입력은 무시한다.
var _busy: bool = false
var _mode_tween: Tween
## 시작이 실패했을 때(`show_start_error`)의 문장. 다음 조작에서 지운다.
var _start_error: String = ""

var _slots: Array = []                     # 5 × DraftSlot (SLOT_ROLES 순)
var _filter_btns: Array = []
var _detail: DraftDetailPanel


func _ready() -> void:
	# 단독 실행이면 부모 `TeamDraft` 가 없다 — 아래 바인드 전에 미리보기 데이터 층을 꽂는다.
	if UiPreview.is_standalone(self):
		_fill_preview()
	mouse_filter = Control.MOUSE_FILTER_PASS
	OutgameTheme.fit_bottom_bar(%Bar, _safe)
	_bind_slots()
	_bind_filters()
	_fill_grid()
	_back_btn.pressed.connect(_on_back_pressed)
	_next_btn.pressed.connect(_on_next_pressed)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`). 썸네일을 누른 채 끌기
	# 시작하면 그 눌림은 취소되므로 스크롤하려던 손이 파일럿을 고르지 않는다.
	DragScroll.attach(%GridScroll)
	_detail = DraftDetailPanel.create()
	add_child(_detail)
	_refresh_slots()
	_apply_mode(false)


# ── 세로 배치 ────────────────────────────────────────────────────────────────
func _gauge_bottom() -> float:
	return _gauge.position.y + _gauge.size.y


## PICK 모드에서 선택 5인 블록이 앉는 y — 필터 줄 바로 위(게이지와는 겹치지 않게).
func _pick_row_y() -> float:
	return maxf(_gauge_bottom() + GAUGE_ROW_GAP,
			_filters.position.y - SLOT_FILTER_GAP - _slot_row.size.y)


## CONFIRM 모드에서 선택 5인 블록이 내려앉는 y — **화면(안전 영역)의 세로 가운데**.
## 게이지 아래 · 하단 바 위로만 걸러 낸다.
func _confirm_row_y() -> float:
	var lo: float = _gauge_bottom() + GAUGE_ROW_GAP
	var hi: float = maxf(lo, OutgameTheme.bottom_bar_top() - _slot_row.size.y - SLOT_BAR_GAP)
	return clampf((_safe.size.y - _slot_row.size.y) * 0.5, lo, hi)


# ── Bind ─────────────────────────────────────────────────────────────────────
# 안전 영역 들여쓰기와 배경은 `RunSetupScreen` 이 화면째 한다 — 여기서 또 하면
# 두 번 내려간다.
func _bind_slots() -> void:
	for c in _slot_row.get_children():
		var slot := c as DraftSlot
		if slot == null:
			continue
		var i: int = _slots.size()
		if i >= SLOT_COUNT:
			break
		slot.set_role(int(TeamDraft.SLOT_ROLES[i]))
		slot.art_pressed.connect(_on_slot_pressed.bind(i))
		slot.level_step.connect(func(delta: int) -> void: _on_level_step(i, delta))
		_slots.append(slot)


func _bind_filters() -> void:
	for c in _filters.get_children():
		var btn := c as Button
		if btn == null:
			continue
		var i: int = _filter_btns.size()
		# i == 0 이 "전체"(-1), 그 뒤는 `SLOT_ROLES` 와 같은 순서다.
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		_filter_btns.append(btn)
	_apply_filter_styles()


## 격자 순서는 **슬롯 순서 안에서 종합 스탯 내림차순**이다.
## `TeamDraft.get_pool_grid()` 는 역할 열거값 순서로 돌려주므로 여기서
## 슬롯 순서로 다시 묶는다.
func _fill_grid() -> void:
	var by_role: Dictionary = {}
	for entry_raw in _draft.get_pool_grid():
		var entry: Dictionary = entry_raw
		var r: int = int(entry["role"])
		if not by_role.has(r):
			by_role[r] = []
		(by_role[r] as Array).append(entry["pilot"])
	for role_raw in TeamDraft.SLOT_ROLES:
		var role: int = int(role_raw)
		for p_raw in by_role.get(role, []):
			var p := p_raw as PlayerData
			var thumb := PilotThumb.create()
			_grid.add_child(thumb)
			thumb.setup(p, false)
			thumb.thumb_tapped.connect(_on_thumb_tapped)
			_thumbs_by_id[p.id] = thumb
			_refresh_thumb_tag(p.id)


# ── 바깥에서 부르는 것 (RunSetupScreen) ─────────────────────────────────────
## 시나리오가 바뀌었을 때 — 캡과 그 판정만 다시 그린다.
func refresh_rules() -> void:
	_start_error = ""
	_refresh_rules()


## `GameManager.start_run` 이 거절했을 때. 입력을 다시 받고 문장을 띄운다.
func show_start_error(msg: String) -> void:
	_busy = false
	_start_error = msg
	_refresh_rules()


## 런 준비를 떠날 때 — 팝업은 CanvasLayer 라 부모의 `visible` 을 따르지 않는다.
func close_detail() -> void:
	if _detail != null:
		_detail.close()


## 역할 순(`GameEnums.Role`)으로 늘어놓은 고른 id — 빈 칸은 빠진다.
## `run_setup.pilot_ids` 가 이 순서다(계약 §10.2).
func picked_ids_role_order() -> Array:
	var ids: Array = []
	for role in SLOT_COUNT:
		var slot: int = TeamDraft.slot_of_role(role)
		if slot >= 0 and int(_picks[slot]) != -1:
			ids.append(int(_picks[slot]))
	return ids


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_filter_pressed(role: int) -> void:
	if _busy or _filter_role == role:
		return
	_filter_role = role
	_apply_filter_styles()
	_apply_filter()


## 필터 밖의 칸은 숨긴다 — `GridContainer` 가 숨긴 칸을 건너뛰고 보이는 칸만
## 5열로 다시 채우므로 빈 구멍이 남지 않는다.
func _apply_filter() -> void:
	for id in _thumbs_by_id:
		var thumb: PilotThumb = _thumbs_by_id[id]
		thumb.visible = _filter_role == -1 or int(thumb.pilot.role) == _filter_role


func _on_thumb_tapped(pilot_id: int) -> void:
	if _busy or not _thumbs_by_id.has(pilot_id):
		return
	var thumb: PilotThumb = _thumbs_by_id[pilot_id]
	var slot: int = TeamDraft.slot_of_role(int(thumb.pilot.role))
	if slot < 0:
		return

	if int(_picks[slot]) == pilot_id:
		_picks[slot] = -1
		thumb.set_selected(false)
	else:
		var prev_id: int = int(_picks[slot])
		if prev_id != -1 and _thumbs_by_id.has(prev_id):
			(_thumbs_by_id[prev_id] as PilotThumb).set_selected(false)
		_picks[slot] = pilot_id
		thumb.set_selected(true)
	_start_error = ""
	_refresh_slots()


func _on_slot_pressed(slot: int) -> void:
	if _busy:
		return
	var pid: int = int(_picks[slot])
	if pid == -1:
		return
	# 상세는 **고른 레벨이 반영된 사본**으로 연다 — 칸 아래의 종합과 팝업의
	# 스탯 칩이 같은 숫자여야 한다.
	var p: PlayerData = _draft.leveled(pid)
	if p != null:
		_detail.open(p)


func _on_level_step(slot: int, delta: int) -> void:
	if _busy:
		return
	var pid: int = int(_picks[slot])
	if pid == -1:
		return
	if _draft.set_level(pid, _draft.level_of(pid) + delta):
		_start_error = ""
		_refresh_thumb_tag(pid)
		_refresh_slots()


func _on_next_pressed() -> void:
	if _busy or _validation_error() != "":
		return
	_confirm_mode = true
	_apply_mode(true)


func _on_back_pressed() -> void:
	if _busy:
		return
	if not _confirm_mode:
		_detail.close()
		_draft.back_requested.emit()
		return
	_confirm_mode = false
	_apply_mode(true)


## PICK ↔ CONFIRM. 바꾸는 것은 셋뿐이다 — 픽창(필터 + 격자)의 자리,
## 선택 5인 블록의 y, 그리고 `다음` / `게임 시작` 중 무엇이 서는가.
func _apply_mode(animate: bool) -> void:
	var picking: bool = not _confirm_mode
	_next_btn.visible = picking
	_confirm_btn.visible = not picking
	_refresh_action_btns()

	var row_y: float = _pick_row_y() if picking else _confirm_row_y()
	# 픽창이 빠지는 거리 — 필터 줄 윗변이 화면 아래끝을 넘을 만큼.
	var pick_y: float = 0.0 if picking \
			else _safe.size.y - _filters.position.y + PICK_EXIT_PAD
	if _mode_tween != null and _mode_tween.is_valid():
		_mode_tween.kill()
	if not animate:
		_slot_row.position.y = row_y
		_pick_root.position.y = pick_y
		_pick_root.visible = picking
		_busy = false
		return

	_busy = true
	_pick_root.visible = true
	_mode_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_mode_tween.tween_property(_pick_root, "position:y", pick_y, MODE_ANIM_SEC)
	_mode_tween.tween_property(_slot_row, "position:y", row_y, MODE_ANIM_SEC)
	_mode_tween.chain().tween_callback(_on_mode_anim_done.bind(picking))


func _on_mode_anim_done(picking: bool) -> void:
	# 다 빠진 픽창은 숨긴다 — 화면 밖이라도 남아 있으면 스크롤 · 버튼이 계속
	# 입력 경로에 걸린다.
	_pick_root.visible = picking
	_busy = false


## **`게임 시작`** — 규칙 검사는 **암전 전에** 한다(거절될 시작이면 화면을
## 가리지 않는다). 런을 여는 일은 `RunSetupScreen` 이 한다.
func _on_confirm_pressed() -> void:
	if _busy:
		return
	var err: String = _validation_error()
	if err != "":
		_refresh_rules()
		return
	_busy = true
	_draft.start_requested.emit(picked_ids_role_order())


# ── Refresh ──────────────────────────────────────────────────────────────────
func _validation_error() -> String:
	return _draft.validate(picked_ids_role_order())


func _refresh_slots() -> void:
	for i in _slots.size():
		var slot: DraftSlot = _slots[i]
		var pid: int = int(_picks[i])
		var p: PlayerData = _draft.leveled(pid) if pid != -1 else null
		if p == null:
			slot.show_empty()
		else:
			var role: int = int(TeamDraft.SLOT_ROLES[i])
			slot.show_pilot(p, ROLE_COLORS[role], _draft.level_of(pid),
					_draft.max_level_of(pid), _draft.salary_of(pid))
	_refresh_rules()


## 게이지 · 규칙 줄 · 하단 버튼 잠금. 고를 때마다 다시 그린다.
func _refresh_rules() -> void:
	var ids: Array = picked_ids_role_order()
	var cap: int = _draft.salary_cap()
	var total: int = _draft.lineup_salary(ids)
	var over: bool = cap > 0 and total > cap
	var scen: Dictionary = RunRules.scenario(_draft.scenario_id)
	var title: Label = %GaugeTitle
	var value: Label = %GaugeValue
	var fill: ColorRect = %GaugeFill
	var gauge_msg: Label = %GaugeMsg
	title.text = "%s · 샐러리캡" % Loc.t(String(scen.get("name_key", "")))  # l10n-dynamic: scenario.*.name
	# M8 — trait `salary_cap` adjustment, when the manager preset carries one.
	var trait_adj: int = _draft.cap_bonus()
	if trait_adj != 0:
		title.text += " (특성 %s)" % ManagerUi.signed(trait_adj)
	value.text = "%d / %d" % [total, cap]
	value.add_theme_color_override("font_color",
			OutgameTheme.NEGATIVE if over else OutgameTheme.TEXT)
	var ratio: float = clampf(float(total) / float(cap), 0.0, 1.0) if cap > 0 else 0.0
	fill.anchor_right = ratio
	fill.color = OutgameTheme.NEGATIVE if over else OutgameTheme.ACCENT

	var err: String = _draft.validate(ids)
	var msg: String = err
	var col: Color = OutgameTheme.TEXT_SUB
	if _start_error != "":
		msg = "시작 실패: " + _start_error
		col = OutgameTheme.NEGATIVE
	elif over:
		# 다섯을 다 고르기 전이라도 캡을 넘겼으면 그것부터 말한다 — 빈 칸을
		# 채우면 더 넘칠 뿐이다.
		msg = "샐러리캡 초과 (%d / %d) — 레벨을 내리거나 다른 선수를 고르세요" % [total, cap]
		col = OutgameTheme.NEGATIVE
	elif ids.size() < SLOT_COUNT:
		msg = "포지션마다 1명씩 — %d / %d명" % [ids.size(), SLOT_COUNT]
	elif err != "":
		col = OutgameTheme.NEGATIVE
	else:
		msg = "편성 완료 — 남은 샐러리 %d" % (cap - total) if cap > 0 else "편성 완료"
		col = OutgameTheme.POSITIVE
	gauge_msg.text = msg
	gauge_msg.add_theme_color_override("font_color", col)
	_refresh_action_btns()


func _refresh_action_btns() -> void:
	var ok: bool = _validation_error() == ""
	_next_btn.disabled = not ok
	_confirm_btn.disabled = not ok


func _refresh_thumb_tag(pilot_id: int) -> void:
	var thumb: PilotThumb = _thumbs_by_id.get(pilot_id, null) as PilotThumb
	if thumb != null:
		thumb.set_tag(str(_draft.salary_of(pilot_id)))


func _apply_filter_styles() -> void:
	for i in _filter_btns.size():
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		var on: bool = role == _filter_role
		(_filter_btns[i] as Button).theme_type_variation = \
				&"SelectableTileOn" if on else &"SelectableTile"


## F6 단독 실행 미리보기 (`resources/UiPreview.gd`) — 부모 `TeamDraft` 대신 데이터 층을
## 하나 만들어 꽂는다: 풀 = game.db CSV 사본(`GameManager.load_match_data()`), 보유 =
## 실제 프로필(`ProfileManager`, `RunSetupScreen` 과 같은 길), 시나리오 = 표 첫 줄.
## `_ready` 가 끝난 뒤 캡 안에 드는 가장 센 다섯을 앉힌다(`_preview_seat` — "편성 완료" 상태).
## 뒤로 / 게임 시작은 받는 호스트(`RunSetupScreen`)가 없어 출력만 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var data: Dictionary = get_node("/root/GameManager").load_match_data()
	if data.has("error"):
		push_error("TeamDraftView 미리보기: " + String(data["error"]))
		return
	var pm: Node = get_node("/root/ProfileManager")
	var pool: Array = data["players"]
	RunRules.apply_breakthroughs(pool, pm.owned_breakthroughs())
	var scens: Array = RunRules.scenarios()
	var d := TeamDraft.new()
	d.name = "PreviewDraft"
	d.visible = false
	d.setup(pool, pm.owned_max_levels(),
			int((scens[0] as Dictionary).get("id", 0)) if not scens.is_empty() else 0)
	add_child(d)
	_draft = d
	UiPreview.trace(d.back_requested)
	UiPreview.trace(d.start_requested)
	_preview_seat.call_deferred()


## 미리보기 — 슬롯 순서대로, 남은 역할을 가장 싼 선수로 채워도 캡 안에 드는 한에서
## 종합이 가장 높은 선수를 고른다(격자 순서 = 역할 안 종합 내림차순).
func _preview_seat() -> void:
	var by_role: Dictionary = {}
	for raw in _draft.get_pool_grid():
		var e: Dictionary = raw
		var r: int = int(e["role"])
		if not by_role.has(r):
			by_role[r] = []
		(by_role[r] as Array).append((e["pilot"] as PlayerData).id)
	var cheapest: Array = []
	for role_raw in TeamDraft.SLOT_ROLES:
		var lo: int = 0
		for pid in by_role.get(int(role_raw), []):
			var sal: int = _draft.salary_of(int(pid))
			lo = sal if lo == 0 else mini(lo, sal)
		cheapest.append(lo)
	var cap: int = _draft.salary_cap()
	var spent: int = 0
	for i in TeamDraft.SLOT_ROLES.size():
		var rest: int = 0
		for j in range(i + 1, cheapest.size()):
			rest += int(cheapest[j])
		for pid in by_role.get(int(TeamDraft.SLOT_ROLES[i]), []):
			var sal: int = _draft.salary_of(int(pid))
			if cap <= 0 or spent + sal + rest <= cap:
				spent += sal
				_on_thumb_tapped(int(pid))
				break
