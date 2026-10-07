class_name MvpView
extends CanvasLayer

# 경기 MVP 전용 뷰 — 경기가 끝나는 순간(`BattleSim.end_match`) 승패 결과 화면보다
# **먼저** 뜨는 한 장. 이긴 팀 다섯 중 `RunStats.mvp_score` 최고 1명의 전신
# 일러스트(`PilotImages.full_for` — 모브는 실루엣 컷으로 자동 전환)를 세우고,
# 이름 · 진영 · 역할 · K/D/A · 핵심 지표 한 줄을 그 아래에 놓는다.
# "계속"(또는 잠깐 뒤 화면 아무 곳 탭) → `closed` → 기존 결과 화면.
#
# **레이아웃의 정본은 `MvpView.tscn` 이다.** 이 스크립트는 `%이름` 노드에 글 · 그림을
# 넣고 시그널만 잇는다. 색 · 판은 `Root` 에 붙은 전투 테마(`resources/BattleTheme.tres`)의
# 변형(`MvpDimPanel` · `MvpTitleLabel` · `BattleGoldPanel` · `BattleOutlinedLabel` ·
# `MvpAllyLabel`/`MvpEnemyLabel` · `MvpSubLabel` · `BattleSlab` · `BattleGoldButton`)이 정한다.
# 코드가 정하는 것: 안전 영역(`%SafeArea` 위아래 오프셋 — 아래 버튼이 제스처 띠 위에
# 선다, docs/mobile_safe_area.md), 진영 줄 변형(아군 / 상대), 전신 크기(그림 비율 ·
# `%ArtArea` 높이 — `_layout_art`), 후광 색(`BattleTheme.GLOW`), 등장 연출.
#
# 쓰는 법:
#   var v := MvpView.create()
#   add_child(v)
#   v.closed.connect(...)
#   v.open(bs, pilot, row)

signal closed

const SCENE_PATH: String = "res://features/battle_sim/ui/MvpView.tscn"

## 다른 오버레이(교전 · 상세 패널 …) 위. 씬의 `layer` 와 같은 값(결과 화면이 읽는다).
const OVERLAY_LAYER := 60
## 전신 최대 크기(디자인 px) — 칸이 이보다 크면 후광 · 전신은 이 크기에서 멈춘다.
const ART_MAX_H := 1000.0
const ART_MAX_W := 900.0
## 그림이 없을 때 자리 표시 판의 가로 / 세로 비율.
const FALLBACK_ASPECT := 0.45
## 전신이 떠오르는 거리(px).
const ART_RISE := 40.0
## 아무 곳이나 눌러 넘기기를 받기 시작하는 시점(s) — 경기를 끝낸 바로 그 탭이
## 뷰를 곧장 닫아 버리지 않게 한다.
const TAP_ARM_SEC := 0.8
const FADE_SEC := 0.35

var _art_tex: Texture2D = null
var _armed: bool = false
var _closing: bool = false


## 씬을 인스턴스한다. `MvpView.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> MvpView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MvpView


func _ready() -> void:
	$Root.gui_input.connect(_on_root_input)
	%Continue.pressed.connect(close)
	%ArtArea.resized.connect(_layout_art)
	var grad := (%Glow.texture as GradientTexture2D).gradient
	grad.set_color(0, BattleTheme.GLOW)
	grad.set_color(1, Color(BattleTheme.GLOW, 0.0))
	if UiPreview.is_standalone(self):
		_fill_preview()


## 뷰를 채우고 등장시킨다. `row` 는 `BattleSim.build_pilot_stats` 의 그 선수 한 줄.
## `bs` 가 null 이면(미리보기) 이름은 역할 + 팀 번호 대신 비어 있다.
func open(bs: BattleSim, p: PilotData, row: Dictionary) -> void:
	_fit_safe_area()
	var ally: bool = p.team == 0
	%Name.text = display_name(bs, p)
	%Side.text = "%s · %s" % ["아군" if ally else "상대 팀", role_label(p)]
	%Side.theme_type_variation = &"MvpAllyLabel" if ally else &"MvpEnemyLabel"
	%Kda.text = kda_text(row)
	%Metric.text = metric_text(row)

	_art_tex = PilotImages.full_for(portrait_id(p))
	%Art.texture = _art_tex
	%Art.visible = _art_tex != null
	%Slab.visible = _art_tex == null
	%FallbackLabel.text = String(bs.ROLE_FULL_NAMES[p.role]) \
			if bs != null and p.role < bs.ROLE_FULL_NAMES.size() else ""
	_layout_art()

	# 등장 — 전신이 살짝 떠오르며 밝아진다.
	var root: Control = $Root
	root.modulate.a = 0.0
	var holder: Control = %ArtHolder
	holder.position.y = ART_RISE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, FADE_SEC)
	tw.tween_property(holder, "position:y", 0.0, FADE_SEC * 1.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(TAP_ARM_SEC).timeout.connect(func() -> void: _armed = true)


## 뷰를 닫는다(한 번만). 버튼 · 탭 · 헤드리스 검증이 같은 길을 탄다.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()


## 제목은 안전 영역 위끝에서, 버튼 · 정보 판은 안전 영역 아래끝에서 잰다.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## 후광은 칸 위끝부터 `ART_MAX_H` 까지, 전신은 칸 아래 가운데에 그림 비율대로
## (`ART_MAX_W` 를 넘으면 폭에 맞춰 줄인다). 그림이 없으면 같은 자리에 판.
func _layout_art() -> void:
	var area: Control = %ArtArea
	var h: float = minf(ART_MAX_H, area.size.y)
	%Glow.offset_bottom = h
	var aspect: float = FALLBACK_ASPECT
	if _art_tex != null and _art_tex.get_size().y > 0.0:
		aspect = _art_tex.get_size().x / _art_tex.get_size().y
	var w: float = minf(ART_MAX_W, h * aspect)
	h = w / aspect
	for n: Control in [%Art, %Slab]:
		n.offset_left = -w * 0.5
		n.offset_right = w * 0.5
		n.offset_top = -h
		n.offset_bottom = 0.0


func _on_root_input(event: InputEvent) -> void:
	if not _armed:
		return
	var tapped: bool = (event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tapped:
		close()


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


## F6 단독 실행 미리보기 — 손으로 만든 파일럿 한 명(그림 있는 0번)으로 연다
## (`resources/UiPreview.gd`). 전투가 없어 이름은 여기서 넣는다.
func _fill_preview() -> void:
	UiPreview.trace(closed)
	var p := PilotData.new(2, 0, Vector2i.ZERO, {"hp": 100, "atk": 10})
	p.pilot_id = 0
	open(null, p, {"k": 7, "d": 2, "a": 11, "role": p.role,
			"dmg": 12345, "taken": 6789, "care": 0})
	%Name.text = "미리보기 선수"
