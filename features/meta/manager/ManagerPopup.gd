class_name ManagerPopup
extends Control

# Lobby 감독 modal — opened by the lobby's top-left level disc (`LobbyScreen.open_manager`).
# The old 감독 tab (`ManagerTab`) lives unchanged inside the sheet: this popup is its **host**
# (same duck-typed contract as `LobbyScreen` — header of `LobbyScreen.gd`) with its own
# two-button action bar (`%Use` / `%Save`); toasts, confirms and currency / badge refreshes
# are forwarded to the lobby.
#
# - Layout lives in `UI_View_ManagerPopup.tscn`; build with `create()`, not `.new()`.
# - A plain Control child of the lobby (added after the bottom bars), so the lobby `%Toast`
#   (z 5) floats over it and the CanvasLayer popups (`ConfirmPopup`, prestige
#   `ManagerTypePopup`) stay above it.
# - Unsaved draft edits survive closing (the tab keeps its draft, as when it was a tab).

signal closed

const SCENE_PATH: String = "res://features/meta/manager/UI_View_ManagerPopup.tscn"
const SLIDE_SEC: float = 0.24

var _lobby = null                 # LobbyScreen (untyped: duck-typed services; null in the F6 preview)
var _sheet_top: float = 0.0       # %Sheet resting y (scene offset_top)
var _tab: ManagerTab = null
var _anim: Tween


## Layout lives in `UI_View_ManagerPopup.tscn` — build with this, not `.new()`.
static func create() -> ManagerPopup:
	var p: ManagerPopup = (load(SCENE_PATH) as PackedScene).instantiate()
	p.visible = false
	return p


func _ready() -> void:
	_sheet_top = (%Sheet as Control).offset_top
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	%Use.pressed.connect(_on_bar_pressed.bind(0))
	%Save.pressed.connect(_on_bar_pressed.bind(1))
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
	rebuild_bar()
	_tab.on_shown()
	_slide(true)


func close() -> void:
	if not visible:
		return
	_slide(false)
	closed.emit()


func is_open() -> bool:
	return visible


## Dim under the notch, bar above the gesture zone (the sheet itself runs to the screen bottom).
func _fit_safe_area() -> void:
	ScreenMetrics.extend_background(%DimRect)
	ScreenMetrics.extend_background(%Dim)
	var below: float = OutgameTheme.bottom_inset()
	var bar: Control = %Bar
	bar.offset_top = -136.0 - below
	bar.offset_bottom = -24.0 - below
	(%Body as Control).offset_bottom = bar.offset_top - 16.0


func _slide(show_it: bool) -> void:
	if _anim != null:
		_anim.kill()
	var sheet: Control = %Sheet
	var off: float = get_viewport_rect().size.y
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
	if show_it:
		modulate.a = 0.0
		sheet.position.y = _sheet_top + off * 0.25
		_anim.set_ease(Tween.EASE_OUT)
		_anim.tween_property(self, "modulate:a", 1.0, SLIDE_SEC * 0.6)
		_anim.tween_property(sheet, "position:y", _sheet_top, SLIDE_SEC)
	else:
		_anim.set_ease(Tween.EASE_IN)
		_anim.tween_property(self, "modulate:a", 0.0, SLIDE_SEC * 0.8)
		_anim.tween_property(sheet, "position:y", _sheet_top + off * 0.25, SLIDE_SEC * 0.8)
		_anim.chain().tween_callback(func() -> void: visible = false)


func _on_bar_pressed(i: int) -> void:
	if _tab != null:
		_tab.on_bar_pressed(i)


# ── Host services for ManagerTab (contract: LobbyScreen.gd header) ───────────
func bar_buttons() -> Array:
	return [%Use, %Save]


## Texts from the tab's `bar_specs()`; the tab sets enabled states itself (`_refresh_bar`).
func rebuild_bar() -> void:
	if _tab == null:
		return
	var specs: Array = _tab.bar_specs()
	var bs: Array = bar_buttons()
	for i in mini(specs.size(), bs.size()):
		(bs[i] as Button).text = String((specs[i] as Dictionary).get("text", ""))


func relayout_bar() -> void:
	pass


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
## 뜨지 않는다. 저장 버튼은 진짜로 저장하므로 누르지 말 것 — 사용 · 저장은 출력만 하게 끊는다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	open(null)
	UiPreview.mute(%Use, self, "이 프리셋 사용")
	UiPreview.mute(%Save, self, "저장")
