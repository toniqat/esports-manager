class_name BanPickOrderRow
extends Control

# The **order row** — the 14 moves of the draft as one strip at the top of the pick pane, right
# above the role-class filter (`ban_pick/README.md` "Order row"). **Layout lives in
# `BanPickOrderRow.tscn`** (the strip, `%Pips` holder, the ✕/✓ icon `%PipIcon`, the turn triangle
# `%TurnArrow`), instanced as `%OrderRow` in `BanPickView.tscn`. Each move is one
# `BanPickOrderPip.tscn` instance in `%Pips` (count = the sequence); the cells' placement, tween,
# pulse and side colours stay code — an animated widget.
#
# - Cell colour = that move's side colour; darker = more current (`seq_color`).
# - Consecutive same-side same-action moves join into one capsule (`same_run` / `seq_run`):
#   no gap inside, only outer corners rounded, a background-coloured joint (the pip's `Joint`
#   child, full height so it follows the tween) at each joint.
# - The current move's capsule thickens (tween); the current cell pulses and holds the icon;
#   the triangle sits below (my turn, bobbing down) or above (opponent's, bobbing up).
#
# Horizontal placement is recomputed on resize (the row is sized by its container after the
# first layout pass); vertical placement only needs the row height (`custom_minimum_size.y`).

const PIP_W: float        = 58.0
const PIP_GAP: float      = 6.0
## Thickness of past / upcoming cells and of the **current** capsule.
const PIP_H: float        = 12.0
const PIP_ACTIVE_H: float = 26.0
const PIP_ICON: float     = 20.0
const PIP_GROW_SEC: float = 0.16
const PIP_PULSE_SEC: float   = 0.9
const PIP_PULSE_DEPTH: float = 0.38
const TURN_ARROW_GAP: float = 3.0
const TURN_ARROW_BOB_PX: float  = 5.0
const TURN_ARROW_BOB_SEC: float = 1.3
const ICON_BAN   := preload("res://resources/images/ui/banpick/ban_x.svg")
const ICON_PICK  := preload("res://resources/images/ui/banpick/pick_v.svg")
const SCENE_PATH: String = "res://features/match_flow/ban_pick/BanPickOrderRow.tscn"
const PIP_SCENE: PackedScene = preload("res://features/match_flow/ban_pick/BanPickOrderPip.tscn")
const PIP_VARIATION: StringName = &"BanPickOrderPip"

var _seq: Array = []            # [[side, kind], …] — BanPickController.SEQUENCE
var _side_colors: Dictionary = {}
var _pips: Array = []           # Array[Panel] (BanPickOrderPip instances in %Pips)
var _action_idx: int = 0
var _pulse_t: float = 0.0
var _arrow_base_y: float = 0.0
var _arrow_dir: float = 1.0      # +1 = bobs down (my turn), -1 = up (opponent's)
var _arrow_t: float = 0.0
var _tween: Tween = null
var _icon: TextureRect = null
var _arrow: TextureRect = null


## Two moves are the same side's same action — the capsule rule (also read by the turn banner).
static func same_run(seq: Array, a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= seq.size() or b >= seq.size():
		return false
	return int(seq[a][0]) == int(seq[b][0]) and int(seq[a][1]) == int(seq[b][1])


## First · last move (x..y) of the capsule `idx` belongs to. A lone move: x == y == idx.
static func seq_run(seq: Array, idx: int) -> Vector2i:
	var a: int = idx
	while same_run(seq, a - 1, a):
		a -= 1
	var b: int = idx
	while same_run(seq, b, b + 1):
		b += 1
	return Vector2i(a, b)


## Instantiates the scene (`BanPickView.tscn` already holds one as `%OrderRow`).
static func create() -> BanPickOrderRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BanPickOrderRow


func _ready() -> void:
	_icon = %PipIcon
	_arrow = %TurnArrow
	resized.connect(_layout_x)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Builds the cells for `seq` (`side_colors`: side → Color).
func build(seq: Array, side_colors: Dictionary) -> void:
	_seq = seq
	_side_colors = side_colors
	var holder: Node = %Pips
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	_pips.clear()
	var mid_y: float = _mid_y()
	var n: int = seq.size()
	for i in range(n):
		var sty := OutgameTheme.variation_box(PIP_VARIATION)
		# Only the capsule's outer corners are round — rounded inner corners would notch
		# the joint and split it back into two.
		var joined_left: bool = i > 0 and same_run(seq, i - 1, i)
		if joined_left:
			sty.corner_radius_top_left = 0
			sty.corner_radius_bottom_left = 0
		if i < n - 1 and same_run(seq, i, i + 1):
			sty.corner_radius_top_right = 0
			sty.corner_radius_bottom_right = 0
		var pip := PIP_SCENE.instantiate() as Panel
		pip.add_theme_stylebox_override(&"panel", sty)
		pip.position = Vector2(0.0, mid_y - PIP_H * 0.5)
		pip.size = Vector2(PIP_W, PIP_H)
		var joint := pip.get_node("Joint") as ColorRect
		joint.color = OutgameTheme.SURFACE
		joint.visible = joined_left
		holder.add_child(pip)
		_pips.append(pip)
	_layout_x()


## Matches the row to move `action_idx` (`mine` = the player's move, `is_ban` = its kind).
## The current capsule grows with a tween; the others snap thin.
func refresh(action_idx: int, mine: bool, is_ban: bool) -> void:
	_action_idx = action_idx
	var mid_y: float = _mid_y()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var run: Vector2i = seq_run(_seq, action_idx) if action_idx < _pips.size() \
			else Vector2i(-1, -2)
	_tween = create_tween().set_parallel()
	for i in range(_pips.size()):
		var pip := _pips[i] as Panel
		var sty := pip.get_theme_stylebox("panel") as StyleBoxFlat
		var in_run: bool = i >= run.x and i <= run.y
		var state: int = 1 if i < action_idx else (2 if i == action_idx else 0)
		if state == 0 and in_run:
			state = 3
		sty.bg_color = seq_color(i, state)
		pip.self_modulate = Color.WHITE
		if not in_run:
			pip.size = Vector2(PIP_W, PIP_H)
			pip.position.y = mid_y - PIP_H * 0.5
		elif not is_equal_approx(pip.size.y, PIP_ACTIVE_H):
			_tween.tween_property(pip, "size", Vector2(PIP_W, PIP_ACTIVE_H), PIP_GROW_SEC) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			_tween.tween_property(pip, "position:y", mid_y - PIP_ACTIVE_H * 0.5, PIP_GROW_SEC) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if action_idx >= _pips.size() or _icon == null or _arrow == null:
		# An empty tween errors when it starts — after the last move nothing is tweened.
		_tween.kill()
		if _icon != null:
			_icon.visible = false
		if _arrow != null:
			_arrow.visible = false
		return

	_pulse_t = 0.0
	_icon.texture = ICON_BAN if is_ban else ICON_PICK
	_icon.size = Vector2(PIP_ICON, PIP_ICON)
	_icon.position.y = mid_y - PIP_ICON * 0.5
	_icon.visible = true
	_icon.modulate = Color(1, 1, 1, 0)
	_tween.tween_property(_icon, "modulate", Color.WHITE, PIP_GROW_SEC)

	# My turn = below the cell pointing down (our block), opponent's = above pointing up.
	_arrow_dir = 1.0 if mine else -1.0
	_arrow.flip_v = not mine
	_arrow.modulate = seq_color(action_idx, 2)
	var ah: float = _arrow.size.y
	_arrow_base_y = (mid_y + PIP_ACTIVE_H * 0.5 + TURN_ARROW_GAP) if mine \
			else (mid_y - PIP_ACTIVE_H * 0.5 - TURN_ARROW_GAP - ah)
	_arrow.position.y = _arrow_base_y
	_arrow.visible = true
	_arrow_t = 0.0
	_layout_x()


## Stops the row (assign step): kills the tween, hides icon and triangle.
func stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _icon != null:
		_icon.visible = false
	if _arrow != null:
		_arrow.visible = false


func seq_color(idx: int, state: int) -> Color:
	# state: 0 = upcoming, 1 = done, 2 = current, 3 = next move inside the current capsule
	var base: Color = _side_colors.get(int(_seq[idx][0]), Color.WHITE)
	# On white paper **darker = more current** — past moves half, upcoming nearly background.
	if state == 1: return base.lerp(OutgameTheme.SURFACE, 0.45)
	if state == 2: return base
	if state == 3: return base.lerp(OutgameTheme.SURFACE, 0.60)
	return base.lerp(OutgameTheme.SURFACE, 0.80)


func _mid_y() -> float:
	return maxf(size.y, custom_minimum_size.y) * 0.5


## Horizontal placement: the strip centred in the row; gaps only between capsules.
func _layout_x() -> void:
	var n: int = _pips.size()
	if n == 0:
		return
	var total: float = float(n) * PIP_W
	for i in range(n - 1):
		if not same_run(_seq, i, i + 1):
			total += PIP_GAP
	var x: float = (size.x - total) * 0.5
	for i in range(n):
		(_pips[i] as Panel).position.x = x
		x += PIP_W + (0.0 if same_run(_seq, i, i + 1) else PIP_GAP)
	if _action_idx < n:
		var cx: float = (_pips[_action_idx] as Panel).position.x + PIP_W * 0.5
		if _icon != null:
			_icon.position.x = cx - PIP_ICON * 0.5
		if _arrow != null:
			_arrow.position.x = cx - _arrow.size.x * 0.5


## The triangle bobs toward what it points at — (1 − cos) / 2, slow at both ends and starting
## from its base spot, so it doesn't jump when the move changes. The current cell pulses.
func _process(delta: float) -> void:
	if _arrow == null or not _arrow.visible:
		return
	if _action_idx < _pips.size():
		_pulse_t = fmod(_pulse_t + delta, PIP_PULSE_SEC)
		var p: float = (1.0 - cos(TAU * _pulse_t / PIP_PULSE_SEC)) * 0.5
		# self_modulate: the cell's own `Joint` line must not pulse with it.
		(_pips[_action_idx] as Panel).self_modulate = Color(1, 1, 1, 1.0 - PIP_PULSE_DEPTH * p)
	_arrow_t = fmod(_arrow_t + delta, TURN_ARROW_BOB_SEC)
	var k: float = (1.0 - cos(TAU * _arrow_t / TURN_ARROW_BOB_SEC)) * 0.5
	_arrow.position.y = _arrow_base_y + _arrow_dir * TURN_ARROW_BOB_PX * k


## F6 단독 실행 미리보기 — 실제 밴픽 순서(`BanPickController.SEQUENCE`, 진영 색)로 칸을 세우고
## 네 번째 수(상대 픽, 두 칸 캡슐)를 지금 차례로 보여 준다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var consts: Dictionary = (load("res://features/match_flow/ban_pick/BanPickController.gd") \
			as GDScript).get_script_constant_map()
	build(consts["SEQUENCE"], {GameEnums.DraftSide.BLUE: consts["BLUE_COLOR"],
			GameEnums.DraftSide.RED: consts["RED_COLOR"]})
	refresh(3, false, false)
