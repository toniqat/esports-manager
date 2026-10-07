class_name ManagerTypePopup
extends CanvasLayer

# First-lobby modal: pick the manager type (운영형 / 실전형) — plan §11.0 (M3).
#
# Shown by `LobbyScreen` while `ProfileManager.manager_type_chosen()` is false.
# **It cannot be dismissed without choosing**: the dim swallows taps but does not
# close, and there is no cancel button. The only way out is picking an option and
# pressing confirm, which emits `chosen(type_id)` — the lobby saves it through
# `ProfileManager.set_manager_type`. Changing it later is a prestige (M9) thing,
# and the popup says so in one line.
#
# Options come from `StaffSystem.manager_types()` (`manager_types.csv`): name,
# description and the six stats (1..20) in `StaffSystem.STATS` order — one
# `ManagerTypeOption.tscn` instance per type inside `%Options`.
#
# **Prestige mode** (M9, `open(true, current_type)`): opened by the lobby `감독` tab
# after the prestige confirm. Same option cards, but the title / body talk about
# prestige, the current type carries a "현재" chip, and it *is* dismissible — a dim tap
# or the ghost `취소` emits `cancelled` (nothing changes). Confirm emits `chosen`.
#
# **Layout lives in `ManagerTypePopup.tscn`** (same frame as `ConfirmPopup`: dim = whole
# viewport, white `PopupCard` centred in `%SafeArea`). Style comes from the shared theme
# (`resources/OutgameTheme.tres`) on `Root`. Code owns: texts, the option instances,
# the selection colour (`ManagerTypeOption.set_selected`), `%Cancel` visibility, the
# `%Dim` haptics, and the safe-area offsets of `%SafeArea`.
#
# Use:
#   var p := ManagerTypePopup.create()
#   add_child(p)
#   p.chosen.connect(...)
#   p.open()            # or open(true, current_type) for prestige

signal chosen(type_id: int)
signal cancelled

const SCENE_PATH: String = "res://features/meta/lobby/ManagerTypePopup.tscn"
const OPTION_SCENE_PATH: String = "res://features/meta/lobby/ManagerTypeOption.tscn"

var _types: Array = []
var _selected: int = -1
var _prestige_mode: bool = false
var _current_type: int = -1


## Instantiates the scene. `ManagerTypePopup.new()` is an empty CanvasLayer — don't use it.
static func create() -> ManagerTypePopup:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as ManagerTypePopup
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(cancel)          # no-op outside prestige mode — the dim just swallows
	%Cancel.pressed.connect(cancel)
	%Confirm.pressed.connect(_on_confirm)


## `prestige_mode` = M9 re-selection (dismissible); `current_type` gets a "현재" chip.
func open(prestige_mode: bool = false, current_type: int = -1) -> void:
	_prestige_mode = prestige_mode
	_current_type = current_type
	_types = StaffSystem.manager_types()
	_selected = -1

	%Title.text = "프레스티지 — 감독 유형 재선택" if prestige_mode else "감독 유형 선택"
	%Sub.text = "새 감독 유형을 고르면 프레스티지가 끝납니다. 같은 유형을 다시 골라도 됩니다." \
			if prestige_mode else \
			"첫 런을 시작하기 전에 감독 유형을 고르세요. 스태프가 없는 영역은 감독 스탯으로 운영합니다."
	%Note.text = "Lv1 · 스탯 제거가 초기화됩니다." if prestige_mode \
			else "이후 변경은 프레스티지로만 가능합니다."

	_sync_options()
	for i in _types.size():
		var opt: ManagerTypeOption = _option(i)
		var row: Dictionary = _types[i]
		opt.fill(row, prestige_mode and int(row.get("id", -1)) == current_type)
		opt.set_selected(false)

	%Cancel.visible = prestige_mode
	var btn: Button = %Confirm
	btn.disabled = true
	btn.text = "유형을 고르세요"
	_apply_dim_haptics(prestige_mode)
	_fit_safe_area()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Selects option `idx` (also used by headless checks).
func select(idx: int) -> void:
	if idx < 0 or idx >= _types.size():
		return
	if idx != _selected:
		Haptics.play(Haptics.Kind.SELECT)
	_selected = idx
	for i in _types.size():
		_option(i).set_selected(i == idx)
	var btn: Button = %Confirm
	btn.disabled = false
	btn.text = ("%s 감독으로 프레스티지" if _prestige_mode else "%s 감독으로 시작") \
			% String((_types[idx] as Dictionary).get("name", ""))


## Prestige mode only — closes without choosing.
func cancel() -> void:
	if not _prestige_mode or not is_open():
		return
	close()
	cancelled.emit()


# ── Options ──────────────────────────────────────────────────────────────────
## Makes `%Options` hold exactly one `ManagerTypeOption` per type. The scene's preview
## instances are reused; extra types instantiate more, fewer types free the rest.
func _sync_options() -> void:
	var box: Node = %Options
	var n: int = _types.size()
	while box.get_child_count() > n:
		var extra: Node = box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.queue_free()
	for i in box.get_child_count():
		_wire_option(box.get_child(i) as ManagerTypeOption, i)
	while box.get_child_count() < n:
		var opt := (load(OPTION_SCENE_PATH) as PackedScene).instantiate() as ManagerTypeOption
		box.add_child(opt)
		_wire_option(opt, box.get_child_count() - 1)


func _wire_option(opt: ManagerTypeOption, idx: int) -> void:
	if opt.tapped.get_connections().is_empty():   # wired once; the index never changes
		opt.tapped.connect(select.bind(idx))


func _option(idx: int) -> ManagerTypeOption:
	return %Options.get_child(idx) as ManagerTypeOption


# ── Frame ────────────────────────────────────────────────────────────────────
## Same as `ConfirmPopup`: shrink `%SafeArea` to the safe area so the confirm button
## stays above the gesture zone.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## First-lobby mode: a dim tap does nothing, so it must not buzz. Prestige mode: it
## cancels, so it gets the normal button feel back.
func _apply_dim_haptics(dismissible: bool) -> void:
	var dim: Button = %Dim
	if dismissible:
		HapticUi.kind(dim, HapticUi.up_kind)
		HapticUi.down_kind_for(dim, HapticUi.down_kind)
	else:
		HapticUi.mute(dim)


func _on_confirm() -> void:
	if _selected < 0 or _selected >= _types.size():
		return
	var type_id: int = int((_types[_selected] as Dictionary).get("id", 0))
	close()
	chosen.emit(type_id)
