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
# `UI_Comp_ManagerTypeOption.tscn` instance per type inside `%Options`.
#
# **Prestige mode** (M9, `open(true, current_type)`): opened by the lobby `감독` tab
# after the prestige confirm. Same option cards, but the title / body talk about
# prestige, the current type carries a "현재" chip, and it *is* dismissible — a dim tap
# or the ghost `취소` emits `cancelled` (nothing changes). Confirm emits `chosen`.
#
# **Layout lives in `UI_View_ManagerTypePopup.tscn`** (dim = whole viewport, white `PopupCard`
# centred in `%Center` = `%SafeArea` minus the scene's top / bottom margin). The option list
# sits in `%Scroll` (+ `DragScroll`): while the card fits `%Center` the scroll is exactly the
# list's height; past that it is capped and the list scrolls — title, texts and buttons stay
# put. Style comes from the shared theme (`resources/OutgameTheme.tres`) on `Root`. Code
# owns: texts, the option instances, the selection colour (`ManagerTypeOption.set_selected`),
# `%Cancel` visibility, the `%Dim` haptics, the safe-area offsets of `%SafeArea` and the
# scroll's height (`_fit_body`).
#
# Use:
#   var p := ManagerTypePopup.create()
#   add_child(p)
#   p.chosen.connect(...)
#   p.open()            # or open(true, current_type) for prestige

signal chosen(type_id: int)
signal cancelled

const SCENE_PATH: String = "res://features/meta/lobby/UI_View_ManagerTypePopup.tscn"
const OPTION_SCENE_PATH: String = "res://features/meta/lobby/UI_Comp_ManagerTypeOption.tscn"

var _types: Array = []
var _selected: int = -1
var _prestige_mode: bool = false
var _current_type: int = -1
var _drag: DragScroll
var _fit_queued: bool = false


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
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`) — 선택지가 안전 영역보다 길 때만 굴러간다.
	_drag = DragScroll.attach(%Scroll)
	# 줄바꿈 라벨은 첫 배치 뒤에야 높이가 정해진다 — 카드 최소 크기가 바뀔 때마다 다시 맞춘다.
	(%Card as Control).minimum_size_changed.connect(_queue_fit)
	(%SafeArea as Control).resized.connect(_queue_fit)
	if UiPreview.is_standalone(self):
		_fill_preview()


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
	_fit_body()
	(%Scroll as ScrollContainer).scroll_vertical = 0
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
			% Loc.t(String((_types[idx] as Dictionary).get("name_key", "")))  # l10n-dynamic: manager.type.*.name


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
		opt.tapped.connect(_on_option_tapped.bind(idx))


## A release that ended a drag of `%Scroll` is a scroll, not a pick (`DragScroll.moved`).
func _on_option_tapped(idx: int) -> void:
	if _drag != null and _drag.moved:
		return
	select(idx)


func _option(idx: int) -> ManagerTypeOption:
	return %Options.get_child(idx) as ManagerTypeOption


# ── Frame ────────────────────────────────────────────────────────────────────
## Same as `ConfirmPopup`: shrink `%SafeArea` to the safe area so the confirm button
## stays above the gesture zone.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## **The card stays centred while it fits, then is capped** — `%Center` (the safe area minus
## the scene's margins) is the most height it may take. Everything but `%Scroll` (title, texts,
## gaps, buttons) keeps its height; `%Scroll` gets the list's full height, or only what is
## left when that is too much — then the list scrolls.
func _fit_body() -> void:
	_fit_queued = false
	var scroll: ScrollContainer = %Scroll
	var center: Control = %Center
	# Room from anchors / offsets — `center.size` may still be inflated by the previous content
	# (a container never shrinks below its minimum size).
	var room: float = (%SafeArea as Control).size.y - center.offset_top + center.offset_bottom
	var chrome: float = (%Card as Control).get_combined_minimum_size().y 			- scroll.get_combined_minimum_size().y
	var want: float = (%Body as Control).get_combined_minimum_size().y + scroll.get_minimum_size().y
	scroll.custom_minimum_size.y = minf(want, maxf(0.0, room - chrome))


## One refit per frame, after the containers have laid the new content out.
func _queue_fit() -> void:
	if _fit_queued or not visible:
		return
	_fit_queued = true
	_fit_body.call_deferred()


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


## F6 단독 실행 미리보기 — 프레스티지 재선택 모드, 현재 유형 칩 + 첫 카드 선택
## (`resources/UiPreview.gd`). 실제 `manager_types.csv` 를 읽는다. 저장은 부르는 쪽(로비)
## 일이라 `chosen` 은 출력만 된다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(chosen)
	UiPreview.trace(cancelled)
	var types: Array = StaffSystem.manager_types()
	var cur: int = int((types[types.size() - 1] as Dictionary).get("id", -1)) if not types.is_empty() else -1
	open(true, cur)
	select(0)
