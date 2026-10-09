class_name CardData
extends Resource

# 시전자 제약 값 (cards.csv `scope` 컬럼). **포지션 목록**이다 — `|` 로 이은
# jungle / top / mid / carry / support(`GameEnums.POSITION_KEYS`). 두 별칭이 있다:
#   `any`  단독 = 다섯 포지션 전부
#   `lane` 단독 = 탑 · 미드 · 원딜 · 서폿 (`GameEnums.LANE_POSITIONS`)
# 목록 안에 섞여 있어도 같은 뜻으로 펼쳐 읽는다(`allowed_positions`).
const SCOPE_ANY    := "any"
const SCOPE_LANE   := "lane"
const SCOPE_JUNGLE := "jungle"

# 키워드 (cards.csv `keyword` 컬럼). **`|` 로 여러 개를 붙일 수 있다** —
# 스킬이 만든 카드는 `exhaust|volatile` 로 "쓰면 소멸, 안 쓰고 버려져도
# 사라진다"를 함께 단다. 판정은 언제나 `has_keyword()` 를 지나야 한다:
# `keyword == "exhaust"` 로 문자열을 통째로 비교하면 두 번째 키워드가 붙는
# 순간 첫 번째가 조용히 꺼진다.
#
# 키워드는 **설명문에 다시 적지 않는다** — 설명판(`CardDescBox`)이 키워드 줄과
# 용어 풀이(`keyword_label` / `keyword_note`)를 따로 그리므로, 설명문에는 그
# 카드만의 효과만 남는다.
const KW_EXHAUST  := "exhaust"    # 사용 후 소멸 (덱으로도 discard 로도 안 감)
## 보존 — **버려지지 않는다.** 손패 상한 초과 자동 버리기도, 버리기 계열 카드
## (재고 / 완벽한 마무리 / 과감한 정리 / 솔로 퍼포먼스 / 버리기:N)도 이 카드를
## 건너뛴다. "쓸 때를 골라야 하는" 한정 카드를 위한 것이라(지금 다는 카드는
## 없다 — [전령 제압]은 버려지면 더미로 가서 덱을 다시 돈다) 작전 단계 한
## 번짜리인 계획 중시(`preserve:N` 효과)와는 수명이 다르다 —
## 그쪽은 `BattleSim.preserved_cards_*` 목록, 이쪽은 카드 자신의 키워드다.
## **`KW_VOLATILE` 과 한 카드에 함께 달 수 없다** — Rebuild game.db 가 거부한다
## (`addons/csv_to_db/csv_to_db.gd` `EXCLUSIVE_KEYWORDS`).
const KW_PRESERVE := "preserve"
## 휘발성 — **버려질 때 버린 더미로 가지 않고 그 자리에서 사라진다.** 파일럿
## 스킬이 손패에 직접 만들어 주는 카드들이 단다(배회의 [이동], 복귀 명령의
## [복귀], 격전의 [교전 개시], 약탈자의 [약탈], 공격적인 전진의 [전진]).
## `KW_EXHAUST` 와 짝이지 같은 것이 아니다 — 소멸은 **쓰면** 사라지는 것이고
## 휘발성은 **안 쓰고 버려지면** 사라지는 것이라, 스킬이 준 카드는 어느 쪽으로도
## 덱을 불리지 않는다. 판정은 `CardPhaseManager.send_to_discard` 한 곳을 지난다.
const KW_VOLATILE := "volatile"
## 충전 — **손패에 들어올 때마다 토큰이 1 쌓인다**(상한 `charge_max`). 사용하면
## 쌓인 토큰이 한꺼번에 나가며 0 으로 돌아온다(미사일 · 전장 강타 · 약자 멸시 ·
## 성장 가속). 효과 쪽은 `|charge` 플래그로 그 수를 읽는다.
##
## **충전은 키워드이고, 충전으로 채워지는 것은 토큰이다.** 카드 위의 토큰 수가
## `charge` 필드다(이름은 예전 그대로 둔다 — 세이브 · 효과 문법이 이미 그 이름을
## 쓴다). 토큰은 충전만 채우는 것이 아니다 — [골드러시]는 쓸 때마다 `token:N`
## 절로 자기 토큰을 올리고, 충전 카드가 아니라 토큰이 사용으로 사라지지 않는다.
##
## 예전에는 같은 카드를 **손패에서 한 장으로 뭉치는** `스택` 키워드였다. 뭉치는
## 표현은 손패 크기 · 상한 정리 · 부채꼴 · 히트 밴드를 건드리지 않는다는 장점이
## 있었지만, 더미로 내려갈 때마다 낱장으로 흩어야 했고(안 그러면 리셔플 한 번에
## 덱 장수가 준다) "덱에 몇 장 넣을 것인가"(count)가 곧 세기의 상한이라
## 카드마다 여러 장씩 덱을 불렸다.
const KW_CHARGE := "charge"
## 재배치 — **손패 맨 왼쪽으로 이동한다.** 낼 수 있는 카드는 쓰고 나면 버린
## 더미 대신 손패 맨 왼쪽으로 돌아온다(정밀 이동 · 골드러시 — 둘 다 그때마다
## 자기 비용을 올리는 `self_cost:N` 을 함께 단다). 라우팅은
## `CardPhaseManager._dispose_used_card`.
const KW_REPOSITION := "reposition"

## 키워드 → 화면 이름 l10n key. 설명판 · 상세 패널이 같은 표를 읽는다(`keyword_label`).
const KEYWORD_LABELS: Dictionary = {  # l10n-keys: term.keyword.*
	KW_EXHAUST: L.TERM_KEYWORD_EXHAUST, KW_PRESERVE: L.TERM_KEYWORD_PRESERVE,
	KW_VOLATILE: L.TERM_KEYWORD_VOLATILE, KW_CHARGE: L.TERM_KEYWORD_CHARGE,
	KW_REPOSITION: L.TERM_KEYWORD_REPOSITION,
}
## 키워드 한 줄 풀이 l10n key. 충전은 상한(`{max}`)이 카드마다 달라 `keyword_note` 가 채운다.
const KEYWORD_NOTES: Dictionary = {  # l10n-keys: keyword.*.note
	KW_EXHAUST: L.KEYWORD_EXHAUST_NOTE, KW_PRESERVE: L.KEYWORD_PRESERVE_NOTE,
	KW_VOLATILE: L.KEYWORD_VOLATILE_NOTE, KW_CHARGE: L.KEYWORD_CHARGE_NOTE,
	KW_REPOSITION: L.KEYWORD_REPOSITION_NOTE,
}

## **특수 키워드** — 설명문에서 `[이름]` 으로 감싼 효과 용어(l10n `keyword` 도메인).
## 설명문에는 대괄호 없이 특수 키워드 색으로 찍히고(`StrategyIcon.fill_rich`), 설명판이
## 용어마다 풀이 판을 단다(`CardDescBox`). `[이름]` 이 무엇을 가리키는지는 **표시 글자가
## 아니라 참조 key** 로 정한다 — 설명 key 의 `Loc.refs()`(`ref_entries`). 참조가 `card`
## 도메인이면 카드 이름이고, 풀이 판 대신 그 카드의 설명판(비용 · 이름 · 설명)을 세운다.
## 값 = 특수 키워드 id(`KeywordIcon.SPECIAL_ICONS` 의 키).
const SPECIAL_LABELS: Dictionary = {  # l10n-keys: term.keyword.*
	"track": L.TERM_KEYWORD_TRACK, "reactive_armor": L.TERM_KEYWORD_REACTIVE_ARMOR,
	"target": L.TERM_KEYWORD_TARGET, "bounty": L.TERM_KEYWORD_BOUNTY,
	"stun": L.TERM_KEYWORD_STUN, "vulnerable": L.TERM_KEYWORD_VULNERABLE,
}
const SPECIAL_NOTES: Dictionary = {  # l10n-keys: keyword.*.note
	"track": L.KEYWORD_TRACK_NOTE, "reactive_armor": L.KEYWORD_REACTIVE_ARMOR_NOTE,
	"target": L.KEYWORD_TARGET_NOTE, "bounty": L.KEYWORD_BOUNTY_NOTE,
	"stun": L.KEYWORD_STUN_NOTE, "vulnerable": L.KEYWORD_VULNERABLE_NOTE,
}

# 카드 종류 (cards.csv `card_type` 컬럼). **cards.csv 의 행은 전부 파일럿
# 카드다** — 메크 카드는 `mech_cards.csv` 에서 오고 `make_mech_card` 만 이 값을
# `mech` 로 찍는다. 예전의 "공용 메크 카드"(cards.csv 의 mech 행)는 없어졌다.
const TYPE_MECH  := "mech"
const TYPE_PILOT := "pilot"

# 카드 분류 (cards.csv `card_cat` 컬럼) — **`|` 로 여러 개**를 달 수 있다.
# 포지션별 슬롯 표(`pilot_card_slots.csv`)의 각 칸이 이 분류로 후보를 고른다.
const CAT_NONE    := "-"          # 지급 전용(오브젝트 보상 · 스킬 생성) — 슬롯 후보가 아니다
const CAT_GROWTH  := "growth"     # 성장
const CAT_ENGAGE  := "engage"     # 교전
const CAT_AMBUSH  := "ambush"     # 매복
const CAT_ATTACK  := "attack"     # 공격
const CAT_DEFENSE := "defense"    # 방어
const CAT_UTILITY := "utility"    # 유틸리티
const CAT_DRAW    := "draw"       # 뽑기
const CAT_JUNGLE  := "jungle"     # 정글
const CAT_LANE    := "lane"       # 라인전
## 분류 → 이름 l10n key. 화면은 `category_label(cat)` 로 읽는다.
const CATEGORY_LABELS: Dictionary = {  # l10n-keys: term.card_cat.*
	CAT_GROWTH: L.TERM_CARD_CAT_GROWTH, CAT_ENGAGE: L.TERM_CARD_CAT_ENGAGE, CAT_AMBUSH: L.TERM_CARD_CAT_AMBUSH,
	CAT_ATTACK: L.TERM_CARD_CAT_ATTACK, CAT_DEFENSE: L.TERM_CARD_CAT_DEFENSE, CAT_UTILITY: L.TERM_CARD_CAT_UTILITY,
	CAT_DRAW: L.TERM_CARD_CAT_DRAW, CAT_JUNGLE: L.TERM_CARD_CAT_JUNGLE, CAT_LANE: L.TERM_CARD_CAT_LANE,
}


## 분류 id 하나 → 현재 로케일 이름("성장"). 모르는 id 는 그대로.
static func category_label(cat: String) -> String:
	if not CATEGORY_LABELS.has(cat):
		return cat
	return Loc.t(String(CATEGORY_LABELS[cat]))  # l10n-dynamic: term.card_cat.*

## cards.csv 행 id. 고정 파일럿 카드(`PlayerData.pilot_cards`)가 이 값으로 카드를
## 가리킨다. 메크 카드와 손으로 만든 카드는 -1.
@export var card_id: int = -1
## 이름 · 설명 l10n key(`cards.csv` / `mech_cards.csv` 의 `name_key` · `description_key`).
## 표시 글자는 저장하지 않고 `card_name` · `description` 이 읽을 때마다 번역한다.
@export var name_key: String = ""
@export var description_key: String = ""
## 표 밖에서 손으로 만든 카드(key 없음)의 글자 — `_init` 인자. key 가 있으면 쓰지 않는다.
var _name_text: String = ""
var _desc_text: String = ""
## 화면 이름. key 가 있으면 현재 로케일 번역, 없으면 손으로 준 글자.
var card_name: String:
	get:
		return Loc.t(name_key) if not name_key.is_empty() else _name_text  # l10n-dynamic: card.*.*.name
	set(value):
		_name_text = value
@export var cost: int = 1
@export var uses: int = 1                 # cards.csv 컬럼. 소멸 판정에는 쓰이지 않는다 (keyword == "exhaust" 만 소멸)
@export var cast_method: String = "instant"  # range / target / location / instant
@export var target: String = "hand"       # caster / enemy / ally / pilot / hand / location
@export var cast_range: int = 0           # tiles from caster (0 = self, 99 = unbounded)
@export var area: int = 0                 # AoE radius around target (0 = single)
@export var keyword: String = ""          # `|` 로 구분된 키워드 목록 — has_keyword() 로만 읽는다
@export var effect: String = ""           # semicolon list, e.g. "draw:N;discard:N"
## 설명문(번역 · `\n` · 조사 처리 끝난 글). key 가 없으면 손으로 준 글자.
var description: String:
	get:
		return Loc.t(description_key, effect_params(), true) if not description_key.is_empty() else _desc_text  # l10n-dynamic: card.*.*.desc
	set(value):
		_desc_text = value


## 설명문 자리표시자 값. `effect` 의 수치를 문장에 적지 않고 이름으로 가리킨다.
## 절 `op:v|mod:w|flag` 하나에서 `{op}` = v, `{op_mod}` = w, 그리고 앞선 절에 없던 이름이면
## `{mod}` = w 도. 숫자 값마다 `{<이름>_abs}` (부호 없는 값)도 함께 준다.
## 예: `retreat_turret;eva_buff:20|turns:10` → eva_buff 20 · eva_buff_turns 10 · turns 10.
func effect_params() -> Dictionary:
	var out: Dictionary = {}
	for clause in effect.split(";", false):
		var parts: PackedStringArray = clause.split("|", false)
		if parts.is_empty():
			continue
		var head: PackedStringArray = parts[0].split(":", true, 1)
		var op: String = head[0].strip_edges()
		if head.size() > 1:
			_put_param(out, op, head[1])
		for i in range(1, parts.size()):
			var kv: PackedStringArray = parts[i].split(":", true, 1)
			if kv.size() < 2:
				continue
			_put_param(out, "%s_%s" % [op, kv[0].strip_edges()], kv[1])
			if not out.has(kv[0].strip_edges()):
				_put_param(out, kv[0].strip_edges(), kv[1])
	return out


static func _put_param(out: Dictionary, nm: String, raw: String) -> void:
	var v: String = raw.strip_edges()
	out[nm] = v
	if v.is_valid_float():
		out[nm + "_abs"] = Loc.number_text(absf(v.to_float()))

# 시전자 제약(포지션 목록). 고정 파일럿 카드를 고를 때와 손패 시전자 판정이 읽는다.
@export var scope: String = SCOPE_ANY
# 1 = 파일럿 카드 후보, 0 = 제외(결투 · 오브젝트 보상 · 스킬 생성 카드).
@export var pool: int = 1
@export var card_type: String = TYPE_PILOT
# 카드 분류(`|` 목록). 메크 카드는 CAT_NONE.
@export var card_cat: String = CAT_NONE
# 상호 배타 그룹 (cards.csv `excl_group`). 비어 있으면 제약 없음. 값이 같은
# 카드끼리는 **한 파일럿이 하나만** 가질 수 있다 — 고정 카드를 뽑는
# `GameManager.roll_pilot_card_ids` 가 유일한 소비자다(지금은 쓰는 카드가 없다).
@export var excl_group: String = ""

# ─── 메크 카드 ───────────────────────────────────────────────────────────────
# 메크 카드는 `cards.csv` 가 아니라 `mech_cards.csv` 에서 온다. 두 값이 그 출신을
# 말한다 — `mech_card_id` 가 그 표의 행 id(효과가 카드를 **지목해** 만들 때 쓰는
# 키), `mech_id` 가 그 카드를 들고 온 기체다. 파일럿 카드는 둘 다 -1 이다.
@export var mech_card_id: int = -1
@export var mech_id: int = -1
## 카드 자신에게 붙는 사건 훅(mech_cards.trigger). 비어 있으면 없음.
@export var trigger: String = ""
## 충전 상한(`charge_max` 컬럼). `KW_CHARGE` 를 안 단 카드는 0.
@export var charge_max: int = 0

## 이 카드 위의 **토큰** 수 — `KW_CHARGE` 주석 참조. 토큰을 쓰지 않는 카드는 0.
var charge: int = 0

## [신중한 예산] — 이번 작전 단계 동안 비용 0. 작전 단계 중 손패에 들어온 순간
## 켜지고(`CardPhaseManager._on_enter_hand`) 그 쪽 작전 단계가 닫힐 때 꺼진다.
var free_this_phase: bool = false

# Runtime — set when this card is dealt to a pilot's mini-deck. Identifies the
# 시전자 (caster) for effect resolution and drives the owner badge on the UI.
# Not @export'd because PilotData is a transient match-only object.
var owner_pilot: PilotData = null


func _init(p_name: String = "", p_cost: int = 1, p_desc: String = "") -> void:
	card_name = p_name
	cost = p_cost
	description = p_desc


## 이 카드가 `kw` 키워드를 달고 있는가. `keyword` 컬럼은 `|` 로 구분된 목록이라
## 문자열 비교가 아니라 반드시 이 함수를 지나야 한다. 공백은 CSV 손질 실수를
## 흡수하려고 걷어 낸다.
func has_keyword(kw: String) -> bool:
	if keyword.is_empty():
		return false
	for raw in keyword.split("|", false):
		if (raw as String).strip_edges() == kw:
			return true
	return false


## 키워드 목록(공백 제거, 순서 유지).
func keyword_list() -> Array:
	var out: Array = []
	for raw in keyword.split("|", false):
		var k: String = (raw as String).strip_edges()
		if not k.is_empty():
			out.append(k)
	return out


## 키워드 하나의 화면 이름. 충전은 상한을 붙인다(`keyword.charge.label`). 표에 없는
## 키워드는 id 그대로.
func keyword_label(kw: String) -> String:
	if kw == KW_CHARGE:
		return Loc.t(L.KEYWORD_CHARGE_LABEL, {"max": maxi(1, charge_max)})
	if not KEYWORD_LABELS.has(kw):
		return kw
	return Loc.t(String(KEYWORD_LABELS[kw]))  # l10n-dynamic: term.keyword.*


## 키워드 하나의 한 줄 풀이. 표에 없는 키워드는 빈 문자열.
func keyword_note(kw: String) -> String:
	if not KEYWORD_NOTES.has(kw):
		return ""
	return Loc.t(String(KEYWORD_NOTES[kw]), {"max": maxi(1, charge_max)})  # l10n-dynamic: keyword.*.note


## 손패에서 강제로 버려지지 않는 카드인가 — `KW_PRESERVE` 주석 참조.
func is_preserved_by_keyword() -> bool:
	return has_keyword(KW_PRESERVE)


## 버려질 때 버린 더미로 가지 않고 사라지는 카드인가 — `KW_VOLATILE` 주석 참조.
func is_volatile() -> bool:
	return has_keyword(KW_VOLATILE)


## 충전 키워드를 단 카드인가 — `KW_CHARGE` 주석 참조.
func is_charge_card() -> bool:
	return has_keyword(KW_CHARGE)


## 쓰고 나면 손패 맨 왼쪽으로 돌아오는 카드인가 — `KW_REPOSITION` 주석 참조.
func is_reposition_card() -> bool:
	return has_keyword(KW_REPOSITION)


## 카드 앞면에 토큰 배지를 띄우는 카드인가. 충전 카드이거나 효과가 자기 토큰을
## 올리는 카드(`token:N` 절 — 골드러시)다.
func shows_tokens() -> bool:
	return is_charge_card() or effect.contains("token:")


## 이 카드가 손패에 들어왔다. 충전 카드면 토큰을 `CARD_CHARGE_HAND_GAIN`(const.csv)만큼
## 올린다(상한까지). 실제로 올랐으면 true.
func gain_charge() -> bool:
	if not is_charge_card():
		return false
	var before: int = charge
	charge = mini(charge + ConstTable.int_of("CARD_CHARGE_HAND_GAIN"), maxi(1, charge_max))
	return charge != before


## 충전 카드의 토큰을 통째로 태운다. 태운 수를 돌려준다 — 충전 카드가 아니면 0.
func spend_charge() -> int:
	if not is_charge_card():
		return 0
	var n: int = charge
	charge = 0
	return n


## **낼 수 있는 카드인가.** 비용 -1 은 "사용할 수 없다"는 뜻이다 — 핸드에 들고
## 있는 것만으로 효과를 내는 카드(캐시 · 계시 · 약자 멸시 · 밸런스 · 자신감 ·
## 맑은 정신)가 쓰며, 드래그도 확정도 거부된다. 0 코스트와 헷갈리지 말 것: 0 은
## 공짜로 낼 수 있다는 뜻이고 -1 은 낼 수 없다는 뜻이다.
func is_playable() -> bool:
	return cost >= 0


## `scope` 를 펼친 포지션 키 목록. 빈 값이나 알 수 없는 토큰만 있으면 다섯 전부 —
## CSV 오타가 카드를 통째로 사라지게 만들지 않는다.
static func positions_of(scope_str: String) -> Array:
	var out: Array = []
	for raw in scope_str.split("|", false):
		var t: String = (raw as String).strip_edges()
		var add: Array = []
		if t == SCOPE_ANY:
			add = GameEnums.POSITION_KEYS
		elif t == SCOPE_LANE:
			add = GameEnums.LANE_POSITIONS
		elif t in GameEnums.POSITION_KEYS:
			add = [t]
		for k in add:
			if not out.has(k):
				out.append(k)
	if out.is_empty():
		return GameEnums.POSITION_KEYS.duplicate()
	return out


func allowed_positions() -> Array:
	return positions_of(scope)


## 이 포지션(`GameEnums.position_key`)의 파일럿이 이 카드를 가질 수 있는가.
## 포지션을 모르면(빈 문자열) 막지 않는다.
func allowed_for_position(pos: String) -> bool:
	if pos.is_empty():
		return true
	return allowed_positions().has(pos)


## 시전자 제약을 사람이 읽는 말로 — "모든 포지션" / "탑 · 미드 · 원딜".
static func scope_label(scope_str: String) -> String:
	var pos: Array = positions_of(scope_str)
	if pos.size() >= GameEnums.POSITION_KEYS.size():
		return Loc.t(L.TERM_POSITION_ALL)
	var names: Array = []
	for k in GameEnums.POSITION_KEYS:
		if pos.has(k):
			names.append(GameEnums.position_label(String(k)))
	return " · ".join(names)


## 분류 목록(`card_cat` 을 펼친 것). CAT_NONE 은 빈 배열.
func categories() -> Array:
	var out: Array = []
	for raw in card_cat.split("|", false):
		var c: String = (raw as String).strip_edges()
		if not c.is_empty() and c != CAT_NONE:
			out.append(c)
	return out


## 분류가 `cats` 중 하나라도 겹치는가 — 슬롯 한 칸의 후보 판정.
func fits_any_category(cats: Array) -> bool:
	for c in categories():
		if cats.has(c):
			return true
	return false


## 이 카드의 분류를 사람이 읽는 말로 — "성장 · 뽑기".
func categories_text() -> String:
	var names: Array = []
	for c in categories():
		names.append(category_label(String(c)))
	return " · ".join(names) if not names.is_empty() else "—"


## `cards.csv` 한 행(= `GameManager.card_pool_bs` 항목) → CardData 한 장.
##
## **static 인 것이 요점이다.** 예전에는 이 조립이 `CardPhaseManager` 안에만
## 있어서 카드를 실물로 보여 주려면 BattleSim 이 서 있어야 했는데, 밴픽의 하단
## 시트와 메크 상세처럼 **전투가 없는 자리**에서도 "이 기체가 주는 카드"를 같은
## 노드로 그려야 한다 — 표가 둘이면 화면에 뜬 카드와 실제로 덱에 들어가는 카드가
## 조용히 갈린다. `mech_cards.csv` 쪽은 컬럼이 달라 자기 팩토리(`from_mech_def`)를 쓴다
## — 밴픽 · 메크 상세도 메크 카드는 반드시 그쪽을 지난다(식별자 `card_uid` 가 갈린다).
static func from_def(def: Dictionary) -> CardData:
	var cd := CardData.new("", int(def.get("cost", 0)), "")
	cd.name_key        = String(def.get("name_key", ""))
	cd.description_key = String(def.get("description_key", ""))
	cd.card_id     = int(def.get("id", -1))
	cd.uses        = int(def.get("uses", 1))
	cd.cast_method = String(def.get("cast_method", "instant"))
	cd.target      = String(def.get("target", "hand"))
	cd.cast_range  = int(def.get("cast_range", 0))
	cd.area        = int(def.get("area", 0))
	cd.keyword     = String(def.get("keyword", ""))
	cd.effect      = String(def.get("effect", ""))
	cd.scope       = String(def.get("scope", SCOPE_ANY))
	cd.pool        = int(def.get("pool", 1))
	cd.card_type   = String(def.get("card_type", TYPE_PILOT))
	cd.card_cat    = String(def.get("card_cat", CAT_NONE))
	cd.excl_group  = String(def.get("excl_group", ""))
	cd.charge_max  = int(def.get("charge_max", 0))
	return cd


## `mech_cards.csv` 한 행(= `GameManager.mech_card_defs` 값) → CardData 한 장.
## `cards.csv` 쪽 행과 컬럼이 다르므로 팩토리도 따로다 — 저쪽에는 없는 `mech_id` /
## `count` / `trigger` 가 있고, 이쪽에는 없는 덱 슬롯 컬럼(card_type / card_cat /
## excl_group / scope / pool)이 있다.
##
## **시전자 제약은 붙지 않는다**(`scope = any`). 메크 카드의 임자는 배정된 기체가
## 정하므로 레인/정글 필터를 한 번 더 씌우면 정글러가 자기 기체 카드를 못 받는
## 자리가 생긴다 — 이동 카드를 들고 오는 메크가 여럿이다.
static func from_mech_def(def: Dictionary) -> CardData:
	var cd := CardData.new("", int(def.get("cost", 0)), "")
	cd.name_key        = String(def.get("name_key", ""))
	cd.description_key = String(def.get("description_key", ""))
	cd.uses         = 1
	cd.cast_method  = String(def.get("cast_method", "instant"))
	cd.target       = String(def.get("target", "hand"))
	cd.cast_range   = int(def.get("cast_range", 0))
	cd.area         = int(def.get("area", 0))
	cd.keyword      = String(def.get("keyword", ""))
	cd.effect       = String(def.get("effect", ""))
	cd.trigger      = String(def.get("trigger", ""))
	cd.charge_max   = int(def.get("charge_max", 0))
	cd.scope        = SCOPE_ANY
	cd.pool         = 0
	cd.card_type    = TYPE_MECH
	cd.card_cat     = CAT_NONE
	cd.card_id      = -1
	# An upgraded "+" row (§15 A) keeps its base card's id (`base_id`, set by GameManager):
	# same art, and `search_card` / `gen_*` / trigger lookups still find it.
	cd.mech_card_id = int(def.get("base_id", def.get("id", -1)))
	cd.mech_id      = int(def.get("mech_id", -1))
	return cd


# ─── 카드 식별 · 설명문 참조 (l10n, 설계서 D3 · D4) ─────────────────────────────
# 카드는 **표시 이름으로 찾지 않는다** — 이름은 언어마다 다르다. 식별자는 출신 표 +
# 행 id(`card_uid`), 설명문의 `[이름]` 은 설명 key 의 참조 key 목록(`Loc.refs`)으로 푼다.

## 이름 key → CardData(없음 = null). 참조 카드 설명판 · 미리보기가 한 번 찾고 캐시한다.
static var _by_name_key: Dictionary = {}


## 이 카드의 안정된 식별자 — `pilot:<cards.id>` / `mech:<mech_cards.id>`. 표 밖에서 손으로
## 만든 카드(강화 선택지 등)는 `effect:<효과>`. 아트 조회(`CardImages`)와 효과 출처
## 기록(`PilotData.fx_src` · `persistent_fx`)이 쓴다.
func card_uid() -> String:
	if mech_card_id >= 0:
		return "mech:%d" % mech_card_id
	if card_id >= 0:
		return "pilot:%d" % card_id
	return "effect:%s" % effect


static func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameManager") if tree != null else null


## `card_uid()` → 그 카드의 현재 로케일 이름. 표에 없는 식별자는 빈 문자열.
static func name_of_uid(uid: String) -> String:
	var gm: Node = _game_manager()
	var parts: PackedStringArray = uid.split(":", true, 1)
	if gm == null or parts.size() != 2 or not parts[1].is_valid_int():
		return ""
	var def: Dictionary = {}
	if parts[0] == "pilot":
		def = gm.card_def(int(parts[1]))
	elif parts[0] == "mech":
		def = gm.mech_card_def(int(parts[1]))
	if def.is_empty():
		return ""
	return Loc.t(String(def.get("name_key", "")))  # l10n-dynamic: card.*.*.name


## 이름 key 로 카드 한 장 — 메크 카드 표를 먼저, 다음 파일럿 카드 표. 결과(없음 포함)는
## 캐시한다. 오토로드가 없으면(에디터 도구 등) null.
static func by_name_key(key: String) -> CardData:
	if key.is_empty():
		return null
	if _by_name_key.has(key):
		return _by_name_key[key] as CardData
	var gm: Node = _game_manager()
	if gm == null:
		return null
	var cd: CardData = null
	for d in (gm.mech_card_defs as Dictionary).values():
		if String((d as Dictionary).get("name_key", "")) == key:
			cd = from_mech_def(d)
			break
	if cd == null:
		for d in gm.card_pool_bs:
			if String((d as Dictionary).get("name_key", "")) == key:
				cd = from_def(d)
				break
	_by_name_key[key] = cd
	return cd


## 특수 키워드 풀이 한 줄(현재 로케일). 튜닝 상수 자리표시자는 `Loc.t` 가 const.csv 로 채우고,
## 카드 효과 값(`{mark_target}` 등)은 호출부가 `params` 로 준다(`CardDescBox.special_note_params`).
## 표에 없는 id 는 빈 문자열.
static func special_note(sp: String, params: Dictionary = {}) -> String:
	if not SPECIAL_NOTES.has(sp):
		return ""
	return Loc.t(String(SPECIAL_NOTES[sp]), params)  # l10n-dynamic: keyword.*.note


## 특수 키워드 이름 key → 특수 키워드 id(`SPECIAL_LABELS` 의 키). 아니면 빈 문자열.
static func special_id_of(key: String) -> String:
	for id in SPECIAL_LABELS:
		if String(SPECIAL_LABELS[id]) == key:
			return String(id)
	return ""


## 설명 key 의 `[x]` 참조 — 원문 등장 순서대로 `{key, text, special, card}`.
##   `key`     참조 key (카드 이름 `card.*.*.name` · 키워드 이름 `term.keyword.*`)
##   `text`    그 key 의 현재 로케일 글자 — 설명문 `[ ]` 안에 찍힌 글자와 같다(E034)
##   `special` 특수 키워드 id(아니면 빈 문자열)
##   `card`    카드 이름 참조면 그 카드(`by_name_key`), 아니면 null
## 설명 key 가 비었거나 참조가 없으면 빈 배열.
static func ref_entries(text_key: String) -> Array:
	var out: Array = []
	if text_key.is_empty():
		return out
	for rk in Loc.refs(text_key):
		var sp: String = special_id_of(rk)
		out.append({
			"key": rk,
			"text": Loc.t(rk),  # l10n-dynamic: card.*.*.name term.keyword.*
			"special": sp,
			"card": by_name_key(rk) if sp.is_empty() else null,
		})
	return out


## 설명문의 `idx` 번째 `[term]` 이 가리키는 참조(`ref_entries` 의 한 항목). 같은 글자의
## 참조를 먼저 찾고(번역문은 `[ ]` 순서가 원문과 다를 수 있다), 없으면 같은 순번의
## 참조를 쓴다. 둘 다 없으면 빈 Dictionary.
static func ref_for(term: String, refs: Array, idx: int) -> Dictionary:
	for e in refs:
		if String((e as Dictionary)["text"]) == term:
			return e
	if idx >= 0 and idx < refs.size():
		return refs[idx]
	return {}
