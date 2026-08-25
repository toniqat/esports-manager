class_name PilotThumb
extends Button

# 드래프트 하단 격자의 캐릭터 썸네일 한 칸 — 얼굴 크롭 · 이름 · 역할 태그 ·
# 종합 스탯. 우마무스메식 "인물 목록"이라 카드가 아니라 **초상화**가 칸의
# 주인이고, 숫자는 그 아래 한 줄로만 붙는다(예전 `PilotCard` 는 200×175 칸에
# 스탯 막대 다섯 줄을 세워서 정작 얼굴이 48px 였다).
#
# 선택 표시는 **금색 테두리 + 우상단 체크 배지** 두 겹이다. 테두리만으로는
# 격자가 5열로 촘촘해 어느 칸이 켜졌는지가 곁눈으로 안 읽힌다.

signal thumb_tapped(pilot_id: int)

const CELL_W: float = 200.0
const CELL_H: float = 250.0

const ART_MARGIN: float = 6.0
const ART_H: float = 168.0

const ROLE_TAG_H: float = 22.0
const NAME_H: float = 30.0
const STAT_H: float = 22.0

const BORDER_W: int = 3
const BORDER_W_SEL: int = 4
const RADIUS: int = 10

const BG_OFF := Color(0.13, 0.15, 0.22, 1.0)
const BG_ON  := Color(0.20, 0.32, 0.55, 1.0)
const BORDER_OFF := Color(0.30, 0.32, 0.40, 1.0)
const BORDER_ON  := Color(1.00, 0.85, 0.20, 1.0)

const BADGE_SIZE: float = 40.0
const BADGE_BG := Color(1.00, 0.85, 0.20, 1.0)
const BADGE_FG := Color(0.10, 0.08, 0.02, 1.0)

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),   # TANK     blue
	Color(1.00, 0.55, 0.20),   # FIGHTER  orange
	Color(0.75, 0.40, 1.00),   # ASSASSIN purple
	Color(0.30, 0.85, 0.45),   # SUPPORT  green
	Color(1.00, 0.35, 0.35),   # SNIPER   red
]

var pilot: PlayerData = null

var _selected: bool = false
var _built: bool = false

var _face: TextureRect
var _role_lbl: Label
var _name_lbl: Label
var _stat_lbl: Label
var _badge: Panel


func setup(p: PlayerData, sel: bool) -> void:
	pilot = p
	if not _built:
		_build()
		_built = true
	_refresh()
	set_selected(sel)


func set_selected(sel: bool) -> void:
	_selected = sel
	if _badge != null:
		_badge.visible = sel
	_apply_style()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	custom_minimum_size = Vector2(CELL_W, CELL_H)
	size               = Vector2(CELL_W, CELL_H)
	focus_mode         = Control.FOCUS_NONE
	clip_contents      = true
	text               = ""
	pressed.connect(_on_pressed)

	var art_w: float = CELL_W - ART_MARGIN * 2.0
	_face = TextureRect.new()
	_face.position     = Vector2(ART_MARGIN, ART_MARGIN)
	_face.size         = Vector2(art_w, ART_H)
	_face.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	var y: float = ART_MARGIN + ART_H + 2.0
	_role_lbl = UiHelpers.mk_label(self, "", 15, Color(1, 1, 1),
			Vector2(ART_MARGIN, y), Vector2(art_w, ROLE_TAG_H),
			HORIZONTAL_ALIGNMENT_CENTER)
	y += ROLE_TAG_H

	_name_lbl = UiHelpers.mk_label(self, "", 22, Color(1, 1, 1),
			Vector2(ART_MARGIN, y), Vector2(art_w, NAME_H),
			HORIZONTAL_ALIGNMENT_CENTER)
	_name_lbl.clip_text = true
	_name_lbl.add_theme_constant_override("outline_size", 2)
	_name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	y += NAME_H

	_stat_lbl = UiHelpers.mk_label(self, "", 15, Color(0.72, 0.78, 0.90),
			Vector2(ART_MARGIN, y), Vector2(art_w, STAT_H),
			HORIZONTAL_ALIGNMENT_CENTER)

	_badge = Panel.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.position = Vector2(CELL_W - BADGE_SIZE - 8.0, 8.0)
	_badge.size     = Vector2(BADGE_SIZE, BADGE_SIZE)
	var bsty := StyleBoxFlat.new()
	bsty.bg_color = BADGE_BG
	bsty.corner_radius_top_left     = int(BADGE_SIZE * 0.5)
	bsty.corner_radius_top_right    = int(BADGE_SIZE * 0.5)
	bsty.corner_radius_bottom_left  = int(BADGE_SIZE * 0.5)
	bsty.corner_radius_bottom_right = int(BADGE_SIZE * 0.5)
	_badge.add_theme_stylebox_override("panel", bsty)
	_badge.visible = false
	add_child(_badge)
	var check := UiHelpers.mk_label(_badge, "✓", 26, BADGE_FG,
			Vector2.ZERO, Vector2(BADGE_SIZE, BADGE_SIZE),
			HORIZONTAL_ALIGNMENT_CENTER)
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh() -> void:
	if pilot == null:
		_face.texture = null
		_name_lbl.text = ""
		_role_lbl.text = ""
		_stat_lbl.text = ""
		return
	_face.texture  = PilotImages.face_for(pilot.id)
	_name_lbl.text = pilot.name
	var r: int = int(pilot.role)
	if r >= 0 and r < ROLE_NAMES.size():
		_role_lbl.text = ROLE_NAMES[r]
		_role_lbl.add_theme_color_override("font_color", ROLE_COLORS[r])
	else:
		_role_lbl.text = "?"
	_stat_lbl.text = "종합 %d" % total_stats(pilot)


static func total_stats(p: PlayerData) -> int:
	return p.laning + p.mechanics + p.gamesense + p.teamfight + p.mental


func _apply_style() -> void:
	var bg := StyleBoxFlat.new()
	bg.corner_radius_top_left     = RADIUS
	bg.corner_radius_top_right    = RADIUS
	bg.corner_radius_bottom_left  = RADIUS
	bg.corner_radius_bottom_right = RADIUS
	bg.bg_color     = BG_ON if _selected else BG_OFF
	bg.border_color = BORDER_ON if _selected else BORDER_OFF
	var w: int = BORDER_W_SEL if _selected else BORDER_W
	bg.border_width_left   = w
	bg.border_width_right  = w
	bg.border_width_top    = w
	bg.border_width_bottom = w
	add_theme_stylebox_override("normal",   bg)
	add_theme_stylebox_override("hover",    bg)
	add_theme_stylebox_override("pressed",  bg)
	add_theme_stylebox_override("focus",    bg)
	add_theme_stylebox_override("disabled", bg)


func _on_pressed() -> void:
	if pilot != null:
		thumb_tapped.emit(pilot.id)
