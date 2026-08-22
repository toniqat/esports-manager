class_name PilotDetailPanel
extends Node

# 파일럿 상세 패널 — 스트립의 얼굴(아군 하단 / **적 상단** 양쪽)을 누르면 열린다.
#
#   좌: 전신 아트 **두 장** — 앞에 선 쪽이 밝고, 뒤에 선 쪽은 오른쪽으로 밀린 채
#       검게 딤드된다. 앞뒤는 전환 버튼이 맞바꾼다(파일럿 ↔ 메크).
#   우: 스탯 — 앞에 선 쪽의 것. 파일럿이면 인게임 + 파일럿, 메크면 메크 스탯.
#   하: 전환 / 닫기
#
# 여는 조건은 **자기 작전 단계**뿐이다 — `HudBuilder._update_pilot_strips` 가
# 스트립 버튼을 그때만 활성화하고, `close_if_phase_left()` 가 단계를 벗어나면
# 강제로 닫는다. BATTLE 이 흐르는 동안 열려 있으면 화면이 딤드된 채 전장이
# 굴러가 버린다.
#
# 열려 있는 동안 **누른 쪽 스트립은 숨긴다**. 딤 위로 스트립만 남으면 "지금 뭘
# 보고 있는지"가 흐려지고, 딤 아래로 넣으면 방금 누른 얼굴이 어두워져 연결이
# 끊긴다 — 아예 치우는 편이 읽힌다.

## 버리기(10) / 대상 지정(11) / 열람·교전(12) 위. 이 패널은 모달이라
## 열려 있는 동안 카드도 못 내고 턴도 못 넘기므로 다른 오버레이와 겹칠 일이
## 없지만, 겹친다면 이쪽이 위여야 한다.
const OVERLAY_LAYER: int = 13

const VP_W: float = 1080.0
const VP_H: float = 1920.0
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.88)

## 앞에 서 있는 아트가 파일럿인가 메크인가. 전환 버튼이 맞바꾼다.
enum Focus { PILOT, MECH }

# ─── 전신 아트 (앞 / 뒤 2슬롯) ───────────────────────────────────────────────
# **아트는 화면 하단에서 잘린다.** 아래끝(`ART_BOTTOM`)을 화면(1920)보다 아래에
# 두어 다리 아랫부분이 화면 밖으로 나간다 — 예전의 `_knee_crop`(알파 실루엣의
# 80% 지점에서 텍스처를 잘라 내던 것)은 그래서 삭제됐다. 자르는 일은 이제
# 화면 가장자리가 하고, 어디서 잘릴지는 아트 크기와 위치 두 상수가 정한다.
#
# 크기는 **높이로 정규화**한다. 전신 아트는 전부 세로 1024 에 인물이 꽉 차 있고
# 가로만 572~756 으로 제각각이라(폭으로 맞추면 인물 키가 이미지마다 다르다),
# 폭은 원본 비율에서 나온다.
#
# 두 아트의 **바닥선은 같다**. 뒤에 선 쪽은 바닥을 딛은 채 `BACK_SCALE` 만큼
# 작아지고(= 멀리 서 있다) 오른쪽으로 `BACK_SHIFT_PX` 밀린다. 축소 기준점을
# 노드의 **아래 가운데**(`pivot_offset`)로 잡았기 때문에 크기를 줄여도 발이
# 뜨지 않는다.
## 앞에 선 아트의 높이(px). 폭은 원본 비율에서 나오므로(대략 0.65~0.74) 이
## 값이 곧 인물이 화면을 얼마나 채우는가다 — 1400 이면 폭 900~1030 으로
## 화면(1080)을 거의 다 쓰고, 그보다 키우면 뒤에 선 메크가 오른쪽으로 완전히
## 밀려 나간다.
const ART_H: float = 1400.0
## 앞에 선 아트의 **아래끝** y. 화면(1920)보다 아래라 하단이 잘린다.
const ART_BOTTOM: float = 2010.0
## 앞에 선 아트의 가로 중심.
const ART_FRONT_CENTER_X: float = 320.0
## 뒤에 선 아트가 오른쪽으로 밀리는 거리(px). 아트 폭이 대략 870 이므로
## 이 값이면 둘이 절반쯤 겹친다.
const ART_BACK_SHIFT_PX: float = 400.0
## 뒤에 선 아트의 축소율(원근).
const ART_BACK_SCALE: float = 0.90
## 뒤에 선 아트에 씌우는 검은 반투명. `modulate` 라 RGB 는 어둡게, A 는 살짝
## 비치게 — 둘 다 필요하다(어둡기만 하면 실루엣이 아니라 검은 판이 된다).
const ART_BACK_TINT := Color(0.14, 0.14, 0.18, 0.88)
## 앞뒤가 자리를 맞바꾸는 데 걸리는 시간(s).
const ART_SWAP_SEC: float = 0.22
## 아트가 없는 메크(= 아직 에셋이 하나도 없다)의 플레이스홀더 가로/세로 비.
const ART_PLACEHOLDER_ASPECT: float = 0.70

# ─── 우: 스탯 ────────────────────────────────────────────────────────────────
# **정보 블록은 아래로 내려왔다.** 아트가 커지면서 화면 위쪽 절반이 인물의
# 머리·상체 자리가 됐고, 스탯이 예전 자리(y 170)에 남으면 얼굴을 덮는다.
const STAT_X: float = 600.0
const STAT_W: float = 452.0
const STAT_TOP: float = 640.0
const ROW_H: float = 42.0
## 한 줄에서 키(항목명)가 차지하는 폭 비율. 값 쪽이 더 넓다 — "162 (기본 160)"
## 처럼 괄호가 붙는 값이 있고, 키는 전부 짧은 명사다.
const KEY_FRACTION: float = 0.40
const SECTION_GAP: float = 26.0
const HEADER_COLOR := Color(1.0, 0.92, 0.55)
const SECTION_COLOR := Color(0.58, 0.78, 1.0)
const KEY_COLOR := Color(0.72, 0.74, 0.80)
const VALUE_COLOR := Color(0.96, 0.96, 0.98)
## 스탯 블록 뒤에 까는 받침. 아트가 이 자리까지 올라오므로 글자만 얹으면
## 일러스트 위에서 읽히지 않는다. 내용 높이에 맞춰 자란다.
const STAT_PANEL_PAD := Vector2(22.0, 26.0)
const STAT_PANEL_BG := Color(0.04, 0.05, 0.09, 0.86)
const STAT_PANEL_BORDER := Color(0.30, 0.34, 0.46, 0.70)

# ─── 하: 버튼 행 ─────────────────────────────────────────────────────────────
# 전환은 **정보 블록의 왼쪽 아래**, 닫기는 그 오른쪽 끝. y 는 고정이다 —
# 메크 쪽 스탯이 훨씬 짧아 받침 높이를 따라가게 두면 버튼이 위아래로 튄다.
const BTN_W: float = 212.0
const BTN_H: float = 76.0
const BTN_Y: float = 1424.0

var _bs: BattleSim = null
var _layer: CanvasLayer = null
var _root: Control = null
var _pilot: PilotData = null
var _focus: int = Focus.PILOT

# 아트 두 장. 어느 쪽이 앞이냐는 `_focus` 가 정하고, 노드 자체는 바뀌지 않는다.
var _art_pilot: Control = null
var _art_mech: Control = null
var _art_holder: Control = null
var _swap_tween: Tween = null

# 스탯 블록은 전환 때마다 통째로 다시 세운다 — 절 구성이 아예 달라진다.
var _stat_root: Control = null
var _stat_panel: Panel = null

## 열면서 숨긴 스트립의 팀. 닫을 때 그 스트립만 되돌린다.
var _hidden_team: int = -1


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
	_focus = Focus.PILOT
	_build()
	if _bs.hud != null:
		_hidden_team = p.team
		_bs.hud.set_strip_visible(_hidden_team, false)


func close() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	_stat_root = null
	_stat_panel = null
	_art_pilot = null
	_art_mech = null
	_art_holder = null
	_pilot = null
	if _bs != null and _bs.hud != null and _hidden_team >= 0:
		_bs.hud.set_strip_visible(_hidden_team, true)
	_hidden_team = -1


## 작전 단계를 벗어나면 닫는다. `HudBuilder.update_hud` 가 매 갱신마다 부른다 —
## 열어 둔 채로 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다.
func close_if_phase_left() -> void:
	if is_active() and _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		close()


## 열려 있는 동안 스탯을 현재 값으로 다시 세운다. `HudBuilder.update_hud` 가
## 매 갱신마다 부른다 — 패널은 모달이라 열려 있는 사이에 카드가 나가지는
## 않지만, 값이 바뀌는 자리(카드 효과 · 만료 · 성장 재계산)는 전부 update_hud
## 를 지나므로 이 한 줄이 "화면의 숫자는 언제나 지금 값"을 보장한다.
## 아트와 앞뒤 자세는 건드리지 않는다(전환 트윈이 끊긴다).
func refresh() -> void:
	if is_active():
		_rebuild_stats()


# ─── UI ──────────────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.name = "PilotDetail"
	# 앵커 프리셋은 쓰지 않는다 — CanvasLayer 아래의 Control 은 full-rect 앵커를
	# 해석해 줄 부모 rect 가 없어서 크기가 그대로 0 이고, 프리셋을 걸어 두면
	# "_ready 뒤에 size 가 덮어써진다"는 경고만 남는다. 크기는 명시한다.
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

	_build_arts()
	_rebuild_stats()
	_build_buttons()


# ─── 전신 아트 ───────────────────────────────────────────────────────────────
# 두 장을 만들어 자기 홀더에 넣고, 앞뒤 자세는 `_apply_focus(false)` 가 잡는다.
func _build_arts() -> void:
	_art_holder = Control.new()
	_art_holder.name = "ArtHolder"
	_art_holder.position = Vector2.ZERO
	_art_holder.size = Vector2(VP_W, VP_H)
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art_holder)

	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = pd.assigned_mech if pd != null else null

	_art_pilot = _make_art(PilotImages.full_for(_pilot.pilot_id), "초상화 없음")
	_art_mech  = _make_art(MechImages.full_for(mech.id) if mech != null else null,
			mech.name if mech != null else "메크 미배정")
	_art_holder.add_child(_art_mech)
	_art_holder.add_child(_art_pilot)
	_apply_focus(false)


## 아트 한 장. `tex` 가 null 이면(메크 에셋이 아직 없다 / INTL 파일럿) 같은
## 자리에 실루엣 플레이스홀더를 세운다 — 자리와 전환 동작은 그대로 확인된다.
##
## 노드 크기는 **언제나 앞에 선 크기**(`ART_H`)로 고정하고, 뒤로 물러날 때는
## `scale` 로만 줄인다. `pivot_offset` 이 아래 가운데라 줄여도 바닥선이 그대로다.
func _make_art(tex: Texture2D, fallback_text: String) -> Control:
	var aspect: float = ART_PLACEHOLDER_ASPECT
	if tex != null:
		var ts: Vector2 = tex.get_size()
		if ts.y > 0.0:
			aspect = ts.x / ts.y
	var w: float = ART_H * aspect

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(w, ART_H)
	holder.pivot_offset = Vector2(w * 0.5, ART_H)

	if tex != null:
		var rect := TextureRect.new()
		rect.position = Vector2.ZERO
		rect.size = Vector2(w, ART_H)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 크기를 원본 비율로 이미 맞췄으므로 STRETCH_SCALE 이 정확히 채운다.
		# KEEP_ASPECT 계열은 여기서 레터박스를 한 번 더 계산할 뿐이다.
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture = tex
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		var slab := Panel.new()
		slab.position = Vector2.ZERO
		slab.size = Vector2(w, ART_H)
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		# 옅게 — 이 판은 "아직 그림이 없다"는 자리 표시이지 그림이 아니다.
		# 알파를 올리면 화면 절반을 차지하는 밝은 사각형이 되어 정작 앞에 선
		# 파일럿보다 눈에 띈다.
		sb.bg_color = Color(0.14, 0.15, 0.20, 0.30)
		sb.border_color = Color(0.42, 0.45, 0.56, 0.45)
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.corner_radius_top_left = 24
		sb.corner_radius_top_right = 24
		slab.add_theme_stylebox_override("panel", sb)
		holder.add_child(slab)

		var lbl := _make_label(fallback_text, 34, Color(0.78, 0.80, 0.88),
				HORIZONTAL_ALIGNMENT_CENTER)
		lbl.position = Vector2(0.0, ART_H * 0.42)
		lbl.size = Vector2(w, 60.0)
		holder.add_child(lbl)
	return holder


## 앞/뒤 자세를 적용한다. `animate` 면 두 노드가 자리를 맞바꾸는 과정이 보인다.
func _apply_focus(animate: bool) -> void:
	var front: Control = _art_pilot if _focus == Focus.PILOT else _art_mech
	var back: Control  = _art_mech if _focus == Focus.PILOT else _art_pilot
	# 앞에 선 쪽이 위에 그려져야 한다 — 형제 순서가 곧 z-order 다.
	_art_holder.move_child(back, 0)
	_art_holder.move_child(front, 1)

	if _swap_tween != null and _swap_tween.is_running():
		_swap_tween.kill()
	if animate:
		_swap_tween = _art_holder.create_tween().set_parallel() \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pose_art(front, true, animate)
	_pose_art(back, false, animate)


## 아트 한 장을 앞자리 / 뒷자리에 앉힌다. 뒷자리는 오른쪽으로 밀리고, 작아지고,
## 검게 딤드된다 — 셋 다 같은 트윈을 탄다.
func _pose_art(node: Control, is_front: bool, animate: bool) -> void:
	var x: float = ART_FRONT_CENTER_X - node.size.x * 0.5
	if not is_front:
		x += ART_BACK_SHIFT_PX
	var goal_pos := Vector2(x, ART_BOTTOM - ART_H)
	var goal_scale: Vector2 = Vector2.ONE if is_front \
			else Vector2(ART_BACK_SCALE, ART_BACK_SCALE)
	var goal_tint: Color = Color.WHITE if is_front else ART_BACK_TINT
	if animate and _swap_tween != null:
		_swap_tween.tween_property(node, "position", goal_pos, ART_SWAP_SEC)
		_swap_tween.tween_property(node, "scale", goal_scale, ART_SWAP_SEC)
		_swap_tween.tween_property(node, "modulate", goal_tint, ART_SWAP_SEC)
	else:
		node.position = goal_pos
		node.scale = goal_scale
		node.modulate = goal_tint


func _on_swap_pressed() -> void:
	_focus = Focus.MECH if _focus == Focus.PILOT else Focus.PILOT
	_apply_focus(true)
	_rebuild_stats()


# ─── 스탯 ────────────────────────────────────────────────────────────────────
# 전환마다 통째로 다시 세운다 — 파일럿 쪽은 3절(이름 · 인게임 · 파일럿), 메크
# 쪽은 1절이라 줄 수가 아예 다르다. 받침 Panel 을 **먼저** 넣어 글자 뒤에 깔고,
# 높이는 다 세운 뒤에 내용에 맞춰 준다.
func _rebuild_stats() -> void:
	if _stat_root != null and is_instance_valid(_stat_root):
		# 트리에서 **먼저** 뗀다 — `queue_free` 만 걸면 이번 프레임까지는 그대로
		# 그려져서 새 블록과 글자가 겹쳐 보인다.
		_root.remove_child(_stat_root)
		_stat_root.queue_free()
	_stat_root = Control.new()
	_stat_root.name = "StatColumn"
	_stat_root.position = Vector2.ZERO
	_stat_root.size = Vector2(VP_W, VP_H)
	_stat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stat_root)
	# 버튼 행보다 아래(= 뒤)에 두어 전환/닫기가 항상 위에 온다.
	if _stat_root.get_index() > 0:
		_root.move_child(_stat_root, 2)

	_stat_panel = Panel.new()
	_stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = STAT_PANEL_BG
	sb.border_color = STAT_PANEL_BORDER
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	_stat_panel.add_theme_stylebox_override("panel", sb)
	_stat_root.add_child(_stat_panel)

	var bottom: float = _build_stats()
	_stat_panel.position = Vector2(STAT_X, STAT_TOP) - STAT_PANEL_PAD
	_stat_panel.size = Vector2(STAT_W, bottom - STAT_TOP) + STAT_PANEL_PAD * 2.0


## 스탯 본문을 세우고 마지막 줄의 아래 y 를 돌려준다.
func _build_stats() -> float:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = pd.assigned_mech if pd != null else null
	var role_name: String = _bs.ROLE_NAMES[_pilot.role] \
			if _pilot.role < _bs.ROLE_NAMES.size() else "?"

	var y: float = STAT_TOP
	var display_name: String = pd.name if pd != null else _bs.pilot_label(_pilot)
	if _focus == Focus.MECH:
		display_name = mech.name if mech != null else "메크 미배정"
	var name_lbl := _make_label(display_name, 44, HEADER_COLOR,
			HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(STAT_X, y)
	name_lbl.size = Vector2(STAT_W, 54.0)
	_stat_root.add_child(name_lbl)
	y += 56.0

	var sub: String = "%s · %s · 성장치 %s" % [
		role_name,
		"아군" if _pilot.team == 0 else "적군",
		BattleSim.fmt_score(_pilot.score)]
	if _focus == Focus.MECH:
		sub = "%s 의 기체" % (pd.name if pd != null else _bs.pilot_label(_pilot))
	var sub_lbl := _make_label(sub, 22, KEY_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	sub_lbl.position = Vector2(STAT_X, y)
	sub_lbl.size = Vector2(STAT_W, 30.0)
	_stat_root.add_child(sub_lbl)
	y += 30.0 + SECTION_GAP

	if _focus == Focus.MECH:
		return _build_mech_stats(y, mech)
	return _build_pilot_stats(y, pd)


func _build_pilot_stats(start_y: float, pd: PlayerData) -> float:
	var y: float = start_y
	# ─ 인게임 전투 스탯 — 지금 이 전장에서의 상태.
	y = _section(y, "인게임")
	# 보호막은 별도 행이 아니라 **체력 뒤에 (+N)** 으로 붙는다 — 보호막은 그
	# 자체로 읽는 숫자가 아니라 "지금 몇 대 더 버티는가"이고, 그 답은 체력과
	# 나란히 놓여야 나온다. 0 이면 아예 안 적는다(빈 괄호는 노이즈다).
	var hp_txt: String = "%d" % _pilot.hp
	if _pilot.shield > 0:
		hp_txt += " (+%d)" % _pilot.shield
	y = _row(y, "체력", "%s / %d" % [hp_txt, _pilot.max_hp])
	y = _row(y, "공격력", "%d  (기본 %d)" % [_pilot.atk, _pilot.base_atk])
	# 성장은 공격력과 최대 체력이 **다른 속도**로 자란다(공격력이 4배 빠르다).
	# 한쪽만 적으면 다른 쪽이 안 자란 것처럼 읽히므로 둘을 한 줄에 적는다.
	y = _row(y, "성장", "공 +%.0f%% · 체 +%.0f%%" % [
		_pilot.growth * 100.0, _pilot.growth_hp * 100.0])
	# **명중 / 회피는 라인전 스탯이 먹은 값으로 적는다.** 카드(안전한 파밍 /
	# 공격적인 라인전)가 미는 것은 `hit` / `evasion` 필드가 아니라 판정 시점의
	# 배율(`PilotData.lane_stat_mod`)이라, 원본 필드를 그대로 찍으면 카드를 내도
	# 이 줄이 1 도 움직이지 않는다 — 판정과 같은 함수(`SimulationCore.lane_adjusted`)
	# 를 통과시켜야 화면의 숫자가 실제로 굴러가는 숫자와 같아진다.
	var eff_hit: int = _bs.sim_core.lane_adjusted(_pilot.hit, _pilot)
	var eff_eva: int = _bs.sim_core.lane_adjusted(_pilot.evasion, _pilot)
	var hitrow: String = "%d / %d" % [eff_hit, eff_eva]
	if not is_zero_approx(_pilot.lane_stat_mod):
		hitrow += "  (기본 %d / %d)" % [_pilot.hit, _pilot.evasion]
	y = _row(y, "명중 / 회피", hitrow)
	# ─ 카드가 걸어 둔 일시 효과. **걸려 있을 때만** 줄이 생긴다 — 늘 `없음`
	# 이라고 적혀 있으면 정작 걸렸을 때 눈에 띄지 않는다.
	if not is_zero_approx(_pilot.lane_stat_mod):
		y = _row(y, "라인전 스탯", "%+d%%%s" % [
			roundi(_pilot.lane_stat_mod * 100.0),
			_remain_txt(_pilot.lane_stat_expire_turn, false)])
	if not is_equal_approx(_pilot.growth_rate_mult, 1.0):
		y = _row(y, "성장 획득", "%+d%%%s" % [
			roundi((_pilot.growth_rate_mult - 1.0) * 100.0),
			_remain_txt(_pilot.growth_rate_expire_turn, _pilot.growth_until_phase)])
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
	return y


## 일시 효과의 남은 수명을 괄호 한 덩이로. 턴 만료형(안전한 파밍 / 공격적인
## 라인전)은 남은 턴 수, 단계 만료형(완벽한 마무리)은 "작전 단계까지". 둘 다
## 아니면 빈 문자열이라 값 뒤에 아무것도 붙지 않는다.
func _remain_txt(expire_turn: int, until_phase: bool) -> String:
	if until_phase:
		return "  (작전 단계까지)"
	if expire_turn < 0:
		return ""
	return "  (%d턴)" % maxi(0, expire_turn - _bs.turn_count)


# 배정된 기체. speed 스탯은 삭제됐다(교전이 턴제가 되면서).
func _build_mech_stats(start_y: float, mech: MechData) -> float:
	var y: float = _section(start_y, "메크")
	if mech == null:
		return _row(y, "—", "미배정")
	y = _row(y, "기체", mech.name)
	y = _row(y, "체력", str(mech.hp))
	y = _row(y, "공격력", str(mech.atk))
	y = _row(y, "존재감", str(mech.presence))
	return y


func _section(y: float, title: String) -> float:
	var lbl := _make_label(title, 26, SECTION_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.position = Vector2(STAT_X, y)
	lbl.size = Vector2(STAT_W, 34.0)
	_stat_root.add_child(lbl)
	var line := ColorRect.new()
	line.color = Color(SECTION_COLOR.r, SECTION_COLOR.g, SECTION_COLOR.b, 0.35)
	line.position = Vector2(STAT_X, y + 34.0)
	line.size = Vector2(STAT_W, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_root.add_child(line)
	return y + 42.0


func _row(y: float, key: String, value: String) -> float:
	var k := _make_label(key, 24, KEY_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	k.position = Vector2(STAT_X, y)
	k.size = Vector2(STAT_W * KEY_FRACTION, ROW_H)
	k.clip_text = true
	_stat_root.add_child(k)
	var v := _make_label(value, 26, VALUE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	v.position = Vector2(STAT_X + STAT_W * KEY_FRACTION, y)
	v.size = Vector2(STAT_W * (1.0 - KEY_FRACTION), ROW_H)
	# **clip_text 는 필수다.** 오른쪽 정렬 Label 은 글자가 rect 보다 넓으면
	# 정렬을 포기하고 rect 왼쪽부터 그려서 **오른쪽으로 넘쳐 화면을 벗어난다**
	# (실측: "아웃게임 데이터 없음" 이 화면 밖에서 잘렸다). 자르는 편이 낫다.
	v.clip_text = true
	_stat_root.add_child(v)
	return y + ROW_H


# ─── 버튼 행 ─────────────────────────────────────────────────────────────────
# 전환은 정보 블록의 **왼쪽 아래**, 닫기는 같은 줄 오른쪽 끝.
func _build_buttons() -> void:
	var swap := Button.new()
	swap.text = "전환"
	swap.add_theme_font_size_override("font_size", 28)
	swap.position = Vector2(STAT_X, BTN_Y)
	swap.size = Vector2(BTN_W, BTN_H)
	swap.focus_mode = Control.FOCUS_NONE
	swap.pressed.connect(_on_swap_pressed)
	_root.add_child(swap)

	var btn := Button.new()
	btn.text = "닫기"
	btn.add_theme_font_size_override("font_size", 28)
	btn.position = Vector2(STAT_X + STAT_W - BTN_W, BTN_Y)
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
