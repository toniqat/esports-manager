class_name DraftDetailPanel
extends CanvasLayer

# 파일럿 상세 팝업 — **아웃게임에서 파일럿 한 명을 들여다보는 유일한 자리**다.
#
#   좌: 전신 아트 한 장
#   우: 머리글(이름 · 역할 · 원소속) → 스탯 칩 6개 → 파일럿 스킬 → 후보 카드
#   하: 닫기
#
# 여는 자리가 둘이다 — **드래프트**(선택 슬롯의 상체 일러스트를 누른다)와
# **밴픽의 배정 단계**(양 팀 파일럿 초상화를 누른다). 그래서 이 팝업은
# `TeamDraft` 인스턴스를 요구하지 않는다: 필요한 것은 `PlayerData` 한 장과
# 오토로드 `GameManager` 뿐이고, 후보 카드 목록은 `TeamDraft` 의 **static**
# 함수에 카드 풀을 직접 넘겨 받는다.
#
# 인게임의 `features/battle_sim/ui/PilotDetailPanel.gd` 와 **같은 언어**를 쓰되
# 같은 클래스가 아니다 — 저쪽은 `BattleSim` 오케스트레이터와 `PilotData`(런타임
# 상태)에 매달려 있고 이쪽이 가진 것은 `PlayerData`(시즌 영속 데이터)뿐이라,
# 상속으로 잇는 길은 저쪽의 `_bs` 의존을 통째로 선택적으로 만드는 일이 된다.
# 공유하는 것은 **모양**(좌 아트 / 우 칩 · 섹션)과 카드 노드이지 구현이 아니다.
#
# **우측 본문은 스크롤된다.** 후보 카드가 역할에 따라 7~14장이라(드로우 풀만
# 11종) 고정 높이 패널에 다 세울 수 없고, 잘라 내면 "이 역할이 무엇을 받는가"를
# 반만 보여 주게 된다. 닫기 버튼은 스크롤 **밖** 고정이다 — 목록 끝까지 내려가야
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

# ─── 후보 카드 ───────────────────────────────────────────────────────────────
# 3열이라 축소율이 곧 열 폭이다 — 0.80 에서 한 장이 128px 이고 3열 + 간격 24 가
# 패널 안쪽 폭(416)에 딱 들어간다(408). 인게임 상세 패널과 같은 축소율이라
# 같은 카드가 두 화면에서 같은 크기로 읽힌다. 처음에 0.62 로 잡았더니 카드
# 이름이 뭉개져 색 슬래브 열세 장이 됐다 — 후보를 "보여 준다"는 목적이 사라진다.
const CARD_SCENE := preload("res://scenes/Card.tscn")
const CARD_VIEW_SCALE: float = 0.80
const CARD_COLS: int = 3
const CARD_GAP: float = 12.0
const CARD_NOTE_FONT: int = 18
const CARD_NOTE_COLOR := OutgameTheme.TEXT_SUB

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
	y = _build_card_sections(body, inner_w, y + 22.0)

	body.custom_minimum_size = Vector2(inner_w, y + 12.0)
	body.size = Vector2(inner_w, y + 12.0)


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


func _build_card_sections(body: Control, w: float, y: float) -> float:
	var r: int = int(_pilot.role)
	# 슬롯 내역은 **제목이 아니라 설명문**에 있다. 제목에 붙이면 "받게 될 파일럿
	# 카드 (라인전 2 · 드로우 1)" 이 한 줄에 안 들어가 `clip_text` 가 끝을 잘라
	# 낸다 — 섹션 제목은 잘리면 안 되는 자리다.
	y = _section(body, w, y, "받게 될 파일럿 카드")
	y += _wrapped_label(body, w, y,
			"%s. 아래는 이 역할이 뽑을 수 있는 후보 전부이고, 실제 3장은 경기 시작 시 표집된다."
					% TeamDraft.slot_summary_for_role(r),
			CARD_NOTE_FONT, CARD_NOTE_COLOR) + 10.0

	for slot_raw in TeamDraft.pilot_card_slots_for_role(r):
		var slot: Array = slot_raw as Array
		var cat: String = String(slot[0])
		var picks: int = int(slot[1])
		var cards: Array = _cards_in_cat(r, cat)
		if cards.is_empty():
			continue
		var lbl := UiHelpers.mk_label(body,
				"%s 슬롯 — 후보 %d종 중 %d장" % [
					TeamDraft.cat_label(cat), cards.size(), picks],
				20, OutgameTheme.TEXT_SUB, Vector2(0, y), Vector2(w, 28))
		lbl.clip_text = true
		y += 30.0
		y = _build_card_grid(body, w, y, cards) + 18.0
	return y


## 이 역할의 후보 카드 중 `cat` 슬롯에 해당하는 것들.
func _cards_in_cat(role: int, cat: String) -> Array:
	var out: Array = []
	var gm: Node = get_node_or_null("/root/GameManager")
	var pool: Array = gm.card_pool_bs if gm != null else []
	for raw in TeamDraft.candidate_cards_for_role(pool, role):
		var cd := raw as CardData
		if cd.fits_category(cat):
			out.append(cd)
	return out


func _build_card_grid(body: Control, w: float, y: float, cards: Array) -> float:
	var cw: float = Card.CARD_W * CARD_VIEW_SCALE
	var ch: float = Card.CARD_H * CARD_VIEW_SCALE
	var row_w: float = float(CARD_COLS) * cw + float(CARD_COLS - 1) * CARD_GAP
	var x0: float = maxf(0.0, (w - row_w) * 0.5)
	var rows: int = int(ceil(float(cards.size()) / float(CARD_COLS)))
	for i in cards.size():
		var col: int = i % CARD_COLS
		@warning_ignore("integer_division")
		var row: int = i / CARD_COLS
		var node := CARD_SCENE.instantiate() as Card
		# add_child 를 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(CardPileViewer / PilotDetailPanel 과 같은 순서).
		body.add_child(node)
		# is_player_card = false → 그림자도 호버 브라이튼도 붙지 않는다. IGNORE 와
		# 합쳐 `Card._refresh_float_state`(= scale 의 주인)가 영영 돌지 않으므로
		# 여기서 준 축소가 그대로 남는다.
		node.setup(cards[i] as CardData, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(CARD_VIEW_SCALE, CARD_VIEW_SCALE)
		node.position = Vector2(x0 + float(col) * (cw + CARD_GAP),
				y + float(row) * (ch + CARD_GAP))
	return y + float(rows) * ch + float(maxi(0, rows - 1)) * CARD_GAP


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
	btn.position = Vector2(PANEL_X, PANEL_BOTTOM + 16.0)
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
