class_name DraftSlot
extends VBoxContainer

# 편성 화면(`TeamDraftView`) 위쪽 다섯 칸 중 한 칸 — 상체 일러스트(누르면 상세 팝업),
# 그 아래 `랭크 R · Lv N` 줄(고를 수 없다 — 컬렉션의 랭크 · 레벨 그대로), 샐러리 줄, 종합 줄.
#
# **모양의 정본은 `UI_Comp_DraftSlot.tscn`** (일러스트 204×412 · 마스크 · 빈 칸 글자 · 배지 자리 ·
# 글자 줄). 이 스크립트는 데이터만 넣는다 — 역할 배지, 일러스트 텍스처,
# 랭크 · 레벨 · 샐러리 · 종합 글자, 그리고 칸 테두리(빈 칸 = 회색, 찬 칸 = 역할 색 → 데이터라 코드).
#
# **`%Frame` 을 `flat` 로 두면 안 된다** — flat 버튼은 스타일박스를 통째로 무시해 빈 칸의
# 테두리가 사라진다.

signal art_pressed


func _ready() -> void:
	(%Frame as Button).pressed.connect(func() -> void: art_pressed.emit())
	if UiPreview.is_standalone(self):
		_fill_preview()


## 칸의 역할 — 배지는 **빈 칸에도 선다**(어느 역할의 자리인지를 말한다).
func set_role(role: int) -> void:
	(%PositionBadge as PositionBadge).set_role(role)


## 빈 칸.
func show_empty() -> void:
	var frame: Button = %Frame
	(%Art as TextureRect).texture = null
	(%EmptyMark as Control).visible = true
	frame.disabled = true
	_set_frame_style(OutgameTheme.SURFACE_SUNK, OutgameTheme.BORDER)
	(%Level as Label).text = ""
	(%Salary as Label).text = ""
	(%Total as Label).text = ""


## 찬 칸. `p` 는 랭크 · 레벨이 반영된 사본(`p.rank` · `p.level` 을 그대로 보인다).
func show_pilot(p: PlayerData, role_color: Color, salary: int) -> void:
	var frame: Button = %Frame
	(%Art as TextureRect).texture = PilotImages.bust_for(p.id)
	(%EmptyMark as Control).visible = false
	frame.disabled = false
	_set_frame_style(OutgameTheme.SURFACE, role_color)
	(%Level as Label).text = Loc.t(L.RUN_SETUP_SLOT_RANK_LEVEL, {"rank": p.rank, "level": p.level})
	(%Salary as Label).text = Loc.t(L.RUN_SETUP_SLOT_SALARY, {"n": salary})
	(%Total as Label).text = Loc.t(L.RUN_SETUP_SLOT_TOTAL, {"n": p.stat_total()})


## 칸 모양(반지름 · 테두리 두께)은 테마 변형 `DraftSlotFrame` 이 정하고 — 일러스트 마스크는
## 씬에서 그 두께만큼 안쪽에 있다 — 여기서는 사본에 바탕 · 테두리 색만 넣는다.
func _set_frame_style(bg: Color, border: Color) -> void:
	var sty := OutgameTheme.variation_box(&"DraftSlotFrame", &"normal")
	sty.bg_color = bg
	sty.border_color = border
	var frame: Button = %Frame
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		frame.add_theme_stylebox_override(st, sty)


## F6 단독 실행 미리보기 — 탑 칸에 랭크 2 · Lv 3 으로 앉은 선수, 손으로 적은 값
## (`resources/UiPreview.gd`). id 는 일러스트가 있는 실제 선수(5 = Evelyn).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(art_pressed)
	var role: int = GameEnums.Role.TANK
	set_role(role)
	var p := PlayerData.new(5, "tx_A57ZKJ2RYN", role, 0, 85, 86, 82, 90, 86, 85, 20)
	p.rank = 2
	p.level = 3
	show_pilot(p, OutgameTheme.ROLE_COLORS[role], 57)
