class_name BanPickView
extends Control

# The ban/pick **screen** — `BanPickController` builds one per `enter` (`create()`) under
# `MatchFlow.canvas` and drives it. This script owns no rules: it binds the scene's nodes for
# the controller, fits the screen to the device (safe area insets, the grid height), and plays
# the turn banner. What to show (picks, bans, tags, sheet text, colours) is the controller's.
#
# **Layout lives in `UI_View_BanPickView.tscn`** — edit it in the editor:
#
#   BanPickView (full rect, OutgameTheme.tres)
#   ├ Background                 BG over the whole viewport (incl. notch / home-indicator bands)
#   ├ %SafeArea                  full rect shrunk to the safe area (offsets from code)
#   │ ├ %EnemyBlock              BanPickTeamBlock, anchored top: ban row · mechs · portraits
#   │ ├ %PlayerBlock             mirrored, anchored bottom, grows upward in the assign step
#   │ ├ %Band                    the space between the blocks (scene offsets)
#   │ │ └ %Pane                  pick pane, height = grid fit (`fit_pane`), centred in the band
#   │ │   ├ PaneCard · Content (%BanPickOrderRow_OrderRow · %Tabs · %Scroll/%Grid)
#   │ │   ├ %SheetDim            dims the pane only (team blocks stay readable)
#   │ │   └ %Sheet               bottom sheet, bottom-aligned to the grid
#   │ ├ %FloatingBarButton_StartButton            assign-step bottom bar ("게임 시작")
#   │ └ %DragGhost              the mech slot under the finger while dragging
#   └ %Banner                    turn banner (viewport-centred, above everything)

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_View_BanPickView.tscn"

## Rows of the grid visible at once. Not an integer on purpose — the half-cut fifth row is
## the only "there's more below" signal.
const GRID_VISIBLE_ROWS: float = 4.5
const GRID_MIN_H: float = 240.0
const BAND_MIN_H: float = 200.0
## Sheet height = grid height − this, clamped to [`SHEET_MIN_H`, `SHEET_MAX_H`].
const SHEET_GRID_INSET: float = 40.0
const SHEET_MIN_H: float = 560.0
const SHEET_MAX_H: float = 700.0

# Turn banner — a side-coloured band sweeping across the centre (same shape as the in-game
# "당신의 차례"): spreads from the centre → holds → fades. Never blocks input.
const BANNER_IN_SEC: float   = 0.22
const BANNER_HOLD_SEC: float = 0.45
const BANNER_OUT_SEC: float  = 0.25
const BANNER_ALPHA: float    = 0.92

var safe_area: Control = null
var enemy_block: BanPickTeamBlock = null
var player_block: BanPickTeamBlock = null
var band: Control = null
var pane: Control = null
var order_row: BanPickOrderRow = null
var tab_buttons: Array = []     # Array[Button], left → right
var scroll: ScrollContainer = null
var grid: BanPickGrid = null

var sheet_dim: ColorRect = null
var sheet: Panel = null
var sheet_art: TextureRect = null
var sheet_art_placeholder: ColorRect = null
var sheet_name: Label = null
var sheet_stats: Label = null
var sheet_no_passive: Label = null
var sheet_passive_icon: Control = null
var sheet_passive_head: Label = null
var sheet_passive_desc: Label = null
var sheet_cards_header: Label = null
var sheet_card_row: HBoxContainer = null
var sheet_no_cards: Label = null
var sheet_rider: Label = null
var sheet_intel: Label = null
var sheet_close: Button = null
var sheet_confirm: Button = null

var start_button: Button = null
var drag_ghost: Panel = null
var drag_ghost_art: TextureRect = null

var _banner_bar: ColorRect = null
var _banner_label: Label = null
var _banner_gen: int = 0
var _banner_tween: Tween = null


## Instantiates the scene. `BanPickView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> BanPickView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BanPickView


func _ready() -> void:
	safe_area = %SafeArea
	enemy_block = %EnemyBlock
	player_block = %PlayerBlock
	band = %Band
	pane = %Pane
	order_row = %BanPickOrderRow_OrderRow
	for c in (%Tabs as Control).get_children():
		if c is Button:
			tab_buttons.append(c)
	scroll = %Scroll
	grid = %Grid
	sheet_dim = %SheetDim
	sheet = %Sheet
	sheet_art = %SheetArt
	sheet_art_placeholder = %SheetArtPlaceholder
	sheet_name = %SheetName
	sheet_stats = %SheetStats
	sheet_no_passive = %SheetNoPassive
	sheet_passive_icon = %SheetPassiveIcon
	sheet_passive_head = %SheetPassiveHead
	sheet_passive_desc = %SheetPassiveDesc
	sheet_cards_header = %SheetCardsHeader
	sheet_card_row = %SheetCardRow
	sheet_no_cards = %SheetNoCards
	sheet_rider = %SheetRider
	sheet_intel = %SheetIntel
	sheet_close = %SheetClose
	sheet_confirm = %SheetConfirm
	start_button = %FloatingBarButton_StartButton
	drag_ghost = %DragGhost
	drag_ghost_art = %DragGhostArt
	_banner_bar = %BannerBar
	_banner_label = %BannerLabel
	# Finger / mouse drag scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(scroll)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Device insets → offsets (`docs/mobile_safe_area.md` pattern B as a scene: the background
## covers the whole viewport, everything else lives in `%SafeArea`). The bottom side is
## `OutgameTheme.fit_bottom_bar`: `%SafeArea` ends at the safe line and the bottom capsule
## (`BarPrimaryButton`) floats 32 px above it.
func fit_safe_area() -> void:
	safe_area.offset_top = ScreenMetrics.top_y()
	OutgameTheme.fit_bottom_bar(start_button, safe_area)


## Grid height for this device: 4.5 rows of `cell_h` (+ the grid's row gap), clamped to what
## the band between the two team blocks leaves. The pane takes exactly that height and sits
## vertically centred in the band; the sheet keeps its bottom on the grid's bottom.
func fit_pane(cell_h: float) -> void:
	var content := pane.get_node("Content") as Control
	var band_h: float = maxf(BAND_MIN_H,
			ScreenMetrics.safe_h() - band.offset_top + band.offset_bottom)
	# Everything in the pane but the grid: padding + order row + tabs + gap.
	var fixed_h: float = content.offset_top - content.offset_bottom \
			+ content.get_combined_minimum_size().y
	var gap: float = grid.v_gap
	var grid_want: float = GRID_VISIBLE_ROWS * (cell_h + gap) - gap
	var grid_h: float = clampf(grid_want, GRID_MIN_H, maxf(GRID_MIN_H, band_h - fixed_h))
	var group_h: float = fixed_h + grid_h
	pane.offset_top = maxf(0.0, (band_h - group_h) * 0.5)
	pane.offset_bottom = pane.offset_top + group_h
	var sheet_h: float = clampf(grid_h - SHEET_GRID_INSET, SHEET_MIN_H, SHEET_MAX_H)
	sheet.offset_top = sheet.offset_bottom - sheet_h


## Sweeps the turn banner (`msg` on a `col` band). A new banner removes the previous one.
func play_banner(msg: String, col: Color) -> void:
	clear_banner()
	_banner_gen += 1
	var gen: int = _banner_gen
	var vp: Vector2 = ScreenMetrics.viewport_size()
	var bh: float = _banner_bar.size.y
	var y: float = vp.y * 0.5 - bh * 0.5
	_banner_bar.color = Color(col.r, col.g, col.b, BANNER_ALPHA)
	_banner_bar.modulate = Color.WHITE
	_banner_bar.position = Vector2(vp.x * 0.5, y)
	_banner_bar.size = Vector2(0.0, bh)
	_banner_bar.visible = true
	_banner_label.text = msg
	_banner_label.modulate = Color(1, 1, 1, 0)
	_banner_label.visible = true

	var tw := create_tween().set_parallel()
	_banner_tween = tw
	tw.tween_property(_banner_bar, "size:x", vp.x, BANNER_IN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_banner_bar, "position:x", 0.0, BANNER_IN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_banner_label, "modulate", Color.WHITE, BANNER_IN_SEC)
	tw.chain().tween_interval(BANNER_HOLD_SEC)
	tw.chain().tween_property(_banner_bar, "modulate", Color(1, 1, 1, 0), BANNER_OUT_SEC)
	tw.parallel().tween_property(_banner_label, "modulate", Color(1, 1, 1, 0), BANNER_OUT_SEC)
	tw.chain().tween_callback(func() -> void:
		if gen == _banner_gen:
			clear_banner(false))


func clear_banner(kill_tween: bool = true) -> void:
	if kill_tween and _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = null
	_banner_bar.visible = false
	_banner_label.visible = false


# ── F6 단독 실행 미리보기 ─────────────────────────────────────────────────────
const _PREVIEW_CONTROLLER_PATH: String = 		"res://features/match_flow/ban_pick/BanPickController.gd"
## 미리보기가 멈추는 수 — 밴 4 · 양 팀 픽 3대씩 끝나고 내 픽 차례(14수 중 11번째).
const _PREVIEW_STOP_AT: int = 10
## 상대 AI 의 뜸 들이기를 빨리 감는 배속(미리보기 동안만).
const _PREVIEW_TIME_SCALE: float = 4.0


## F6 단독 실행 미리보기 — 메모리 런(`UiPreview.ensure_run`)의 실제 메크 · 내 팀 · 다음
## 경기 상대(`UiPreview.ensure_league`) 로스터로 **미리보기 전용 `BanPickController`** 를
## 이 화면에 붙여(`preview_view`) 진짜 밴픽을 돌린다. 내 차례는 격자 칸을 두 번 누르는
## 보통 입력으로 두고(밴 = 남은 칸 끝, 픽 = 아직 없는 역할군), 상대는 원래 AI 가 둔다 —
## 밴 4 · 픽 3:3 이 끝난 내 픽 차례에서 멈추고 칸 하나를 열어 시트를 띄운다. 그 뒤로는
## 손으로 이어서 둘 수 있다(`게임 시작` 은 출력만 — 화면이 걷힌다).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var data: Dictionary = gm.load_match_data()
	if data.has("error"):
		push_error("BanPickView preview: " + String(data["error"]))
		return
	var s: Dictionary = gm.season_state
	var lm: LeagueManager = UiPreview.ensure_league(self, 0)
	var pid: int = int(s["player_team_id"])
	var eid: int = (pid + 1) % 8
	var next_match: Variant = lm.next_unplayed_player_match()
	if next_match != null:
		eid = int(next_match["team_b"]) if int(next_match["team_a"]) == pid 				else int(next_match["team_a"])
	var ctrl_script := load(_PREVIEW_CONTROLLER_PATH) as GDScript
	var ctrl: Node = ctrl_script.new()
	ctrl.name = "PreviewBanPick"
	ctrl.preview_view = self
	add_child(ctrl)
	UiPreview.trace(ctrl.phase_finished, "ban_pick finished")
	var blue: int = GameEnums.DraftSide.BLUE
	ctrl.enter(data["mechs"], blue,
			_preview_copies(OpponentIntel.team_roster(s, pid)),
			_preview_copies(OpponentIntel.team_roster(s, eid)),
			lm.team_name(pid), lm.team_name(eid))
	_preview_autoplay(ctrl_script.get_script_constant_map()["SEQUENCE"],
			_preview_grid_mechs(data["mechs"]), blue)


## 경기용 사본 — 배정(`assigned_mech`)이 메모리 런의 원본 파일럿에 새겨지지 않게.
func _preview_copies(roster: Array) -> Array:
	var out: Array = []
	for raw in roster:
		out.append((raw as PlayerData).duplicate())
	return out


## 격자 칸 순서와 같은 메크 순서(`BanPickController._sorted_for_grid` 와 같은 정렬).
func _preview_grid_mechs(mechs: Array) -> Array:
	var out: Array = mechs.duplicate()
	out.sort_custom(func(a, b):
		var ra: int = GameEnums.role_seat((a as MechData).role)
		var rb: int = GameEnums.role_seat((b as MechData).role)
		if ra != rb:
			return ra < rb
		return (a as MechData).id < (b as MechData).id)
	return out


## 둔 수 = 덮개(BAN / BLUE / RED)가 씌워진 격자 칸 수.
func _preview_taken() -> int:
	var n: int = 0
	for c in grid.get_children():
		if (c as BanPickMechCell).veil.visible:
			n += 1
	return n


func _preview_autoplay(seq: Array, grid_mechs: Array, my_side: int) -> void:
	var my_roles: Array = []
	Engine.time_scale = _PREVIEW_TIME_SCALE
	while is_inside_tree():
		var idx: int = _preview_taken()
		if idx >= _PREVIEW_STOP_AT or idx >= seq.size():
			break
		if int(seq[idx][0]) == my_side:
			var is_ban: bool = int(seq[idx][1]) == 0
			var pick: int = _preview_choose(grid_mechs, my_roles, is_ban)
			if pick < 0:
				break
			if not is_ban:
				my_roles.append((grid_mechs[pick] as MechData).role)
			var cell := grid.get_child(pick) as BanPickMechCell
			cell.pressed.emit()
			cell.pressed.emit()
		await get_tree().create_timer(0.1).timeout
	Engine.time_scale = 1.0
	if not is_inside_tree():
		return
	# 멈춘 자리 — 아직 없는 역할군의 남은 칸 하나를 열어 시트(픽 확정)를 띄워 둔다.
	var open_idx: int = _preview_choose(grid_mechs, my_roles, false)
	if open_idx >= 0:
		(grid.get_child(open_idx) as BanPickMechCell).pressed.emit()


## 내 수로 누를 격자 칸 번호(-1 = 없음). 밴은 남은 칸의 끝에서, 픽은 앞에서부터 아직
## 내 팀에 없는 역할군을 고른다.
func _preview_choose(grid_mechs: Array, my_roles: Array, is_ban: bool) -> int:
	var order: Array = range(grid_mechs.size())
	if is_ban:
		order.reverse()
	var fallback: int = -1
	for i in order:
		if (grid.get_child(i) as BanPickMechCell).veil.visible:
			continue
		if is_ban or not (grid_mechs[i] as MechData).role in my_roles:
			return i
		if fallback < 0:
			fallback = i
	return fallback
