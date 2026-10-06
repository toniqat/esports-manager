class_name PilotThumb
extends Button

# 런 준비 편성(`TeamDraftView`) 하단 격자의 캐릭터 썸네일 한 칸 — **얼굴 하나와
# 역할군 배지, 그리고 오른쪽 아래 샐러리 꼬리표가 전부다.**
#
# 샐러리 꼬리표(`set_tag`)는 편성이 샐러리캡을 갖게 되면서 붙었다 — 캡은
# 고를 때 보여야 하는 규칙이라, 누구를 앉히면 얼마가 드는지가 얼굴 옆에 있어야
# 위의 게이지가 빨개지기 전에 판단이 선다.
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

const ART_MARGIN: float = 4.0

const BORDER_W: int = 3
const BORDER_W_SEL: int = 4
const RADIUS: int = 14
## 얼굴을 깎는 마스크의 모서리 굴림. 칸 테두리(`RADIUS`)와 **같은 중심을 공유하는
## 곡선**이 되도록 안쪽 여백만큼 줄인다 — 같은 값을 쓰면 얼굴 모서리가 테두리보다
## 더 둥글어져 구석에 바탕이 삐져나온다.
const ART_RADIUS: int = RADIUS - int(ART_MARGIN)

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
var _badge: Panel
var _tag: Panel
var _tag_lbl: Label

const TAG_H: float = 34.0
const TAG_BG := OutgameTheme.RAIL


func setup(p: PlayerData, sel: bool) -> void:
	pilot = p
	if not _built:
		_build()
		_built = true
	_refresh()
	set_selected(sel)


## 오른쪽 아래 꼬리표 글자(샐러리). 빈 문자열이면 숨긴다.
func set_tag(text: String) -> void:
	if _tag == null:
		return
	_tag.visible = text != ""
	_tag_lbl.text = text
	var w: float = maxf(TAG_H, 18.0 + 14.0 * float(text.length()))
	_tag.size = Vector2(w, TAG_H)
	_tag.position = Vector2(CELL_W - ART_MARGIN - 6.0 - w, CELL_H - ART_MARGIN - 6.0 - TAG_H)
	_tag_lbl.size = _tag.size


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
	# **STOP 이면 안 된다** — 이 칸은 ScrollContainer 안에 있고, 격자를 굴리는
	# `DragScroll` 은 press 가 ScrollContainer 까지 올라가야 제스처를 시작한다.
	# STOP 은 그 전파를 끊으므로 칸이 격자를 빈틈없이 덮는 이 화면에서는 스크롤이
	# 통째로 죽는다. PASS 는 버튼 자신도 그대로 이벤트를 받으므로 탭은 그대로이고,
	# 끌기가 문턱을 넘으면 `DragScroll` 이 이 버튼의 눌림을 취소한다.
	mouse_filter       = Control.MOUSE_FILTER_PASS
	text               = ""
	pressed.connect(_on_pressed)

	var art_sz: float = CELL_W - ART_MARGIN * 2.0
	_face = add_rounded_art(self, Vector2(ART_MARGIN, ART_MARGIN),
			Vector2(art_sz, art_sz), ART_RADIUS)

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

	_tag = Panel.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(TAG_BG, int(TAG_H * 0.5)))
	_tag.visible = false
	add_child(_tag)
	_tag_lbl = UiHelpers.mk_label(_tag, "", 22, OutgameTheme.TEXT_ON_FILL,
			Vector2.ZERO, Vector2(TAG_H, TAG_H), HORIZONTAL_ALIGNMENT_CENTER)
	_tag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh() -> void:
	if _role_badge != null:
		_role_badge.queue_free()
		_role_badge = null
	if pilot == null:
		_face.texture = null
		return
	_face.texture = PilotImages.face_for(pilot.id)
	_role_badge = add_role_badge(self, int(pilot.role),
			Vector2(ART_MARGIN + 6.0, ART_MARGIN + 6.0))
	# 체크 배지보다 아래에 깔리게 — 둘이 겹칠 일은 없지만 순서를 못박아 둔다.
	if _role_badge != null:
		move_child(_role_badge, _badge.get_index())


## **둥근 사각형으로 깎은 그림 한 장.** 마스크는 둥근 `StyleBoxFlat` 을 그리는
## `Panel` 이고 그림은 그 자식이다 — `clip_children` 이 자식을 부모가 그린
## 알파로 잘라 내므로 모서리가 칸 테두리와 같은 곡선으로 떨어진다.
## `clip_contents` 는 사각형으로만 자르므로 이 자리에 쓸 수 없다.
## 돌려주는 것은 텍스처를 꽂을 `TextureRect`.
static func add_rounded_art(parent: Control, pos: Vector2, sz: Vector2,
		radius: int) -> TextureRect:
	var mask := Panel.new()
	mask.position = pos
	mask.size = sz
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.anti_aliasing = true
	sb.corner_radius_top_left     = radius
	sb.corner_radius_top_right    = radius
	sb.corner_radius_bottom_left  = radius
	sb.corner_radius_bottom_right = radius
	mask.add_theme_stylebox_override("panel", sb)
	parent.add_child(mask)

	var art := TextureRect.new()
	art.position     = Vector2.ZERO
	art.size         = sz
	art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(art)
	return art


## **역할군 배지**(`Tk` / `As` …) — 격자 썸네일과 드래프트 상단의 상체 일러스트가
## 같은 함수로 세운다. 화면마다 자기 배지를 그리면 같은 역할이 화면마다 다른
## 크기 · 색 · 글자로 서서 "색으로 알아본다"는 전제가 무너진다.
## 알 수 없는 역할이면 아무것도 안 세우고 null.
static func add_role_badge(parent: Control, role: int, pos: Vector2) -> Panel:
	if role < 0 or role >= ROLE_INITIALS.size():
		return null
	var badge := Panel.new()
	badge.position = pos
	badge.size     = Vector2(ROLE_BADGE_W, ROLE_BADGE_H)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = (ROLE_COLORS[role] as Color).darkened(0.15)
	sb.border_color = Color(0, 0, 0, 0.18)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left     = 8
	sb.corner_radius_top_right    = 8
	sb.corner_radius_bottom_left  = 8
	sb.corner_radius_bottom_right = 8
	badge.add_theme_stylebox_override("panel", sb)
	parent.add_child(badge)
	var lbl := UiHelpers.mk_label(badge, String(ROLE_INITIALS[role]), 19,
			OutgameTheme.TEXT_ON_FILL, Vector2.ZERO,
			Vector2(ROLE_BADGE_W, ROLE_BADGE_H), HORIZONTAL_ALIGNMENT_CENTER)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


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
