class_name EventResultPanel
extends VBoxContainer

# Event result body: what an answer / visit did, one block per pilot.
#
#                 ( portrait )                         ← %TopPortrait: the main pilot, centred on
#   -------------(            )------------              the hosting card's top edge (half out)
#   스트레스      [██████████░░░░░░]  7 (-5) / 100     ← row: name · EventResultBar · now (change) / max
#   신뢰도 Lv.3   [██████░░░░░░░░░░]   64% (+16%)      ← rows without a max: now (change)
#   (공격 명중 +1) (능력치 EXP +40)                     ← chips: compact stat gains
#   ( 외출 2회째 · … )                                  ← lines: other notes (MessengerNoteChip)
#
# No names anywhere. The main block (`main` in the block data = the result's own pilot) has no
# left portrait: its portrait sits on top of the card instead. Other pilots' blocks keep a small
# left portrait; the team block (notes without a pilot) has none.
#
# Rows: stress (bar = `STRESS_THRESHOLD`, overflow up to `STRESS_MAX` drawn red), trust (level +
# progress in the level) and 깨달음 레벨 EXP (EXP in the level / the bar, over level-ups; locked =
# "한계돌파 필요"). The data comes from `MentalEvents.result_blocks` (merged notes: several
# stress sources of one result are one row with the sum).
#
# **Hosting**: the panel must be the first thing inside its card (the nearest `PanelContainer`
# ancestor, e.g. a `PopupCard`); `%TopPortrait` reserves the room under the portrait's lower
# half itself, and the card must not clip (PanelContainer default).
#
# **Layout lives in `UI_Comp_EventResultPanel.tscn`**: blocks, rows and chips are duplicates of
# the hidden templates `%BlockTemplate` / `%RowTemplate` / `%ChipTemplate`. Create with
# `EventResultPanel.create()`. Self-contained: any result screen can host it.

const SCENE_PATH: String = "res://features/season/mental/UI_Comp_EventResultPanel.tscn"
## Gap between the top portrait's lower edge and the first row.
const TOP_PORTRAIT_GAP: float = 16.0

var _top_pid: int = -1

@onready var _top: Control = %TopPortrait
@onready var _disc: Control = %TopPortrait.get_node("Disc")
@onready var _blocks: VBoxContainer = %Blocks
@onready var _block_tpl: Control = %BlockTemplate
@onready var _row_tpl: Control = %RowTemplate
@onready var _chip_tpl: Control = %ChipTemplate


static func create() -> EventResultPanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as EventResultPanel


func _ready() -> void:
	_block_tpl.visible = false
	_row_tpl.visible = false
	_chip_tpl.visible = false
	_top.visible = false
	# The host's layout moves the panel inside its card → re-place the portrait.
	item_rect_changed.connect(_place_top_portrait)
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── API ──────────────────────────────────────────────────────────────────────
## Fill from note dicts **right after** their effects were applied (the bars read the values
## now: previous = now − delta). `pid` = the result's pilot (its block comes first, an `outing`
## note joins it; its portrait goes on top). `animate` = the bars run before → after once the
## panel is in the tree.
func show_result(state: Dictionary, pid: int, notes: Array, animate: bool = true) -> void:
	show_blocks(MentalEvents.result_blocks(state, notes, pid), animate)


## Fill from precomputed blocks (`MentalEvents.result_blocks`, also `outcome_view.result_blocks`).
## The first block marked `main` puts its pilot's portrait on top of the card.
func show_blocks(blocks: Array, animate: bool = true) -> void:
	clear()
	for b in blocks:
		var bd: Dictionary = b
		if _top_pid < 0 and bool(bd.get("main", false)) and int(bd.get("pid", -1)) >= 0:
			_set_top_portrait(int(bd["pid"]))
		_add_block(bd, animate)


## Text-only notes (an outcome view without blocks, e.g. the limit-break goal) → one
## `MessengerNoteChip` line each, no portrait.
func show_texts(texts: Array) -> void:
	clear()
	if texts.is_empty():
		return
	_add_block({"pid": -2, "name": "", "rows": [], "chips": [], "lines": texts}, false)


func clear() -> void:
	for c in _blocks.get_children():
		_blocks.remove_child(c)
		c.queue_free()
	_set_top_portrait(-1)


## The pilot whose portrait sits on top of the card (-1 = none shown).
func top_pilot_id() -> int:
	return _top_pid


# ── Top portrait ─────────────────────────────────────────────────────────────
func _set_top_portrait(pid: int) -> void:
	_top_pid = pid
	for c in _disc.get_children():
		_disc.remove_child(c)
		c.queue_free()
	_top.visible = pid >= 0
	if pid < 0:
		return
	OutgameTheme.add_round_portrait(_disc, PilotImages.circle_for(pid), Vector2.ZERO,
			_disc.custom_minimum_size.x, OutgameTheme.SURFACE)
	_place_top_portrait()
	# Positions are only final once the host has laid the card out.
	_place_top_portrait.call_deferred()


## Centres the disc on the hosting card's top edge (the nearest `PanelContainer` ancestor) and
## sizes `%TopPortrait` to the room the disc's lower half still needs below the card's padding.
func _place_top_portrait() -> void:
	if not _top.visible:
		return
	var d: float = _disc.custom_minimum_size.x
	# Distance from the card's top edge down to this panel (sum of the local offsets).
	var down: float = 0.0
	var n: Node = self
	while n is Control and not (n is PanelContainer):
		down += (n as Control).position.y
		n = n.get_parent()
	if not (n is PanelContainer):
		# No card (e.g. the panel run alone): the whole disc sits inside the panel's top.
		down = -d * 0.5
	var room: float = maxf(0.0, d * 0.5 + TOP_PORTRAIT_GAP - down)
	if not is_equal_approx(_top.custom_minimum_size.y, room):
		_top.custom_minimum_size.y = room
	_disc.offset_top = -down - d * 0.5
	_disc.offset_bottom = _disc.offset_top + d


func is_empty() -> bool:
	return _blocks.get_child_count() == 0


# ── Blocks ───────────────────────────────────────────────────────────────────
func _add_block(b: Dictionary, animate: bool) -> void:
	var block: Control = _block_tpl.duplicate() as Control
	block.visible = true
	_blocks.add_child(block)
	var pid: int = int(b.get("pid", -1))
	# The main pilot's portrait is the top one; the team block has none. No names.
	var portrait: Control = block.get_node("Portrait")
	portrait.visible = pid >= 0 and pid != _top_pid
	if portrait.visible:
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(pid), Vector2.ZERO,
				portrait.custom_minimum_size.x)
	var rows: Control = block.get_node("Body/Rows")
	for r in (b.get("rows", []) as Array):
		rows.add_child(_row(r as Dictionary, animate))
	rows.visible = rows.get_child_count() > 0
	var chips: Control = block.get_node("Body/Chips")
	for t in (b.get("chips", []) as Array):
		var chip: Control = _chip_tpl.duplicate() as Control
		chip.visible = true
		(chip.get_node("Text") as Label).text = String(t)
		chips.add_child(chip)
	chips.visible = chips.get_child_count() > 0
	var lines: Control = block.get_node("Body/Lines")
	for t in (b.get("lines", []) as Array):
		var line := MessengerNoteChip.create()
		line.setup(String(t), true)
		lines.add_child(line)
	lines.visible = lines.get_child_count() > 0


## One line: name · bar · `now (delta) / max` (counted rows) or `now (delta)`.
func _row(r: Dictionary, animate: bool) -> Control:
	var row: Control = _row_tpl.duplicate() as Control
	row.visible = true
	(row.get_node("Label") as Label).text = String(r.get("label", ""))
	var look: StringName = &"NegativeLabel" if bool(r.get("over", false)) else &"BodyLabel"
	var now: Label = row.get_node("Value/Now")
	now.text = String(r.get("value", ""))
	now.theme_type_variation = look
	var cap: Label = row.get_node("Value/Max")
	var cap_text: String = String(r.get("max", ""))
	cap.text = "/ " + cap_text
	cap.visible = not cap_text.is_empty()
	cap.theme_type_variation = look
	var delta: Label = row.get_node("Value/Delta")
	var delta_text: String = String(r.get("delta", ""))
	delta.text = "(%s)" % delta_text
	delta.visible = not delta_text.is_empty()
	# 0 (sources that cancelled out, `±0`) reads grey: neither welcome nor not.
	if bool(r.get("neutral", false)):
		delta.theme_type_variation = &"CaptionLabel"
	else:
		delta.theme_type_variation = &"PositiveLabel" if bool(r.get("good", true)) else &"NegativeLabel"
	var bar: EventResultBar = row.get_node("Bar")
	# The bar needs its size: start it once the row is laid out.
	bar.play.call_deferred(r, animate)
	return row


## F6 단독 실행 미리보기 — 메모리 런의 내 첫 두 선수에게 실제 효과를 넣고(스트레스 두 출처 · 신뢰 ·
## 깨달음 레벨 EXP · 능력치 EXP) 그 노트로 판을 채운다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(s)
	if ids.size() < 2:
		return
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	StressSystem.add(s, a, 80)
	StressSystem.add(s, b, 130)
	var notes: Array = []
	notes.append(MentalEvents.stress_note(s, a, StressSystem.add(s, a, -6)))
	notes.append(MentalEvents.stress_note(s, a, StressSystem.add(s, a, -10)))
	var d: int = MentalSystem.add_trust(s, a, 30)
	notes.append({"type": "trust", "pid": a, "delta": d, "after": MentalSystem.trust(s, a)})
	notes.append(FocusTraining.add_training_exp(s, a, 450, "preview"))
	notes.append_array(FocusTraining.add_stat_exp(s, a, {"field_hit": 260, "engage_hit": 260}))
	notes.append(MentalEvents.stress_note(s, b, StressSystem.add(s, b, 12)))
	notes.append({"type": "trust_all", "delta": 3})
	notes.append({"type": "outing", "count": 2})
	show_result(s, a, notes)
