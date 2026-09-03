class_name DraftDetailPanel
extends CanvasLayer

# 파일럿 상세 팝업 — **아웃게임에서 파일럿 한 명을 들여다보는 유일한 자리**다.
#
#   좌: 전신 아트 한 장
#   우: 머리글(이름 · 역할 · 원소속) → 스탯 칩 6개 → 파일럿 스킬
#   하: 닫기
#
# 여는 자리가 둘이다 — **드래프트**(선택 슬롯의 상체 일러스트를 누른다)와
# **밴픽의 배정 단계**(양 팀 파일럿 초상화를 누른다). 그래서 이 팝업은
# `TeamDraft` 인스턴스를 요구하지 않는다 — 필요한 것은 `PlayerData` 한 장과
# 오토로드 `GameManager` 뿐이다.
#
# **카드는 보여 주지 않는다.** 예전에는 여기 "받게 될 파일럿 카드" 절이 있어
# 역할별 후보 풀 전부(7~14장)를 카드 노드로 깔았는데, 그 목록이 답하는 질문이
# 없었다 — 실제 3장은 경기 시작 시 표집되므로 드래프트에서 본 후보와 인게임에서
# 손에 잡히는 카드가 다르고, 후보 풀은 **역할이 정하는 것이라 선수를 고르는
# 판단에 들어가지 않는다**(같은 역할이면 누구를 뽑아도 같은 목록이다). 의미를
# 갖는 것은 인게임에서 확정된 카드뿐이고, 그건 `battle_sim/ui/PilotDetailPanel`
# 이 `BattleSim.starter_cards` 를 읽어 보여 준다. 그때 `TeamDraft` 의 후보 풀
# 헬퍼 넷(`pilot_card_slots_for_role` / `candidate_cards_for_role` /
# `slot_summary_for_role` / `cat_label`)도 함께 삭제됐다 — 이 팝업이 유일한
# 소비자였다. 배분 규칙 자체는 `CardPhaseManager._pilot_slots_for` 가 그대로
# 들고 있다(그쪽이 원본이다).
#
# 인게임의 `features/battle_sim/ui/PilotDetailPanel.gd` 와 **같은 언어**를 쓰되
# 같은 클래스가 아니다 — 저쪽은 `BattleSim` 오케스트레이터와 `PilotData`(런타임
# 상태)에 매달려 있고 이쪽이 가진 것은 `PlayerData`(시즌 영속 데이터)뿐이라,
# 상속으로 잇는 길은 저쪽의 `_bs` 의존을 통째로 선택적으로 만드는 일이 된다.
# 공유하는 것은 **모양**(좌 아트 / 우 칩 · 섹션)이지 구현이 아니다.
#
# **우측 본문은 여전히 스크롤된다.** 카드 격자가 빠져 지금은 대개 한 화면에
# 들어가지만, 스킬 설명문은 길이가 제각각이라 넘칠 때가 남는다 — 넘치면 잘리는
# 대신 굴러가야 한다. 닫기 버튼은 스크롤 **밖** 고정이다 — 목록 끝까지 내려가야
# 닫을 수 있는 모달은 모달이 아니다.

const OVERLAY_LAYER: int = 20

## 화면 크기는 고정 상수가 아니라 런타임 값이다 — 스트레치가 `expand` 라
## 세로로 긴 기기에서는 높이가 1920 보다 커진다. 딤 · 루트가 뷰포트 전체를
## 덮지 않으면 그 차이만큼 화면 끝에 안 덮인 띠가 남는다.
## `docs/mobile_safe_area.md` 참고.
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)

# ─── 좌: 전신 아트 ───────────────────────────────────────────────────────────
# 인게임 상세 패널과 같은 값 — 세로 1400 에 아래끝을 화면 밖(2010)에 두어
# 다리 아랫부분이 잘려 나간다. 전신 아트는 전부 세로 1024 에 인물이 꽉 차 있고
# 가로만 572~756 이라 **높이로 정규화**해야 파일럿마다 키가 같아진다.
const ART_H: float = 1400.0
const ART_BOTTOM: float = 2010.0
const ART_CENTER_X: float = 300.0
const ART_PLACEHOLDER_ASPECT: float = 0.70

# ─── 우: 정보 패널 ───────────────────────────────────────────────────────────
const PANEL_X: float = 596.0
const PANEL_W: float = 460.0
const PANEL_TOP: float = 150.0
const PANEL_BOTTOM: float = 1740.0
const PANEL_PAD: float = 22.0
const PANEL_BG := OutgameTheme.SURFACE
const PANEL_BORDER := OutgameTheme.BORDER

const HDR_NAME_FONT: int = 40
const HDR_SUB_FONT: int = 22
const SECTION_H: float = 36.0
const SECTION_FONT: int = 24
const SECTION_COLOR := OutgameTheme.TEXT_SUB

# ─── 스탯 칩 ─────────────────────────────────────────────────────────────────
const CHIP_COLS: int = 3
const CHIP_GAP: float = 12.0
const CHIP_H: float = 92.0
const CHIP_RADIUS: int = 16
const CHIP_BG := OutgameTheme.SURFACE_SUNK
const CHIP_BORDER := OutgameTheme.BORDER
const CHIP_NAME_FONT: int = 19
const CHIP_VALUE_FONT: int = 34
const CHIP_NAME_COLOR := OutgameTheme.TEXT_SUB
const CHIP_VALUE_COLOR := OutgameTheme.TEXT
const CHIP_TOTAL_COLOR := OutgameTheme.ACCENT_TEXT

# ─── 스킬 ────────────────────────────────────────────────────────────────────
const SKILL_NAME_FONT: int = 30
const SKILL_META_FONT: int = 19
const SKILL_DESC_FONT: int = 21
const SKILL_NAME_COLOR := OutgameTheme.ACCENT_TEXT
const SKILL_META_COLOR := OutgameTheme.TEXT_SUB
const SKILL_DESC_COLOR := OutgameTheme.TEXT

const CLOSE_H: float = 84.0

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
## 역할 색은 팔레트가 소유한다 — 화면마다 자기 배열을 들면 같은 역할이
## 화면마다 다른 색으로 그려진다.
const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

## 칩 목록 — 선수 스탯 여섯에 "종합" 한 칸을 더한다(3열 × 세 줄 중
## 마지막 한 칸은 비운다). 글자는 짧은 쪽을 쓴다 — 칩 한 칸이 141px 라
## "전장 명중" 은 들어가지만 줄바꿈 없이 꽉 차서 값과 붙어 보인다.
const STAT_KEYS: Array = ["전장 명중", "전장 회피", "교전 명중",
		"교전 회피", "공격 성장", "체력 성장"]

var _pilot: PlayerData = null
var _root: Control = null
## 받침의 실제 아래끝(내용이 정한다). 닫기 버튼이 이 값을 따라간다.
var _panel_bottom: float = PANEL_BOTTOM


func _init() -> void:
	layer = OVERLAY_LAYER


## 팝업을 연다. 필요한 것은 파일럿 한 명뿐이다 — 스킬 행과 카드 풀은 오토로드
## `GameManager` 에서 직접 읽는다.
func open(p: PlayerData) -> void:
	close()
	_pilot = p
	if p == null:
		return
	_build()


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null


func is_open() -> bool:
	return _root != null and is_instance_valid(_root)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	# CanvasLayer 아래의 Control 은 앵커 프리셋이 뷰포트로 풀리지 않는다 —
	# 크기를 직접 준다.
	_root.position = Vector2.ZERO
	_root.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 딤은 클릭을 먹어 뒤의 격자로 새지 않게 하고, 빈 곳을 누르면 닫힌다.
	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.position = Vector2.ZERO
	dim.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	dim.pressed.connect(close)
	_root.add_child(dim)

	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.position = Vector2.ZERO
	dim_rect.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	_build_art()
	_build_panel()
	_build_close()


func _build_art() -> void:
	var tex: Texture2D = PilotImages.full_for(_pilot.id)
	if tex == null:
		var slab := ColorRect.new()
		slab.color = Color(0.30, 0.33, 0.42, 0.14)
		var slab_w: float = ART_H * ART_PLACEHOLDER_ASPECT
		slab.size = Vector2(slab_w, ART_H)
		slab.position = Vector2(ART_CENTER_X - slab_w * 0.5, ART_BOTTOM - ART_H)
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(slab)
		return
	# 높이 정규화 — 폭으로 맞추면 아트마다 인물 키가 제각각이 된다.
	var aspect: float = float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	var art_w: float = ART_H * aspect
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = Vector2(art_w, ART_H)
	rect.position = Vector2(ART_CENTER_X - art_w * 0.5, ART_BOTTOM - ART_H)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)


func _build_panel() -> void:
	var panel_h: float = PANEL_BOTTOM - PANEL_TOP
	var backdrop := Panel.new()
	backdrop.position = Vector2(PANEL_X, PANEL_TOP)
	backdrop.size = Vector2(PANEL_W, panel_h)
	var sty := StyleBoxFlat.new()
	sty.bg_color = PANEL_BG
	sty.border_color = PANEL_BORDER
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 14
	sty.corner_radius_top_right    = 14
	sty.corner_radius_bottom_left  = 14
	sty.corner_radius_bottom_right = 14
	backdrop.add_theme_stylebox_override("panel", sty)
	_root.add_child(backdrop)

	var inner_w: float = PANEL_W - PANEL_PAD * 2.0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(PANEL_X + PANEL_PAD, PANEL_TOP + PANEL_PAD)
	scroll.size = Vector2(inner_w, panel_h - PANEL_PAD * 2.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	# 스크롤 안쪽은 컨테이너가 아니라 좌표로 쌓는다 — 칩 격자와 카드 격자가
	# 둘 다 2차원이라 VBox 로는 행마다 컨테이너를 하나씩 더 세워야 한다.
	# ScrollContainer 는 자식의 `custom_minimum_size` 로 스크롤 범위를 잡으므로
	# 마지막에 그 값만 실제 높이로 채워 주면 된다.
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)

	var y: float = 0.0
	y = _build_header(body, inner_w, y)
	y = _build_stat_chips(body, inner_w, y + 18.0)
	y = _build_skill_block(body, inner_w, y + 22.0)

	body.custom_minimum_size = Vector2(inner_w, y + 12.0)
	body.size = Vector2(inner_w, y + 12.0)

	# **받침 높이는 내용이 정한다** — 위쪽은 `PANEL_TOP` 에 못박고 아래끝만
	# 내용에 맞춰 올라온다(넘치면 `PANEL_BOTTOM` 에서 멈추고 그때부터 스크롤이
	# 일한다). 카드 격자가 있던 시절에는 언제나 꽉 찼으므로 고정 높이로 두어도
	# 됐지만, 지금은 스탯 칩과 스킬 한 문단뿐이라 고정으로 두면 받침 아래
	# 절반이 텅 빈 흰 판으로 남는다.
	var content_h: float = y + 12.0 + PANEL_PAD * 2.0
	var panel_h2: float = minf(content_h, panel_h)
	backdrop.size = Vector2(PANEL_W, panel_h2)
	scroll.size = Vector2(inner_w, panel_h2 - PANEL_PAD * 2.0)
	_panel_bottom = PANEL_TOP + panel_h2


func _build_header(body: Control, w: float, y: float) -> float:
	var name_lbl := UiHelpers.mk_label(body, _pilot.name, HDR_NAME_FONT,
			OutgameTheme.TEXT, Vector2(0, y), Vector2(w, 52))
	name_lbl.clip_text = true
	y += 54.0

	var r: int = int(_pilot.role)
	var role_name: String = String(ROLE_NAMES[r]) if r >= 0 and r < ROLE_NAMES.size() else "?"
	var role_col: Color = ROLE_COLORS[r] if r >= 0 and r < ROLE_COLORS.size() else OutgameTheme.TEXT
	var slot: int = TeamDraft.slot_of_role(r)
	var slot_name: String = String(TeamDraft.SLOT_NAMES[slot]) if slot >= 0 else "?"
	var sub := UiHelpers.mk_label(body,
			"%s · %s · 원소속 %s" % [slot_name, role_name, _team_short(_pilot.team_id)],
			HDR_SUB_FONT, role_col, Vector2(0, y), Vector2(w, 28))
	sub.clip_text = true
	return y + 30.0


func _build_stat_chips(body: Control, w: float, y: float) -> float:
	y = _section(body, w, y, "선수 능력치")
	var chip_w: float = (w - CHIP_GAP * float(CHIP_COLS - 1)) / float(CHIP_COLS)
	var n: int = STAT_KEYS.size() + 1      # 스탯 여섯 + 종합
	for i in n:
		var col: int = i % CHIP_COLS
		@warning_ignore("integer_division")
		var row: int = i / CHIP_COLS
		var at := Vector2(float(col) * (chip_w + CHIP_GAP),
				y + float(row) * (CHIP_H + CHIP_GAP))
		var is_total: bool = i == STAT_KEYS.size()
		var key: String = "종합" if is_total else String(STAT_KEYS[i])
		var val: int = PilotThumb.total_stats(_pilot) if is_total 				else int(_pilot.get(String(PlayerData.STAT_KEYS[i])))
		_mk_chip(body, at, Vector2(chip_w, CHIP_H), key, str(val),
				CHIP_TOTAL_COLOR if is_total else CHIP_VALUE_COLOR)
	@warning_ignore("integer_division")
	var rows: int = (n + CHIP_COLS - 1) / CHIP_COLS
	return y + CHIP_H * float(rows) + CHIP_GAP * float(rows - 1)


func _mk_chip(body: Control, at: Vector2, sz: Vector2, key: String,
		val: String, val_color: Color) -> void:
	var chip := Panel.new()
	chip.position = at
	chip.size = sz
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color = CHIP_BG
	sty.border_color = CHIP_BORDER
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = CHIP_RADIUS
	sty.corner_radius_top_right    = CHIP_RADIUS
	sty.corner_radius_bottom_left  = CHIP_RADIUS
	sty.corner_radius_bottom_right = CHIP_RADIUS
	chip.add_theme_stylebox_override("panel", sty)
	body.add_child(chip)

	UiHelpers.mk_label(chip, key, CHIP_NAME_FONT, CHIP_NAME_COLOR,
			Vector2(0, 10), Vector2(sz.x, 24), HORIZONTAL_ALIGNMENT_CENTER)
	var v := UiHelpers.mk_label(chip, val, CHIP_VALUE_FONT, val_color,
			Vector2(0, 36), Vector2(sz.x, 44), HORIZONTAL_ALIGNMENT_CENTER)
	v.clip_text = true


func _build_skill_block(body: Control, w: float, y: float) -> float:
	y = _section(body, w, y, "파일럿 스킬")
	var sk: Dictionary = _skill_def()
	if sk.is_empty():
		# 모브는 여기서 자기 정체를 말한다 — 스탯 10% 하향보다 이쪽이 크다.
		UiHelpers.mk_label(body, "고유 스킬 없음 (이름 없는 선수)",
				SKILL_DESC_FONT, SKILL_META_COLOR, Vector2(0, y), Vector2(w, 30))
		return y + 32.0

	var name_lbl := UiHelpers.mk_label(body, String(sk.get("name", "?")),
			SKILL_NAME_FONT, SKILL_NAME_COLOR, Vector2(0, y), Vector2(w, 40))
	name_lbl.clip_text = true
	y += 42.0

	var meta: String = TeamDraft.skill_type_label(String(sk.get("type", "")))
	var kw: String = String(sk.get("keyword", ""))
	if not kw.is_empty():
		meta += " · " + kw
	UiHelpers.mk_label(body, meta, SKILL_META_FONT, SKILL_META_COLOR,
			Vector2(0, y), Vector2(w, 26))
	y += 28.0

	return y + _wrapped_label(body, w, y, String(sk.get("description", "")),
			SKILL_DESC_FONT, SKILL_DESC_COLOR)


## 줄바꿈되는 문단 한 덩이. **실제 높이는 폰트가 정한다** — 손으로 재면 긴
## 설명문이 아래 블록을 덮는다. 반환값은 그 높이다.
func _wrapped_label(body: Control, w: float, y: float, text: String,
		font_size: int, color: Color) -> float:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(0, y)
	lbl.custom_minimum_size = Vector2(w, 0)
	body.add_child(lbl)
	var h: float = lbl.get_minimum_size().y
	lbl.size = Vector2(w, h)
	return h


func _section(body: Control, w: float, y: float, title: String) -> float:
	var lbl := UiHelpers.mk_label(body, title, SECTION_FONT, SECTION_COLOR,
			Vector2(0, y), Vector2(w, SECTION_H))
	lbl.clip_text = true
	return y + SECTION_H


func _build_close() -> void:
	var btn := Button.new()
	btn.text = "닫기"
	OutgameTheme.style_ghost_button(btn, 30)
	btn.focus_mode = Control.FOCUS_NONE
	# 받침 아래끝에 붙어 다닌다 — 인게임 상세 패널(`_reposition_close`)과 같은
	# 규칙이다. 고정 y 에 두면 내용이 짧은 파일럿에서 버튼만 허공에 뜬다.
	btn.position = Vector2(PANEL_X, _panel_bottom + 16.0)
	btn.size = Vector2(PANEL_W, CLOSE_H)
	# **불투명 스타일이 필수다.** 이 자리는 드래프트 화면의 "드래프트 확정"
	# 버튼과 겹치는데, 기본 Button 테마는 반투명이라 딤 아래의 그 글자가
	# 비쳐 "닫기"와 "드래프트 확정"이 한 칸에 겹쳐 읽혔다.
	var sty := StyleBoxFlat.new()
	sty.bg_color = OutgameTheme.SURFACE
	sty.border_color = OutgameTheme.BORDER_STRONG
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 10
	sty.corner_radius_top_right    = 10
	sty.corner_radius_bottom_left  = 10
	sty.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  sty)
	btn.add_theme_stylebox_override("hover",   sty)
	btn.add_theme_stylebox_override("pressed", sty)
	btn.add_theme_stylebox_override("focus",   sty)
	btn.pressed.connect(close)
	_root.add_child(btn)


## 이 선수의 고유 스킬 행. 모브(스킬 없음)는 빈 Dictionary 를 돌려준다.
func _skill_def() -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or _pilot == null or _pilot.skill_id < 0:
		return {}
	return gm.skill_def(_pilot.skill_id)


func _team_short(team_id: int) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return "T%d" % team_id
	var meta: Array = gm.season_state.get("team_meta", [])
	if team_id < 0 or team_id >= meta.size():
		return "T%d" % team_id
	return String(meta[team_id]["short_name"])
