class_name LeagueRow
extends Panel

# One standings row of `LeagueView` — rank · team · W-L · win rate · PO mark.
#
# **Layout lives in `LeagueRow.tscn`** (column offsets, font sizes, the full-row `%Hit`
# button). `LeagueView` keeps one instance per ranked team inside its `%Rows` box. This
# script fills text and paints the card: the fill / border are data (own team = amber tint +
# amber border, playoff cut = green left bar, empty slot = sunk), so the card's
# `StyleBoxFlat` is built here from `OutgameTheme.card_style` and mutated per refresh — no
# theme variation carries a state colour. The rank colour (own team = `TEXT`) is data too.

## The whole row was tapped (the scene's flat `%Hit` button covers it).
signal tapped

const ROW_RADIUS: int = 14

var _style: StyleBoxFlat


func _ready() -> void:
	_style = OutgameTheme.card_style(ROW_RADIUS)
	add_theme_stylebox_override("panel", _style)
	(%Hit as Button).pressed.connect(func() -> void: tapped.emit())
	if UiPreview.is_standalone(self):
		_fill_preview()


## An empty slot (fewer ranked teams than rows).
func clear() -> void:
	%Rank.text = ""
	%Team.text = ""
	%Record.text = ""
	%Pct.text = ""
	%Po.text = ""
	_style.bg_color = OutgameTheme.SURFACE_SUNK
	_style.border_color = OutgameTheme.BORDER
	_style.set_border_width_all(1)


func fill(rank: int, team_text: String, wins: int, losses: int,
		made_po: bool, is_player: bool) -> void:
	var played: int = wins + losses
	%Rank.text = "%d" % rank
	%Team.text = team_text
	%Record.text = "%d승 %d패" % [wins, losses]
	%Pct.text = "—" if played == 0 else "%.3f" % (float(wins) / float(played))
	%Po.text = "PO" if made_po else ""

	# 플레이어 줄은 앰버 틴트 + 앰버 테두리, 진출권은 왼쪽 초록 띠 하나.
	# 색면으로 칠하면 그 줄의 숫자가 안 읽힌다 — 흰 종이에서 강조는 테두리다.
	_style.bg_color = OutgameTheme.ACCENT_DIM if is_player else OutgameTheme.SURFACE
	if is_player:
		_style.set_border_width_all(2)
		_style.border_color = OutgameTheme.ACCENT
	elif made_po:
		# `StyleBoxFlat` 의 테두리 색은 **한 가지뿐**이라 "옅은 외곽선 + 초록
		# 왼쪽 띠"를 한 판으로 낼 수 없다. 띠 쪽을 택한다 — 흰 종이 위에서는
		# 그림자가 이미 카드의 윤곽을 만들고 있어 외곽선이 없어도 판이 선다.
		_style.set_border_width_all(0)
		_style.border_width_left = 6
		_style.border_color = OutgameTheme.POSITIVE
	else:
		_style.set_border_width_all(1)
		_style.border_color = OutgameTheme.BORDER

	(%Rank as Label).add_theme_color_override("font_color",
			OutgameTheme.TEXT if is_player else OutgameTheme.TEXT_SUB)


## F6 단독 실행 미리보기 — 진출권 · 내 팀 줄 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(tapped)
	fill(3, "T1  (T1)", 5, 2, true, true)
