class_name LobbyScreen
extends Control

# 프로젝트 진입점 — 로비. **탭 화면의 주인(host)** 이다(M8~M10, 계획서 §12).
#
#   ┌ 재화 줄 (%CurrencyStrip) ─────────────────────┐
#   │ 탭 본문 (지금 탭의 Control, %Tabs 아래)          │
#   ├ 행동 바 (%ActionBar — 탭이 `bar_specs()` 를 주면) ┤
#   └ 탭 바 (%TabBar — 홈 · 컬렉션 · 감독 · 상점 · 패스) ┘
#
# **레이아웃 · 스타일의 정본은 `scenes/Lobby.tscn`** (+ 아이템 씬 `LobbyCurrencyCell.tscn` ·
# `LobbyTabButton.tscn`). 이 스크립트는 화면 틀을 만들지 않는다 — 표(`TABS` ·
# `CURRENCY_STRIP`) 만큼 아이템 수를 맞추고, 글을 넣고, 시그널을 잇는다. 코드가 정하는 것:
# 안전 영역 오프셋(`_fit_safe_area`), 탭 본문 칸(`_place_tab` — 행동 바 유무), 선택 탭
# 글자색 · 배지, 행동 바 버튼(공용 `OutgameTheme.add_bottom_bar` 를 `%ActionBar` 칸에),
# 에러 토스트 색.
#
# - 탭은 `TABS` 표 한 줄 + 그 탭의 스크립트(`extends Control`)다. 탭은 처음 열 때 한 번
#   만들어 `%Tabs` 에 넣고 그 뒤로는 숨겼다 보인다. 탭이 구현하는 것(덕 타이핑):
#     bar_specs() -> Array        행동 바 구간(`OutgameTheme.add_bottom_bar` 의 specs).
#                                 빈 배열이면 바가 없고 본문이 탭 바까지 내려온다.
#                                 **있다 / 없다는 탭마다 고정**이다(글자는 바뀌어도 된다).
#     setup(host: LobbyScreen)    한 번. 탭은 자기 rect(위치 · 크기는 host 가 정했다 —
#                                 앵커 full rect + 오프셋)의 로컬 좌표로 그린다.
#     on_bar_pressed(i: int)      행동 바 i 번째 구간이 눌렸다.
#     on_shown()                  탭이 보일 때마다(프로필이 바뀌었을 수 있다 → 다시 그린다).
# - host 가 주는 것: `show_toast(msg, is_error)`, `refresh_currency()`, `rebuild_bar()`
#   (글자 · 활성 상태가 바뀌면), `bar_buttons()`, `switch_tab(id)`, `set_tab_badge(id, on)`,
#   `open_confirm(...)`.
# - 하단 바 규칙(`resources/README.md`)의 예외: 로비만 **탭 바가 맨 아래**이고 행동 바가
#   그 바로 위에 선다. 행동 바 모양 · 무게 · 주 행동 오른쪽 규칙은 그대로다.

const TABS: Array = [
	{"id": "home",       "label": "홈"},
	{"id": "collection", "label": "컬렉션"},
	{"id": "manager",    "label": "감독"},
	{"id": "shop",       "label": "상점"},
	{"id": "pass",       "label": "패스"},
]

## 재화 줄에 보이는 재화(순서대로). 나머지 재화는 상점 · 컬렉션 화면이 보인다.
const CURRENCY_STRIP: Array = [
	{"key": "outgame",            "label": "재화"},
	{"key": "levelup",            "label": "레벨업"},
	{"key": "gacha_ticket_pilot", "label": "선수권"},
	{"key": "gacha_ticket_trait", "label": "특성권"},
	{"key": "pilot_shard",        "label": "파편"},
]

const CURRENCY_CELL_SCENE: String = "res://features/meta/lobby/LobbyCurrencyCell.tscn"
const TAB_BUTTON_SCENE: String = "res://features/meta/lobby/LobbyTabButton.tscn"

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _pm: Node = get_node("/root/ProfileManager")

var current_tab: String = ""

var _tabs: Dictionary = {}           # id → Control
var _tab_buttons: Dictionary = {}    # id → Button
var _tab_badges: Dictionary = {}     # id → Control (dot)
var _bar: Array = []                 # Array[Button] — current action bar
var _bar_specs: Array = []
var _currency_labels: Dictionary = {}
var _toast_tween: Tween
var _toast_style: StyleBox           # %Toast's scene style (normal look)
var _toast_error_style: StyleBox     # the same pill, recoloured NEGATIVE
var _confirm: ConfirmPopup
var _confirm_cb: Callable = Callable()
var _manager_popup: ManagerTypePopup = null
var _built: bool = false


func _ready() -> void:
	# 로비를 거쳐 들어간 시즌은 진짜 런 파일에 저장한다. 에디터에서 Season /
	# MatchFlow 를 바로 실행하면 기본값(true)이 남아 숨은 테스트 런에 쓴다.
	_gm.use_test_run = false
	if _built:
		return
	_built = true
	_build()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	_fit_safe_area()
	_sync_currency_cells()
	_sync_tab_buttons()
	_toast_style = (%Toast as Panel).get_theme_stylebox("panel")
	_toast_error_style = _toast_style.duplicate()
	if _toast_error_style is StyleBoxFlat:
		(_toast_error_style as StyleBoxFlat).bg_color = OutgameTheme.NEGATIVE
	_hide_toast()

	_confirm = ConfirmPopup.create()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_confirmed)

	switch_tab("home")
	refresh_badges()

	# First lobby of a profile: the manager type must be chosen before anything
	# else (plan §11.0). The popup can't be dismissed without choosing.
	if not _pm.manager_type_chosen():
		_manager_popup = ManagerTypePopup.create()
		add_child(_manager_popup)
		_manager_popup.chosen.connect(_on_manager_type_chosen)
		_manager_popup.open()


## 기기마다 다른 값만 오프셋으로 넣는다(패턴 B) — 배경 · 재화 줄 판은 노치 밑까지
## 올리고, 아래쪽 바들은 제스처 띠 위로 올리되 탭 바 판만 화면 끝까지 내린다.
func _fit_safe_area() -> void:
	ScreenMetrics.extend_background(%Background)
	ScreenMetrics.extend_background(%StripBack)
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	(%SafeBottom as Control).offset_bottom = -below
	(%TabBarBack as Control).offset_bottom = below


## `box` 의 자식(아이템 씬 인스턴스)을 `n` 개로 맞춘다 — 씬의 미리보기 인스턴스를
## 다시 쓰고, 모자라면 인스턴스하고, 남으면 지운다.
func _sync_items(box: Control, scene_path: String, n: int) -> Array:
	var items: Array = box.get_children()
	while items.size() > n:
		var extra: Node = items.pop_back()
		box.remove_child(extra)
		extra.queue_free()
	while items.size() < n:
		var item: Node = (load(scene_path) as PackedScene).instantiate()
		box.add_child(item)
		items.append(item)
	return items


func _sync_currency_cells() -> void:
	var cells: Array = _sync_items(%CurrencyCells, CURRENCY_CELL_SCENE, CURRENCY_STRIP.size())
	for i in cells.size():
		var spec: Dictionary = CURRENCY_STRIP[i]
		var cell: Node = cells[i]
		(cell.get_node("%Caption") as Label).text = String(spec["label"])
		_currency_labels[String(spec["key"])] = cell.get_node("%Value")
	refresh_currency()


func _sync_tab_buttons() -> void:
	var buttons: Array = _sync_items(%TabButtons, TAB_BUTTON_SCENE, TABS.size())
	for i in buttons.size():
		var id: String = String(TABS[i]["id"])
		var b: Button = buttons[i]
		b.text = String(TABS[i]["label"])
		b.pressed.connect(switch_tab.bind(id))
		_tab_buttons[id] = b
		var dot: Control = b.get_node("%Badge")
		dot.visible = false
		_tab_badges[id] = dot


## 탭 본문 칸 — 재화 줄 아래부터, 바가 있는 탭이면 행동 바 위까지, 없으면 탭 바 위까지.
## 값은 씬 노드의 오프셋에서 읽는다(씬에서 바 높이를 고치면 본문이 따라온다).
func _place_tab(tab: Control, has_bar: bool) -> void:
	var slot: Control = %ActionBar if has_bar else %TabBar
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.offset_left = 0.0
	tab.offset_right = 0.0
	tab.offset_top = (%CurrencyStrip as Control).offset_bottom
	tab.offset_bottom = (%SafeBottom as Control).offset_bottom + slot.offset_top


# ── Tabs ─────────────────────────────────────────────────────────────────────
func switch_tab(id: String) -> void:
	if id == current_tab:
		return
	if current_tab != "" and _tabs.has(current_tab):
		(_tabs[current_tab] as Control).visible = false
	current_tab = id
	var tab: Control = _tabs.get(id, null)
	if tab == null:
		tab = _make_tab(id)
		_tabs[id] = tab
		# %Tabs 는 재화 줄 · 바 · 토스트보다 아래 층이다(씬 순서).
		%Tabs.add_child(tab)
		_place_tab(tab, not (tab.call("bar_specs") as Array).is_empty())
		tab.call("setup", self)
	tab.visible = true
	for k in _tab_buttons.keys():
		var on: bool = String(k) == id
		(_tab_buttons[k] as Button).add_theme_color_override("font_color",
				OutgameTheme.ACCENT_TEXT if on else OutgameTheme.TEXT_SUB)
		(_tab_buttons[k] as Button).add_theme_color_override("font_hover_color",
				OutgameTheme.ACCENT_TEXT if on else OutgameTheme.TEXT)
	_hide_toast()
	rebuild_bar()
	tab.call("on_shown")
	refresh_currency()
	refresh_badges()


func _make_tab(id: String) -> Control:
	match id:
		"collection": return CollectionTab.create()
		"manager":    return ManagerTab.create()
		"shop":       return ShopTab.new()
		"pass":       return PassTab.new()
	return HomeTab.create()


## The current tab's action bar, rebuilt from its `bar_specs()`.
func rebuild_bar() -> void:
	for b in _bar:
		(b as Button).queue_free()
	_bar = []
	var tab: Control = _tabs.get(current_tab, null)
	if tab == null:
		return
	_bar_specs = tab.call("bar_specs")
	if _bar_specs.is_empty():
		return
	_bar = OutgameTheme.add_bottom_bar(%ActionBar, _bar_specs)
	_lift_bar()
	for i in _bar.size():
		(_bar[i] as Button).pressed.connect(_on_bar_pressed.bind(i))


func bar_buttons() -> Array:
	return _bar


## Re-lays the bar after a tab toggled a button's `visible`.
func relayout_bar() -> void:
	OutgameTheme.layout_bottom_bar(_bar, _bar_specs)
	_lift_bar()


# The shared bar sits on the very bottom; here it fills the %ActionBar slot on top of the
# tab bar (the slot is already above the gesture zone, so no inset padding).
func _lift_bar() -> void:
	var slot: Control = %ActionBar
	var h: float = slot.offset_bottom - slot.offset_top
	for raw in _bar:
		var b: Button = raw
		# Margin first: while it still holds the inset padding, the button's minimum
		# height exceeds the slot and `size.y = h` would be clamped (the bar then
		# overhung the tab bar on devices with a bottom inset).
		for n in OutgameTheme.BUTTON_STATES:
			var sb := b.get_theme_stylebox(n) as StyleBoxFlat
			if sb != null:
				sb.content_margin_bottom = 8.0
		b.position.y = 0.0
		b.size.y = h
		for c in b.get_children():
			var sep := c as ColorRect
			if sep != null:
				sep.size.y = h


func _on_bar_pressed(i: int) -> void:
	var tab: Control = _tabs.get(current_tab, null)
	if tab != null:
		tab.call("on_bar_pressed", i)


# ── Host services ────────────────────────────────────────────────────────────
func refresh_currency() -> void:
	for k in _currency_labels.keys():
		(_currency_labels[k] as Label).text = str(_pm.currency_of(String(k)))


func set_tab_badge(id: String, on: bool) -> void:
	if _tab_badges.has(id):
		(_tab_badges[id] as Control).visible = on


## Badges derived from the profile: 감독 — unseen unlocked traits.
func refresh_badges() -> void:
	var pending: Array = (_pm.profile.get("traits", {}) as Dictionary).get("unlocked_pending", [])
	set_tab_badge("manager", not pending.is_empty())


const TOAST_SEC: float = 2.4


## Toast = an opaque pill above the action bar (it floats over scrolling tab bodies, so bare
## text would be unreadable); fades out after TOAST_SEC. Normal look = the scene's `%Toast`
## style; an error swaps in the same pill recoloured `NEGATIVE`.
func show_toast(msg: String, is_error: bool = false) -> void:
	var toast: Panel = %Toast
	toast.add_theme_stylebox_override("panel", _toast_error_style if is_error else _toast_style)
	%ToastText.text = msg
	toast.modulate.a = 1.0
	toast.visible = msg != ""
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SEC)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: toast.visible = false)
	if is_error:
		Haptics.play(Haptics.Kind.ERROR)


func _hide_toast() -> void:
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	%Toast.visible = false
	%ToastText.text = ""


## Modal confirm; `on_confirm` runs when confirmed.
func open_confirm(title: String, body: String, cancel_text: String, confirm_text: String,
		danger: bool, on_confirm: Callable) -> void:
	_confirm_cb = on_confirm
	_confirm.open(title, body, cancel_text, confirm_text, danger)


func _on_confirmed() -> void:
	var cb: Callable = _confirm_cb
	_confirm_cb = Callable()
	if cb.is_valid():
		cb.call()


func _on_manager_type_chosen(type_id: int) -> void:
	var err: String = _pm.set_manager_type(type_id)
	if err != "":
		# Profile write failed — say so; the choice still holds for this session.
		show_toast("감독 유형 저장 실패: " + err, true)
	var tab: Control = _tabs.get(current_tab, null)
	if tab != null:
		tab.call("on_shown")
