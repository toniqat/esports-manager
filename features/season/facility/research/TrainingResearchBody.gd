class_name TrainingResearchBody
extends Control

# Training facility body (`TrainingResearch.make_body` → `FacilityView` %BodySlot, full rect;
# README "Body contract" + "TrainingResearch"). The facility's research rows as cards
# (`TrainingResearchCard`) in a 3-column grid that scrolls inside the body (≈ 4.5 rows on a
# 1080×1920 screen, more on long phones):
# - rows in CSV order; hidden when the handler says the row gives nothing any more (line
#   owned higher, a finished non-repeatable basic row) unless it is the active one;
#   below `min_level` → faded with `Lv n 필요`;
# - tap a card = `ResearchSystem.select` (HUB only) → `changed` (header refresh) + refill;
# - tap a thumbnail = the course info popover (`TrainingCoursePopover`, any tap closes it);
# - bottom bar action `보유 중인 훈련 코스` → `TrainingResearchOwned` modal.
# Layout is the scene; this script binds `%` nodes, fills data and places the popover.

signal changed
signal message(text: String)

const SCENE_PATH: String = "res://features/season/facility/research/UI_View_TrainingResearchBody.tscn"
## Gap between the tapped thumbnail and the popover, and the popover's margin to the body edge.
const POP_GAP: float = 8.0
const POP_EDGE: float = 4.0

var _state: Dictionary = {}
var _fid: String = ""
var _built: bool = false


static func create() -> TrainingResearchBody:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingResearchBody


func _ready() -> void:
	_bind()
	if not _fid.is_empty():
		_apply()
	if UiPreview.is_standalone(self):
		_fill_preview()


func _bind() -> void:
	if _built:
		return
	_built = true
	var grid: GridContainer = %Grid
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	DragScroll.attach(%Scroll)
	(%InfoCatcher as Control).gui_input.connect(_on_info_input)
	(%TrainingCoursePopover_Info as Control).gui_input.connect(_on_info_input)


## Shows `fid` (a training facility) for the run `state`. Callable before the node enters
## the tree (`make_body` builds the body first) — applied on `_ready` then.
func fill(state: Dictionary, fid: String) -> void:
	_state = state
	_fid = fid
	if is_node_ready():
		_apply()


## Body contract: the header changed (seat, upgrade) — refill in place.
func refresh() -> void:
	if is_node_ready() and not _fid.is_empty():
		_apply()


## Body contract: label of the bottom bar's left slot.
func bottom_action_text() -> String:
	return Loc.t(L.RESEARCH_TRAINING_OWNED_TITLE)


## Body contract: the bottom bar's left slot was pressed → owned courses modal.
func on_bottom_action() -> void:
	_close_info()
	TrainingResearchOwned.open(self, _state)


# ── Fill ─────────────────────────────────────────────────────────────────────
func _apply() -> void:
	_close_info()
	var infos: Array = _card_infos()
	var grid: GridContainer = %Grid
	while grid.get_child_count() < infos.size():
		var card := TrainingResearchCard.create()
		grid.add_child(card)
		card.pressed.connect(_on_card_pressed)
		card.thumb_pressed.connect(_show_info)
	for i in grid.get_child_count():
		var card: TrainingResearchCard = grid.get_child(i)
		card.visible = i < infos.size()
		if card.visible:
			card.fill(infos[i])


# Card data of every shown row, CSV order (see `TrainingResearchCard.fill`).
func _card_infos() -> Array:
	var state: Dictionary = _state
	var fid: String = _fid
	var out: Array = []
	var act: Dictionary = ResearchSystem.active(state, fid)
	var active_rid: String = String(act.get("rid", ""))
	var lvl: int = FacilitySystem.level(state, fid)
	var selectable: bool = ResearchSystem.can_select(state)
	for raw in ResearchSystem.rows_for(fid):
		var r: Dictionary = raw
		if String(r.get("kind", "")) != "training":
			continue
		var rid: String = String(r["id"])
		var tile_id: String = String(r.get("p1", ""))
		var t: TrainingTile = _tile(tile_id)
		if t == null:
			continue
		var is_active: bool = rid == active_rid
		var spent: bool = TrainingResearch.row_available(state, r) != "" \
				or (not bool(r.get("repeatable", false)) and ResearchSystem.done_count(state, rid, "") > 0)
		if spent and not is_active:
			continue
		var weeks: int = maxi(1, int(r.get("weeks", 1)))
		var need: int = int(r.get("min_level", 1))
		var locked: bool = lvl < need
		var status: String = Loc.t(L.RESEARCH_TRAINING_CARD_WEEKS, {"weeks": weeks})
		var variation: String = "CaptionLabel"
		if locked:
			status = Loc.t(L.RESEARCH_TRAINING_CARD_NEED_LEVEL, {"level": need})
			variation = "FaintLabel"
		elif is_active and ResearchSystem.block_reason(state, fid, r) != "":
			status = Loc.t(L.RESEARCH_TRAINING_CARD_PAUSED)
			variation = "NegativeLabel"
		elif is_active:
			var left: int = ResearchSystem.weeks_left(state, fid, rid, "")
			status = Loc.t(L.RESEARCH_TRAINING_CARD_ACTIVE) if left < 0 \
					else Loc.t(L.RESEARCH_TRAINING_CARD_WEEKS_LEFT, {"weeks": maxi(1, left)})
			variation = "AccentLabel"
		out.append({
			"rid": rid, "tile": t, "cap": cap_of(state, tile_id),
			"status": status, "status_variation": variation, "weeks": weeks,
			"progress": ResearchSystem.progress(state, fid, rid, ""),
			"active": is_active, "locked": locked, "selectable": selectable,
		})
	return out


## Owned copies of exactly `tile_id`, as the course card's cap: `×n`, `∞` (basic line) or 미보유.
static func cap_of(state: Dictionary, tile_id: String) -> String:
	var n: int = TrainingCourses.owned_count(state, tile_id)
	if n == TrainingCourses.UNLIMITED:
		return "∞"
	if n <= 0:
		return Loc.t(L.UI_WORD_UNOWNED)
	return "×%d" % n


static func _tile(tile_id: String) -> TrainingTile:
	var def: Dictionary = (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameManager") \
			.training_tile_def(tile_id)
	return null if def.is_empty() else TrainingTile.from_def(def)


# ── Handlers ─────────────────────────────────────────────────────────────────
func _on_card_pressed(rid: String) -> void:
	_close_info()
	var why: String = ResearchSystem.select(_state, _fid, rid, "")
	if why != "":
		message.emit(why)
		return
	_apply()
	changed.emit()


# ── Course info popover ──────────────────────────────────────────────────────
func _show_info(card: TrainingResearchCard) -> void:
	if card.tile == null:
		return
	var pop: TrainingCoursePopover = %TrainingCoursePopover_Info
	pop.fill(card.tile, card.cap_text)
	var thumb: Control = card.get_node("%TrainingCourseCard_Thumb")
	place_popover(pop, thumb.get_global_rect(), get_global_rect())
	pop.visible = true
	(%InfoCatcher as Control).visible = true


func _close_info() -> void:
	if not _built:
		return
	(%TrainingCoursePopover_Info as Control).visible = false
	(%InfoCatcher as Control).visible = false


func _on_info_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_close_info()
		accept_event()


## Places `pop` (a child of the control whose global rect is `bounds`) next to the target
## rect `at` (global): below it when it fits, else above, else clamped; centred on it
## horizontally, kept inside `bounds`. Shared with `TrainingResearchOwned`.
static func place_popover(pop: Control, at: Rect2, bounds: Rect2) -> void:
	var w: float = pop.size.x
	var h: float = pop.size.y
	var x: float = at.position.x + (at.size.x - w) * 0.5
	x = clampf(x, bounds.position.x + POP_EDGE, bounds.end.x - w - POP_EDGE)
	var y: float = at.end.y + POP_GAP
	if y + h > bounds.end.y - POP_EDGE:
		y = at.position.y - h - POP_GAP
	y = clampf(y, bounds.position.y + POP_EDGE, maxf(bounds.position.y + POP_EDGE, bounds.end.y - h - POP_EDGE))
	pop.global_position = Vector2(x, y)


# ── F6 preview ───────────────────────────────────────────────────────────────
## In-memory run, `train_field` at Lv2: two courses owned, 사격 훈련 II active with points.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	TrainingCourses.grant(state, "T03", 1)
	TrainingCourses.grant(state, "T04", 2)
	FacilitySystem.set_level(state, FacilitySystem.FRONT, 2)
	FacilitySystem.set_level(state, "train_field", 2)
	state["week_day"] = -1
	ResearchSystem.select(state, "train_field", "tr_h2", "")
	var res: Dictionary = state["research"]
	(res["points"] as Dictionary)[ResearchSystem.key_of("tr_h2", "")] = \
			int(ResearchSystem.cost(ResearchSystem.row("tr_h2")) * 0.45)
	UiPreview.trace(changed, "changed")
	UiPreview.trace(message, "message")
	fill(state, "train_field")
