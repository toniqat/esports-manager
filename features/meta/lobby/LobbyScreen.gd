class_name LobbyScreen
extends Control

# 프로젝트 진입점 — 로비. **탭 화면의 주인(host)** 이다(M8~M10, 계획서 §12).
#
#   ┌ 재화 줄 (CURRENCY_H) ─────────────────────────┐
#   │ 탭 본문 (지금 탭의 Control)                     │
#   ├ 행동 바 (탭이 `bar_specs()` 를 주면) ──────────┤
#   └ 탭 바 (홈 · 컬렉션 · 감독 · 상점 · 패스) ───────┘
#
# - 탭은 `TABS` 표 한 줄 + 그 탭의 스크립트(`extends Control`)다. 탭은 처음 열 때 한 번
#   만들고 그 뒤로는 숨겼다 보인다. 탭이 구현하는 것(덕 타이핑):
#     bar_specs() -> Array        행동 바 구간(`OutgameTheme.add_bottom_bar` 의 specs).
#                                 빈 배열이면 바가 없고 본문이 탭 바까지 내려온다.
#                                 **있다 / 없다는 탭마다 고정**이다(글자는 바뀌어도 된다).
#     setup(host: LobbyScreen)    한 번. 탭은 자기 rect(위치 · 크기는 host 가 정했다)의
#                                 로컬 좌표로 그린다.
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

const CURRENCY_H: float = 96.0
const TAB_BAR_H: float = 128.0

## 재화 줄에 보이는 재화(순서대로). 나머지 재화는 상점 · 컬렉션 화면이 보인다.
const CURRENCY_STRIP: Array = [
	{"key": "outgame",            "label": "재화"},
	{"key": "levelup",            "label": "레벨업"},
	{"key": "gacha_ticket_pilot", "label": "선수권"},
	{"key": "gacha_ticket_trait", "label": "특성권"},
	{"key": "pilot_shard",        "label": "파편"},
]

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _pm: Node = get_node("/root/ProfileManager")

var current_tab: String = ""

var _tabs: Dictionary = {}           # id → Control
var _tab_buttons: Dictionary = {}    # id → Button
var _tab_badges: Dictionary = {}     # id → Control (dot)
var _bar: Array = []                 # Array[Button] — current action bar
var _bar_specs: Array = []
var _currency_labels: Dictionary = {}
var _toast: Panel
var _toast_lbl: Label
var _toast_tween: Tween
var _confirm: ConfirmPopup
var _confirm_cb: Callable = Callable()
var _manager_popup: ManagerTypePopup = null
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 로비를 거쳐 들어간 시즌은 진짜 런 파일에 저장한다. 에디터에서 Season /
	# MatchFlow 를 바로 실행하면 기본값(true)이 남아 숨은 테스트 런에 쓴다.
	_gm.use_test_run = false
	if _built:
		return
	_built = true
	_build()


# ── Layout (화면째 안전 영역으로 내린 좌표계) ──────────────────────────────────
static func tab_bar_top() -> float:
	return OutgameTheme.bottom_bar_top()


static func action_bar_top() -> float:
	return tab_bar_top() - OutgameTheme.BOTTOM_BAR_H


## 탭 본문 rect — 바가 있는 탭이면 행동 바 위까지, 없으면 탭 바 위까지.
static func content_rect(has_bar: bool) -> Rect2:
	var bottom: float = action_bar_top() if has_bar else tab_bar_top()
	return Rect2(0.0, CURRENCY_H, ScreenMetrics.vp_w(), bottom - CURRENCY_H)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)
	_build_currency_strip()
	_build_tab_bar()
	# Toast = an opaque pill above the action bar (it floats over scrolling tab bodies,
	# so bare text would be unreadable); fades out after TOAST_SEC.
	_toast = Panel.new()
	_toast.position = Vector2(40.0, action_bar_top() - 88.0)
	_toast.size = Vector2(ScreenMetrics.vp_w() - 80.0, 68.0)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 5
	_toast.visible = false
	add_child(_toast)
	_toast_lbl = UiHelpers.mk_label(_toast, "", 26, OutgameTheme.TEXT_ON_FILL,
			Vector2(16, 0), _toast.size - Vector2(32, 0), HORIZONTAL_ALIGNMENT_CENTER)
	_toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_lbl.clip_text = true

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


func _build_currency_strip() -> void:
	var strip := Panel.new()
	strip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE, 0))
	strip.position = Vector2.ZERO
	strip.size = Vector2(ScreenMetrics.vp_w(), CURRENCY_H)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	ScreenMetrics.backfill_top(strip, OutgameTheme.SURFACE)
	OutgameTheme.add_divider(strip, Vector2(0, CURRENCY_H - 1.0), ScreenMetrics.vp_w())
	var n: int = CURRENCY_STRIP.size()
	var cell_w: float = (ScreenMetrics.vp_w() - 32.0) / float(n)
	for i in n:
		var spec: Dictionary = CURRENCY_STRIP[i]
		var x: float = 16.0 + cell_w * i
		UiHelpers.mk_label(strip, String(spec["label"]), 18, OutgameTheme.TEXT_SUB,
				Vector2(x, 12), Vector2(cell_w, 26), HORIZONTAL_ALIGNMENT_CENTER)
		_currency_labels[String(spec["key"])] = UiHelpers.mk_label(strip, "0", 30,
				OutgameTheme.TEXT, Vector2(x, 40), Vector2(cell_w, 40),
				HORIZONTAL_ALIGNMENT_CENTER)
	refresh_currency()


func _build_tab_bar() -> void:
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	var vp_w: float = ScreenMetrics.vp_w()
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE, 0))
	back.position = Vector2(0, tab_bar_top())
	back.size = Vector2(vp_w, TAB_BAR_H + below)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	OutgameTheme.add_divider(back, Vector2.ZERO, vp_w, OutgameTheme.BORDER_STRONG)
	var w: float = vp_w / float(TABS.size())
	for i in TABS.size():
		var id: String = String(TABS[i]["id"])
		var b := Button.new()
		b.text = String(TABS[i]["label"])
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(w * i, tab_bar_top())
		b.size = Vector2(w, TAB_BAR_H)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(switch_tab.bind(id))
		add_child(b)
		_tab_buttons[id] = b
		var dot := ColorRect.new()
		dot.color = OutgameTheme.NEGATIVE
		dot.size = Vector2(14, 14)
		dot.position = Vector2(w * 0.5 + 44.0, 30.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = false
		b.add_child(dot)
		_tab_badges[id] = dot


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
		add_child(tab)
		# 탭 바 · 재화 줄 · 토스트 · 팝업보다 아래에 깐다.
		move_child(tab, 1)
		var rect: Rect2 = content_rect(not (tab.call("bar_specs") as Array).is_empty())
		tab.position = rect.position
		tab.size = rect.size
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
		"collection": return CollectionTab.new()
		"manager":    return ManagerTab.new()
		"shop":       return ShopTab.new()
		"pass":       return PassTab.new()
	return HomeTab.new()


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
	_bar = OutgameTheme.add_bottom_bar(self, _bar_specs)
	_lift_bar()
	for i in _bar.size():
		(_bar[i] as Button).pressed.connect(_on_bar_pressed.bind(i))


func bar_buttons() -> Array:
	return _bar


## Re-lays the bar after a tab toggled a button's `visible`.
func relayout_bar() -> void:
	OutgameTheme.layout_bottom_bar(_bar, _bar_specs)
	_lift_bar()


# The shared bar sits on the very bottom; here it stands on top of the tab bar.
func _lift_bar() -> void:
	for raw in _bar:
		var b: Button = raw
		b.position.y = action_bar_top()
		b.size.y = OutgameTheme.BOTTOM_BAR_H
		for n in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb := b.get_theme_stylebox(n) as StyleBoxFlat
			if sb != null:
				sb.content_margin_bottom = 8.0
		for c in b.get_children():
			var sep := c as ColorRect
			if sep != null:
				sep.size.y = OutgameTheme.BOTTOM_BAR_H


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


func show_toast(msg: String, is_error: bool = false) -> void:
	_toast.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
			OutgameTheme.NEGATIVE if is_error else OutgameTheme.RAIL, 34))
	_toast_lbl.text = msg
	_toast.modulate.a = 1.0
	_toast.visible = msg != ""
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SEC)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)
	if is_error:
		Haptics.play(Haptics.Kind.ERROR)


func _hide_toast() -> void:
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	_toast.visible = false
	_toast_lbl.text = ""


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
