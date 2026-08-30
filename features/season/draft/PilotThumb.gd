class_name PilotThumb
extends Button

# 드래프트 하단 격자의 캐릭터 썸네일 한 칸 — **얼굴 하나와 역할군 배지가 전부다.**
#
# 예전에는 얼굴 밑에 역할군 이름 · 파일럿 이름 · 종합 스탯 세 줄이 붙어 있었고,
# 그 세 줄이 250px 짜리 칸의 3분의 1을 먹었다. 우마무스메식 인물 고르기에서
# 격자가 하는 일은 **누구인지 알아보게 하는 것**이지 능력치를 비교하게 하는
# 것이 아니다 — 이름도 스탯도 한 번 눌러 위 칸에 앉힌 뒤 상세 팝업이 통째로
# 들고 있고, 그 세 줄을 걷어 낸 만큼 얼굴이 칸을 다 쓴다(칸이 정사각이 됐다).
#
# 남은 글자는 **왼쪽 위 역할군 배지 두 글자**뿐이고, 그것도 읽으라고 있는 것이
# 아니라 색을 확인해 주는 것이다 — 밴픽 화면의 메크 격자와 **같은 배지**라
# (`BanPickController._build_role_badge`) 두 화면이 같은 표시를 쓴다.
#
# 선택 표시는 **금색 테두리 + 우상단 체크 배지** 두 겹이다. 테두리만으로는
# 격자가 5열로 촘촘해 어느 칸이 켜졌는지가 곁눈으로 안 읽힌다.

signal thumb_tapped(pilot_id: int)

const CELL_W: float = 200.0
## 칸은 **정사각**이다 — 얼굴 크롭(256²)이 정사각이라 아래 글자 줄이 사라진
## 지금은 칸도 그 비율을 그대로 따르는 것이 맞다.
const CELL_H: float = 200.0

const ART_MARGIN: float = 6.0

const BORDER_W: int = 3
const BORDER_W_SEL: int = 4
const RADIUS: int = 10

const BG_OFF := OutgameTheme.SURFACE
const BG_ON  := OutgameTheme.ACCENT_DIM
const BORDER_OFF := OutgameTheme.BORDER
const BORDER_ON  := OutgameTheme.ACCENT

const BADGE_SIZE: float = 40.0
const BADGE_BG := OutgameTheme.ACCENT
const BADGE_FG := OutgameTheme.RAIL

# ─── 역할군 배지 (왼쪽 위) ───────────────────────────────────────────────────
## 두 글자 약칭. 밴픽 화면의 `ROLE_INITIALS` 와 **같은 표**다 — 같은 역할이
## 화면마다 다른 글자면 색으로 알아본다는 전제가 무너진다.
const ROLE_INITIALS: Array = ["Tk", "Fi", "As", "Su", "Sn"]
const ROLE_BADGE_W: float = 44.0
const ROLE_BADGE_H: float = 30.0
## 역할 색은 팔레트가 소유한다 — 화면마다 자기 배열을 들면 같은 역할이
## 화면마다 다른 색으로 그려진다.
const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

var pilot: PlayerData = null

var _selected: bool = false
var _built: bool = false

var _face: TextureRect
var _role_badge: Panel
var _role_lbl: Label
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
	# **STOP 이면 안 된다** — 이 칸은 ScrollContainer 안에 있고, 모바일의 드래그
	# 스크롤은 (터치에서 에뮬레이트된) 마우스 press/motion 이 ScrollContainer 까지
	# 올라가야 시작된다. STOP 은 그 전파를 끊으므로 손가락이 썸네일 위에서
	# 시작하면 격자가 영영 안 움직인다 — 칸이 격자를 빈틈없이 덮으므로 사실상
	# 스크롤이 통째로 죽는다. PASS 는 버튼 자신도 그대로 이벤트를 받으므로
	# 탭은 지금과 똑같이 동작하고, 드래그가 시작되면 Godot 이 그 눌림을 취소한다.
	mouse_filter       = Control.MOUSE_FILTER_PASS
	text               = ""
	pressed.connect(_on_pressed)

	var art_sz: float = CELL_W - ART_MARGIN * 2.0
	_face = TextureRect.new()
	_face.position     = Vector2(ART_MARGIN, ART_MARGIN)
	_face.size         = Vector2(art_sz, art_sz)
	_face.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	_role_badge = Panel.new()
	_role_badge.position = Vector2(ART_MARGIN + 4.0, ART_MARGIN + 4.0)
	_role_badge.size     = Vector2(ROLE_BADGE_W, ROLE_BADGE_H)
	_role_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_role_badge)
	_role_lbl = UiHelpers.mk_label(_role_badge, "", 19, OutgameTheme.TEXT_ON_FILL,
			Vector2.ZERO, Vector2(ROLE_BADGE_W, ROLE_BADGE_H),
			HORIZONTAL_ALIGNMENT_CENTER)
	_role_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
		_role_badge.visible = false
		return
	_face.texture = PilotImages.face_for(pilot.id)
	var r: int = int(pilot.role)
	var known: bool = r >= 0 and r < ROLE_INITIALS.size()
	_role_badge.visible = known
	if known:
		_role_lbl.text = String(ROLE_INITIALS[r])
		var sb := StyleBoxFlat.new()
		sb.bg_color = (ROLE_COLORS[r] as Color).darkened(0.15)
		sb.border_color = Color(0, 0, 0, 0.18)
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.corner_radius_top_left     = 8
		sb.corner_radius_top_right    = 8
		sb.corner_radius_bottom_left  = 8
		sb.corner_radius_bottom_right = 8
		_role_badge.add_theme_stylebox_override("panel", sb)


static func total_stats(p: PlayerData) -> int:
	return p.stat_total()


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
