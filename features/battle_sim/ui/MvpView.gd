class_name MvpView
extends CanvasLayer

# 경기 MVP 전용 뷰 — 경기가 끝나는 순간(`BattleSim.end_match`) 승패 결과 화면보다
# **먼저** 뜨는 한 장. 이긴 팀 다섯 중 `RunStats.mvp_score` 최고 1명의 전신
# 일러스트(`PilotImages.full_for` — 모브는 실루엣 컷으로 자동 전환)를 세우고,
# 이름 · 진영 · 역할 · K/D/A · 핵심 지표 한 줄을 그 아래에 놓는다.
# "계속"(또는 잠깐 뒤 화면 아무 곳 탭) → `closed` → 기존 결과 화면.
#
# 전장과 같은 **어두운 화면**이다(OutgameTheme 를 쓰지 않는다). 좌표는 전부
# `ScreenMetrics` 의 안전 영역 안 — 아래 버튼은 하단 제스처 띠 위에 선다
# (docs/mobile_safe_area.md).

signal closed

## 다른 오버레이(교전 · 상세 패널 …) 위.
const OVERLAY_LAYER := 60
const DIM_COLOR := Color(0.02, 0.03, 0.06, 0.95)
const GLOW_COLOR := Color(1.0, 0.80, 0.30, 0.28)
const TITLE_COLOR := Color(1.0, 0.85, 0.35)
const NAME_COLOR := Color(0.97, 0.97, 1.0)
const SUB_COLOR := Color(0.72, 0.78, 0.90)
const ALLY_COLOR := Color(0.55, 0.80, 1.0)
const ENEMY_COLOR := Color(1.0, 0.55, 0.55)
const PANEL_BG := Color(0.06, 0.07, 0.12, 0.92)
const PANEL_BORDER := Color(1.0, 0.80, 0.30, 0.75)
const BTN_BG := Color(0.16, 0.21, 0.34, 0.98)

## 레이아웃(디자인 px). 위에서부터 제목 → 전신 → 정보 판 → 버튼.
const TITLE_TOP := 40.0
const ART_TOP := 170.0
const ART_MAX_H := 1000.0
const ART_MAX_W := 900.0
const INFO_H := 330.0
const INFO_SIDE := 60.0
const BTN_H := 120.0
const BTN_SIDE := 120.0
const BTN_BOTTOM_GAP := 40.0
## 아무 곳이나 눌러 넘기기를 받기 시작하는 시점(s) — 경기를 끝낸 바로 그 탭이
## 뷰를 곧장 닫아 버리지 않게 한다.
const TAP_ARM_SEC := 0.8
const FADE_SEC := 0.35

var _root: Control = null
var _art: Control = null
var _armed: bool = false
var _closing: bool = false


func _init() -> void:
	layer = OVERLAY_LAYER


## 뷰를 세운다. `row` 는 `BattleSim.build_pilot_stats` 의 그 선수 한 줄.
func open(bs: BattleSim, p: PilotData, row: Dictionary) -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	var vp_h: float = ScreenMetrics.vp_h()
	var top: float = ScreenMetrics.top_y()
	var bottom: float = ScreenMetrics.bottom_y()

	_root = Control.new()
	_root.name = "MvpRoot"
	_root.position = Vector2.ZERO
	_root.size = Vector2(vp_w, vp_h)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.size = Vector2(vp_w, vp_h)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	# 제목 두 줄 — "MATCH MVP" + 승리 팀.
	var title := _label("MATCH MVP", 72, TITLE_COLOR)
	title.position = Vector2(0.0, top + TITLE_TOP)
	title.size = Vector2(vp_w, 90.0)
	_root.add_child(title)

	# 버튼 · 정보 판은 아래에서부터 쌓는다 — 남는 높이가 전신 몫이다.
	var btn_y: float = bottom - BTN_BOTTOM_GAP - BTN_H
	var info_y: float = btn_y - 30.0 - INFO_H
	var art_top: float = top + ART_TOP
	var art_h: float = minf(ART_MAX_H, info_y - 10.0 - art_top)

	# 전신 뒤의 둥근 후광 — 가운데가 가장 밝고 가장자리로 갈수록 사라진다.
	var grad := Gradient.new()
	grad.set_color(0, GLOW_COLOR)
	grad.set_color(1, Color(GLOW_COLOR, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)
	var glow := TextureRect.new()
	glow.texture = glow_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = Vector2(0.0, art_top)
	glow.size = Vector2(vp_w, art_h)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)

	_art = _make_art(PilotImages.full_for(portrait_id(p)), art_h,
			bs.ROLE_FULL_NAMES[p.role] if p.role < bs.ROLE_FULL_NAMES.size() else "")
	_art.position = Vector2((vp_w - _art.size.x) * 0.5, info_y - 10.0 - _art.size.y)
	_root.add_child(_art)

	_build_info(bs, p, row, Rect2(INFO_SIDE, info_y, vp_w - INFO_SIDE * 2.0, INFO_H))

	var btn := Button.new()
	btn.text = "계속"
	btn.position = Vector2(BTN_SIDE, btn_y)
	btn.size = Vector2(vp_w - BTN_SIDE * 2.0, BTN_H)
	btn.add_theme_font_size_override("font_size", 40)
	btn.add_theme_stylebox_override("normal", _box(BTN_BG, PANEL_BORDER, 3))
	btn.add_theme_stylebox_override("hover", _box(BTN_BG, PANEL_BORDER, 3))
	btn.add_theme_stylebox_override("pressed", _box(BTN_BG.lightened(0.15), PANEL_BORDER, 3))
	btn.pressed.connect(close)
	_root.add_child(btn)

	# 등장 — 전신이 살짝 떠오르며 밝아진다.
	_root.modulate.a = 0.0
	var art_y: float = _art.position.y
	_art.position.y = art_y + 40.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_root, "modulate:a", 1.0, FADE_SEC)
	tw.tween_property(_art, "position:y", art_y, FADE_SEC * 1.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(TAP_ARM_SEC).timeout.connect(func() -> void: _armed = true)


## 뷰를 닫는다(한 번만). 버튼 · 탭 · 헤드리스 검증이 같은 길을 탄다.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()


func _on_root_input(event: InputEvent) -> void:
	if not _armed:
		return
	var tapped: bool = (event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tapped:
		close()


func _build_info(bs: BattleSim, p: PilotData, row: Dictionary, r: Rect2) -> void:
	var panel := Panel.new()
	panel.position = r.position
	panel.size = r.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, PANEL_BORDER, 3))
	_root.add_child(panel)

	var name_lbl := _label(display_name(bs, p), 64, NAME_COLOR)
	name_lbl.position = Vector2(0.0, 18.0)
	name_lbl.size = Vector2(r.size.x, 80.0)
	name_lbl.clip_text = true
	panel.add_child(name_lbl)

	var ally: bool = p.team == 0
	var side_lbl := _label("%s · %s" % ["아군" if ally else "상대 팀", role_label(p)],
			32, ALLY_COLOR if ally else ENEMY_COLOR)
	side_lbl.position = Vector2(0.0, 100.0)
	side_lbl.size = Vector2(r.size.x, 44.0)
	panel.add_child(side_lbl)

	var kda := _label(kda_text(row), 56, NAME_COLOR)
	kda.position = Vector2(0.0, 156.0)
	kda.size = Vector2(r.size.x, 72.0)
	panel.add_child(kda)

	var metric := _label(metric_text(row), 30, SUB_COLOR)
	metric.position = Vector2(0.0, 240.0)
	metric.size = Vector2(r.size.x, 44.0)
	panel.add_child(metric)


## 전신 한 장. 그림이 없으면(INTL 파일럿 · 단독 실행) 같은 자리에 판을 세운다.
func _make_art(tex: Texture2D, h: float, fallback: String) -> Control:
	var aspect: float = 0.45
	if tex != null and tex.get_size().y > 0.0:
		aspect = tex.get_size().x / tex.get_size().y
	var w: float = minf(ART_MAX_W, h * aspect)
	h = w / aspect
	var holder := Control.new()
	holder.size = Vector2(w, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var art_rect := TextureRect.new()
		art_rect.texture = tex
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_SCALE
		art_rect.size = Vector2(w, h)
		art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art_rect)
	else:
		var slab := Panel.new()
		slab.size = Vector2(w, h)
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slab.add_theme_stylebox_override("panel",
				_box(Color(0.14, 0.15, 0.20, 0.6), Color(0.30, 0.34, 0.46, 0.7), 2))
		holder.add_child(slab)
		var lbl := _label(fallback, 40, SUB_COLOR)
		lbl.size = Vector2(w, h)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(lbl)
	return holder


# ─── 표시 문자열 (결과 화면의 MVP 한 줄도 같은 함수를 쓴다) ─────────────────────

## 초상화 조회용 id — 전장 마커와 같은 `PilotData.pilot_id`.
static func portrait_id(p: PilotData) -> int:
	return p.pilot_id if p != null else -1


## 선수 이름. 선수가 없으면(단독 실행) 역할 이름 + 팀 번호.
static func display_name(bs: BattleSim, p: PilotData) -> String:
	if p == null:
		return ""
	var pd: PlayerData = bs.player_data_for(p) if bs != null else null
	if pd != null and not pd.name.is_empty():
		return pd.name
	var role_name: String = String(bs.ROLE_FULL_NAMES[p.role]) \
			if bs != null and p.role < bs.ROLE_FULL_NAMES.size() else "?"
	return "%s %d" % [role_name, p.team]


## 다섯 자리 이름(탑 · 정글 · 미드 · 원딜 · 서폿).
static func role_label(p: PilotData) -> String:
	return String(GameEnums.POSITION_LABELS.get(GameEnums.position_key(p.role), "?"))


static func kda_text(row: Dictionary) -> String:
	return "%d / %d / %d" % [int(row.get("k", 0)), int(row.get("d", 0)), int(row.get("a", 0))]


## 지표의 핵심 한 줄 — 서폿은 돌봄과 받은 피해, 탑은 딜과 받은 피해, 나머지는 딜.
static func metric_text(row: Dictionary) -> String:
	var role: int = int(row.get("role", -1))
	var dmg: String = _fmt(int(row.get("dmg", 0)))
	var taken: String = _fmt(int(row.get("taken", 0)))
	if role == RunStats.support_role():
		return "돌봄 %s · 받은 피해 %s" % [_fmt(int(row.get("care", 0))), taken]
	if role == RunStats.top_role():
		return "준 피해 %s · 받은 피해 %s" % [dmg, taken]
	return "준 피해 %s" % dmg


static func _fmt(v: int) -> String:
	if v >= 10000:
		return "%.1fk" % (float(v) / 1000.0)
	return str(v)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(18)
	return sb
