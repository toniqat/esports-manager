class_name ManagerPopup
extends Control

# Lobby 감독 modal — opened by the lobby's top-left level disc (`LobbyScreen.open_manager`).
# A sheet drops from the top edge (rounded bottom) holding one `ManagerTab`; the floating close
# capsule sits bottom-right under it. This popup is the tab's **host**: toasts, confirms and
# currency / badge refreshes are forwarded to the lobby. Every edit in the tab saves at once —
# there is no action bar.
#
# - Layout lives in `UI_View_ManagerPopup.tscn`; build with `create()`, not `.new()`.
# - A plain Control child of the lobby (added after the bottom bars), so the lobby `%Toast`
#   (z 5) floats over it and the CanvasLayer popups (`ConfirmPopup`, prestige
#   `ManagerTypePopup`, trait swap) stay above it.

signal closed

const SCENE_PATH: String = "res://features/meta/manager/UI_View_ManagerPopup.tscn"

var _lobby = null                 # LobbyScreen (untyped: duck-typed services; null in the F6 preview)
var _sheet_rest: float = 0.0      # %Sheet resting offset_top (= −notch)
var _tab: ManagerTab = null
var _anim: Tween


## Layout lives in `UI_View_ManagerPopup.tscn` — build with this, not `.new()`.
static func create() -> ManagerPopup:
	var p: ManagerPopup = (load(SCENE_PATH) as PackedScene).instantiate()
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(close)
	%FloatingCloseButton_Close.pressed.connect(close)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `lobby` = the `LobbyScreen` (services are forwarded to it); null = preview, no forwarding.
func open(lobby: Node) -> void:
	_lobby = lobby
	_fit_safe_area()
	if _tab == null:
		_tab = ManagerTab.create()
		%Body.add_child(_tab)
		_tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tab.setup(self)
	visible = true
	_tab.on_shown()
	_anim = UiHelpers.slide_top_sheet(self, _anim, self, %Sheet, _sheet_rest, true)


func close() -> void:
	if not visible:
		return
	_anim = UiHelpers.slide_top_sheet(self, _anim, self, %Sheet, _sheet_rest, false,
			func() -> void: visible = false)
	closed.emit()


func is_open() -> bool:
	return visible


## The lobby root already sits below the notch: dim + sheet reach up over the notch band, the
## sheet's content starts below it, and the sheet stops 16 px above the close capsule.
func _fit_safe_area() -> void:
	ScreenMetrics.extend_background(%DimRect)
	ScreenMetrics.extend_background(%Dim)
	var sheet: Control = %Sheet
	ScreenMetrics.extend_background(sheet)
	(%Content as Control).offset_top = ScreenMetrics.top_y()
	sheet.offset_bottom = UiHelpers.place_floating_close(%FloatingCloseButton_Close) - 16.0
	_sheet_rest = sheet.offset_top


# ── Host services for ManagerTab (contract: LobbyScreen.gd header) ───────────
func show_toast(msg: String, is_error: bool = false) -> void:
	if _lobby != null:
		_lobby.show_toast(msg, is_error)
	else:
		print("[ManagerPopup] toast: %s%s" % [msg, " (error)" if is_error else ""])


func refresh_currency() -> void:
	if _lobby != null:
		_lobby.refresh_currency()


func refresh_badges() -> void:
	if _lobby != null:
		_lobby.refresh_badges()


func set_tab_badge(id: String, on: bool) -> void:
	if _lobby != null:
		_lobby.set_tab_badge(id, on)


func open_confirm(title: String, body: String, cancel_text: String, confirm_text: String,
		danger: bool, on_confirm: Callable) -> void:
	if _lobby != null:
		_lobby.open_confirm(title, body, cancel_text, confirm_text, danger, on_confirm)


## F6 단독 실행 미리보기 — 로비 없이 시트를 연다(실제 프로필). 토스트는 출력만, 확인 팝업은
## 뜨지 않는다. 프리셋 · 스탯 · 특성 교체는 곧바로 저장하므로 미리보기에서는 누르지 말 것.
func _fill_preview() -> void:
	UiPreview.stage(self)
	open(null)
