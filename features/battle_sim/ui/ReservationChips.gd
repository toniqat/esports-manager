class_name ReservationChips
extends Control

# 예약 칩 — **나중에 정산되는 카드 효과**를 전략 점수 도넛 곁에 작은 칩으로
# 남긴다. 카드를 낸 순간에는 아무 일도 일어나지 않는 효과라(아드레날린의 뒷절 ·
# 준비 태세 · 계획 살인 · 매복 탐색), 화면에 흔적이 없으면 무엇을 예약해 두었는지가
# 잊힌다.
#
# 칩 하나 = 왼쪽 둥근 사각형 카드 아트(그 예약을 건 카드, `BattleSim.reserve_src`)
# + 오른쪽 값. 아군 칩은 아군 도넛 **위로** 쌓이고, 적 칩은 적 도넛 **아래로**
# 쌓인다. 값은 `BattleSim` 의 장부를 그대로 읽으므로 정산되어 0 이 되면 칩도
# 저절로 사라진다(매 프레임 서명을 견줘 바뀔 때만 다시 그린다).

const CHIP_W: float = 150.0
## 칩 줄의 왼쪽 끝(캔버스 x). 도넛 열(좌측 여백)보다 넓어서 가운데 정렬 대신
## 화면 왼쪽에 붙인다.
const CHIP_LEFT_X: float = 8.0
const CHIP_H: float = 40.0
const CHIP_GAP: float = 6.0
const CHIP_ART: float = 32.0
const CHIP_FONT: int = 18
const CHIP_BG := Color(0.06, 0.06, 0.10, 0.90)
const CHIP_BORDER := Color(1.0, 1.0, 1.0, 0.35)
## 도넛 가장자리와 첫 칩 사이 — 아군 쪽은 도넛 미리보기의 `+N` 이 뜰 자리를 비운다.
const DONUT_CLEAR_PLAYER: float = 52.0
const DONUT_CLEAR_ENEMY: float = 10.0

var _bs: BattleSim = null
var _is_player: bool = true
var _sig: String = ""
## 구성이 바뀐 뒤 몇 프레임 더 다시 그린다 — 처음 쓰는 카드 아트는
## `prime_texture` 로 올린 다음 프레임부터 제대로 그려진다.
var _settle: int = 0


## `donut_center` 는 캔버스 좌표. 아군이면 그 위로, 적이면 그 아래로 쌓는다.
func setup(bs: BattleSim, is_player: bool, donut_center: Vector2) -> void:
	_bs = bs
	_is_player = is_player
	name = "ReservationChips%s" % ("P" if is_player else "AI")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(CHIP_W, CHIP_H)
	var x: float = CHIP_LEFT_X
	if is_player:
		position = Vector2(x, donut_center.y - CostDonut.RADIUS
				- DONUT_CLEAR_PLAYER - CHIP_H)
	else:
		position = Vector2(x, donut_center.y + CostDonut.RADIUS + DONUT_CLEAR_ENEMY)


func _process(_delta: float) -> void:
	var sig: String = str(_entries())
	if sig != _sig:
		_sig = sig
		_settle = 3
	if _settle > 0:
		_settle -= 1
		queue_redraw()


## 지금 떠 있어야 할 칩들 — `[아트 키, 글자]`.
func _entries() -> Array:
	var out: Array = []
	if _bs == null:
		return out
	var side: String = "p" if _is_player else "ai"
	var strat: int = _bs.next_phase_strategy_p if _is_player else _bs.next_phase_strategy_ai
	var draw_n: int = _bs.next_phase_draw_p if _is_player else _bs.next_phase_draw_ai
	var bounty: int = _bs.kill_bounty_p if _is_player else _bs.kill_bounty_ai
	var ambush: Array = _bs.ambush_search_p if _is_player else _bs.ambush_search_ai
	if strat != 0:
		out.append(["strategy_" + side, "다음 %+d" % strat])
	if draw_n > 0:
		out.append(["draw_" + side, "다음 뽑기 %d" % draw_n])
	if bounty > 0:
		out.append(["bounty_" + side, "처치 +%d" % bounty])
	if not ambush.is_empty():
		var n: int = 0
		for raw in ambush:
			n += int((raw as Dictionary).get("n", 0))
		out.append(["ambush_" + side, "찾기 %d" % n])
	return out


func _draw() -> void:
	var entries: Array = _entries()
	var font := ThemeDB.fallback_font
	for i in entries.size():
		var e: Array = entries[i] as Array
		var dy: float = float(i) * (CHIP_H + CHIP_GAP)
		var box := Rect2(0.0, -dy if _is_player else dy, CHIP_W, CHIP_H)
		var sb := StyleBoxFlat.new()
		sb.bg_color = CHIP_BG
		sb.border_color = CHIP_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		draw_style_box(sb, box)
		var art_rect := Rect2(box.position.x + 4.0,
				box.position.y + (CHIP_H - CHIP_ART) * 0.5, CHIP_ART, CHIP_ART)
		var tex: Texture2D = CardImages.art_for(String(_bs.reserve_src.get(String(e[0]), "")))
		_bs.prime_texture(tex)
		if tex != null:
			BattleRenderer.draw_textured_rounded_rect(self, tex, art_rect, 7.0)
		else:
			var ph := StyleBoxFlat.new()
			ph.bg_color = Color(0.25, 0.25, 0.32)
			ph.set_corner_radius_all(7)
			draw_style_box(ph, art_rect)
		var txt: String = String(e[1])
		var text_x: float = art_rect.end.x + 5.0
		var max_w: float = box.end.x - 4.0 - text_x
		var at := Vector2(text_x, box.position.y + CHIP_H * 0.5
				+ font.get_ascent(CHIP_FONT) * 0.5 - 2.0)
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, max_w, CHIP_FONT,
				Color(1.0, 0.95, 0.80))
