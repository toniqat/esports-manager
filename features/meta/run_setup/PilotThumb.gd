class_name PilotThumb
extends Button

# 런 준비 편성(`TeamDraftView`) 하단 격자의 캐릭터 썸네일 한 칸 — **얼굴 하나와
# 역할군 배지, 그리고 오른쪽 아래 샐러리 꼬리표가 전부다.**
#
# **모양의 정본은 `UI_Comp_PilotThumb.tscn`** (칸 크기 · 얼굴 마스크 · 배지 / 체크 / 꼬리표 자리 ·
# 스타일). 이 스크립트는 데이터만 넣는다 — 얼굴 텍스처, 포지션 배지(`PositionBadge`),
# 꼬리표 글자와 그 폭, 그리고 선택 상태에 따른 칸의 테마 변형(`_apply_style` —
# `SelectableCardButton` / `SelectableCardButtonOn`, 모서리 `OutgameTheme.CARD_RADIUS`;
# 얼굴 마스크 `ArtMask` 의 모서리는 그 반경 - 안쪽 여백 4 로 씬이 맞춘다).
# 생성은 `PilotThumb.create()` — `.new()` 는 빈 버튼이라 쓰지 않는다.
#
# 샐러리 꼬리표(`set_tag`)는 편성이 샐러리캡을 갖게 되면서 붙었다 — 캡은
# 고를 때 보여야 하는 규칙이라, 누구를 앉히면 얼마가 드는지가 얼굴 옆에 있어야
# 위의 게이지가 빨개지기 전에 판단이 선다.
#
# 격자가 하는 일은 **누구인지 알아보게 하는 것**이지 능력치를 비교하게 하는
# 것이 아니다 — 이름도 스탯도 한 번 눌러 위 칸에 앉힌 뒤 상세 팝업이 통째로
# 들고 있고, 얼굴이 칸을 다 쓴다(칸이 정사각).
#
# 남은 글자는 **왼쪽 위 역할군 배지 두 글자**뿐이다 — 밴픽 화면의 메크 격자와
# **같은 배지**라(`BanPickController._build_role_badge`) 두 화면이 같은 표시를 쓴다.
#
# 선택 표시는 **금색 테두리 + 우상단 체크 배지** 두 겹이다. 테두리만으로는
# 격자가 5열로 촘촘해 어느 칸이 켜졌는지가 곁눈으로 안 읽힌다.
#
# 칸은 `ScrollContainer` 안에 있으므로 씬에서 **`mouse_filter = PASS`** 다 — STOP 이면
# 격자를 굴리는 `DragScroll` 이 press 를 못 받아 스크롤이 통째로 죽는다.

signal thumb_tapped(pilot_id: int)

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_PilotThumb.tscn"

## 칸 크기 — 씬의 `custom_minimum_size` 와 같다. 격자 높이 계산(`TeamDraftView.grid_h`)이 읽는다.
const CELL_W: float = 200.0
const CELL_H: float = 200.0

## 꼬리표 높이 — 폭은 글자 수로 정한다(`set_tag`).
const TAG_H: float = 34.0

var pilot: PlayerData = null

var _selected: bool = false


static func create() -> PilotThumb:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PilotThumb


func _ready() -> void:
	pressed.connect(_on_pressed)
	_apply_style()
	if UiPreview.is_standalone(self):
		_fill_preview()


func setup(p: PlayerData, sel: bool) -> void:
	pilot = p
	_refresh()
	set_selected(sel)


## 오른쪽 아래 꼬리표 글자(샐러리). 빈 문자열이면 숨긴다. 폭은 글자 수에 따른다 —
## 오른쪽 · 아래 자리는 씬이 정한다.
func set_tag(text: String) -> void:
	var tag: Control = %Tag
	tag.visible = text != ""
	(%TagText as Label).text = text
	var w: float = maxf(TAG_H, 18.0 + 14.0 * float(text.length()))
	tag.offset_left = tag.offset_right - w


func set_selected(sel: bool) -> void:
	_selected = sel
	(%Check as Control).visible = sel
	_apply_style()


func _refresh() -> void:
	var face: TextureRect = %Face
	var badge: PositionBadge = %PositionBadge
	if pilot == null:
		face.texture = null
		badge.visible = false
		return
	face.texture = PilotImages.face_for(pilot.id)
	badge.set_role(int(pilot.role))


## **둥근 사각형으로 깎은 그림 한 장** — 컬렉션(`CollectionCell` · `CollectionDetailSheet`)이
## 코드로 세우는 자리를 위해 남긴 도우미. 이 폴더의 씬(`UI_Comp_PilotThumb.tscn` · `UI_Comp_DraftSlot.tscn`)은
## 같은 구조(`ArtMask` Panel + `clip_children` → TextureRect)를 노드로 들고 있다.
## 마스크는 둥근 `StyleBoxFlat` 을 그리는 `Panel` 이고 그림은 그 자식이다 —
## `clip_children` 이 자식을 부모가 그린 알파로 잘라 내므로 모서리가 칸 테두리와 같은
## 곡선으로 떨어진다. `clip_contents` 는 사각형으로만 자르므로 이 자리에 쓸 수 없다.
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
	OutgameTheme.set_corner_radius(sb, radius)
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


## **포지션 배지**를 `parent` 의 `pos` 에 세운다 — `UI_Comp_PositionBadge.tscn` 한 장. 컬렉션처럼
## 코드로 배치하는 자리용. 알 수 없는 역할이면 아무것도 안 세우고 null.
static func add_position_badge(parent: Control, role: int, pos: Vector2) -> PositionBadge:
	var badge := PositionBadge.create()
	if not badge.set_role(role):
		badge.free()
		return null
	badge.position = pos
	parent.add_child(badge)
	return badge


static func total_stats(p: PlayerData) -> int:
	return p.stat_total()


## 선택 상태 → 칸의 테마 변형(테두리 · 바탕). 상태라 코드가 이름만 바꾼다.
func _apply_style() -> void:
	theme_type_variation = &"SelectableCardButtonOn" if _selected else &"SelectableCardButton"


func _on_pressed() -> void:
	if pilot != null:
		thumb_tapped.emit(pilot.id)


## F6 단독 실행 미리보기 — 고른 칸(금 테두리 + 체크) + 샐러리 꼬리표, 손으로 적은 값
## (`resources/UiPreview.gd`). id 는 얼굴 그림이 있는 실제 선수(2 = Corin).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(thumb_tapped)
	setup(PlayerData.new(2, "Corin", GameEnums.Role.ASSASSIN, 5, 80, 85, 82, 80, 81, 82, 19), true)
	set_tag("49")
