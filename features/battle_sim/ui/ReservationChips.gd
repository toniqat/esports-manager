class_name ReservationChips
extends Control

# 예약 칩 — **나중에 정산되는 카드 효과**를 전략 점수 도넛 곁에 작은 칩으로
# 남긴다. 카드를 낸 순간에는 아무 일도 일어나지 않는 효과라(아드레날린의 뒷절 ·
# 준비 태세 · 계획 살인 · 매복 탐색), 화면에 흔적이 없으면 무엇을 예약해 두었는지가
# 잊힌다.
#
# **칩 하나 = 출처 카드 한 장** — 왼쪽 둥근 사각형 카드 아트 + 그 카드가 건 예약 값을
# 한 줄로(전략 점수는 작은 팔각형 + `+3`, 나머지는 `뽑기 3` · `처치 +2` · `찾기 1`).
# 준비 태세처럼 한 장이 예약 둘을 걸어도 칩은 하나다. 판(바탕)은 없고 글자에 외곽선만
# 두른다. 출처는 `BattleSim.reserve_log`(카드가 예약을 걸 때 `note_reserve`)에서,
# 값은 각 장부(`BattleSim.reserve_ledger`)에서 읽는다 — 장부에 있는데 출처 줄이 없는
# 몫은 "출처 모름" 칩(아트 자리 표시)으로 남는다. 정산되어 0 이 되면 칩도 저절로
# 사라진다(매 프레임 서명을 견줘 바뀔 때만 다시 그린다).
#
# 칩을 누르면 그 카드의 예약 설명 판(`ReserveInfo`)이 칩 오른쪽에 뜬다 — 같은 칩을
# 다시 누르거나 바깥을 누르면 닫힌다.

const KINDS: Array = ["strategy", "draw", "bounty", "ambush"]
## 칩 줄의 왼쪽 끝(캔버스 x).
const CHIP_LEFT_X: float = 8.0
const CHIP_H: float = 44.0
const CHIP_GAP: float = 8.0
const CHIP_ART: float = 40.0
const CHIP_FONT: int = 22
const CHIP_TEXT: Color = BattleTheme.TEXT_SCORE
const CHIP_OUTLINE: Color = BattleTheme.OUTLINE
const CHIP_OUTLINE_SIZE: int = 6
## 아트와 값 사이 · 값끼리 사이.
const PART_GAP: float = 8.0
## 전략 점수 값 앞의 작은 팔각형 반지름.
const GLYPH_R: float = 10.0
const GLYPH_COLOR: Color = BattleTheme.TEAM_DONUT[0]
## 출처를 모르는 칩의 아트 자리 표시.
const ART_PLACEHOLDER: Color = BattleTheme.SLAB_BG
## 도넛 가장자리와 첫 칩 사이 — 아군 쪽은 도넛 미리보기의 `+N` 이 뜰 자리를 비운다.
const DONUT_CLEAR_PLAYER: float = 52.0
const DONUT_CLEAR_ENEMY: float = 10.0

var _bs: BattleSim = null
var _is_player: bool = true
var _sig: Array = []
## 지금 칩들 — `[{uid, card, strategy, draw, bounty, ambush}]` (`_groups`).
var _cur: Array = []
## 칩마다 로컬 사각형(아트 + 값) — 그리기와 누름 판정이 같은 것을 쓴다.
var _rects: Array = []
## 구성이 바뀐 뒤 몇 프레임 더 다시 그린다 — 처음 쓰는 카드 아트는
## `prime_texture` 로 올린 다음 프레임부터 제대로 그려진다.
var _settle: int = 0
var _info: ReserveInfo = null


## `donut_center` 는 캔버스 좌표. 아군이면 그 위로, 적이면 그 아래로 쌓는다.
func setup(bs: BattleSim, is_player: bool, donut_center: Vector2) -> void:
	_bs = bs
	_is_player = is_player
	name = "ReservationChips%s" % ("P" if is_player else "AI")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(CHIP_ART, CHIP_H)
	var x: float = CHIP_LEFT_X
	if is_player:
		position = Vector2(x, donut_center.y - CostDonut.RADIUS
				- DONUT_CLEAR_PLAYER - CHIP_H)
	else:
		position = Vector2(x, donut_center.y + CostDonut.RADIUS + DONUT_CLEAR_ENEMY)


func _process(_delta: float) -> void:
	if _bs == null:
		return
	_cur = _groups()
	# 배열끼리 값으로 비교한다 — `str()` 로 매 프레임 문자열을 굽지 않는다.
	var sig: Array = []
	for g in _cur:
		var d: Dictionary = g
		sig.append([d["uid"], d["strategy"], d["draw"], d["bounty"], d["ambush"]])
	if sig != _sig:
		_sig = sig
		_settle = 3
		_layout()
		_sync_info()
	if _settle > 0:
		_settle -= 1
		queue_redraw()


## 출처 카드별로 묶은 예약 — 출처 줄 순서(먼저 건 카드가 아래).
func _groups() -> Array:
	var out: Array = []
	_bs.prune_reserve_log()
	var side: String = "p" if _is_player else "ai"
	var by_uid: Dictionary = {}
	var logged: Dictionary = {"strategy": 0, "draw": 0, "bounty": 0, "ambush": 0}
	for raw in _bs.reserve_log:
		var e: Dictionary = raw
		if e["side"] != side:
			continue
		var kind: String = String(e["kind"])
		var n: int = int(e["n"])
		var g: Dictionary = _group_for(by_uid, out, String(e["uid"]), e["card"] as CardData)
		if kind == "bounty":
			g[kind] = maxi(int(g[kind]), n)
			logged[kind] = maxi(int(logged[kind]), n)
		else:
			g[kind] = int(g[kind]) + n
			logged[kind] = int(logged[kind]) + n
	# 장부에 있는데 출처 줄이 없는 몫(카드 밖에서 건 예약) — 출처 모름 칩.
	for kind in KINDS:
		var ledger: int = _bs.reserve_ledger(kind, _is_player)
		var rest: int
		if kind == "bounty":
			rest = ledger if ledger > int(logged[kind]) else 0
		else:
			rest = ledger - int(logged[kind])
		if rest != 0:
			var g: Dictionary = _group_for(by_uid, out, "", null)
			g[kind] = rest if kind == "bounty" else int(g[kind]) + rest
	return out.filter(func(g: Dictionary) -> bool:
		return int(g["strategy"]) != 0 or int(g["draw"]) > 0 \
				or int(g["bounty"]) > 0 or int(g["ambush"]) > 0)


func _group_for(by_uid: Dictionary, out: Array, uid: String, card: CardData) -> Dictionary:
	if by_uid.has(uid):
		return by_uid[uid]
	var g: Dictionary = {"uid": uid, "card": card,
			"strategy": 0, "draw": 0, "bounty": 0, "ambush": 0}
	by_uid[uid] = g
	out.append(g)
	return g


## 칩 한 줄의 값 조각 — `[전략 팔각형인가, 글자]`.
func _parts(g: Dictionary) -> Array:
	var out: Array = []
	if int(g["strategy"]) != 0:
		out.append([true, "%+d" % int(g["strategy"])])
	if int(g["draw"]) > 0:
		out.append([false, Loc.t(L.HUD_RESERVE_CHIP_DRAW, {"n": int(g["draw"])})])
	if int(g["bounty"]) > 0:
		out.append([false, Loc.t(L.HUD_RESERVE_CHIP_BOUNTY, {"n": int(g["bounty"])})])
	if int(g["ambush"]) > 0:
		out.append([false, Loc.t(L.HUD_RESERVE_CHIP_SEARCH, {"n": int(g["ambush"])})])
	return out


## 설명 판 줄 — 예약 하나당 한 줄.
func _lines(g: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if int(g["strategy"]) != 0:
		out.append(Loc.t(L.HUD_RESERVE_STRATEGY, {"n": "%+d" % int(g["strategy"])}))
	if int(g["draw"]) > 0:
		out.append(Loc.t(L.HUD_RESERVE_DRAW, {"n": int(g["draw"])}))
	if int(g["bounty"]) > 0:
		out.append(Loc.t(L.HUD_RESERVE_BOUNTY, {"n": int(g["bounty"])}))
	if int(g["ambush"]) > 0:
		out.append(Loc.t(L.HUD_RESERVE_SEARCH, {"n": int(g["ambush"])}))
	return out


func _part_width(part: Array, font: Font) -> float:
	var w: float = font.get_string_size(String(part[1]), HORIZONTAL_ALIGNMENT_LEFT, -1,
			CHIP_FONT).x
	if bool(part[0]):
		w += GLYPH_R * 2.0 + 4.0
	return w


func _layout() -> void:
	_rects.clear()
	var font := ThemeDB.fallback_font
	for i in _cur.size():
		var w: float = CHIP_ART
		for part in _parts(_cur[i]):
			w += PART_GAP + _part_width(part, font)
		var dy: float = float(i) * (CHIP_H + CHIP_GAP)
		_rects.append(Rect2(0.0, -dy if _is_player else dy, w, CHIP_H))


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in mini(_cur.size(), _rects.size()):
		var g: Dictionary = _cur[i]
		var box: Rect2 = _rects[i]
		var art_rect := Rect2(box.position.x,
				box.position.y + (CHIP_H - CHIP_ART) * 0.5, CHIP_ART, CHIP_ART)
		var tex: Texture2D = CardImages.art_for(String(g["uid"]))
		_bs.prime_texture(tex)
		if tex != null:
			BattleRenderer.draw_textured_rounded_rect(self, tex, art_rect, 8.0)
		else:
			var ph := StyleBoxFlat.new()
			ph.bg_color = ART_PLACEHOLDER
			ph.set_corner_radius_all(8)
			draw_style_box(ph, art_rect)
		var x: float = art_rect.end.x + PART_GAP
		var mid_y: float = box.position.y + CHIP_H * 0.5
		var base_y: float = mid_y + font.get_ascent(CHIP_FONT) * 0.5 - 2.0
		for part in _parts(g):
			if bool(part[0]):
				var c := Vector2(x + GLYPH_R, mid_y)
				var oct: PackedVector2Array = StrategyIcon.points(c, GLYPH_R)
				var rim := oct.duplicate()
				rim.append(oct[0])
				draw_polyline(rim, CHIP_OUTLINE, 4.0, true)
				draw_colored_polygon(oct, GLYPH_COLOR)
				x += GLYPH_R * 2.0 + 4.0
			var txt: String = String(part[1])
			var at := Vector2(x, base_y)
			draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT,
					CHIP_OUTLINE_SIZE, CHIP_OUTLINE)
			draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT, CHIP_TEXT)
			x += font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT).x \
					+ PART_GAP


# ── 누름 → 설명 판 ───────────────────────────────────────────────────────────

## `pos`(캔버스 좌표) 아래의 칩 번호, 없으면 -1.
func chip_at(pos: Vector2) -> int:
	if not is_visible_in_tree():
		return -1
	var local: Vector2 = get_global_transform().affine_inverse() * pos
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(local):
			return i
	return -1


func _chip_global_rect(i: int) -> Rect2:
	var r: Rect2 = _rects[i]
	return Rect2(get_global_transform() * r.position, r.size)


func _input(event: InputEvent) -> void:
	if _bs == null or PointerPress.state(event) != PointerPress.PRESS:
		return
	var i: int = chip_at(PointerPress.position_of(event))
	if i < 0 or i >= _cur.size():
		return
	get_viewport().set_input_as_handled()
	var g: Dictionary = _cur[i]
	if _info != null and _info.shown_key() == String(g["uid"]):
		_info.close()
		return
	if _info == null:
		_info = ReserveInfo.create()
		_info.is_on_anchor = func(p: Vector2) -> bool: return chip_at(p) >= 0
		add_child(_info)
	_info.open(String(g["uid"]), _lines(g), g["card"] as CardData, _chip_global_rect(i))


## 열린 설명 판을 칩 구성 변화에 맞춘다 — 그 칩이 사라졌으면 닫고, 남았으면 새 값으로.
func _sync_info() -> void:
	if _info == null or not _info.is_open():
		return
	var key: String = _info.shown_key()
	for i in _cur.size():
		var g: Dictionary = _cur[i]
		if String(g["uid"]) == key:
			_info.open(key, _lines(g), g["card"] as CardData, _chip_global_rect(i))
			return
	_info.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() \
			and _info != null:
		_info.close()
