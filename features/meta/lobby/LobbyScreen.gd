class_name LobbyScreen
extends Control

# 프로젝트 진입점 — 로비. **탭 화면의 주인(host)** 이다(M8~M10, 계획서 §12).
#
#   ┌ 위 막대 (%TopBar) — 감독 레벨 원(좌) · 재화 알약 둘 · 설정 원(우), 판 없이 ┐
#   │ 탭 본문 (지금 탭의 Control, %Tabs 아래)                                 │
#   ├ 행동 바 (%ActionBar — 탭이 `bar_specs()` 를 주면)                      ┤
#   └ 떠 있는 캡슐 메뉴 (%NavBar — 기록 · 컬렉션 · 홈 · 패스 · 상점, 아이콘만)  ┘
#
# **레이아웃 · 스타일의 정본은 `scenes/Lobby.tscn`** (+ 아이템 씬 `UI_Comp_LobbyCurrencyPill.tscn` ·
# `UI_Comp_LobbyNavButton.tscn`). 이 스크립트는 화면 틀을 만들지 않는다 — 표(`TABS` ·
# `WALLET`) 만큼 아이템 수를 맞추고, 글 · 아이콘을 넣고, 시그널을 잇는다. 코드가 정하는 것:
# 안전 영역 오프셋(`_fit_safe_area`), 탭 본문 칸(`_place_tab` — 행동 바 유무), 캡슐 안
# 선택 알약(`%NavSelector`)의 위치 · 미끄러짐, 메뉴 아이콘 색(선택 = 흰 알약 위 짙은 색) ·
# 영문 이름 표시, 레벨 원(`refresh_level`), 배지, 행동 바 버튼(공용
# `OutgameTheme.add_bottom_bar` 를 `%ActionBar` 칸에), 에러 토스트 색.
#
# - 탭은 `TABS` 표 한 줄 + 그 탭의 스크립트(`extends Control`)다. 탭은 처음 열 때 한 번
#   만들어 `%Tabs` 에 넣고 그 뒤로는 숨겼다 보인다. `locked` 줄(기록)은 아이콘만 흐리고
#   누름에 반응하지 않는다. 탭이 구현하는 것(덕 타이핑):
#     bar_specs() -> Array        행동 바 구간(`OutgameTheme.add_bottom_bar` 의 specs).
#                                 빈 배열이면 바가 없고 본문이 캡슐 메뉴 위까지 내려온다.
#                                 **있다 / 없다는 탭마다 고정**이다(글자는 바뀌어도 된다).
#     setup(host: LobbyScreen)    한 번. 탭은 자기 rect(위치 · 크기는 host 가 정했다 —
#                                 앵커 full rect + 오프셋)의 로컬 좌표로 그린다.
#     on_bar_pressed(i: int)      행동 바 i 번째 구간이 눌렸다.
#     on_shown()                  탭이 보일 때마다(프로필이 바뀌었을 수 있다 → 다시 그린다).
# - 감독 화면은 탭이 아니라 **레벨 원을 누르면 뜨는 모달**(`ManagerPopup`, 같은 계약의
#   `ManagerTab` 을 시트 안에 담는다). 재화 알약을 누르면 재화 구매처(`CurrencyShopPopup`).
#   둘 다 로비의 자식 Control 이라 `%Toast`(z 5) 가 그 위에 뜬다.
# - host 가 주는 것: `show_toast(msg, is_error)`, `refresh_currency()`(재화 + 레벨 원),
#   `rebuild_bar()` (글자 · 활성 상태가 바뀌면), `bar_buttons()`, `switch_tab(id)`,
#   `set_tab_badge(id, on)`, `refresh_badges()`, `open_confirm(...)`, `open_abandon_run(meta, cb)`, `open_scenario_select(animate)`.
# - 탭이 선택적으로 주는 것: `bar_scale() -> Vector2` — 행동 바 전체 폭 × x(가운데 정렬),
#   캡슐 높이 × y(아래끝 고정). 없으면 (1, 1).
# - **Scenario mode** (`open_scenario_select`): the home tab's `게임 시작` without a run. The
#   wallet slides up past the notch, the nav capsule + action bar slide down off-screen
#   (`_slide_chrome`), and `ScenarioSelectView` covers the tab body between `%Tabs` and `%TopBar`
#   — the level disc and the settings disc stay on top and usable. 뒤로 slides the chrome back;
#   a pick resets the season and goes to RunSetup on that scenario.
# - 하단 바 규칙(`resources/README.md`)의 예외: 로비만 **캡슐 메뉴가 맨 아래**이고 행동 바가
#   그 바로 위에 선다. 행동 바 모양 · 무게 · 주 행동 오른쪽 규칙은 그대로다.

const ICON_DIR: String = "res://resources/images/ui/lobby/"

## 캡슐 메뉴 칸 — 왼쪽부터. `caption` = 선택됐을 때 아이콘 아래 영문 대문자 이름(l10n key).
const TABS: Array = [    # l10n-keys: lobby.nav.*
	{"id": "record",     "caption": L.LOBBY_NAV_RECORD, "icon": "nav_record.svg", "locked": true},
	{"id": "collection", "caption": L.LOBBY_NAV_PILOT,  "icon": "nav_pilot.svg"},
	{"id": "home",       "caption": L.LOBBY_NAV_HOME,   "icon": "nav_home.svg"},
	{"id": "pass",       "caption": L.LOBBY_NAV_PASS,   "icon": "nav_pass.svg"},
	{"id": "shop",       "caption": L.LOBBY_NAV_SHOP,   "icon": "nav_shop.svg"},
]

## 위 막대의 재화 알약(순서대로 — 오른쪽 끝이 마지막). 나머지 재화는 상점 · 컬렉션 화면이
## 보인다. `plus` = 오른쪽 "+" 원(유료 재화). 아이콘은 `CurrencyShopPopup.CURRENCY_ICONS`.
const WALLET: Array = [
	{"key": "outgame"},
	{"key": "premium", "plus": true},
]

const PILL_SCENE: String = "res://features/meta/lobby/UI_Comp_LobbyCurrencyPill.tscn"
const NAV_BUTTON_SCENE: String = "res://features/meta/lobby/UI_Comp_LobbyNavButton.tscn"

## 선택 알약이 칸 사이를 미끄러지는 시간(초).
const SELECTOR_SEC: float = 0.28
## Scenario mode: wallet / nav / action bar slide time (s) and the extra distance past the edge.
const CHROME_SLIDE_SEC: float = 0.38
const CHROME_SLIDE_MARGIN: float = 40.0
const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"
## 캡슐 메뉴 아이콘 색: 어두운 캡슐 위(꺼짐) · 흰 알약 위(켜짐) · 막힌 칸.
const NAV_ICON_OFF: Color = Color(0.85, 0.85, 0.88, 1.0)
const NAV_ICON_ON: Color = OutgameTheme.TEXT
const NAV_ICON_LOCKED: Color = Color(0.85, 0.85, 0.88, 0.28)

## Set before `change_scene_to_file(Lobby.tscn)` to open straight into the scenario pick
## (RunSetup team step 뒤로, RunResult 새 런). Cleared by the lobby once read.
static var open_scenario_on_enter: bool = false

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _pm: Node = get_node("/root/ProfileManager")

var current_tab: String = ""

var _tabs: Dictionary = {}           # id → Control
var _tab_buttons: Dictionary = {}    # id → Button
var _tab_badges: Dictionary = {}     # id → Control (dot)
var _bar: Array = []                 # Array[Button] — current action bar
var _bar_specs: Array = []
var _currency_labels: Dictionary = {}
var _selector_tween: Tween
var _toast_tween: Tween
var _toast_style: StyleBox           # %Toast's scene style (normal look)
var _toast_error_style: StyleBox     # the same pill, recoloured NEGATIVE
var _confirm: ConfirmPopup
var _abandon: AbandonRunPopup
var _confirm_cb: Callable = Callable()
var _manager_popup: ManagerTypePopup = null
var _manager_sheet: ManagerPopup = null
var _wallet_popup: CurrencyShopPopup = null
var _nav_fade: Tween
var _settings: SettingsPopup = null
var _scenario_view: ScenarioSelectView = null
var _chrome_back_animate: bool = true   # how the chrome returns once the scenario view has closed
var _scenario_open: bool = false
var _chrome_tween: Tween
var _chrome_t: float = 0.0           # 0 = wallet / nav / bar in place, 1 = slid off-screen
var _chrome_base: Dictionary = {}    # Control → Vector2(offset_top, offset_bottom) from the scene
var _built: bool = false


func _ready() -> void:
	# 로비를 거쳐 들어간 시즌은 진짜 런 파일에 저장한다. 에디터에서 Season /
	# MatchFlow 를 바로 실행하면 기본값(true)이 남아 숨은 테스트 런에 쓴다.
	_gm.use_test_run = false
	if _built:
		return
	_built = true
	_build()
	if open_scenario_on_enter:
		# Back from RunSetup's first step / RunResult 새 런: straight into the scenario pick.
		open_scenario_on_enter = false
		switch_tab("home")
		open_scenario_select(false)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	_fit_safe_area()
	for c in [%Wallet, %NavBar, %ActionBar]:
		_chrome_base[c] = Vector2((c as Control).offset_top, (c as Control).offset_bottom)
	_sync_wallet()
	_sync_nav_buttons()
	%LevelButton.pressed.connect(open_manager)
	%SettingsButton.pressed.connect(open_settings)
	# 칸 크기는 첫 배치 뒤에야 정해진다 — 그때(와 화면이 바뀔 때마다) 알약을 제자리에 놓는다.
	%NavButtons.sort_children.connect(_move_selector.bind(false))
	_toast_style = (%Toast as Panel).get_theme_stylebox("panel")
	_toast_error_style = _toast_style.duplicate()
	if _toast_error_style is StyleBoxFlat:
		(_toast_error_style as StyleBoxFlat).bg_color = OutgameTheme.NEGATIVE
	_hide_toast()

	_confirm = ConfirmPopup.create()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_confirmed)
	_abandon = AbandonRunPopup.create()
	add_child(_abandon)
	_abandon.confirmed.connect(_on_confirmed)

	switch_tab("home")
	refresh_badges()

	# First lobby of a profile: the manager type must be chosen before anything
	# else (plan §11.0). The popup can't be dismissed without choosing.
	if not _pm.manager_type_chosen():
		_manager_popup = ManagerTypePopup.create()
		add_child(_manager_popup)
		_manager_popup.chosen.connect(_on_manager_type_chosen)
		_manager_popup.open()


## 기기마다 다른 값만 오프셋으로 넣는다(패턴 B) — 배경은 노치 밑까지 올리고, 아래쪽
## 바들은 제스처 띠 위로 올린다(캡슐 메뉴는 떠 있으므로 바닥까지 내릴 판이 없다).
func _fit_safe_area() -> void:
	ScreenMetrics.extend_background(%Background)
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	(%SafeBottom as Control).offset_bottom = -below


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


func _sync_wallet() -> void:
	var pills: Array = _sync_items(%Wallet, PILL_SCENE, WALLET.size())
	for i in pills.size():
		var spec: Dictionary = WALLET[i]
		var key: String = String(spec["key"])
		var pill: Button = pills[i]
		(pill.get_node("%Icon") as TextureRect).texture = CurrencyShopPopup.currency_icon(key)
		(pill.get_node("%Plus") as Control).visible = bool(spec.get("plus", false))
		pill.pressed.connect(open_wallet)
		_currency_labels[key] = pill.get_node("%Value")
	refresh_currency()


func _sync_nav_buttons() -> void:
	var buttons: Array = _sync_items(%NavButtons, NAV_BUTTON_SCENE, TABS.size())
	for i in buttons.size():
		var spec: Dictionary = TABS[i]
		var id: String = String(spec["id"])
		var b: Button = buttons[i]
		(b.get_node("%Icon") as TextureRect).texture = load(ICON_DIR + String(spec["icon"]))
		(b.get_node("%Caption") as Label).text = Loc.t(String(spec["caption"]))  # l10n-dynamic: lobby.nav.*
		if bool(spec.get("locked", false)):
			# 막힌 칸(기록) — 누름에 아무 반응도 없다(감촉 포함).
			b.disabled = true
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			b.pressed.connect(switch_tab.bind(id))
		_tab_buttons[id] = b
		var dot: Control = b.get_node("%Badge")
		dot.visible = false
		_tab_badges[id] = dot


## 탭 본문 칸 — 위 막대 아래부터, 바가 있는 탭이면 행동 바 위까지, 없으면 캡슐 메뉴 위까지.
## 값은 씬 노드의 오프셋에서 읽는다(씬에서 바 높이를 고치면 본문이 따라온다).
func _place_tab(tab: Control, has_bar: bool) -> void:
	var slot: Control = %ActionBar if has_bar else %NavBar
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.offset_left = 0.0
	tab.offset_right = 0.0
	tab.offset_top = (%TopBar as Control).offset_bottom
	# The scene's offset, not the live one — the slot may be slid away (scenario mode).
	tab.offset_bottom = (%SafeBottom as Control).offset_bottom + (_chrome_base[slot] as Vector2).x


# ── Tabs ─────────────────────────────────────────────────────────────────────
func switch_tab(id: String) -> void:
	if id == current_tab or not _tab_buttons.has(id) or (_tab_buttons[id] as Button).disabled:
		return
	if current_tab != "" and _tabs.has(current_tab):
		(_tabs[current_tab] as Control).visible = false
	current_tab = id
	var tab: Control = _tabs.get(id, null)
	if tab == null:
		tab = _make_tab(id)
		_tabs[id] = tab
		# %Tabs 는 위 막대 · 바 · 토스트보다 아래 층이다(씬 순서).
		%Tabs.add_child(tab)
		_place_tab(tab, not (tab.call("bar_specs") as Array).is_empty())
		tab.call("setup", self)
	tab.visible = true
	_paint_nav()
	_move_selector(true)
	_hide_toast()
	rebuild_bar()
	tab.call("on_shown")
	refresh_currency()
	refresh_badges()


func _make_tab(id: String) -> Control:
	match id:
		"collection": return CollectionTab.create()
		"shop":       return ShopTab.create()
		"pass":       return PassTab.create()
	return HomeTab.create()


## 메뉴 칸의 아이콘 색과 영문 이름 — 선택 칸만 흰 알약 위 짙은 아이콘 + 이름.
func _paint_nav() -> void:
	for spec in TABS:
		var id: String = String(spec["id"])
		var b: Button = _tab_buttons.get(id, null)
		if b == null:
			continue
		var on: bool = id == current_tab
		var icon: TextureRect = b.get_node("%Icon")
		var cap: Label = b.get_node("%Caption")
		cap.visible = on
		cap.add_theme_color_override("font_color", NAV_ICON_ON)
		var target: Color = NAV_ICON_ON if on else NAV_ICON_OFF
		if bool(spec.get("locked", false)):
			target = NAV_ICON_LOCKED
		if icon.self_modulate != target:
			create_tween().tween_property(icon, "self_modulate", target, SELECTOR_SEC * 0.6)


## 선택 알약을 지금 탭의 칸 위로 — `animate` 면 스르륵, 아니면 바로(첫 배치 · 화면 크기 변화).
func _move_selector(animate: bool) -> void:
	var b: Button = _tab_buttons.get(current_tab, null)
	if b == null:
		return
	var sel: Control = %NavSelector
	var target := Rect2((%NavButtons as Control).position + b.position, b.size)
	if target.size.x <= 0.0:
		return
	if _selector_tween != null:
		_selector_tween.kill()
		_selector_tween = null
	if not animate:
		sel.position = target.position
		sel.size = target.size
		return
	_selector_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_selector_tween.tween_property(sel, "position", target.position, SELECTOR_SEC)
	_selector_tween.tween_property(sel, "size", target.size, SELECTOR_SEC)


# ── Modals ───────────────────────────────────────────────────────────────────
## 감독 모달(예전 감독 탭) — 레벨 원을 누르면.
func open_manager() -> void:
	if _manager_sheet == null:
		_manager_sheet = ManagerPopup.create()
		add_child(_manager_sheet)
		_manager_sheet.closed.connect(_on_modal_closed)
	_hide_toast()
	if not _scenario_open:
		_fade_nav(false)
	_manager_sheet.open(self)


## 재화 구매처 — 재화 알약을 누르면.
func open_wallet() -> void:
	if _wallet_popup == null:
		_wallet_popup = CurrencyShopPopup.create()
		add_child(_wallet_popup)
		_wallet_popup.closed.connect(_on_modal_closed)
	_hide_toast()
	_fade_nav(false)
	_wallet_popup.open(self)


## The modals that drop from the top put their floating close capsule where the nav capsule
## sits — the nav fades out (hidden once faded, so it takes no taps) while one is open.
func _fade_nav(show_it: bool) -> void:
	var nav: Control = %NavBar
	if _nav_fade != null:
		_nav_fade.kill()
	nav.visible = true
	_nav_fade = create_tween()
	_nav_fade.tween_property(nav, "modulate:a", 1.0 if show_it else 0.0, 0.18)
	if not show_it:
		_nav_fade.tween_callback(func() -> void: nav.visible = false)


func _on_modal_closed() -> void:
	# In scenario mode the nav stays slid away — only the 감독 modal can open there.
	if not _scenario_open:
		_fade_nav(true)
	refresh_currency()
	refresh_badges()
	var tab: Control = _tabs.get(current_tab, null)
	if tab != null:
		tab.call("on_shown")


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


# `layout_bottom_bar` stands the capsules on the safe line; here they move up into the
# %ActionBar slot above the nav capsule (the slot is already above the gesture zone).
# A tab's optional `bar_scale()` then shrinks the whole row to x × its width, centred (the
# capsules keep the shared gap and their weights), and makes each capsule y × the slot height,
# growing upwards from the slot's bottom (the gap to the nav capsule stays).
func _lift_bar() -> void:
	var base: Vector2 = _chrome_base[%ActionBar]
	var slot_h: float = base.y - base.x
	var scale_xy := Vector2.ONE
	var tab: Control = _tabs.get(current_tab, null)
	if tab != null and tab.has_method("bar_scale"):
		scale_xy = tab.call("bar_scale")
	var h: float = roundf(slot_h * scale_xy.y)
	var main: Array = []        # visible capsules (round icon slots excluded)
	var shown: Array = []
	var total_w: float = 0.0
	for raw in _bar:
		var b: Button = raw
		b.position.y = slot_h - h
		b.size.y = h
		if b.has_meta(&"bar_round"):
			b.size.x = h
		if not b.visible:
			continue
		shown.append(b)
		if not b.has_meta(&"bar_round"):
			main.append(b)
			total_w += b.size.x
	if main.is_empty() or (is_equal_approx(scale_xy.x, 1.0) and main.size() == shown.size()):
		return
	var gap: float = OutgameTheme.BOTTOM_BAR_GAP
	var gaps: float = gap * float(main.size() - 1)
	# The capsules (round slots aside) fill x × the full row, centred — so a round slot never
	# moves the main button off the centre; it hangs beside the row.
	var full: float = ScreenMetrics.vp_w() - OutgameTheme.BOTTOM_BAR_SIDE * 2.0
	var avail: float = roundf(full * scale_xy.x) - gaps
	# A capsule never goes under its own minimum width (text + padding) — a Control would grow
	# past its slot on its own and cover its neighbour; the row widens instead, still centred.
	var widths: Array = []
	var row: float = gaps
	for raw in main:
		var b: Button = raw
		var w: float = maxf(floorf(avail * b.size.x / total_w), ceilf(b.get_combined_minimum_size().x))
		widths.append(w)
		row += w
	var x: float = roundf((ScreenMetrics.vp_w() - row) * 0.5)
	for i in main.size():
		var b: Button = main[i]
		b.position.x = x
		b.size.x = widths[i]
		x += float(widths[i]) + gap
	# Round slots before the first capsule hang to its left, the ones after the last to its right.
	var first: int = shown.find(main[0])
	var left: float = (main[0] as Button).position.x
	for i in range(first - 1, -1, -1):
		var r: Button = shown[i]
		left -= gap + h
		r.position.x = left
	var right: float = x - gap
	for i in range(shown.find(main[main.size() - 1]) + 1, shown.size()):
		var r: Button = shown[i]
		r.position.x = right + gap
		right += gap + h


func _on_bar_pressed(i: int) -> void:
	var tab: Control = _tabs.get(current_tab, null)
	if tab != null:
		tab.call("on_bar_pressed", i)


# ── Host services ────────────────────────────────────────────────────────────
## Wallet pills (thousands commas) + the manager level disc — both change together
## (run settlement, prestige rewards).
func refresh_currency() -> void:
	for k in _currency_labels.keys():
		(_currency_labels[k] as Label).text = Loc.grouped(int(_pm.currency_of(String(k))))
	refresh_level()


## Level disc: number + radial EXP ring inside the level (full at the max level).
func refresh_level() -> void:
	var lp: Dictionary = ManagerProgress.level_progress(_pm.profile)
	(%LevelValue as Label).text = str(int(lp["level"]))
	var span: int = int(lp["span"])
	(%LevelRing as Range).value = 1.0 if bool(lp["is_max"]) or span <= 0 \
			else float(lp["into"]) / float(span)


## `id` = a `TABS` id, or `"manager"` for the level disc's dot.
func set_tab_badge(id: String, on: bool) -> void:
	if id == "manager":
		(%LevelBadge as Control).visible = on
	elif _tab_badges.has(id):
		(_tab_badges[id] as Control).visible = on


## Badges derived from the profile: 감독 (level disc) — unseen unlocked traits.
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


# ── Settings (language, l10n D10 · §10.4) ────────────────────────────────────
## The settings disc (top bar, right of the wallet) — one `SettingsPopup`, made on first open.
func open_settings() -> void:
	if _settings == null:
		_settings = SettingsPopup.create()
		add_child(_settings)
		_settings.locale_chosen.connect(_on_locale_chosen)
	_hide_toast()
	_settings.open()


## Saves the language and reloads the lobby — the only path that rebuilds code-filled texts in
## the new language (no `NOTIFICATION_TRANSLATION_CHANGED` handling).
func _on_locale_chosen(code: String) -> void:
	var err: String = _pm.set_locale(code)
	if err != "":
		show_toast(Loc.t(L.SETTINGS_SAVE_FAILED, {"error": err}), true)
		return
	get_tree().reload_current_scene()


# ── Scenario mode ────────────────────────────────────────────────────────────
## Opens the scenario pick over the home tab: wallet / nav / action bar slide away
## (`animate` = tween, else snap), the view (made once) opens on the last picked scenario.
func open_scenario_select(animate: bool = true) -> void:
	if _scenario_open:
		return
	_scenario_open = true
	_hide_toast()
	var selected: int = maxi(0, RunSetupScreen.entry_scenario)
	if _scenario_view == null:
		_scenario_view = ScenarioSelectView.create()
		add_child(_scenario_view)
		# Above the tab bodies, below the top bar (level / settings discs stay on top),
		# the bottom chrome, the toast and the modals.
		move_child(_scenario_view, (%TopBar as Control).get_index())
		_scenario_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scenario_view.back_requested.connect(close_scenario_select)
		_scenario_view.scenario_chosen.connect(_on_scenario_chosen)
		_scenario_view.closed.connect(_on_scenario_closed)
	else:
		selected = _scenario_view.selected_id
	_slide_chrome(true, animate)
	_scenario_view.open(selected, animate)


## 뒤로 from the scenario view — the view closes itself (contents fade, slab swings out, black wipe);
## the chrome slides back only once that has fully finished (`closed`), never in parallel.
func close_scenario_select(animate: bool = true) -> void:
	if not _scenario_open:
		return
	_scenario_open = false
	if _scenario_view == null:
		_slide_chrome(false, animate)
		return
	_chrome_back_animate = animate
	_scenario_view.close(animate)


func _on_scenario_closed() -> void:
	# Re-opened before the close finished (the view's open kills its close) — keep the chrome away.
	if _scenario_open:
		return
	_slide_chrome(false, _chrome_back_animate)


func is_scenario_open() -> bool:
	return _scenario_open


func _on_scenario_chosen(scenario_id: int) -> void:
	_gm.reset_season_state()
	RunSetupScreen.entry_scenario = scenario_id
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)


## Slides the wallet up past the notch and the nav capsule + action bar down past the bottom
## edge (`away`), or back. Hidden while off-screen, so they take no taps.
func _slide_chrome(away: bool, animate: bool) -> void:
	if _chrome_tween != null:
		_chrome_tween.kill()
		_chrome_tween = null
	var target: float = 1.0 if away else 0.0
	if not away:
		(%NavBar as Control).modulate.a = 1.0
	if not animate:
		_apply_chrome(target)
		return
	_chrome_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_chrome_tween.tween_method(_apply_chrome, _chrome_t, target, CHROME_SLIDE_SEC)


func _apply_chrome(t: float) -> void:
	_chrome_t = t
	var up: float = ScreenMetrics.top_y() + CHROME_SLIDE_MARGIN
	var below: float = maxf(0.0, ScreenMetrics.insets().w) + CHROME_SLIDE_MARGIN
	for raw in _chrome_base.keys():
		var c: Control = raw
		var base: Vector2 = _chrome_base[c]
		# Wallet: its bottom edge ends `up` above the top bar's top (= above the notch).
		# Bottom slots: their top edge ends `below` under the safe bottom (= under the screen).
		var dy: float = -(base.y + up) if c == %Wallet else -base.x + below
		c.offset_top = base.x + dy * t
		c.offset_bottom = base.y + dy * t
		c.visible = t < 1.0


## Run-abandon modal (`AbandonRunPopup`): the run summary from `meta` (`SaveSystem.read_run_meta()`)
## + the warning; `on_confirm` runs when the player abandons.
func open_abandon_run(meta: Dictionary, on_confirm: Callable) -> void:
	_confirm_cb = on_confirm
	_abandon.open(meta)


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
		show_toast(Loc.t(L.LOBBY_MANAGER_TYPE_SAVE_FAILED, {"error": err}), true)
	var tab: Control = _tabs.get(current_tab, null)
	if tab != null:
		tab.call("on_shown")
