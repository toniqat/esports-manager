extends Node

# LoL international ban/pick: B-B-P-PP-PP-P-B-B-PP-PP
# Each side ends with 2 bans + 5 picks. Sides alternate per token.
# AI picks/bans are completely random among legal mechs.
#
# ── 화면 ─────────────────────────────────────────────────────────────────────
# 세로 한 장을 **위 / 가운데 / 아래** 세 덩이로 나눈다.
#
#   위     — 상대 팀 블록: 밴 칩 2개 → 눈높이 초상화 5인 → 이름 → 픽 슬롯 5칸
#   가운데 — 역할군 필터 탭 + **메크 격자(가로 5칸 · 세로 3.5칸이 보이는 수직
#            스크롤)**. 반쯤 잘린 넷째 줄이 곧 "아래로 더 있다"는 신호다.
#   아래   — 아군 팀 블록: 위 블록을 **거울로 뒤집은 순서**(픽 슬롯 → 이름 →
#            초상화 → 밴 칩). 두 팀의 픽 슬롯이 격자를 사이에 두고 마주 보므로
#            "지금까지 어느 쪽이 뭘 가져갔나"가 한 줄로 읽힌다.
#
# 초상화는 전장 스트립과 **같은 eye 크롭**(`PilotImages.eye_for`)이다 — 인게임
# 상단 / 하단에서 보던 얼굴이 밴픽에서도 같은 자리(위 = 적 / 아래 = 아군)에 선다.
#
# **배정은 ASSIGN 단계**라 이 시점에 어느 파일럿이 어느 메크를 타는지는 아직
# 정해지지 않았다. 그래서 픽 슬롯은 파일럿과 짝지어지지 않고 **픽 순서대로
# 왼쪽부터** 채워진다 — "우리 팀이 가져간 다섯 대"라는 뜻이지 "이 선수의 기체"
# 라는 뜻이 아니다.
#
# ── 조작 (1탭 선택 → 2탭 확정) ───────────────────────────────────────────────
# 메크를 한 번 누르면 격자 위로 **하단 시트**가 올라와 그 기체의 스탯 · 패시브 ·
# 카드 셋을 보여 준다. 확정은 시트의 버튼이거나 **같은 메크를 한 번 더 누르는
# 것**이다. 한 번 누르면 곧장 나가던 예전 방식은 되돌릴 수 없는 선택에서 실수
# 한 번이 경기를 통째로 바꿔 버렸다.
#
# 시트는 **내 차례가 아닐 때도 열린다** — 상대가 고민하는 동안 다음에 뭘 고를지
# 들여다보는 것이 밴픽 화면이 하는 일의 절반이다. 그때는 확정 버튼만 잠긴다.

signal phase_finished(result: Dictionary)

const CARD_SCENE := preload("res://scenes/Card.tscn")

const _AI_THINK_SEC := 0.45

# Per-action sequence (14 entries). Each = [side, kind].
# kind: 0 = BAN, 1 = PICK
const ACTION_BAN  := 0
const ACTION_PICK := 1

const SEQUENCE: Array = [
	[GameEnums.DraftSide.BLUE, ACTION_BAN],   # 0
	[GameEnums.DraftSide.RED,  ACTION_BAN],   # 1
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 2
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 3
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 4
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 5
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 6
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 7
	[GameEnums.DraftSide.BLUE, ACTION_BAN],   # 8
	[GameEnums.DraftSide.RED,  ACTION_BAN],   # 9
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 10
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 11
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 12
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 13
]

## 한 팀의 슬롯 수 — 초상화 · 이름 · 픽 칸이 모두 이 수만큼 선다.
const SLOT_COUNT: int = 5
const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
## 역할군 필터 탭. 첫 칸(-1)은 거르지 않는다.
const FILTER_TABS: Array = [
	[-1, "전체"], [0, "TANK"], [1, "FIGHTER"], [2, "ASSASSIN"], [3, "SUPPORT"], [4, "SNIPER"],
]

# ── 레이아웃 ─────────────────────────────────────────────────────────────────
# 세로 좌표는 전부 아래 상수들에서 **계산해서** 나온다(`_layout()`). 안전 영역이
# 기기마다 다르므로 격자 칸 높이만은 남은 공간에서 역산한다 — 그래야 어느
# 화면에서나 "세로 3.5칸"이 지켜진다.
const SIDE_MARGIN: float  = 25.0
const TOP_PAD: float      = 8.0
const BOT_PAD: float      = 10.0
const BLOCK_GAP: float    = 10.0
const STATUS_H: float     = 62.0
const TABS_H: float       = 58.0
const GRID_COLS: int      = 5
const GRID_GAP: float     = 10.0
## 격자에서 한 화면에 보이는 줄 수. 정수가 아닌 것이 요점이다 — 넷째 줄이
## 반쯤 잘려 보이는 것이 "아래로 더 있다"는 유일한 신호다.
const GRID_VISIBLE_ROWS: float = 3.5
## 세로 스크롤바가 먹는 폭. 칸 폭을 여기서 뺀 나머지로 잡아야 마지막 열이
## 스크롤바 밑으로 들어가지 않는다.
const SCROLLBAR_W: float  = 16.0

# 팀 블록 내부 (위 블록 기준 순서 — 아래 블록은 이 순서를 뒤집는다)
const BAN_ROW_H: float       = 44.0
const BAN_CHIP: float        = 38.0
## eye 크롭의 가로:세로 비 (`PilotStrip.EYE_ASPECT` 와 같은 값). 임의 높이로
## 늘리면 얼굴이 찌그러진다.
const EYE_ASPECT: float      = 2.4
const NAME_H: float          = 24.0
const PICK_SLOT_H: float     = 78.0
const BLOCK_INNER_GAP: float = 5.0

# 하단 시트
const SHEET_PAD: float        = 20.0
## 왼쪽 아트 칸의 **폭**. 높이는 시트에서 남는 만큼을 통째로 쓰고 그 안에서
## 세로 가운데 정렬한다 — 아트를 위에 붙이면 그 밑에 아무것도 없는 구멍이
## 300px 넘게 남는다(정사각 아트라 폭을 늘리는 것 말고는 커지지 않는다).
const SHEET_ART_W: float      = 280.0
const SHEET_CARD_SCALE: float = 0.9
const SHEET_CARD_GAP: float   = 10.0
const SHEET_BTN_H: float      = 76.0

## 격자 썸네일로 굽는 한 변(px). 원본 메크 아트는 1024² 무압축이라 21대를 그대로
## 들고 있으면 VRAM 88MB 다 — 격자에서 실제로 필요한 크기로 한 번 줄여 굽고
## 원본은 놓아 준다(시트만 원본 전신 아트를 쓰고, 그건 언제나 한 대뿐이다).
const THUMB_PX: int = 256

const BG_COLOR    := Color(0.04, 0.04, 0.10, 1.0)
const PANEL_COLOR := Color(0.09, 0.10, 0.16, 1.0)
const SHEET_COLOR := Color(0.11, 0.12, 0.19, 1.0)
const BLUE_COLOR  := Color(0.36, 0.62, 0.98)
const RED_COLOR   := Color(0.98, 0.44, 0.40)
const BAN_TINT    := Color(0.30, 0.30, 0.34, 1.0)
const TEXT_DIM    := Color(0.62, 0.66, 0.78)
const ACCENT      := Color(1.0, 0.85, 0.30)

@onready var _mf: MatchFlow = get_parent() as MatchFlow
@onready var _gm: Node = get_node("/root/GameManager")

var _all_mechs: Array = []
var _player_side: int = GameEnums.DraftSide.BLUE
var _action_idx: int  = 0
var _banned: Array = []            # Array[int] — 양 팀 밴 전부 (합법성 판정의 유일한 표)
var _side_bans: Dictionary  = {}   # side(int) → Array[int]
var _side_picks: Dictionary = {}   # side(int) → Array[int]

var _rosters: Dictionary    = {}   # side(int) → Array[PlayerData]
var _team_names: Dictionary = {}   # side(int) → String

# ── UI ───────────────────────────────────────────────────────────────────────
var _panel: Panel
var _lbl_status: Label
var _seq_pips: Array = []          # Array[Panel]
var _cells: Dictionary = {}        # mech_id(int) → {btn, art, veil, tag, mech}
var _side_ui: Dictionary = {}      # side(int) → {ban_chips: Array, pick_slots: Array}
var _filter_role: int = -1
var _filter_btns: Array = []       # Array[Button]
var _scroll: ScrollContainer
var _grid_content: Control
var _thumbs: Dictionary = {}       # mech_id(int) → Texture2D

# 하단 시트
var _sheet_dim: ColorRect
var _sheet: Panel
var _sheet_confirm: Button
var _selected_mech_id: int = -1

## `_layout()` 이 채우는 계산된 좌표표. 화면 하나를 세우는 동안 열 군데가 같은
## 값을 물어보므로 한 번만 풀어 둔다.
var _lay: Dictionary = {}


func enter(all_mechs: Array, player_side: int,
		player_roster: Array = [], enemy_roster: Array = [],
		player_team_name: String = "", enemy_team_name: String = "") -> void:
	_all_mechs   = all_mechs
	_player_side = player_side
	_action_idx  = 0
	_banned.clear()
	var enemy_side: int = _other_side(player_side)
	_side_bans  = {player_side: [], enemy_side: []}
	_side_picks = {player_side: [], enemy_side: []}
	_rosters    = {player_side: player_roster, enemy_side: enemy_roster}
	_team_names = {
		player_side: (player_team_name if player_team_name != "" else "아군"),
		enemy_side:  (enemy_team_name  if enemy_team_name  != "" else "상대"),
	}
	_selected_mech_id = -1
	_filter_role = -1
	_build_ui()
	_refresh_ui()
	_maybe_run_ai()


# ── 레이아웃 계산 ────────────────────────────────────────────────────────────
func _layout() -> void:
	var w: float = ScreenMetrics.vp_w()
	var h: float = ScreenMetrics.safe_h()
	var strip_w: float = w - SIDE_MARGIN * 2.0
	var cell_w: float = strip_w / float(SLOT_COUNT)
	var portrait_w: float = cell_w - 14.0
	var portrait_h: float = portrait_w / EYE_ASPECT
	var block_h: float = BAN_ROW_H + BLOCK_INNER_GAP + portrait_h + 2.0 \
			+ NAME_H + BLOCK_INNER_GAP + PICK_SLOT_H

	var grid_y: float = TOP_PAD + STATUS_H + BLOCK_GAP + block_h + BLOCK_GAP + TABS_H + BLOCK_GAP
	var grid_bottom: float = h - BOT_PAD - block_h - BLOCK_GAP
	var grid_h: float = maxf(240.0, grid_bottom - grid_y)

	# 격자 칸 — 폭은 열 수가, 높이는 "3.5줄이 보인다"가 정한다.
	var content_w: float = strip_w - SCROLLBAR_W
	var gcell_w: float = (content_w - GRID_GAP * float(GRID_COLS - 1)) / float(GRID_COLS)
	var gcell_h: float = (grid_h + GRID_GAP) / GRID_VISIBLE_ROWS - GRID_GAP

	_lay = {
		"w": w, "h": h, "strip_w": strip_w,
		"cell_w": cell_w, "portrait_w": portrait_w, "portrait_h": portrait_h,
		"block_h": block_h,
		"status_y": TOP_PAD,
		"top_block_y": TOP_PAD + STATUS_H + BLOCK_GAP,
		"tabs_y": TOP_PAD + STATUS_H + BLOCK_GAP + block_h + BLOCK_GAP,
		"grid_y": grid_y, "grid_h": grid_h, "grid_bottom": grid_bottom,
		"content_w": content_w, "gcell_w": gcell_w, "gcell_h": gcell_h,
		"bot_block_y": h - BOT_PAD - block_h,
		"sheet_h": clampf(grid_h - 40.0, 560.0, 700.0),
	}


# ── UI build ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_layout()
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	_panel.add_theme_stylebox_override("panel", bg)
	_mf.canvas.add_child(_panel)
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 상태 줄이 깔리지 않게. 한 줄만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(_panel)
	# 판을 내리면 위쪽 띠가 비므로 같은 색으로 메운다 — 노치 자리는 비워 둘
	# 곳이 아니라 쓰지 않을 곳이다.
	ScreenMetrics.backfill_top(_panel, BG_COLOR)

	_bake_thumbs()
	_build_status()
	_build_team_block(_other_side(_player_side), true)
	_build_filter_tabs()
	_build_grid()
	_build_team_block(_player_side, false)


## 메크 전신 아트를 격자 크기로 한 번 줄여 굽는다. 여기서 만든 `ImageTexture`
## 만 참조를 들고 있으므로 1024² 원본은 곧바로 놓여난다 — 21대를 원본째 들고
## 있으면 VRAM 88MB 이고, 격자 칸은 200px 도 안 된다.
func _bake_thumbs() -> void:
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		var tex := MechImages.full_for(m.id)
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		img = img.duplicate() as Image
		if img.is_compressed():
			# 압축 포맷은 resize 를 못 한다. 풀 수 없으면 원본을 그대로 쓴다 —
			# 메모리를 아끼려다 그림을 잃는 쪽이 더 나쁘다.
			if img.decompress() != OK:
				_thumbs[m.id] = tex
				continue
		img.resize(THUMB_PX, THUMB_PX, Image.INTERPOLATE_LANCZOS)
		_thumbs[m.id] = ImageTexture.create_from_image(img)


func _mech_thumb(mech_id: int) -> Texture2D:
	return _thumbs.get(mech_id, null) as Texture2D


# ── 상태 줄 (순서 표시 + 지금 누구 차례) ─────────────────────────────────────
func _build_status() -> void:
	var y: float = _lay["status_y"]
	var w: float = _lay["w"]
	var pip_w: float = 58.0
	var pip_gap: float = 6.0
	var total: float = float(SEQUENCE.size()) * pip_w + float(SEQUENCE.size() - 1) * pip_gap
	var x0: float = (w - total) * 0.5
	for i in range(SEQUENCE.size()):
		var pip := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.corner_radius_top_left = 3
		sty.corner_radius_top_right = 3
		sty.corner_radius_bottom_left = 3
		sty.corner_radius_bottom_right = 3
		pip.add_theme_stylebox_override("panel", sty)
		pip.position = Vector2(x0 + float(i) * (pip_w + pip_gap), y)
		pip.size = Vector2(pip_w, 12.0)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(pip)
		_seq_pips.append(pip)

	_lbl_status = UiHelpers.mk_label(_panel, "", 30, Color(1.0, 1.0, 0.92),
			Vector2(0.0, y + 18.0), Vector2(w, 42.0), HORIZONTAL_ALIGNMENT_CENTER)


# ── 팀 블록 (밴 칩 / 초상화 / 이름 / 픽 슬롯) ────────────────────────────────
## `is_top` 이면 위에서부터 밴 → 초상화 → 이름 → 픽, 아니면 그 반대. 두 블록의
## 픽 슬롯이 격자를 사이에 두고 마주 보게 하려는 것이다 — 지금까지 어느 쪽이
## 뭘 가져갔나가 격자 위아래 한 줄씩으로 읽힌다.
func _build_team_block(side: int, is_top: bool) -> void:
	var block_y: float = _lay["top_block_y"] if is_top else _lay["bot_block_y"]
	var strip_w: float = _lay["strip_w"]
	var cell_w: float = _lay["cell_w"]
	var pw: float = _lay["portrait_w"]
	var ph: float = _lay["portrait_h"]
	var side_col: Color = BLUE_COLOR if side == GameEnums.DraftSide.BLUE else RED_COLOR

	var holder := Control.new()
	holder.position = Vector2(SIDE_MARGIN, block_y)
	holder.size = Vector2(strip_w, _lay["block_h"])
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(holder)

	var ban_y: float
	var por_y: float
	var name_y: float
	var pick_y: float
	if is_top:
		ban_y  = 0.0
		por_y  = BAN_ROW_H + BLOCK_INNER_GAP
		name_y = por_y + ph + 2.0
		pick_y = name_y + NAME_H + BLOCK_INNER_GAP
	else:
		pick_y = 0.0
		name_y = PICK_SLOT_H + BLOCK_INNER_GAP
		por_y  = name_y + NAME_H + 2.0
		ban_y  = por_y + ph + BLOCK_INNER_GAP

	# ── 밴 줄 ──
	var side_label: String = "%s  ·  %s" % [
			("BLUE" if side == GameEnums.DraftSide.BLUE else "RED"),
			String(_team_names.get(side, ""))]
	var side_lbl := UiHelpers.mk_label(holder, side_label, 22, side_col,
			Vector2(0.0, ban_y + 8.0), Vector2(strip_w * 0.5, 28.0))
	side_lbl.clip_text = true
	var ban_lbl := UiHelpers.mk_label(holder, "BAN", 18, TEXT_DIM,
			Vector2(strip_w - 2.0 * (BAN_CHIP + 8.0) - 62.0, ban_y + 12.0),
			Vector2(48.0, 24.0), HORIZONTAL_ALIGNMENT_RIGHT)
	ban_lbl.clip_text = true
	var chips: Array = []
	for i in range(2):
		chips.append(_build_chip(holder,
				Vector2(strip_w - float(2 - i) * (BAN_CHIP + 8.0) + 8.0, ban_y + 3.0),
				BAN_CHIP))

	# ── 초상화 + 이름 ──
	var roster: Array = _rosters.get(side, [])
	for i in range(SLOT_COUNT):
		var cx: float = cell_w * (float(i) + 0.5)
		var px: float = cx - pw * 0.5

		# 초상화 뒤판 — 이미지가 없을 때(INTL 팀 / 단독 실행) 그대로 보이는 폴백.
		var back := ColorRect.new()
		back.position = Vector2(px, por_y)
		back.size = Vector2(pw, ph)
		back.color = Color(0.12, 0.13, 0.19)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(back)

		var p: PlayerData = null
		if i < roster.size():
			p = roster[i] as PlayerData
		if p != null:
			# **`expand_mode` 를 `texture` 보다 먼저 준다.** 기본
			# `EXPAND_KEEP_SIZE` 에서는 텍스처 크기가 그대로 최소 크기가 되어,
			# 그 뒤에 준 `size` 가 위로 잡아당겨진다 — 480×200 짜리 eye 크롭이
			# 192×80 칸을 뚫고 나와 아래 이름·픽 슬롯을 통째로 덮었다(실측).
			var eye := TextureRect.new()
			eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			eye.texture = PilotImages.eye_for(p.id)
			eye.position = Vector2(px, por_y)
			eye.size = Vector2(pw, ph)
			eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(eye)

		var rim := Panel.new()
		rim.position = Vector2(px, por_y)
		rim.size = Vector2(pw, ph)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rim_sb := StyleBoxFlat.new()
		rim_sb.bg_color = Color(0, 0, 0, 0)
		rim_sb.border_color = side_col
		rim_sb.border_width_top = 2
		rim_sb.border_width_bottom = 2
		rim_sb.border_width_left = 2
		rim_sb.border_width_right = 2
		rim.add_theme_stylebox_override("panel", rim_sb)
		holder.add_child(rim)

		# 역할 태그 — 초상화 좌하단. 검은 외곽선이 없으면 어두운 머리카락
		# 위에서 한 단어가 통째로 사라진다(전장 스트립과 같은 이유).
		var role_idx: int = p.role if p != null else i
		var tag := UiHelpers.mk_label(holder,
				String(ROLE_NAMES[role_idx]) if role_idx >= 0 and role_idx < ROLE_NAMES.size() else "?",
				13, Color(1, 1, 1), Vector2(px + 4.0, por_y + ph - 20.0),
				Vector2(pw - 8.0, 18.0))
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tag.add_theme_constant_override("outline_size", 4)
		tag.clip_text = true

		var nm := UiHelpers.mk_label(holder, p.name if p != null else "—",
				18, Color(0.88, 0.90, 0.96), Vector2(px, name_y),
				Vector2(pw, NAME_H), HORIZONTAL_ALIGNMENT_CENTER)
		nm.clip_text = true

	# ── 픽 슬롯 ── (파일럿과 짝이 아니라 **픽 순서**다)
	var slots: Array = []
	for i in range(SLOT_COUNT):
		var cx2: float = cell_w * (float(i) + 0.5)
		var sw: float = cell_w - 12.0
		slots.append(_build_pick_slot(holder,
				Vector2(cx2 - sw * 0.5, pick_y), Vector2(sw, PICK_SLOT_H), side_col))

	_side_ui[side] = {"ban_chips": chips, "pick_slots": slots}


## 밴 칩 한 칸 — 작은 정사각 썸네일 + 붉은 ✕. 비어 있으면 테두리만 남는다.
func _build_chip(parent: Control, pos: Vector2, sz: float) -> Dictionary:
	var frame := Panel.new()
	frame.position = pos
	frame.size = Vector2(sz, sz)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.14, 0.19)
	sb.border_color = Color(0.35, 0.30, 0.32)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	frame.add_theme_stylebox_override("panel", sb)
	parent.add_child(frame)

	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(1.0, 1.0)
	art.size = Vector2(sz - 2.0, sz - 2.0)
	art.modulate = BAN_TINT
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)

	var x_lbl := UiHelpers.mk_label(frame, "", 26, Color(1.0, 0.35, 0.35),
			Vector2(0.0, 0.0), Vector2(sz, sz), HORIZONTAL_ALIGNMENT_CENTER)
	x_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	x_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	x_lbl.add_theme_constant_override("outline_size", 5)
	return {"art": art, "x": x_lbl}


## 픽 슬롯 한 칸 — 왼쪽에 기체 썸네일, 오른쪽에 기체명 + 패시브명.
func _build_pick_slot(parent: Control, pos: Vector2, sz: Vector2, side_col: Color) -> Dictionary:
	var frame := Panel.new()
	frame.position = pos
	frame.size = sz
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.21)
	sb.border_color = side_col.darkened(0.55)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	frame.add_theme_stylebox_override("panel", sb)
	parent.add_child(frame)

	var art_sz: float = sz.y - 8.0
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(4.0, 4.0)
	art.size = Vector2(art_sz, art_sz)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)

	var tx: float = art_sz + 10.0
	var nm := UiHelpers.mk_label(frame, "", 17, Color(0.92, 0.94, 1.0),
			Vector2(tx, 10.0), Vector2(sz.x - tx - 6.0, 24.0))
	nm.clip_text = true
	var sub := UiHelpers.mk_label(frame, "", 15, TEXT_DIM,
			Vector2(tx, 36.0), Vector2(sz.x - tx - 6.0, 36.0))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.clip_text = true
	return {"art": art, "name": nm, "sub": sub, "style": sb, "side_col": side_col}


# ── 역할군 필터 탭 ───────────────────────────────────────────────────────────
func _build_filter_tabs() -> void:
	var y: float = _lay["tabs_y"]
	var strip_w: float = _lay["strip_w"]
	var gap: float = 6.0
	var n: int = FILTER_TABS.size()
	var bw: float = (strip_w - gap * float(n - 1)) / float(n)
	for i in range(n):
		var role: int = int(FILTER_TABS[i][0])
		var btn := Button.new()
		btn.text = String(FILTER_TABS[i][1])
		btn.add_theme_font_size_override("font_size", 20)
		btn.clip_text = true
		btn.position = Vector2(SIDE_MARGIN + float(i) * (bw + gap), y)
		btn.size = Vector2(bw, TABS_H)
		btn.pressed.connect(_on_filter_pressed.bind(role))
		_panel.add_child(btn)
		_filter_btns.append(btn)


func _on_filter_pressed(role: int) -> void:
	if _filter_role == role:
		return
	_filter_role = role
	_apply_filter()
	_refresh_filter_tabs()


func _refresh_filter_tabs() -> void:
	for i in range(_filter_btns.size()):
		var btn := _filter_btns[i] as Button
		var on: bool = int(FILTER_TABS[i][0]) == _filter_role
		btn.add_theme_color_override("font_color", ACCENT if on else TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", ACCENT if on else Color(0.86, 0.89, 0.96))
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, _tab_style(on))


func _tab_style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.19, 0.11) if on else PANEL_COLOR
	sb.border_color = ACCENT if on else Color(0.24, 0.26, 0.34)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	return sb


# ── 메크 격자 ────────────────────────────────────────────────────────────────
func _build_grid() -> void:
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(SIDE_MARGIN, _lay["grid_y"])
	_scroll.size = Vector2(_lay["strip_w"], _lay["grid_h"])
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	_panel.add_child(_scroll)

	# 칸을 절대 좌표로 놓으므로 컨테이너가 아니라 맨 Control 이다 — 필터가
	# 바뀔 때 자리를 다시 흘려 놓는 곳이 `_apply_filter()` 한 군데뿐이어야 한다.
	_grid_content = Control.new()
	_grid_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid_content)

	for m_raw in _all_mechs:
		var m := m_raw as MechData
		_cells[m.id] = _build_mech_cell(m)
	_apply_filter()


func _build_mech_cell(m: MechData) -> Dictionary:
	var cw: float = _lay["gcell_w"]
	var ch: float = _lay["gcell_h"]

	var btn := Button.new()
	btn.size = Vector2(cw, ch)
	btn.custom_minimum_size = Vector2(cw, ch)
	# 스크롤 안의 탭 대상은 **PASS** 여야 한다 — 모바일 드래그 스크롤은 터치에서
	# 에뮬레이트된 마우스 press 가 ScrollContainer 까지 올라가야 시작되는데
	# STOP 이 그걸 끊는다. 칸이 격자를 빈틈없이 덮으므로 STOP 이면 손가락을
	# 어디에 대도 격자가 안 움직인다(실측). 탭은 PASS 로도 그대로 동작한다.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.pressed.connect(_on_mech_pressed.bind(m.id))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, _cell_style(false))
	_grid_content.add_child(btn)

	# 아트는 남는 높이를 통째로 쓰되 **잘라내지 않는다**(KEEP_ASPECT_CENTERED) —
	# 검·날개가 옆으로 뻗은 기체가 많아 COVERED 로 채우면 실루엣이 잘려 나간다.
	var pad: float = 6.0
	var text_h: float = 30.0 + 26.0 + 26.0 + 10.0
	var art_h: float = maxf(60.0, ch - pad * 2.0 - text_h)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _mech_thumb(m.id)
	art.position = Vector2(pad, pad)
	art.size = Vector2(cw - pad * 2.0, art_h)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(art)

	var role_txt: String = String(ROLE_NAMES[m.role]) if m.role >= 0 and m.role < ROLE_NAMES.size() else "—"
	var role_lbl := UiHelpers.mk_label(btn, role_txt, 14, Color(0.72, 0.80, 0.96),
			Vector2(pad + 2.0, pad + 2.0), Vector2(cw - pad * 2.0 - 4.0, 20.0))
	role_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	role_lbl.add_theme_constant_override("outline_size", 4)
	role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_lbl.clip_text = true

	var y: float = pad + art_h + 4.0
	var nm := UiHelpers.mk_label(btn, m.name, 22, Color(0.95, 0.96, 1.0),
			Vector2(pad, y), Vector2(cw - pad * 2.0, 30.0), HORIZONTAL_ALIGNMENT_CENTER)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	y += 30.0

	var stats := UiHelpers.mk_label(btn,
			"HP %d · ATK %d · 존재감 %d" % [m.hp, m.atk, m.presence],
			16, TEXT_DIM, Vector2(pad, y), Vector2(cw - pad * 2.0, 26.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	stats.clip_text = true
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	y += 26.0

	# 패시브 이름은 격자 칸에 **그대로 적는다** — 기체를 고르는 순간 패시브
	# 하나가 함께 정해지므로, 그걸 보려고 매번 시트를 열어야 하면 21대를 훑는
	# 데 탭이 21번 든다. 자세한 설명문만 시트가 들고 있다.
	var pas: Dictionary = _gm.mech_passive_def(m.id)
	var pas_txt: String = ("◆ " + String(pas["name"])) if not pas.is_empty() else "패시브 없음"
	var pas_lbl := UiHelpers.mk_label(btn, pas_txt, 17,
			ACCENT if not pas.is_empty() else Color(0.45, 0.48, 0.58),
			Vector2(pad, y), Vector2(cw - pad * 2.0, 26.0), HORIZONTAL_ALIGNMENT_CENTER)
	pas_lbl.clip_text = true
	pas_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 상태 슬래브 (밴 / 픽) — 칸 전체를 덮고 그 위에 태그 한 줄.
	var veil := ColorRect.new()
	veil.position = Vector2.ZERO
	veil.size = Vector2(cw, ch)
	veil.color = Color(0, 0, 0, 0)
	veil.visible = false
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(veil)

	var tag := UiHelpers.mk_label(btn, "", 30, Color(1, 1, 1),
			Vector2(0.0, ch * 0.5 - 22.0), Vector2(cw, 44.0), HORIZONTAL_ALIGNMENT_CENTER)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	tag.add_theme_constant_override("outline_size", 6)
	tag.visible = false
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return {"btn": btn, "art": art, "veil": veil, "tag": tag, "mech": m}


func _cell_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = ACCENT if selected else Color(0.22, 0.24, 0.32)
	var bw: int = 4 if selected else 2
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.border_width_left = bw
	sb.border_width_right = bw
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb


## 필터를 적용해 격자를 다시 흘려 놓는다. 걸러진 칸은 숨기고 **자리도 비운다** —
## 빈 칸을 남기면 그 역할군에 몇 대가 있는지가 안 읽힌다.
func _apply_filter() -> void:
	var cw: float = _lay["gcell_w"]
	var ch: float = _lay["gcell_h"]
	var idx: int = 0
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		var btn := (_cells[m.id] as Dictionary)["btn"] as Button
		if _filter_role >= 0 and m.role != _filter_role:
			btn.visible = false
			continue
		btn.visible = true
		var col: int = idx % GRID_COLS
		@warning_ignore("integer_division")
		var row: int = idx / GRID_COLS
		btn.position = Vector2(float(col) * (cw + GRID_GAP), float(row) * (ch + GRID_GAP))
		idx += 1
	var rows: int = int(ceil(float(idx) / float(GRID_COLS)))
	_grid_content.custom_minimum_size = Vector2(_lay["content_w"],
			maxf(0.0, float(rows) * (ch + GRID_GAP) - GRID_GAP))
	_scroll.scroll_vertical = 0


# ── 하단 시트 (선택한 메크의 스탯 · 패시브 · 카드) ───────────────────────────
func _open_sheet(mech_id: int) -> void:
	_close_sheet()
	var m := _find_mech(mech_id)
	if m == null:
		return
	_selected_mech_id = mech_id

	# 딤은 **격자와 필터 탭만** 덮는다 — 위아래 팀 블록은 지금까지의 밴픽
	# 상황이라 시트를 보는 동안에도 보여야 한다(무엇이 이미 나갔는지 모르면
	# 이 기체를 고를지 판단할 수 없다).
	_sheet_dim = ColorRect.new()
	_sheet_dim.position = Vector2(0.0, _lay["tabs_y"] - 6.0)
	_sheet_dim.size = Vector2(_lay["w"], _lay["grid_bottom"] - _lay["tabs_y"] + 12.0)
	_sheet_dim.color = Color(0.0, 0.0, 0.02, 0.72)
	_sheet_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_dim.gui_input.connect(_on_dim_input)
	_panel.add_child(_sheet_dim)

	var sh: float = _lay["sheet_h"]
	var sw: float = _lay["strip_w"]
	_sheet = Panel.new()
	_sheet.position = Vector2(SIDE_MARGIN, _lay["grid_bottom"] - sh)
	_sheet.size = Vector2(sw, sh)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHEET_COLOR
	sb.border_color = ACCENT.darkened(0.25)
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	_sheet.add_theme_stylebox_override("panel", sb)
	_panel.add_child(_sheet)

	_build_sheet_body(m, sw, sh)


func _build_sheet_body(m: MechData, sw: float, sh: float) -> void:
	# ── 왼쪽: 전신 아트 (원본 — 한 번에 한 대뿐이라 여기서만 1024² 를 쓴다) ──
	var art_h: float = maxf(120.0, sh - SHEET_PAD * 2.0 - SHEET_BTN_H - 16.0)
	var full := MechImages.full_for(m.id)
	if full == null:
		var ph := ColorRect.new()
		ph.position = Vector2(SHEET_PAD, SHEET_PAD)
		ph.size = Vector2(SHEET_ART_W, art_h)
		ph.color = Color(1, 1, 1, 0.06)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(ph)
	else:
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = full
		art.position = Vector2(SHEET_PAD, SHEET_PAD)
		art.size = Vector2(SHEET_ART_W, art_h)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(art)

	# ── 오른쪽: 이름 · 스탯 · 패시브 · 카드 ──
	var rx: float = SHEET_PAD + SHEET_ART_W + 24.0
	var rw: float = sw - rx - SHEET_PAD
	var y: float = SHEET_PAD
	var nm := UiHelpers.mk_label(_sheet, m.name, 38, Color(1, 1, 1),
			Vector2(rx, y), Vector2(rw, 48.0))
	nm.clip_text = true
	y += 52.0

	var role_txt: String = String(ROLE_NAMES[m.role]) if m.role >= 0 and m.role < ROLE_NAMES.size() else "—"
	var st := UiHelpers.mk_label(_sheet,
			"%s   ·   HP %d   ·   ATK %d   ·   존재감 %d" % [role_txt, m.hp, m.atk, m.presence],
			24, Color(0.80, 0.85, 0.96), Vector2(rx, y), Vector2(rw, 34.0))
	st.clip_text = true
	y += 42.0

	var pas: Dictionary = _gm.mech_passive_def(m.id)
	if pas.is_empty():
		UiHelpers.mk_label(_sheet, "패시브 없음", 24, Color(0.48, 0.51, 0.62),
				Vector2(rx, y), Vector2(rw, 32.0))
	else:
		var kw: String = String(pas.get("keyword", ""))
		var head: String = "◆ %s" % String(pas["name"])
		if kw != "":
			head += "   [%s]" % kw
		var hl := UiHelpers.mk_label(_sheet, head, 26, ACCENT,
				Vector2(rx, y), Vector2(rw, 34.0))
		hl.clip_text = true
		y += 38.0
		var desc := Label.new()
		desc.text = String(pas.get("description", ""))
		desc.add_theme_font_size_override("font_size", 20)
		desc.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(rx, y)
		desc.size = Vector2(rw, 128.0)
		desc.clip_text = true
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(desc)

	# ── 카드 셋 ── (오른쪽 칸에서 이어진다 — 왼쪽은 아트 한 장이 통째로 쓴다)
	var cy: float = SHEET_PAD + 250.0
	var defs: Array = _gm.mech_cards_for(m.id)
	UiHelpers.mk_label(_sheet, "메크 카드  %d종" % defs.size(), 22,
			Color(0.78, 0.82, 0.92), Vector2(rx, cy), Vector2(rw, 28.0))
	cy += 32.0
	_build_card_row(defs, cy, rx, rw)

	# ── 버튼 ──
	var by: float = sh - SHEET_PAD - SHEET_BTN_H
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.position = Vector2(sw - SHEET_PAD - 340.0 - 12.0 - 190.0, by)
	close_btn.size = Vector2(190.0, SHEET_BTN_H)
	close_btn.pressed.connect(_close_sheet)
	_sheet.add_child(close_btn)

	_sheet_confirm = Button.new()
	_sheet_confirm.add_theme_font_size_override("font_size", 28)
	_sheet_confirm.position = Vector2(sw - SHEET_PAD - 340.0, by)
	_sheet_confirm.size = Vector2(340.0, SHEET_BTN_H)
	_sheet_confirm.pressed.connect(_on_confirm_pressed)
	_sheet.add_child(_sheet_confirm)
	_refresh_sheet_confirm()


## 메크 카드들을 손패와 **같은 노드**(`Card.tscn`)로 늘어놓는다 — 따로 그린
## 그림이면 실제로 덱에 들어갈 카드와 같은 것인지 확인할 길이 없다.
## `rx` / `rw` 는 오른쪽 칸의 왼쪽 끝과 폭이다 — 시트 전체 폭으로 가운데를
## 잡으면 카드 줄이 왼쪽 아트 위로 밀려 들어간다.
func _build_card_row(defs: Array, y: float, rx: float, rw: float) -> void:
	if defs.is_empty():
		UiHelpers.mk_label(_sheet, "이 기체에는 고유 카드가 없다", 20,
				Color(0.48, 0.51, 0.62), Vector2(rx, y), Vector2(rw, 30.0))
		return
	var cw: float = Card.CARD_W * SHEET_CARD_SCALE
	var chh: float = Card.CARD_H * SHEET_CARD_SCALE
	var row_w: float = float(defs.size()) * cw + float(defs.size() - 1) * SHEET_CARD_GAP
	var x0: float = rx + maxf(0.0, (rw - row_w) * 0.5)
	for i in range(defs.size()):
		var def: Dictionary = defs[i]
		var node := CARD_SCENE.instantiate() as Card
		# add_child 를 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(DraftDetailPanel / CardPileViewer 와 같은 순서).
		_sheet.add_child(node)
		node.setup(CardData.from_def(def), false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(SHEET_CARD_SCALE, SHEET_CARD_SCALE)
		node.position = Vector2(x0 + float(i) * (cw + SHEET_CARD_GAP), y)

		# 장수 배지 — `count = 0` 인 카드는 덱에 처음부터 들어가지 않고 패시브나
		# 다른 카드가 만들어 줄 때만 세상에 나온다. 그 사정을 적어 두지 않으면
		# "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
		var cnt: int = int(def.get("count", 0))
		var badge := UiHelpers.mk_label(_sheet,
				("×%d" % cnt) if cnt > 0 else "생성 전용",
				18, Color(0.92, 0.94, 1.0) if cnt > 0 else Color(0.62, 0.70, 0.92),
				Vector2(x0 + float(i) * (cw + SHEET_CARD_GAP), y + chh + 2.0),
				Vector2(cw, 24.0), HORIZONTAL_ALIGNMENT_CENTER)
		badge.clip_text = true


func _refresh_sheet_confirm() -> void:
	if _sheet_confirm == null:
		return
	var ok: bool = _is_player_turn() and _is_legal(_selected_mech_id)
	_sheet_confirm.disabled = not ok
	if ok:
		_sheet_confirm.text = "밴 확정" if _current_kind() == ACTION_BAN else "픽 확정"
	elif not _is_player_turn():
		_sheet_confirm.text = "상대 차례"
	else:
		_sheet_confirm.text = "선택 불가"


func _on_dim_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_sheet()


func _close_sheet() -> void:
	_selected_mech_id = -1
	_sheet_confirm = null
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null
	if _sheet_dim != null:
		_sheet_dim.queue_free()
		_sheet_dim = null
	_refresh_cell_selection()


func _on_confirm_pressed() -> void:
	var id: int = _selected_mech_id
	if id < 0 or not _is_player_turn() or not _is_legal(id):
		return
	_close_sheet()
	_commit_action(id)


# ── State refresh ────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	for i in range(_seq_pips.size()):
		var pip := _seq_pips[i] as Panel
		var sty := pip.get_theme_stylebox("panel") as StyleBoxFlat
		sty.bg_color = _seq_color(i, 1 if i < _action_idx else (2 if i == _action_idx else 0))

	var blue_picks: Array = _picks_of(GameEnums.DraftSide.BLUE)
	var red_picks: Array  = _picks_of(GameEnums.DraftSide.RED)
	for id in _cells.keys():
		var cell: Dictionary = _cells[id]
		var veil := cell["veil"] as ColorRect
		var tag := cell["tag"] as Label
		var art := cell["art"] as TextureRect
		var mid: int = int(id)
		if mid in _banned:
			veil.visible = true
			veil.color = Color(0.0, 0.0, 0.0, 0.62)
			tag.visible = true
			tag.text = "BAN"
			tag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.42))
			art.modulate = BAN_TINT
		elif mid in blue_picks:
			veil.visible = true
			veil.color = Color(0.10, 0.24, 0.52, 0.62)
			tag.visible = true
			tag.text = "BLUE"
			tag.add_theme_color_override("font_color", BLUE_COLOR)
			art.modulate = Color(0.74, 0.80, 0.94)
		elif mid in red_picks:
			veil.visible = true
			veil.color = Color(0.46, 0.12, 0.12, 0.62)
			tag.visible = true
			tag.text = "RED"
			tag.add_theme_color_override("font_color", RED_COLOR)
			art.modulate = Color(0.94, 0.78, 0.76)
		else:
			veil.visible = false
			tag.visible = false
			art.modulate = Color(1, 1, 1)

	_refresh_cell_selection()
	_refresh_filter_tabs()
	_refresh_side_block(GameEnums.DraftSide.BLUE)
	_refresh_side_block(GameEnums.DraftSide.RED)
	_refresh_sheet_confirm()

	if _action_idx >= SEQUENCE.size():
		_lbl_status.text = "밴픽 완료 — 배정으로 넘어간다"
		return
	var cur: Array = SEQUENCE[_action_idx]
	var side_name: String = "BLUE" if cur[0] == GameEnums.DraftSide.BLUE else "RED"
	var kind_name: String = "밴" if cur[1] == ACTION_BAN else "픽"
	var who: String = "내 차례" if cur[0] == _player_side else "상대 차례"
	_lbl_status.text = "%s %s — %s   (%d / %d)" % [
			side_name, kind_name, who, _action_idx + 1, SEQUENCE.size()]
	_lbl_status.add_theme_color_override("font_color",
			ACCENT if cur[0] == _player_side else Color(0.72, 0.76, 0.88))


func _refresh_cell_selection() -> void:
	for id in _cells.keys():
		var btn := (_cells[id] as Dictionary)["btn"] as Button
		var on: bool = int(id) == _selected_mech_id
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(st, _cell_style(on))


func _refresh_side_block(side: int) -> void:
	var ui: Dictionary = _side_ui.get(side, {})
	if ui.is_empty():
		return
	var bans: Array = _side_bans.get(side, [])
	var chips: Array = ui["ban_chips"]
	for i in range(chips.size()):
		var chip: Dictionary = chips[i]
		var art := chip["art"] as TextureRect
		var x_lbl := chip["x"] as Label
		if i < bans.size():
			art.texture = _mech_thumb(int(bans[i]))
			x_lbl.text = "✕"
		else:
			art.texture = null
			x_lbl.text = ""

	var picks: Array = _side_picks.get(side, [])
	var slots: Array = ui["pick_slots"]
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var sty := slot["style"] as StyleBoxFlat
		var side_col: Color = slot["side_col"]
		var nm := slot["name"] as Label
		var sub := slot["sub"] as Label
		if i < picks.size():
			var mid: int = int(picks[i])
			var m := _find_mech(mid)
			(slot["art"] as TextureRect).texture = _mech_thumb(mid)
			nm.text = m.name if m != null else "?"
			var pas: Dictionary = _gm.mech_passive_def(mid)
			sub.text = String(pas["name"]) if not pas.is_empty() else "패시브 없음"
			sub.add_theme_color_override("font_color",
					ACCENT if not pas.is_empty() else Color(0.45, 0.48, 0.58))
			sty.bg_color = side_col.darkened(0.72)
			sty.border_color = side_col
		else:
			(slot["art"] as TextureRect).texture = null
			nm.text = "픽 %d" % (i + 1)
			sub.text = ""
			sty.bg_color = Color(0.13, 0.14, 0.21)
			sty.border_color = side_col.darkened(0.55)


func _seq_color(idx: int, state: int) -> Color:
	# state: 0=upcoming, 1=done, 2=current
	var side: int = SEQUENCE[idx][0]
	var base: Color = BLUE_COLOR if side == GameEnums.DraftSide.BLUE else RED_COLOR
	if state == 1: return base.darkened(0.45)
	if state == 2: return base.lightened(0.20)
	return base.darkened(0.75)


# ── Click handling ───────────────────────────────────────────────────────────
## 1탭 = 선택(시트 열기), **같은 메크 2탭 = 확정**. 시트는 상대 차례에도 열린다 —
## 다음 수를 들여다보는 것이 밴픽 화면이 하는 일의 절반이다.
func _on_mech_pressed(mech_id: int) -> void:
	if _selected_mech_id == mech_id:
		if _is_player_turn() and _is_legal(mech_id):
			_close_sheet()
			_commit_action(mech_id)
		return
	_open_sheet(mech_id)
	_refresh_cell_selection()


func _is_player_turn() -> bool:
	if _action_idx >= SEQUENCE.size(): return false
	return SEQUENCE[_action_idx][0] == _player_side


func _current_kind() -> int:
	if _action_idx >= SEQUENCE.size(): return ACTION_PICK
	return int(SEQUENCE[_action_idx][1])


func _is_legal(mech_id: int) -> bool:
	if mech_id < 0:
		return false
	return not (mech_id in _banned) \
		and not (mech_id in _picks_of(GameEnums.DraftSide.BLUE)) \
		and not (mech_id in _picks_of(GameEnums.DraftSide.RED))


func _picks_of(side: int) -> Array:
	return _side_picks.get(side, [])


func _other_side(side: int) -> int:
	return GameEnums.DraftSide.RED if side == GameEnums.DraftSide.BLUE else GameEnums.DraftSide.BLUE


func _commit_action(mech_id: int) -> void:
	var cur: Array = SEQUENCE[_action_idx]
	var side: int = int(cur[0])
	if cur[1] == ACTION_BAN:
		_banned.append(int(mech_id))
		(_side_bans[side] as Array).append(int(mech_id))
	else:
		(_side_picks[side] as Array).append(int(mech_id))
	_action_idx += 1
	_refresh_ui()
	if _action_idx >= SEQUENCE.size():
		_finish()
	else:
		_maybe_run_ai()


func _maybe_run_ai() -> void:
	if _action_idx >= SEQUENCE.size():
		return
	if _is_player_turn():
		return
	# AI turn — pick a random legal mech after a short delay
	await get_tree().create_timer(_AI_THINK_SEC).timeout
	if _action_idx >= SEQUENCE.size() or _panel == null:
		return
	var legal: Array = []
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if _is_legal(m.id): legal.append(m)
	if legal.is_empty():
		push_error("BanPickController: no legal mechs left for AI")
		return
	var pick := legal[randi() % legal.size()] as MechData
	_commit_action(pick.id)


func _finish() -> void:
	var player_picks: Array = (_picks_of(_player_side) as Array).duplicate()
	var enemy_picks: Array  = (_picks_of(_other_side(_player_side)) as Array).duplicate()
	_close_sheet()
	_panel.queue_free()
	_panel = null
	_cells.clear()
	_side_ui.clear()
	_seq_pips.clear()
	_filter_btns.clear()
	_thumbs.clear()
	_scroll = null
	_grid_content = null
	phase_finished.emit({
		"banned": _banned.duplicate(),
		"player_picks": player_picks,
		"enemy_picks": enemy_picks,
	})


# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_mech(id: int) -> MechData:
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if m.id == id: return m
	return null
