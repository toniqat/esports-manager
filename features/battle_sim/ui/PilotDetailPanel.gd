class_name PilotDetailPanel
extends Node

# 파일럿 상세 패널 — 하단 아군 스트립의 얼굴을 누르면 열린다.
#
#   좌: 전신 아트를 **무릎 언저리에서 잘라** 세로로 길게
#   우: 아웃게임 스탯 / 인게임 전투 스탯 / 메크 스탯
#   하: 닫기 버튼
#
# 여는 조건은 **자기 작전 단계**뿐이다 — `HudBuilder._update_pilot_strips` 가
# 스트립 버튼을 그때만 활성화하고, `close_if_phase_left()` 가 단계를 벗어나면
# 강제로 닫는다. BATTLE 이 흐르는 동안 열려 있으면 화면이 딤드된 채 전장이
# 굴러가 버린다.
#
# 열려 있는 동안 **아군 스트립은 숨긴다**. 딤 위로 스트립만 남으면 "지금 뭘
# 보고 있는지"가 흐려지고, 딤 아래로 넣으면 방금 누른 얼굴이 어두워져 연결이
# 끊긴다 — 아예 치우는 편이 읽힌다.

## 버리기(10) / 대상 지정(11) / 열람·교전(12) 위. 이 패널은 모달이라
## 열려 있는 동안 카드도 못 내고 턴도 못 넘기므로 다른 오버레이와 겹칠 일이
## 없지만, 겹친다면 이쪽이 위여야 한다.
const OVERLAY_LAYER: int = 13

const VP_W: float = 1080.0
const VP_H: float = 1920.0
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.88)

# ─── 좌: 전신 아트 ───────────────────────────────────────────────────────────
# 폭이 아트 크기를 정한다 — 잘라 낸 상반신의 가로:세로가 대략 0.8 이라 세로로
# 채우려면 폭이 1000px 넘게 필요하고, 그러면 스탯 칸이 남지 않는다. 그래서
# **폭 610 에 맞춰 위쪽 정렬**하고(높이 900 은 그 결과를 담을 여유), 남는 아래
# 공간은 그냥 딤으로 둔다.
const ART_RECT := Rect2(24.0, 196.0, 610.0, 900.0)
## 전신 아트를 어디서 자를 것인가 — **불투명 영역**(= 캐릭터 실루엣) 높이의
## 이 비율까지 남긴다. 이미지마다 인물 크기와 여백이 달라 고정 픽셀로는 누구는
## 허리에서, 누구는 발목에서 잘린다. 알파 바운딩 박스를 재서 그 안에서 자르면
## 40장이 대체로 무릎 언저리에서 맞는다.
const KNEE_FRACTION: float = 0.80

# ─── 우: 스탯 ────────────────────────────────────────────────────────────────
const STAT_X: float = 656.0
const STAT_W: float = 400.0
const STAT_TOP: float = 170.0
const ROW_H: float = 44.0
## 한 줄에서 키(항목명)가 차지하는 폭 비율. 값 쪽이 더 넓다 — "162 (기본 160)"
## 처럼 괄호가 붙는 값이 있고, 키는 전부 짧은 명사다.
const KEY_FRACTION: float = 0.40
const SECTION_GAP: float = 26.0
const HEADER_COLOR := Color(1.0, 0.92, 0.55)
const SECTION_COLOR := Color(0.58, 0.78, 1.0)
const KEY_COLOR := Color(0.72, 0.74, 0.80)
const VALUE_COLOR := Color(0.96, 0.96, 0.98)

const BTN_W: float = 320.0
const BTN_H: float = 84.0
const BTN_Y: float = 1620.0

var _bs: BattleSim = null
var _layer: CanvasLayer = null
var _root: Control = null
var _pilot: PilotData = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = OVERLAY_LAYER
	_layer.name = "PilotDetailLayer"
	add_child(_layer)


# CardSelectOverlay / CardPileViewer 와 같은 패턴 — BattleSim._ready 가
# add_child 직후 호출한다.
func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return _root != null


func open(p: PilotData) -> void:
	if p == null:
		return
	if is_active():
		close()
	_pilot = p
	_build()
	if _bs.hud != null:
		_bs.hud.set_player_strip_visible(false)


func close() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	_pilot = null
	if _bs != null and _bs.hud != null:
		_bs.hud.set_player_strip_visible(true)


## 작전 단계를 벗어나면 닫는다. `HudBuilder.update_hud` 가 매 갱신마다 부른다 —
## 열어 둔 채로 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다.
func close_if_phase_left() -> void:
	if is_active() and _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		close()


# ─── UI ──────────────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.name = "PilotDetail"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.position = Vector2.ZERO
	_root.size = Vector2(VP_W, VP_H)
	# 모달 — 뒤쪽(핸드 · 전장 · 도넛) 입력을 전부 삼킨다.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_build_art()
	_build_stats()
	_build_close_button()


# 전신 아트를 알파 바운딩 박스 기준으로 무릎 언저리에서 자른다. AtlasTexture 로
# 영역만 지정하므로 이미지를 새로 만들지 않는다.
func _build_art() -> void:
	var tex: Texture2D = PilotImages.full_for(_pilot.pilot_id)
	var rect := TextureRect.new()
	rect.position = ART_RECT.position
	rect.size = ART_RECT.size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP_ASPECT — 비율을 지키며 칸 **좌상단에** 맞춘다. CENTERED 로 두면 칸이
	# 아트보다 세로로 길어서 인물이 칸 한가운데로 내려앉아 위아래로 큰 빈칸이
	# 생긴다(실측 확인). COVERED 는 칸을 채우느라 좌우를 잘라 팔이 사라진다.
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		rect.texture = _knee_crop(tex)
	_root.add_child(rect)
	if tex == null:
		# 초상화가 없는 파일럿(단독 실행 / INTL) — 자리만 표시한다.
		var ph := _make_label("(초상화 없음)", 26, KEY_COLOR,
				HORIZONTAL_ALIGNMENT_CENTER)
		ph.position = ART_RECT.position + Vector2(0.0, ART_RECT.size.y * 0.5)
		ph.size = Vector2(ART_RECT.size.x, 40.0)
		_root.add_child(ph)


static func _knee_crop(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image()
	if img == null:
		return tex
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return tex
	var h: int = maxi(1, int(round(float(used.size.y) * KNEE_FRACTION)))
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used.position.x, used.position.y, used.size.x, h)
	return atlas


func _build_stats() -> void:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = pd.assigned_mech if pd != null else null
	var role_name: String = _bs.ROLE_NAMES[_pilot.role] \
			if _pilot.role < _bs.ROLE_NAMES.size() else "?"

	var y: float = STAT_TOP
	var display_name: String = pd.name if pd != null else _bs.pilot_label(_pilot)
	var name_lbl := _make_label(display_name, 44, HEADER_COLOR,
			HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(STAT_X, y)
	name_lbl.size = Vector2(STAT_W, 54.0)
	_root.add_child(name_lbl)
	y += 56.0

	var sub: String = "%s · %s · 성장치 %s" % [
		role_name,
		"아군" if _pilot.team == 0 else "적군",
		BattleSim.fmt_score(_pilot.score)]
	var sub_lbl := _make_label(sub, 22, KEY_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	sub_lbl.position = Vector2(STAT_X, y)
	sub_lbl.size = Vector2(STAT_W, 30.0)
	_root.add_child(sub_lbl)
	y += 30.0 + SECTION_GAP

	# ─ 인게임 전투 스탯 — 지금 이 전장에서의 상태.
	y = _section(y, "인게임")
	y = _row(y, "체력", "%d / %d" % [_pilot.hp, _pilot.max_hp])
	y = _row(y, "공격력", "%d  (기본 %d)" % [_pilot.atk, _pilot.base_atk])
	y = _row(y, "성장", "+%.0f%%" % (_pilot.growth * 100.0))
	y = _row(y, "명중 / 회피", "%d / %d" % [_pilot.hit, _pilot.evasion])
	y = _row(y, "보호막", str(_pilot.shield))
	y = _row(y, "라인 / 위치", "%s%s" % [
		_bs.LANE_NAMES[_pilot.lane] if _pilot.lane < _bs.LANE_NAMES.size() else "?",
		"  (정글)" if _pilot.is_guerrilla else ""])
	if not _pilot.alive:
		y = _row(y, "부활까지", "%d턴" % _bs.turns_until_return(_pilot))
	y += SECTION_GAP

	# ─ 아웃게임 스탯 — 파일럿이라는 '사람'의 능력치.
	y = _section(y, "파일럿")
	if pd != null:
		y = _row(y, "라인전", str(pd.laning))
		y = _row(y, "메카닉", str(pd.mechanics))
		y = _row(y, "게임센스", str(pd.gamesense))
		y = _row(y, "한타", str(pd.teamfight))
		y = _row(y, "멘탈", str(pd.mental))
	else:
		y = _row(y, "—", "데이터 없음")
	y += SECTION_GAP

	# ─ 메크 — 배정된 기체. speed 스탯은 삭제됐다(교전이 턴제가 되면서).
	y = _section(y, "메크")
	if mech != null:
		y = _row(y, "기체", mech.name)
		y = _row(y, "체력", str(mech.hp))
		y = _row(y, "공격력", str(mech.atk))
		y = _row(y, "존재감", str(mech.presence))
	else:
		y = _row(y, "—", "미배정")


func _section(y: float, title: String) -> float:
	var lbl := _make_label(title, 26, SECTION_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.position = Vector2(STAT_X, y)
	lbl.size = Vector2(STAT_W, 34.0)
	_root.add_child(lbl)
	var line := ColorRect.new()
	line.color = Color(SECTION_COLOR.r, SECTION_COLOR.g, SECTION_COLOR.b, 0.35)
	line.position = Vector2(STAT_X, y + 34.0)
	line.size = Vector2(STAT_W, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)
	return y + 42.0


func _row(y: float, key: String, value: String) -> float:
	var k := _make_label(key, 24, KEY_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	k.position = Vector2(STAT_X, y)
	k.size = Vector2(STAT_W * KEY_FRACTION, ROW_H)
	k.clip_text = true
	_root.add_child(k)
	var v := _make_label(value, 26, VALUE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	v.position = Vector2(STAT_X + STAT_W * KEY_FRACTION, y)
	v.size = Vector2(STAT_W * (1.0 - KEY_FRACTION), ROW_H)
	# **clip_text 는 필수다.** 오른쪽 정렬 Label 은 글자가 rect 보다 넓으면
	# 정렬을 포기하고 rect 왼쪽부터 그려서 **오른쪽으로 넘쳐 화면을 벗어난다**
	# (실측: "아웃게임 데이터 없음" 이 화면 밖에서 잘렸다). 자르는 편이 낫다.
	v.clip_text = true
	_root.add_child(v)
	return y + ROW_H


func _build_close_button() -> void:
	var btn := Button.new()
	btn.text = "닫기"
	btn.add_theme_font_size_override("font_size", 30)
	btn.position = Vector2((VP_W - BTN_W) * 0.5, BTN_Y)
	btn.size = Vector2(BTN_W, BTN_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(close)
	_root.add_child(btn)


static func _make_label(text: String, font_size: int, color: Color,
		halign: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
