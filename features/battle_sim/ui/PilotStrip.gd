class_name PilotStrip
extends Control

# 파일럿 5인 스트립 — **원형 초상 5개를 가로로 나란히** 놓고, 원 아래로
# 늘어진 둥근 탭에 성장치 숫자를 찍는다(Deadlock 중계 HUD 의 초상 줄).
# 스트립 뒤판(배경)과 초상 원의 테두리는 없다.
#
# **레이아웃의 정본은 `UI_Comp_PilotStrip.tscn`(스트립 + `%Row`) 과 `UI_Comp_PilotStripCell.tscn`(한 칸)
# 이다.** 이 스크립트는 칸 노드를 묶고, 팀색 · 그림 · 숫자를 넣고, 누르기를 판정한다.
# 칸 치수(원 지름 · 흉상 칸 · 탭 · 배지 자리)는 씬에 박혀 있고, 코드는 거기서 읽는다
# (`anchor_for` · `pilot_at` · 누름 축).
#
# 한 칸의 초상은 **팀색 원 + 그 위의 머리~어깨 흉상**이다. 흉상은
# `shaders/pilot_bust_mask.gdshader` 가 잘라 낸다 — 원 중심 아래는 원 모양으로,
# 그 위는 원 **폭**으로만 잘라 머리가 원 위로 튀어나온다. 흉상 칸의 위쪽
# 1/5 이 그 돌출부 몫이다(`PilotImages.STRIP_ASPECT` = 0.8).
#
# 화면에 두 벌이 있다(`UI_View_BattleHud.tscn` 에 인스턴스):
#   • 적 팀 — 화면 **최상단**. (`EnemyTopLayer/%EnemyPilotStrip`)
#   • 아군  — **핸드 행보다 아래**. (`Canvas/%PlayerPilotStrip`)
# 누르는 동안 그 초상이 `BattleRenderer.PRESS_SCALE` 로 커진다(전장 초상과 같은
# 감각). **아군**은 짧은 탭 = 스킬 말풍선(`SkillPopup`), 꾹 누르기
# (`MarkerTouch.LONG_PRESS_SEC`) = 파일럿 상세 패널. **적**은 탭 / 꾹 누르기
# 모두 상세 패널. 신호만 쏘고 무엇을 열지는 `HudBuilder` 가 정한다.
# 게이트는 `PilotDetailPanel.can_open`(`set_interactive_enabled`).
#
# **체력 바는 삭제됐다** — 원형 초상으로 바뀌며 원 아래에는 성장치 배지만
# 남겼다. 체력은 전장 마커와 상세 패널이 보여 준다.
#
# **성장치는 게이지가 아니라 숫자다** — 상한이 없어서 채울 바탕이 없다.
# 개시 0.50k 에서 시작해 처치 / 피해 / 오브젝트로 오른다(`BattleSim` 의
# `SCORE_*` 절 참고).

## 짧게 눌렀다 뗐을 때(칸 안에서).
signal pilot_tapped(pilot: PilotData)
## `LONG_PRESS_SEC` 동안 누르고 있을 때 — 그 누름의 뗌은 탭이 되지 않는다.
signal pilot_long_pressed(pilot: PilotData)

const SLOT_COUNT: int = 5

## 원 바탕색 — 팀색. [아군, 적]. 성장치 탭도 같은 색이라 원에서 이어져 내려온
## 한 덩어리로 읽힌다(흰 판 팔레트에서도 일부러 팀색 그대로 — `BattleTheme` PilotStripScoreTab).
const DISC_COLOR := BattleTheme.TEAM_DISC
## 스킬 배지의 (스택이 없을 때) 테두리색. (초상 원 자체의 테두리는 삭제됐다 —
## 씬의 셰이더 재질이 `rim_width = 0` 이다.)
const TEAM_RIM := BattleTheme.TEAM_RIM
## 쓰러진 파일럿의 **흉상**에 씌우는 틴트(원은 제외).
const DEAD_TINT        := BattleTheme.DEAD_TINT
## **역할 태그는 삭제됐다.** 스트립의 자리 순서 자체가 이미 역할이다
## (`GameEnums.ROLE_DISPLAY_ORDER` — 탑 · 정글 · 미드 · 원딜 · 서폿).

var _team: int = 0

var _cells: Array = []          # Array[Dictionary] — `_bind_cell` 참고
## 누르고 있는 칸(-1 = 없음), 누른 시간, 꾹 누르기가 이미 터졌는가.
var _held_idx: int = -1
var _held_t: float = 0.0
var _long_fired: bool = false
var _pilots: Array = []         # Array[PilotData]
var _bs: BattleSim = null


func _ready() -> void:
	var idx: int = 0
	for raw in %Row.get_children():
		var cell := raw as Control
		if cell == null:
			continue
		_cells.append(_bind_cell(cell, idx))
		idx += 1
	if UiPreview.is_standalone(self):
		_fill_preview()


## 이 스트립이 어느 팀인가 — 팀색(원 · 성장치 탭)을 칠하고, 적이면 스킬 배지를
## 지운다(스킬은 아군만 쓴다). 자리 · 크기는 씬(`UI_View_BattleHud.tscn`)이 정한다.
func setup(bs: BattleSim, team: int) -> void:
	_bs = bs
	_team = team
	for raw in _cells:
		var cell: Dictionary = raw
		var tab := BattleTheme.variation_box(&"PilotStripScoreTab")
		tab.bg_color = DISC_COLOR[_team]
		(cell["pill"] as Panel).add_theme_stylebox_override("panel", tab)
		(cell["mat"] as ShaderMaterial).set_shader_parameter("disc_color", DISC_COLOR[_team])
		var badge := cell["badge"] as SkillBadge
		if badge == null:
			continue
		if _team == 0:
			badge.setup(badge.size.x, TEAM_RIM[_team])
		else:
			badge.queue_free()
			cell["badge"] = null


## 칸 씬 하나를 묶는다. 원 중심 · 흉상 위끝은 `%Bust` 의 자리에서 나온다(셀 로컬,
## 누름 확대와 무관한 고정값).
func _bind_cell(cell: Control, idx: int) -> Dictionary:
	var holder := cell.get_node("%Holder") as Control
	var bust := cell.get_node("%Bust") as ColorRect
	# 씬의 재질은 칸 인스턴스끼리 공유된다 — 칸마다 그림 · 틴트가 달라야 하므로 복제한다.
	var mat := (bust.material as ShaderMaterial).duplicate() as ShaderMaterial
	bust.material = mat
	mat.set_shader_parameter("rect_size", bust.size)
	var r: float = bust.size.x * 0.5
	var disc_c := bust.position + Vector2(r, bust.size.y - r)
	holder.pivot_offset = disc_c
	var btn := cell.get_node("%Hit") as Button
	btn.button_down.connect(func() -> void: _on_cell_down(idx))
	btn.pressed.connect(func() -> void: _on_cell_tapped(idx))
	btn.button_up.connect(func() -> void: _on_cell_up(idx))
	return {
		"cell": cell, "holder": holder,
		"bust": bust, "mat": mat, "dead": cell.get_node("%Dead"),
		"pill": cell.get_node("%Pill"), "score": cell.get_node("%Score"), "btn": btn,
		"badge": cell.get_node("%Badge"),
		"mood": cell.get_node("%Mood"),
		# 스킬 말풍선 화살표가 가리킬 점 — 머리 위끝 가운데(셀 로컬).
		"head": bust.position + Vector2(r, 0.0),
	}


# ─── 누르기 ──────────────────────────────────────────────────────────────────
# `BaseButton` 은 뗄 때 `pressed` → `button_up` 순으로 쏜다. 칸 밖에서 떼면
# `pressed` 가 없다(탭 취소).
func _on_cell_down(idx: int) -> void:
	if idx >= _pilots.size():
		return
	_set_pressed_visual(_held_idx, false)
	_held_idx = idx
	_held_t = 0.0
	_long_fired = false
	_set_pressed_visual(idx, true)


func _on_cell_tapped(idx: int) -> void:
	if idx != _held_idx or _long_fired or idx >= _pilots.size():
		return
	pilot_tapped.emit(_pilots[idx] as PilotData)


func _on_cell_up(idx: int) -> void:
	if idx != _held_idx:
		return
	_set_pressed_visual(idx, false)
	_held_idx = -1


func _process(delta: float) -> void:
	if _held_idx < 0 or _long_fired:
		return
	var btn: Button = (_cells[_held_idx] as Dictionary)["btn"]
	# 비활성으로 바뀌었으면(단계 전환) 누름 자체를 취소한다.
	if btn == null or btn.disabled or not is_visible_in_tree():
		_set_pressed_visual(_held_idx, false)
		_held_idx = -1
		return
	# 손가락이 칸 밖으로 나가 있는 동안은 꾹 누르기를 세지 않는다.
	if btn.get_draw_mode() != BaseButton.DRAW_PRESSED:
		_held_t = 0.0
		return
	_held_t += delta
	if _held_t < MarkerTouch.LONG_PRESS_SEC:
		return
	_long_fired = true
	_set_pressed_visual(_held_idx, false)
	if _held_idx < _pilots.size():
		Haptics.play(Haptics.Kind.MEDIUM)
		pilot_long_pressed.emit(_pilots[_held_idx] as PilotData)


## **숨겨지면 누름을 통째로 버린다.** 꾹 누르기로 상세 패널이 열리면 그 패널이
## 이 스트립을 손가락이 아직 닿아 있는 채로 숨긴다(`HudBuilder.set_strip_visible`)
## — 그러면 떼는 이벤트가 버튼에 닿지 않아 (1) `BaseButton` 이 속으로 "눌림 중"
## 으로 남아 다음 터치에 `button_down` 을 쏘지 않고, (2) `_long_fired` 도 서 있어
## 그 터치의 `pressed` 가 탭으로 인정되지 않았다. 패널을 닫은 뒤 **첫 터치가
## 통째로 먹히던** 원인이다(실측: 터치 경로에서만 — 마우스 `push_input` 은 재현 안 됨).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_cancel_press()


func _cancel_press() -> void:
	_set_pressed_visual(_held_idx, false)
	_held_idx = -1
	_held_t = 0.0
	_long_fired = false
	# `BaseButton` 의 속 누름 상태는 비활성으로 한 번 돌려야만 풀린다
	# (`set_disabled(true)` 가 press_attempt 를 지운다) — 원래 값으로 되돌린다.
	for raw in _cells:
		var btn: Button = (raw as Dictionary)["btn"]
		if btn != null and not btn.disabled:
			btn.disabled = true
			btn.disabled = false


## 눌린 칸의 그림을 `PRESS_SCALE` 로 키우고 이웃 칸 위로 올린다(뗄 때 되돌림).
func _set_pressed_visual(idx: int, on: bool) -> void:
	if idx < 0 or idx >= _cells.size():
		return
	var cell: Dictionary = _cells[idx]
	var holder := cell["holder"] as Control
	holder.z_index = 1 if on else 0
	var prev: Tween = cell.get("tween")
	if prev != null and prev.is_valid():
		prev.kill()
	var tw := holder.create_tween()
	cell["tween"] = tw
	tw.tween_property(holder, "scale",
			Vector2.ONE * (BattleRenderer.PRESS_SCALE if on else 1.0),
			BattleRenderer.PRESS_TWEEN_SEC)


## 칸 `p` 의 머리 위끝 가운데(전역 좌표) — 스킬 말풍선 화살표가 가리킬 점.
## 이 스트립에 없는 파일럿이면 null.
func anchor_for(p: PilotData) -> Variant:
	var idx: int = _pilots.find(p)
	if idx < 0 or idx >= _cells.size():
		return null
	var cell: Dictionary = _cells[idx]
	return (cell["cell"] as Control).get_global_transform() * (cell["head"] as Vector2)


## 전역 좌표 `pos` 가 어느 칸의 히트 영역 안에 있는가 — 그 파일럿, 없으면 null.
func pilot_at(pos: Vector2) -> PilotData:
	for i in mini(_cells.size(), _pilots.size()):
		var cell := (_cells[i] as Dictionary)["cell"] as Control
		var local: Vector2 = cell.get_global_transform().affine_inverse() * pos
		if Rect2(Vector2.ZERO, cell.size).has_point(local):
			return _pilots[i] as PilotData
	return null


## 이 스트립이 보여 줄 파일럿 5인. `HudBuilder` 가 역할 순으로 정렬해 넘긴다.
func set_pilots(list: Array) -> void:
	_pilots = list
	refresh()


## 입력 게이트. 자기 작전 단계가 아닐 때는 눌러도 아무 일이 없어야 한다.
func set_interactive_enabled(on: bool) -> void:
	for raw in _cells:
		var btn: Button = (raw as Dictionary)["btn"]
		if btn != null:
			btn.disabled = not on


func refresh() -> void:
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		if i >= _pilots.size():
			_set_cell_visible(cell, false)
			continue
		_set_cell_visible(cell, true)
		_apply_cell(cell, _pilots[i] as PilotData)


static func _set_cell_visible(cell: Dictionary, on: bool) -> void:
	(cell["bust"] as ColorRect).visible = on
	(cell["pill"] as Panel).visible = on
	(cell["score"] as Label).visible = on
	if not on:
		(cell["dead"] as Label).visible = false
		(cell["mood"] as Label).visible = false
		if cell["badge"] != null:
			(cell["badge"] as SkillBadge).visible = false


func _apply_cell(cell: Dictionary, p: PilotData) -> void:
	var mat := cell["mat"] as ShaderMaterial
	var tex: Texture2D = PilotImages.strip_for(p.pilot_id)
	mat.set_shader_parameter("has_portrait", tex != null)
	mat.set_shader_parameter("portrait", tex)
	mat.set_shader_parameter("tint", Color.WHITE if p.alive else DEAD_TINT)

	var dead_lbl := cell["dead"] as Label
	dead_lbl.visible = not p.alive
	if not p.alive:
		# 미리보기(전투 없음)에는 씬의 샘플 숫자를 그대로 둔다.
		if _bs != null:
			dead_lbl.text = str(_bs.turns_until_return(p))

	(cell["score"] as Label).text = fmt_strip_score(p.score)
	_apply_skill_state(cell, p)
	# 스트레스 상태(위축 · 각성 · 패닉) — 내 파일럿에게만 있다.
	var mood_lbl := cell["mood"] as Label
	var mood: int = _bs.stress.mood_of(p) if _bs != null and _bs.stress != null \
			else StressSystem.Mood.NONE
	mood_lbl.visible = mood != StressSystem.Mood.NONE
	if mood_lbl.visible:
		mood_lbl.text = StressSystem.mood_label(mood)
		mood_lbl.theme_type_variation = StressEvents.mood_variation(mood)


## 스트립 탭의 성장치 표기 — 소수 한 자리(`9.9k`), **10k 이상은 정수**(`12k`).
## 상세 패널은 여전히 `BattleSim.fmt_score`(소수 두 자리)를 쓴다 — 탭은 원
## 지름의 58% 폭이라 자릿수가 적어야 한다. 9.95 이상은 `%.1f` 가 `10.0` 으로
## 올라가므로 그 자리부터 정수 표기로 넘긴다.
static func fmt_strip_score(v: float) -> String:
	if absf(v) >= 9.95:
		return "%.0fk" % v
	return "%.1fk" % v


## 스킬 배지. **아군 스트립에만** 있다 — 스킬은 아군만 쓴다.
## 딤드 기준은 **자원**(`is_ready`)과 생존이다 — 상대 차례라도 준비된 스킬은
## 밝다. 패시브는 상시 적용이라 늘 밝다(쓰러졌을 때만 딤드).
func _apply_skill_state(cell: Dictionary, p: PilotData) -> void:
	var badge := cell["badge"] as SkillBadge
	if badge == null:
		return
	var sk: PilotSkillSystem = _bs.skill if _bs != null else null
	if sk == null or not sk.has_skill(p):
		badge.visible = false
		return
	badge.visible = true
	var icon: Texture2D = SkillImages.icon_for(String(sk.def_for(p).get("key", "")))
	var lit: float = 1.0
	var stack_max: int = 0
	var number: String = ""
	match sk.skill_type(p):
		PilotSkillSystem.TYPE_COOLDOWN:
			lit = sk.progress(p)
			var left: int = sk.cooldown_left(p)
			if left > 0:
				number = str(left)
		PilotSkillSystem.TYPE_CHARGE:
			lit = 1.0 if sk.is_ready(p) else 0.0
			stack_max = sk.max_charge_of(p)
		_:
			stack_max = sk.max_charge_of(p)
	if not p.alive:
		lit = 0.0
	var stack: int = sk.charge_of(p)
	if stack_max > SkillBadge.STACK_SEGMENT_MAX and number.is_empty():
		number = str(stack)
	badge.set_state(icon, lit, stack_max, stack, number)


## 단독 실행(F6) 미리보기 — 전투 없이 손으로 만든 아군 다섯(한 명은 쓰러짐)과
## 스킬 배지 하나(쿨타임 2턴 남음). 바탕은 전장 회색.
func _fill_preview() -> void:
	UiPreview.stage(self)
	RenderingServer.set_default_clear_color(BattleTheme.PREVIEW_FIELD)
	setup(null, 0)
	var list: Array = []
	for i in SLOT_COUNT:
		var p := PilotData.new(GameEnums.ROLE_DISPLAY_ORDER[i], 0, Vector2i.ZERO,
				{"hp": 100, "atk": 10})
		p.pilot_id = i
		p.score = 0.5 + float(i) * 2.37
		p.alive = i != 1
		list.append(p)
	set_pilots(list)
	UiPreview.trace(pilot_tapped)
	UiPreview.trace(pilot_long_pressed)
	var badge := (_cells[0] as Dictionary)["badge"] as SkillBadge
	badge.visible = true
	badge.set_state(null, 0.4, 0, 0, "2")
