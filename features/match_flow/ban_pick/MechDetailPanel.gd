class_name MechDetailPanel
extends CanvasLayer

# 메크 상세 팝업 — 배정 단계에서 **메크 초상화를 누르면** 열린다.
#
#   좌: 전신 아트 한 장
#   우: 머리글(기체명 · 역할군) → 스탯 칩 3개 → 메크 패시브 → 메크 카드
#   (in a season run a mastery block sits between the stat chips and the passive
#    — `open(m, mastery_rows)`, rows built by `BanPickController._mastery_rows`)
#   하: 닫기
#
# `features/meta/run_setup/DraftDetailPanel.gd`(파일럿 상세)와 **좌우 구성이
# 같다** — 배정 단계에서는 같은 줄의 얼굴과 기체를 번갈아 누르게 되므로, 둘이
# 다른 모양으로 열리면 무엇을 보고 있는지가 매번 새로 읽힌다. 공유하는 것은
# 그 모양이지 구현이 아니다: 이쪽이 다루는 것은 `MechData` 와 메크 카드 표이고
# 저쪽은 `PlayerData` 와 파일럿 스킬 표다.
#
# **인게임 상세 패널(`battle_sim/ui/PilotDetailPanel.gd`)과는 다르다** — 그쪽은
# 파일럿과 메크를 한 화면에 겹쳐 세우고 인게임 탭(체력 · 공격력 · 지속 효과)을
# 앞세우지만, 밴픽은 아직 경기가 시작되지 않아 인게임 상태라는 것이 없다.
#
# **레이아웃의 정본은 `MechDetailPanel.tscn` 이다.** 이 스크립트는 정적 노드를 만들지
# 않는다 — `%이름` 노드에 글을 넣고, 데이터마다 개수가 달라지는 줄만 아이템 씬으로
# 붙인다: 숙련도 줄(`MechMasteryRow.tscn`), 기벽 줄(`MechQuirkRow.tscn`), 메크 카드 칸
# (`MechCardCell.tscn`), 그리고 카드를 누르면 뜨는 설명판(`CardDescBox.build`).
# 이 팝업은 **어두운 모달**이라 흰 종이용 공용 테마 변형이 맞지 않는다 — 받침 · 칩 ·
# 닫기 버튼의 스타일박스와 글자 색은 씬의 로컬 값이다. 코드가 정하는 색은 데이터 색
# (역할 색, 숙련 등급 색, 기벽 등급 색, 장수 배지 색)뿐이다.
#
# 쓰는 법:
#   var d := MechDetailPanel.create()
#   add_child(d)
#   d.open(mech_data, mastery_rows, quirk_info)

const SCENE_PATH: String = "res://features/match_flow/ban_pick/MechDetailPanel.tscn"

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]

## 카드를 누르면 뜨는 설명판의 폭 — 받침(`Backdrop`) 폭과 같다.
const DESC_W: float = 460.0

var _mech: MechData = null
## 누른 카드의 설명판(`CardDescBox`) — 카드 앞면에 설명문이 없으므로 그 글은
## 카드를 누르면 카드 **위쪽**에 뜨는 이 판이 든다. 같은 카드를 다시 누르면 닫힌다.
var _desc_box: Panel = null
var _desc_node: Card = null


## 씬을 인스턴스한다. `MechDetailPanel.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> MechDetailPanel:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as MechDetailPanel
	p.visible = false
	return p


func _ready() -> void:
	# 딤은 클릭을 먹어 뒤의 배정판으로 새지 않게 하고, 빈 곳을 누르면 닫힌다.
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`).
	DragScroll.attach(%Scroll)


## `mastery_rows` — `[{name, value, tier, bonus, current}]` (BanPickController
## `_mastery_rows`), empty outside a season run or for an unanalysed enemy.
## `quirk_info` — quirks of the tapped seat's pilot (my side only, §14):
## `{pilot, slots, total, rows: [{name, grade, effect, active}]}`.
## 노드는 재사용한다(매번 다시 만들지 않음).
func open(m: MechData, mastery_rows: Array = [], quirk_info: Dictionary = {}) -> void:
	close()
	_mech = m
	if m == null:
		return
	_fill_art()
	_fill_header()
	_fill_stats()
	_fill_mastery(mastery_rows)
	_fill_quirks(quirk_info)
	_fill_passive()
	_fill_cards()
	(%Scroll as ScrollContainer).scroll_vertical = 0
	visible = true


func close() -> void:
	_hide_card_desc()
	visible = false


func is_open() -> bool:
	return visible


# ── Fill ─────────────────────────────────────────────────────────────────────
## **높이로 정규화하지 않는다.** 메크 아트는 1024×1024 고정 캔버스라 파일럿
## 아트(가변 폭 × 1024)처럼 높이를 맞추면 폭이 그대로 1400 이 되어 오른쪽
## 정보 패널을 통째로 덮는다. 대신 씬의 `%Art` 상자 안에서 `KEEP_ASPECT_CENTERED` 로
## 앉히므로 기체마다 본체 겉보기 크기가 고르게 남는다. 아트가 없으면 회색 판 + 이름.
func _fill_art() -> void:
	var tex: Texture2D = MechImages.full_for(_mech.id)
	(%Art as TextureRect).texture = tex
	%Art.visible = tex != null
	%ArtPlaceholder.visible = tex == null
	%ArtName.text = _mech.name


func _fill_header() -> void:
	%Name.text = _mech.name
	var r: int = int(_mech.role)
	var sub: Label = %Sub
	sub.text = String(ROLE_NAMES[r]) if r >= 0 and r < ROLE_NAMES.size() else "?"
	sub.add_theme_color_override("font_color",
			ROLE_COLORS[r] if r >= 0 and r < ROLE_COLORS.size() else Color(1, 1, 1))


func _fill_stats() -> void:
	%HpValue.text = str(int(_mech.hp))
	%AtkValue.text = str(int(_mech.atk))
	%PresenceValue.text = str(int(_mech.presence))


## Mastery of each pilot of that team with this mech — the pilot on the tapped
## seat is marked ▶ and drawn bright. The block hides when there are no rows.
func _fill_mastery(rows: Array) -> void:
	_clear(%MasteryRows)
	%MasteryBlock.visible = not rows.is_empty()
	for raw in rows:
		var row := MechMasteryRow.create()
		%MasteryRows.add_child(row)
		row.fill(raw)


## Quirks of the tapped seat's pilot with this mech: head `기벽 — name n/slots
## (스탯 +total)`, then per quirk a grade-coloured name and its effect line.
func _fill_quirks(info: Dictionary) -> void:
	_clear(%QuirkRows)
	%QuirkBlock.visible = not info.is_empty()
	if info.is_empty():
		return
	var rows: Array = info.get("rows", [])
	%QuirkTitle.text = "기벽 — %s  %d / %d  (스탯 +%d)" % [
			String(info.get("pilot", "")), rows.size(),
			int(info.get("slots", 0)), int(info.get("total", 0))]
	%QuirkEmpty.visible = rows.is_empty()
	for raw in rows:
		var row := MechQuirkRow.create()
		%QuirkRows.add_child(row)
		row.fill(raw)


func _fill_passive() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	var pas: Dictionary = gm.mech_passive_def(_mech.id) if gm != null else {}
	# 21대 중 15대만 패시브를 갖는다 — 없는 것이 결함이 아니라 그 기체의
	# 성질이므로 한 줄로 말해 준다(`%NoPassive`).
	%NoPassive.visible = pas.is_empty()
	%PassiveBox.visible = not pas.is_empty()
	if pas.is_empty():
		return
	%PassiveName.text = String(pas.get("name", "?"))
	var kw: String = String(pas.get("keyword", ""))
	%PassiveKw.text = kw
	%PassiveKw.visible = not kw.is_empty()
	%PassiveDesc.text = String(pas.get("description", ""))


## 메크 카드 격자 — 인게임 파일럿 상세 패널(`battle_sim/ui/PilotDetailPanel`)의 카드
## 격자와 **같은 축소율 · 같은 열 수**다(축소율은 `MechCardCell.tscn`, 열 수는 `%CardGrid`).
func _fill_cards() -> void:
	_clear(%CardGrid)
	var gm: Node = get_node_or_null("/root/GameManager")
	var defs: Array = gm.mech_cards_for(_mech.id) if gm != null else []
	%NoCards.visible = defs.is_empty()
	%CardsBox.visible = not defs.is_empty()
	for raw in defs:
		var cell := MechCardCell.create()
		%CardGrid.add_child(cell)
		cell.fill(raw)
		cell.tapped.connect(_toggle_card_desc)


func _toggle_card_desc(node: Card) -> void:
	var same: bool = node == _desc_node
	_hide_card_desc()
	if same or node == null or not is_instance_valid(node) or node.data == null:
		return
	var root: Control = %Root
	_desc_box = CardDescBox.build(node.data, DESC_W)
	root.add_child(_desc_box)
	CardDescBox.place_near(_desc_box, node.get_global_rect(), root.size, true)
	_desc_node = node


func _hide_card_desc() -> void:
	if _desc_box != null and is_instance_valid(_desc_box):
		_desc_box.queue_free()
	_desc_box = null
	_desc_node = null


## 다시 열 때 이전 기체의 줄을 걷어 낸다. `queue_free` 는 프레임 끝에야 지우므로
## 먼저 떼어 낸다 — 남아 있으면 이번 배치에 섞인다.
func _clear(holder: Node) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
