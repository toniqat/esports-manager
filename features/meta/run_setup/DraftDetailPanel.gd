class_name DraftDetailPanel
extends CanvasLayer

# 파일럿 상세 팝업 — **아웃게임에서 파일럿 한 명을 들여다보는 유일한 자리**다.
#
#   좌: 전신 아트 한 장
#   우: 머리글(이름 · 역할 · 원소속) → 스탯 칩 6개 → 파일럿 스킬
#   하: 닫기
#
# 여는 자리가 둘이다 — **런 준비 편성**(선택 슬롯의 상체 일러스트를 누른다,
# 고른 레벨이 반영된 사본이 넘어온다)과
# **밴픽의 배정 단계**(양 팀 파일럿 초상화를 누른다). 그래서 이 팝업은
# `TeamDraft` 인스턴스를 요구하지 않는다 — 필요한 것은 `PlayerData` 한 장과
# 오토로드 `GameManager` 뿐이다.
#
# **파일럿 카드 3장을 보여 준다.** 파일럿 카드는 이제 **선수마다 고정**이라
# (`GameManager.pilot_card_ids_for` — `players.pilot_cards`, 비었으면 선수 id 를
# 씨앗 삼은 결정적 뽑기) 여기서 본 3장이 인게임에서 손에 잡히는 바로 그 3장이고,
# 같은 역할이라도 선수마다 다르므로 **선수를 고르는 판단에 들어간다**. 카드는
# 설명판(`CardDescBox`, 흰 판)으로 쌓는다 — 키워드 줄과 풀이가 함께 붙는다.
#
# 예전에는 3장이 경기 시작 시 표집돼 드래프트에서 보여 줄 것이 역할별 후보 풀뿐
# 이었고, 그 목록은 누구를 뽑아도 같아서 절째로 지웠었다.
#
# 인게임의 `features/battle_sim/ui/PilotDetailPanel.gd` 와 **같은 언어**를 쓰되
# 같은 클래스가 아니다 — 저쪽은 `BattleSim` 오케스트레이터와 `PilotData`(런타임
# 상태)에 매달려 있고 이쪽이 가진 것은 `PlayerData`(시즌 영속 데이터)뿐이라,
# 상속으로 잇는 길은 저쪽의 `_bs` 의존을 통째로 선택적으로 만드는 일이 된다.
# 공유하는 것은 **모양**(좌 아트 / 우 칩 · 섹션)이지 구현이 아니다.
#
# **레이아웃의 정본은 `DraftDetailPanel.tscn` 이다.** 이 스크립트는 정적 노드를 만들지
# 않는다 — `%이름` 노드에 글을 넣고, 데이터마다 달라지는 조각만 코드로 붙인다:
# 스탯 칩(`DraftStatChip.tscn` 일곱 칸, 처음 한 번), 돌파 알약 칩(`OutgameTheme.add_chip` —
# 칩마다 색이 다르다), 스킬 아이콘 타일(`SkillImages.make_icon_tile`), 스킬 설명
# RichTextLabel(`StrategyIcon.make_rich_label`), 파일럿 카드 설명판(`CardDescBox.build`).
# 색 · 스타일박스는 `Root` 에 붙은 공용 테마(`resources/OutgameTheme.tres`)의 변형
# (`DimPanel` · `Card` · `SunkPanel` · `GhostButton` · `*Label`)이 정한다. 코드가 정하는
# 색은 역할 색(머리글 둘째 줄) 하나다 — 데이터가 정하는 색이다.
#
# **우측 본문은 여전히 스크롤된다.** 카드 격자가 빠져 지금은 대개 한 화면에
# 들어가지만, 스킬 설명문은 길이가 제각각이라 넘칠 때가 남는다 — 넘치면 잘리는
# 대신 굴러가야 한다. 닫기 버튼은 스크롤 **밖** 고정이다 — 목록 끝까지 내려가야
# 닫을 수 있는 모달은 모달이 아니다.
#
# 쓰는 법:
#   var d := DraftDetailPanel.create()
#   add_child(d)
#   d.open(player_data)

## 받침(`%PanelBox`)이 자랄 수 있는 최대 높이 — 위끝은 씬이 150 에 못박고, 이 높이를
## 넘는 내용은 `%Scroll` 이 굴린다(아래끝 1740). 그 아래에 닫기 버튼(16 간격 + 84)이 붙는다.
const PANEL_MAX_H: float = 1590.0

const SCENE_PATH: String = "res://features/meta/run_setup/DraftDetailPanel.tscn"

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
## 역할 색은 팔레트가 소유한다 — 화면마다 자기 배열을 들면 같은 역할이
## 화면마다 다른 색으로 그려진다.
const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

## 칩 목록 — 선수 스탯 여섯에 "종합" 한 칸을 더한다(3열 × 세 줄 중
## 마지막 두 칸은 비운다). 글자는 짧은 쪽을 쓴다 — 칩 한 칸이 130px 남짓이라
## "전장 명중" 은 들어가지만 줄바꿈 없이 꽉 차서 값과 붙어 보인다.
const STAT_KEYS: Array = ["전장 명중", "전장 회피", "교전 명중",
		"교전 회피", "공격 성장", "체력 성장"]

# ─── 코드가 만드는 위젯의 인자 (스킬 타일 · 설명문 · 돌파 칩) ────────────────
const SKILL_TILE_BG := OutgameTheme.RAIL
const SKILL_TILE_ICON := OutgameTheme.ACCENT
const SKILL_TILE_SHADOW := Color(0.11, 0.11, 0.18, 0.28)
const SKILL_TILE_SHADOW_PX: float = 14.0
const SKILL_DESC_FONT: int = 21
const SKILL_DESC_COLOR := OutgameTheme.TEXT
## 설명 RichTextLabel 의 "knock" 색 = 받침 색.
const PANEL_BG := OutgameTheme.SURFACE
const BT_CHIP_H: float = 36.0
const BT_CHIP_FONT: int = 20

var _pilot: PlayerData = null
var _chips: Array = []


## 씬을 인스턴스한다. `DraftDetailPanel.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> DraftDetailPanel:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as DraftDetailPanel
	p.visible = false
	return p


func _ready() -> void:
	# 딤은 클릭을 먹어 뒤의 화면으로 새지 않게 하고, 빈 곳을 누르면 닫힌다.
	# 받침(`Backdrop`, STOP) 위 누름은 딤까지 내려가지 않는다.
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`).
	DragScroll.attach(%Scroll)
	for i in STAT_KEYS.size() + 1:      # 스탯 여섯 + 종합
		var chip := DraftStatChip.create()
		%Stats.add_child(chip)
		_chips.append(chip)


## 팝업을 연다. 필요한 것은 파일럿 한 명뿐이다 — 스킬 행과 파일럿 카드는
## 오토로드 `GameManager` 에서 직접 읽는다. 노드는 재사용한다(매번 다시 만들지 않음).
func open(p: PlayerData) -> void:
	close()
	_pilot = p
	if p == null:
		return
	_fill_art()
	_fill_header()
	_fill_stats()
	_fill_skill()
	_fill_pilot_cards()
	_fit_panel()
	(%Scroll as ScrollContainer).scroll_vertical = 0
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## 스크롤 안쪽 폭 — 받침 폭에서 `%Pad` 여백을 뺀 값. 설명문 높이 계산과 카드
## 설명판 폭이 이 값을 쓴다(씬에서 폭 · 여백을 고치면 따라온다).
func _inner_w() -> float:
	var pad: MarginContainer = %Pad
	return (%Column as Control).size.x - float(pad.get_theme_constant("margin_left")) \
			- float(pad.get_theme_constant("margin_right"))


# ── Fill ─────────────────────────────────────────────────────────────────────
## 높이 정규화 — `%Art` 는 세로 1400 · 가로 넉넉한 칸에 `KEEP_ASPECT_CENTERED` 라
## 아트마다 인물 키가 같고 가로 가운데(x 300)에 선다. 다리 아랫부분은 화면 밖(2010)으로
## 잘려 나간다. 폭으로 맞추면 아트마다 인물 키가 제각각이 된다. 아트가 없으면 회색 판.
func _fill_art() -> void:
	var tex: Texture2D = PilotImages.full_for(_pilot.id)
	var art: TextureRect = %Art
	art.texture = tex
	art.visible = tex != null
	%ArtPlaceholder.visible = tex == null
	if tex == null:
		return
	# 칸 폭을 아트 비율에 맞춰 좁힌다 — 가운데 · 높이는 씬 값 그대로. 넉넉한 칸에
	# 가운데 정렬로만 두어도 같은 자리지만 소수점 위치가 칸 안쪽으로 옮겨 가
	# 다시 샘플링되면서 윤곽이 반 픽셀 번진다.
	var cx: float = (art.offset_left + art.offset_right) * 0.5
	var w: float = (art.offset_bottom - art.offset_top) \
			* float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	art.offset_left = cx - w * 0.5
	art.offset_right = cx + w * 0.5


func _fill_header() -> void:
	%Name.text = _pilot.name
	var r: int = int(_pilot.role)
	var role_name: String = String(ROLE_NAMES[r]) if r >= 0 and r < ROLE_NAMES.size() else "?"
	var role_col: Color = ROLE_COLORS[r] if r >= 0 and r < ROLE_COLORS.size() else OutgameTheme.TEXT
	var slot: int = TeamDraft.slot_of_role(r)
	var slot_name: String = String(TeamDraft.SLOT_NAMES[slot]) if slot >= 0 else "?"
	var sub: Label = %Sub
	sub.text = "%s · %s · 원소속 %s" % [slot_name, role_name, _team_short(_pilot.team_id)]
	sub.add_theme_color_override("font_color", role_col)
	# M10 — breakthrough stage. The copy handed in already carries it (stats, salary,
	# swapped pilot card: `RunRules.apply_breakthrough` on the pool / run copies), so
	# this chip only names *why* the numbers below differ from the base pilot.
	_clear(%BtChips)
	%BtRow.visible = _pilot.breakthrough > 0
	if _pilot.breakthrough > 0:
		_bt_chip("돌파 %d" % _pilot.breakthrough, OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT)
		if _pilot.train_bonus_pct != 0:
			_bt_chip("훈련 EXP +%d%%" % _pilot.train_bonus_pct,
					OutgameTheme.SURFACE_SUNK, OutgameTheme.TEXT)


## Header pill sized to its text (`%BtChips` lines them up).
func _bt_chip(text: String, bg: Color, fg: Color) -> void:
	var cw: float = 28.0 + 13.0 * float(text.length())
	var chip: Panel = OutgameTheme.add_chip(%BtChips, text, Vector2.ZERO,
			Vector2(cw, BT_CHIP_H), bg, fg, BT_CHIP_FONT)
	chip.custom_minimum_size = chip.size


func _fill_stats() -> void:
	for i in _chips.size():
		var is_total: bool = i == STAT_KEYS.size()
		var key: String = "종합" if is_total else String(STAT_KEYS[i])
		var val: int = PilotThumb.total_stats(_pilot) if is_total \
				else int(_pilot.get(String(PlayerData.STAT_KEYS[i])))
		(_chips[i] as DraftStatChip).fill(key, str(val), is_total)


func _fill_skill() -> void:
	_clear(%SkillTile)
	_clear(%SkillDesc)
	var sk: Dictionary = _skill_def()
	# 모브는 여기서 자기 정체를 말한다 — 스탯 하향보다 이쪽이 크다.
	%NoSkill.visible = sk.is_empty()
	%SkillRow.visible = not sk.is_empty()
	%SkillDesc.visible = not sk.is_empty()
	if sk.is_empty():
		return

	# 타일 크기 = 씬의 `%SkillTile` 칸 크기.
	var tile_slot: Control = %SkillTile
	tile_slot.add_child(SkillImages.make_icon_tile(String(sk.get("key", "")),
			tile_slot.size.x, SKILL_TILE_BG, SKILL_TILE_ICON, SKILL_TILE_SHADOW,
			SKILL_TILE_SHADOW_PX))
	%SkillName.text = String(sk.get("name", "?"))
	var meta: String = TeamDraft.skill_type_label(String(sk.get("type", "")))
	var kw: String = String(sk.get("keyword", ""))
	if not kw.is_empty():
		meta += " · " + kw
	%SkillMeta.text = meta
	_rich_paragraph(%SkillDesc, String(sk.get("description", "")))


## 이 선수의 고정 파일럿 카드 3장 — 설명판을 위에서부터 쌓는다(`%Cards` 간격).
func _fill_pilot_cards() -> void:
	_clear(%Cards)
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var w: float = _inner_w()
	for raw in gm.pilot_card_ids_for(_pilot):
		var def: Dictionary = gm.card_def(int(raw))
		if def.is_empty():
			continue
		var box := CardDescBox.build(CardData.from_def(def), w, true)
		# 높이만 최소로 준다. 폭까지 주면 `%Scroll` 의 최소 폭이 "본문 + 스크롤 막대"가
		# 되어, 막대가 켜지는 순간 `%Pad` 가 받침 밖으로 4px 씩 벌어지고 막대가 꺼져도
		# 돌아오지 않는다(ScrollContainer 가 최소 크기 변화를 다시 알리지 않는다).
		box.custom_minimum_size = Vector2(0.0, box.size.y)
		%Cards.add_child(box)


## Rich description paragraph — skill descriptions carry `\n` breaks,
## `{eul}` particle tags, keyword icons and `[card name]` tokens, so this is
## `StrategyIcon.make_rich_label` on light-theme colours (same as the light
## `CardDescBox`). **The height comes from `StrategyIcon.rich_height`** —
## measuring by hand lets a long description overlap the block below.
func _rich_paragraph(holder: Control, text: String) -> void:
	var costs: Dictionary = {}
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		costs = gm.card_costs_by_name()
	var w: float = _inner_w()
	var lbl := StrategyIcon.make_rich_label(text, SKILL_DESC_FONT, SKILL_DESC_COLOR,
			OutgameTheme.ACCENT_TEXT, PANEL_BG, KeywordIcon.TARGET_ANY_COLOR,
			KeywordIcon.TARGET, KeywordIcon.SPECIAL_COLOR_LIGHT, costs)
	var h: float = StrategyIcon.rich_height(text, w, SKILL_DESC_FONT, costs)
	lbl.position = Vector2.ZERO
	lbl.size = Vector2(w, h)
	holder.add_child(lbl)
	holder.custom_minimum_size = Vector2(0, h)


## **받침 높이는 내용이 정한다** — 위쪽은 씬이 못박고 아래끝만 내용에 맞춰
## 올라온다(넘치면 `PANEL_MAX_H` 에서 멈추고 그때부터 스크롤이 일한다). 스탯 칩과
## 스킬 한 문단뿐인 선수에서 고정 높이로 두면 받침 아래 절반이 텅 빈 흰 판으로 남는다.
## 닫기 버튼은 `%Column` 에서 받침 바로 아래에 붙어 따라다닌다 — 고정 y 에 두면
## 내용이 짧은 파일럿에서 버튼만 허공에 뜬다.
func _fit_panel() -> void:
	var pad: MarginContainer = %Pad
	var content_h: float = (%Body as Control).get_combined_minimum_size().y \
			+ float(pad.get_theme_constant("margin_top")) \
			+ float(pad.get_theme_constant("margin_bottom"))
	var box: Control = %PanelBox
	var h: float = minf(content_h, PANEL_MAX_H)
	box.custom_minimum_size.y = h
	# 높이만 내용으로 줄인다(폭은 씬 그대로) — VBox 는 스스로 줄지 않는다.
	var col: Control = %Column
	col.size = Vector2(col.size.x, 0.0)


## 다시 열 때 이전 파일럿의 코드 조각을 걷어 낸다. `queue_free` 는 프레임 끝에야
## 지우므로 먼저 떼어 낸다 — 남아 있으면 이번 높이 계산에 섞인다.
func _clear(holder: Node) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()


## 이 선수의 고유 스킬 행. 모브(스킬 없음)는 빈 Dictionary 를 돌려준다.
func _skill_def() -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or _pilot == null or _pilot.skill_id < 0:
		return {}
	return gm.skill_def(_pilot.skill_id)


func _team_short(team_id: int) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return "T%d" % team_id
	var meta: Array = gm.season_state.get("team_meta", [])
	# 런 준비(편성)에서는 시즌이 아직 열리지 않아 team_meta 가 비어 있다 —
	# 그때는 팀 패키지 표(`teams.csv`)에서 같은 약칭을 찾는다.
	if meta.is_empty():
		meta = RunRules.team_packages()
	if team_id < 0 or team_id >= meta.size():
		return "T%d" % team_id
	return String(meta[team_id]["short_name"])
