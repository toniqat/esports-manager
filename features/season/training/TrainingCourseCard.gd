class_name TrainingCourseCard
extends Panel

# 코스 카드 한 장 — `TrainingView` 인벤토리 줄(`%CourseRow`)의 반복 항목. 세로로 선
# 카드이고 위에서부터 등급 띠(등급 글자 · 놓임/상한) → 오목한 상자 안의 모양
# 미니어처 → 이름. 설명문과 EXP 요약은 정보 팝오버(`TrainingCoursePopover`)가 든다.
#
# **레이아웃의 정본은 `TrainingCourseCard.tscn` 이다** (카드 크기, 띠 높이, 상자 자리,
# 이름 칸, 잠금 칩 — 에디터에서 고친다). 이 스크립트가 정하는 것은 데이터뿐:
# 등급 색(테두리 · 띠 · 등급 글자), 고른 카드의 옷, 잠긴 카드의 흐림, 모양 미니어처
# (`%Mini` 의 `draw` — 상자 크기에서 칸 크기를 역산한다).
#
# 입력은 이 카드가 받지 않는다 — `TrainingView` 가 `gui_input` 을 잇는다(탭 = 고르기,
# 세로 드래그 = 집기). 카드는 씬에서 **PASS** 라 눌림이 스크롤까지 올라간다.

const SCENE_PATH: String = "res://features/season/training/TrainingCourseCard.tscn"

## 미니어처 칸 한 변의 상한. 모양이 커지면 상자에 맞게 줄어든다.
const MINI_MAX: float = 26.0
## 고른 카드의 테두리 두께(평소는 테마 변형 `TrainingCourseCardFrame` 두께).
const SELECTED_BORDER: int = 4

var tile: TrainingTile = null

var _frame: StyleBoxFlat = null    # `TrainingCourseCardFrame` 사본 — 고르기/잠김마다 복사해 색만 바꾼다


## 씬을 인스턴스한다. `TrainingCourseCard.new()` 는 빈 Panel 이라 쓰지 않는다.
static func create() -> TrainingCourseCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingCourseCard


func _ready() -> void:
	(%Mini as Control).draw.connect(_draw_mini)
	if UiPreview.is_standalone(self):
		_fill_preview()


## 카드를 채운다. `grade_locked` = 전술이 모자라 등급이 안 열림(잠금 칩),
## `locked` = 그것이거나 등급 상한에 닿음(흐림, 집을 수 없음).
func fill(t: TrainingTile, cap_text: String, grade_locked: bool, locked: bool,
		lock_reason: String) -> void:
	tile = t
	if _frame == null:
		_frame = OutgameTheme.variation_box(&"TrainingCourseCardFrame")
	var g: Color = t.grade_color()
	set_selected(false, locked)

	var band: Panel = %Band
	var bsty := OutgameTheme.variation_box(&"TrainingCourseGradeBand")
	bsty.bg_color = Color(g.r, g.g, g.b, 0.22)
	band.add_theme_stylebox_override(&"panel", bsty)
	(%Grade as Label).text = t.grade_name()
	(%Grade as Label).add_theme_color_override(&"font_color", g)
	(%Cap as Label).text = cap_text
	(%Name as Label).text = t.tile_name
	(%Body as Control).modulate = Color(1, 1, 1, 0.42) if locked else Color(1, 1, 1, 1)

	(%LockChip as Control).visible = grade_locked
	(%LockText as Label).text = lock_reason
	(%Mini as Control).queue_redraw()


## 카드의 옷 — 고른 카드는 앰버 틴트 바탕 + 굵은 테두리, 잠긴 카드는 테두리가 옅다.
func set_selected(selected: bool, locked: bool) -> void:
	if tile == null or _frame == null:
		return
	var g: Color = tile.grade_color()
	var sty := _frame.duplicate() as StyleBoxFlat
	sty.border_color = Color(g.r, g.g, g.b, 0.35 if locked else 1.0)
	if selected:
		sty.bg_color = OutgameTheme.ACCENT_DIM
		sty.set_border_width_all(SELECTED_BORDER)
	add_theme_stylebox_override(&"panel", sty)


## 모양 미니어처 — 칸 하나를 최대 `MINI_MAX` 로 잡되 모양이 커지면 줄여 언제나 같은
## 상자 안에 가운데로 들어오게 한다. 6칸 타일과 1칸 타일이 같은 크기로 그려지면
## "몇 칸짜리인가"가 카드에서 안 읽힌다.
func _draw_mini() -> void:
	if tile == null:
		return
	var mini: Control = %Mini
	var box: Vector2 = mini.size
	var ext: Vector2i = tile.extent()
	var s: float = minf(MINI_MAX, minf(box.x / float(ext.x), box.y / float(ext.y)))
	var ox: float = (box.x - s * float(ext.x)) * 0.5
	var oy: float = (box.y - s * float(ext.y)) * 0.5
	for i in tile.cells.size():
		var c: Vector2i = tile.cells[i]
		mini.draw_rect(Rect2(ox + float(c.x) * s + 1.0, oy + float(c.y) * s + 1.0,
				s - 2.0, s - 2.0), TrainingTile.color_of(String(tile.cell_colors[i])), true)


## F6 단독 실행 미리보기 — 손으로 적은 3등급 2×2 코스, 고른 상태(`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var t := TrainingTile.from_def({"id": "T12", "name": "합숙 스크림", "grade": 3,
			"shape": "CC/DD", "exp": "engage_hit:52|engage_eva:52", "effect": ""})
	fill(t, "1/2", false, false, "")
	set_selected(true, false)
