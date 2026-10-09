@tool
extends RefCounted

# CSV → game.db 변환 로직 본체.
#
# EditorPlugin(`plugin.gd`) 에서 분리해 둔 이유: EditorPlugin 은 에디터 밖에서
# 인스턴스화할 수 없어서(`Class 'EditorPlugin' can only be instantiated by
# editor`), 로직이 그 안에 있으면 DB 를 헤드리스로 다시 만들 수 없다. 순수
# RefCounted 로 빼 두면 두 경로가 **같은 코드**를 쓴다:
#
#   에디터  : Project → Tools → Rebuild game.db  (plugin.gd 가 호출)
#   CLI     : godot --headless --path <proj> --script <SceneTree 스크립트>
#             안에서 load("res://addons/csv_to_db/csv_to_db.gd").new().rebuild()
#
# 테이블을 추가할 때는 SCHEMAS 와 TABLE_DEFS 양쪽에 항목을 넣는다.

const CSV_DIR = "res://data/csv/"
const DB_PATH = "res://data/game.db"

# Required columns and primary key per table
const SCHEMAS: Dictionary = {
	"pilots":      {"req": ["id","name","abbrev","hp","atk","heal"],           "pk": "id"},
	"cards":       {"req": ["id","name_key","cost","uses","cast_method","target","cast_range","area","keyword","effect","description_key","scope","pool","card_type","card_cat","excl_group","charge_max","upgrade_id"], "pk": "id"},
	"game_config": {"req": ["key","value"],                                     "pk": "key"},
	"const":       {"req": ["key","value","module","note"],                     "pk": "key"},
	"lane_config": {"req": ["lane_id","name","max_pilots","mid_col","mid_row"], "pk": "lane_id"},
	"players":     {"req": ["id","team_id","name_key","role","field_hit","field_eva","engage_hit","engage_eva","atk_growth","hp_growth","skill_id","is_mob","pilot_cards","salary","rarity","starter","main_mechs","mech_pref"], "pk": "id"},
	"pilot_skills": {"req": ["id","key","name_key","role","type","p1","p2","keyword","description_key"], "pk": "id"},
	"mechs":       {"req": ["id","name_key","role","hp","atk","presence"],          "pk": "id"},
	"mech_passives": {"req": ["id","mech_id","key","name_key","p1","p2","keyword","description_key"], "pk": "id"},
	"mech_cards":    {"req": ["id","mech_id","name_key","count","cost","cast_method","target","cast_range","area","keyword","charge_max","effect","trigger","description_key","upgrade_id"], "pk": "id"},
	"teams":       {"req": ["id","name_key","short_name_key","budget","facility_level","staff_ids","manual_areas","desc_key","map_id"], "pk": "id"},
	"intl_teams":   {"req": ["id","name_key","short_name_key"],                         "pk": "id"},
	"intl_players": {"req": ["id","team_id","name_key","role","field_hit","field_eva","engage_hit","engage_eva","atk_growth","hp_growth","pilot_cards","main_mechs","mech_pref"], "pk": "id"},
	"pilot_card_slots": {"req": ["position","slot1","slot2","slot3"], "pk": "position"},
	"training_tiles": {"req": ["id","name_key","grade","shape","exp","effect"], "pk": "id"},
	"scenarios":   {"req": ["id","name_key","salary_cap","desc_key"], "pk": "id"},
	"pilot_levels": {"req": ["level","stat_bonus","salary_bonus","levelup_cost","exp_required"], "pk": "level"},
	# M3~M7 (감독 · 스태프 · 재무 · 멘탈) — 계약: docs/outgame_dev_plan.md §11
	"manager_types": {"req": ["id","name_key","gender","training","tactics","knowledge","mental","analysis","finance","desc_key"], "pk": "id"},
	"staff":         {"req": ["id","name_key","job","training","tactics","knowledge","mental","analysis","finance","salary"], "pk": "id"},
	"facilities":    {"req": ["level","upkeep","upgrade_cost","train_exp_pct","mastery_pct","incident_pct","income_pct"], "pk": "level"},
	"mental_events": {"req": ["id","kind","manager_type","stage","cond","effects","weight"], "pk": "id"},
	"mental_texts":  {"req": ["id","event_id","slot","choice","branch","seq","text_key"], "pk": "id"},
	# M8~M10 (특성 · 감독 성장 · 수집 경제) — 계약: docs/outgame_dev_plan.md §12
	"traits":        {"req": ["id","key","name_key","rarity","polarity","bonus_cost","layer","p1","p2","unlock","default_owned","craft_cost","desc_key"], "pk": "id"},
	"manager_levels": {"req": ["level","exp_required"], "pk": "level"},
	"pilot_ranks":   {"req": ["id","pilot_id","rank","kind","value"], "pk": "id"},
	"mech_upgrades": {"req": ["id","mech_id","level","target","param","card_id","value","desc_key"], "pk": "id"},
	"gacha_rates":   {"req": ["id","pool","rarity","weight"], "pk": "id"},
	"pass_rewards":  {"req": ["level","currency","amount"], "pk": "level"},
	# §14 (기벽 · 재무 특별 지출) — 계약: docs/outgame_dev_plan.md §14
	"quirks":        {"req": ["id","name_key","grade","stats","cond","cond_stats","weight","desc_key"], "pk": "id"},
	"finance_specials": {"req": ["id","name_key","kind","cost","p1","p2","weeks","cond","desc_key"], "pk": "id"},
	# §16 facilities · research — contract: docs/outgame_dev_plan.md §16, features/season/facility/README.md
	"facility_defs": {"req": ["id","kind","name_key","desc_key","stat","spot","icon","cost_pct"], "pk": "id"},
	"research":      {"req": ["id","facility","kind","name_key","desc_key","weeks","min_level","repeatable","p1","p2","icon"], "pk": "id"},
}

# SQLite column definitions per table
const TABLE_DEFS: Dictionary = {
	"pilots": {
		"id":     {"data_type": "int", "primary_key": true, "not_null": true},
		"name":   {"data_type": "text", "not_null": true},
		"abbrev": {"data_type": "text", "not_null": true},
		"hp":     {"data_type": "int",  "not_null": true},
		"atk":    {"data_type": "int",  "not_null": true},
		"heal":   {"data_type": "int",  "not_null": true},
	},
	"cards": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":        {"data_type": "text", "not_null": true},
		"cost":        {"data_type": "int",  "not_null": true},
		"uses":        {"data_type": "int",  "not_null": true},
		"cast_method": {"data_type": "text", "not_null": true},
		"target":      {"data_type": "text", "not_null": true},
		"cast_range":  {"data_type": "int",  "not_null": true},
		"area":        {"data_type": "int",  "not_null": true},
		"keyword":     {"data_type": "text", "not_null": true},
		"effect":      {"data_type": "text", "not_null": true},
		"description_key": {"data_type": "text", "not_null": true},
		# 시전자 제약(포지션). `any` 단독 = 모든 포지션, `lane` 단독 = 탑/미드/원딜/서폿,
		# 그 밖에는 jungle / top / mid / carry / support 를 `|` 로 이은 목록.
		"scope":       {"data_type": "text", "not_null": true},
		# 1 = 랜덤 카드풀에 포함, 0 = 제외(메크 고유 카드 등 별도 경로로만 지급).
		"pool":        {"data_type": "int",  "not_null": true},
		# 카드 종류. cards.csv 의 행은 **전부 pilot** 이다 — 메크 카드는 mech_cards 에 산다.
		"card_type":   {"data_type": "text", "not_null": true},
		# 카드 분류 — `|` 로 여러 개를 달 수 있다(growth / engage / ambush / attack /
		# defense / utility / draw / jungle / lane). 지급 전용 카드는 "-".
		# pilot_card_slots 의 각 칸이 이 값으로 후보를 고른다.
		"card_cat":    {"data_type": "text", "not_null": true},
		# 상호 배타 그룹. 비어 있지 않은 같은 값끼리는 **한 파일럿이 하나만**
		# 가질 수 있다(지금은 쓰는 카드가 없다). 고정 카드를 뽑을 때 본다.
		"excl_group":  {"data_type": "text", "not_null": true},
		# 충전 상한(`charge` 키워드를 단 카드만 읽는다, 그 밖에는 0) — mech_cards 와 같은 뜻.
		"charge_max":  {"data_type": "int",  "not_null": true},
		# Upgraded version of this card (a separate row, `+` name) — -1 = none. §15.
		"upgrade_id":  {"data_type": "int",  "not_null": true},
	},
	"game_config": {
		"key":   {"data_type": "text", "primary_key": true, "not_null": true},
		"value": {"data_type": "text", "not_null": true},
	},
	# 스크립트에서 뺀 게임플레이 튜닝 상수 — `ConstTable` 이 소비한다.
	# `module` 은 그 값을 읽는 스크립트(찾기용), `note` 는 뜻 — **값을 다시 적지 않는다**.
	"const": {
		"key":    {"data_type": "text", "primary_key": true, "not_null": true},
		"value":  {"data_type": "text", "not_null": true},
		"module": {"data_type": "text", "not_null": true},
		"note":   {"data_type": "text", "not_null": true},
	},
	"lane_config": {
		"lane_id":    {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":       {"data_type": "text", "not_null": true},
		"max_pilots": {"data_type": "int",  "not_null": true},
		"mid_col":    {"data_type": "int",  "not_null": true},
		"mid_row":    {"data_type": "int",  "not_null": true},
	},
	"players": {
		"id":        {"data_type": "int",  "primary_key": true, "not_null": true},
		"team_id":   {"data_type": "int",  "not_null": true},
		"name_key":      {"data_type": "text", "not_null": true},
		"role":      {"data_type": "int",  "not_null": true},
		"field_hit":  {"data_type": "int",  "not_null": true},
		"field_eva":  {"data_type": "int",  "not_null": true},
		"engage_hit": {"data_type": "int",  "not_null": true},
		"engage_eva": {"data_type": "int",  "not_null": true},
		"atk_growth": {"data_type": "int",  "not_null": true},
		"hp_growth":  {"data_type": "int",  "not_null": true},
		# 이 파일럿의 고유 파일럿 스킬 id(pilot_skills.id). -1 = 없음(모브).
		"skill_id":  {"data_type": "int",  "not_null": true},
		# 1 = 모브 파일럿 — 스킬이 없고 스탯이 네임드보다 낮으며 초상화가
		# 실루엣 컷으로 나온다(PilotImages.set_mob_ids). 스탯 하향은 런타임
		# 계수가 아니라 **CSV 값 자체**에 이미 반영돼 있다.
		"is_mob":    {"data_type": "int",  "not_null": true},
		# 이 선수의 **고정 파일럿 카드 3장** — `cards.id` 를 `|` 로 이은 것.
		# 비어 있으면 GameManager 가 `pilot_card_slots` 로 선수 id 를 씨앗 삼아
		# 결정적으로 뽑는다(매 판 같은 3장).
		"pilot_cards": {"data_type": "text", "not_null": true},
		# Run setup (salary cap) — Lv0 base salary; level bonus = pilot_levels.salary_bonus.
		"salary":    {"data_type": "int",  "not_null": true},
		# Stars ★1..★3 for named pilots (mobs 0) — gacha tier, start rank.
		"rarity":    {"data_type": "int",  "not_null": true},
		# 1 = 프로필 첫 생성 때 지급하는 초기 보유 선수(ProfileManager).
		"starter":   {"data_type": "int",  "not_null": true},
		# 주력 메크 — `mechs.id` 를 `|` 로(M4). 런 시작 숙련도가 높게 시작한다.
		"main_mechs": {"data_type": "text", "not_null": true},
		# Mech preference, best first (`mechs.id` joined by `|`, up to 11) — run-start mastery
		# levels are dealt from the front by pilot rank (§15 A). Empty = derived from main_mechs.
		"mech_pref":   {"data_type": "text", "not_null": true},
	},
	"pilot_skills": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		# 런타임 분기 키(snake_case). 스킬 하나하나가 고유 효과라 효과 문법을
		# 만드는 대신 이 키로 갈라 쓴다 — PilotSkillSystem 이 소비한다.
		"key":         {"data_type": "text", "not_null": true},
		"name_key":        {"data_type": "text", "not_null": true},
		# GameEnums.Role. 스킬은 라인(역할)에 묶여 있으므로 같은 역할의
		# 파일럿에게만 붙는다.
		"role":        {"data_type": "int",  "not_null": true},
		# cooldown / charge / passive
		"type":        {"data_type": "text", "not_null": true},
		# cooldown = 재사용까지의 턴 수, charge = 활성화에 드는 충전 수.
		"p1":          {"data_type": "int",  "not_null": true},
		# 최대 충전 수(0 = 충전 없음).
		"p2":          {"data_type": "int",  "not_null": true},
		# 성향 태그 — `|` 로 이은 ascii id(`engage|strategy`), 표시는 `GameEnums.tags_text`.
		"keyword":     {"data_type": "text", "not_null": true},
		"description_key": {"data_type": "text", "not_null": true},
	},
	"mechs": {
		"id":       {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":     {"data_type": "text", "not_null": true},
		# GameEnums.Role. **메크에 역할이 생겼다** — 예전에는 "메크는 역할이
		# 없다"가 설계였지만, 메크마다 고유 패시브와 고유 카드 셋이 붙으면서
		# 그 카드들이 역할군을 전제하게 됐다(탱커의 반응 장갑 / 원딜의 사거리
		# 지정 공격 …). 배정 자체는 여전히 자유다 — 이 값은 밴픽 화면의 분류와
		# 데이터 검증용이고, 어느 슬롯에 어느 메크를 앉힐지는 막지 않는다.
		"role":     {"data_type": "int",  "not_null": true},
		"hp":       {"data_type": "int",  "not_null": true},
		"atk":      {"data_type": "int",  "not_null": true},
		# 존재감 — 전투 개시 시 타겟 어그로 가중치. 근접 메크가 원거리 메크보다 높다.
		"presence": {"data_type": "int",  "not_null": true},
	},
	# ── 메크 패시브 ──────────────────────────────────────────────────────────
	# 메크 한 대에 붙는 상시 능력. pilot_skills 와 같은 형태(런타임 분기 키
	# `key` + 파라미터 p1/p2)이고 소비자는 MechSkillSystem 이다. 21대 중 15대만
	# 가지며 나머지 6대는 카드로만 논다.
	"mech_passives": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		"mech_id":     {"data_type": "int",  "not_null": true},
		"key":         {"data_type": "text", "not_null": true},
		"name_key":        {"data_type": "text", "not_null": true},
		# 패시브마다 뜻이 다른 두 숫자. 충전형이면 p1 = 시작 충전, p2 = 최대 충전.
		"p1":          {"data_type": "int",  "not_null": true},
		"p2":          {"data_type": "int",  "not_null": true},
		# 성향 태그 — pilot_skills.keyword 와 같은 ascii id 목록.
		"keyword":     {"data_type": "text", "not_null": true},
		"description_key": {"data_type": "text", "not_null": true},
	},
	# ── 메크 카드 ────────────────────────────────────────────────────────────
	# 파일럿이 받는 **메크 카드 3장**이 사라지고, 그 자리를 배정된 메크의 고유
	# 카드 목록이 통째로 채운다. `count` 가 그 메크를 채용했을 때 덱에 들어가는
	# 장수이고 `count = 0` 인 카드는 다른 효과가 만들어 줄 때만 세상에 나온다.
	# 컬럼 구성은 cards.csv 와 나란하되 덱 슬롯(card_type/card_cat/excl_group)과
	# 시전자 제약(scope)이 없다 — 메크 카드의 임자는 메크가 정하기 때문.
	"mech_cards": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		"mech_id":     {"data_type": "int",  "not_null": true},
		"name_key":        {"data_type": "text", "not_null": true},
		# 채용 시 덱에 들어가는 장수. 0 = 별도 효과로만 생성된다.
		"count":       {"data_type": "int",  "not_null": true},
		# **-1 = 사용할 수 없는 카드.** 핸드에 들고 있는 것만으로 효과를 낸다
		# (캐시 · 계시 · 약자 멸시 · 밸런스). 드래그도 거부된다.
		"cost":        {"data_type": "int",  "not_null": true},
		"cast_method": {"data_type": "text", "not_null": true},
		# cards.csv 의 값에 셋이 더 붙는다 — foe(적 파일럿 또는 포탑) /
		# turret_outer(최외곽 적 포탑) / turret_any(살아 있는 적 포탑 전부).
		"target":      {"data_type": "text", "not_null": true},
		"cast_range":  {"data_type": "int",  "not_null": true},
		"area":        {"data_type": "int",  "not_null": true},
		# `|` 로 구분된 목록. exhaust / preserve / volatile 에 **charge** 가 더해졌다.
		"keyword":     {"data_type": "text", "not_null": true},
		# 충전 상한. `charge` 키워드를 단 카드만 읽는다(그 밖에는 0).
		"charge_max":  {"data_type": "int",  "not_null": true},
		"effect":      {"data_type": "text", "not_null": true},
		# 카드 자신에게 붙는 사건 훅(비어 있으면 없음). 패시브가 아니라 **그
		# 카드**가 존재를 얻는 조건이라 여기에 산다 — turret_kill_deck(꿰뚫는
		# 번개) / death_hand(공격 명령).
		"trigger":     {"data_type": "text", "not_null": true},
		"description_key": {"data_type": "text", "not_null": true},
		# Upgraded version of this card (a separate row, `+` name) — -1 = none. §15.
		"upgrade_id":  {"data_type": "int",  "not_null": true},
	},
	"teams": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":       {"data_type": "text", "not_null": true},
		"short_name_key": {"data_type": "text", "not_null": true},
		# 팀 패키지(런 준비 팀 선택 화면) — M1 은 표시 · 스냅샷만, 효과는 M3/M6.
		"budget":         {"data_type": "int",  "not_null": true},
		"facility_level": {"data_type": "int",  "not_null": true},
		# 감독이 직접 해야 하는 영역 — `training|knowledge|analysis|finance` 를 `|` 로.
		"manual_areas":   {"data_type": "text", "not_null": true},
		# 팀의 초기 스태프 — `staff.id` 를 `|` 로(M3). 빈 칸 = 스태프 없음.
		"staff_ids":      {"data_type": "text", "not_null": true},
		"desc_key":           {"data_type": "text", "not_null": true},
		# 팀 부지 맵: `BaseMap.SCENES` 인덱스 (시간 경과 화면, features/season/week/base_map/).
		"map_id":         {"data_type": "int",  "not_null": true},
	},
	"intl_teams": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":       {"data_type": "text", "not_null": true},
		"short_name_key": {"data_type": "text", "not_null": true},
	},
	"intl_players": {
		"id":        {"data_type": "int",  "primary_key": true, "not_null": true},
		"team_id":   {"data_type": "int",  "not_null": true},
		"name_key":      {"data_type": "text", "not_null": true},
		"role":      {"data_type": "int",  "not_null": true},
		"field_hit":  {"data_type": "int",  "not_null": true},
		"field_eva":  {"data_type": "int",  "not_null": true},
		"engage_hit": {"data_type": "int",  "not_null": true},
		"engage_eva": {"data_type": "int",  "not_null": true},
		"atk_growth": {"data_type": "int",  "not_null": true},
		"hp_growth":  {"data_type": "int",  "not_null": true},
		"pilot_cards": {"data_type": "text", "not_null": true},
		# 주력 메크 — `mechs.id` 를 `|` 로(M4). 런 시작 숙련도가 높게 시작한다.
		"main_mechs":  {"data_type": "text", "not_null": true},
		# Mech preference, best first — same as `players.mech_pref` (§15 A).
		"mech_pref":   {"data_type": "text", "not_null": true},
	},
	# 포지션별 파일럿 카드 슬롯 3칸. 각 칸은 `|` 로 이은 카드 분류(`cards.card_cat`)
	# 목록이고, 그 칸은 분류가 하나라도 겹치는 카드 중에서 채운다. 위치 키는
	# top / jungle / mid / carry / support (`GameEnums.position_key`).
	"pilot_card_slots": {
		"position":  {"data_type": "text", "primary_key": true, "not_null": true},
		"slot1":     {"data_type": "text", "not_null": true},
		"slot2":     {"data_type": "text", "not_null": true},
		"slot3":     {"data_type": "text", "not_null": true},
	},
	# 주간 훈련판에 올리는 코스 타일. `shape` 은 `/` 로 줄을 나눈
	# 색 문자열(한 줄 = 하루, 한 글자 = 선수 한 명), `exp` 은 `|` 로 이은
	# `스탯:값` 목록(`all` = 여섯 전부), `effect` 는 `;` 로 이은 절 목록.
	# 문법과 색 표는 `features/season/training/TrainingTile.gd` 가 소유한다.
	"training_tiles": {
		"id":          {"data_type": "text", "primary_key": true, "not_null": true},
		"name_key":        {"data_type": "text", "not_null": true},
		"grade":       {"data_type": "int",  "not_null": true},
		# Upgrade line (`basic`, `field_hit` …) — optional, "" = the tile is its own line.
		# Owning a higher grade of a line replaces the lower one (`TrainingCourses`).
		"line":        {"data_type": "text", "not_null": false},
		"shape":       {"data_type": "text", "not_null": true},
		"exp":         {"data_type": "text", "not_null": true},
		"effect":      {"data_type": "text", "not_null": true},
		# Facility (base-map spot H E C D G M Q W) — optional, "" = the course's first cell colour.
		"facility":    {"data_type": "text", "not_null": false},
	},
	"scenarios": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":       {"data_type": "text", "not_null": true},
		"salary_cap": {"data_type": "int",  "not_null": true},
		"desc_key":       {"data_type": "text", "not_null": true},
	},
	# 선수 레벨 1..10 — 모든 선수 공통. 값은 Lv1 대비 **누적** 가산.
	"pilot_levels": {
		"level":        {"data_type": "int", "primary_key": true, "not_null": true},
		"stat_bonus":   {"data_type": "int", "not_null": true},
		"salary_bonus": {"data_type": "int", "not_null": true},
		# Levelup currency to go from level-1 to this level (`currency.levelup`, Lv0 = 0).
		"levelup_cost": {"data_type": "int", "not_null": true},
		# Cumulative pilot EXP from Lv0 **inside one rank** to reach this level (reset on rank-up).
		"exp_required": {"data_type": "int", "not_null": true},
	},
	# ── M3~M7 ──────────────────────────────────────────────────────────────
	# 감독 타입(운영형 / 실전형) — 초기 감독 스탯 6종(1~20).
	"manager_types": {
		"id":        {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":      {"data_type": "text", "not_null": true},
		"gender":    {"data_type": "text", "not_null": true},
		"training":  {"data_type": "int",  "not_null": true},
		"tactics":   {"data_type": "int",  "not_null": true},
		"knowledge": {"data_type": "int",  "not_null": true},
		"mental":    {"data_type": "int",  "not_null": true},
		"analysis":  {"data_type": "int",  "not_null": true},
		"finance":   {"data_type": "int",  "not_null": true},
		"desc_key":      {"data_type": "text", "not_null": true},
	},
	# 스태프 — `job` 은 coach_training / coach_tactics / coach_knowledge /
	# analyst / finance / assistant. 스탯 6종(1~20), `salary` 는 주급.
	"staff": {
		"id":        {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":      {"data_type": "text", "not_null": true},
		"job":       {"data_type": "text", "not_null": true},
		"training":  {"data_type": "int",  "not_null": true},
		"tactics":   {"data_type": "int",  "not_null": true},
		"knowledge": {"data_type": "int",  "not_null": true},
		"mental":    {"data_type": "int",  "not_null": true},
		"analysis":  {"data_type": "int",  "not_null": true},
		"finance":   {"data_type": "int",  "not_null": true},
		"salary":    {"data_type": "int",  "not_null": true},
	},
	# 시설 레벨 1..5 — 주간 유지비, 다음 레벨 업그레이드 비용(최고 레벨 0),
	# 효과 배율 넷(100 = 변화 없음).
	"facilities": {
		"level":         {"data_type": "int", "primary_key": true, "not_null": true},
		"upkeep":        {"data_type": "int", "not_null": true},
		"upgrade_cost":  {"data_type": "int", "not_null": true},
		"train_exp_pct": {"data_type": "int", "not_null": true},
		"mastery_pct":   {"data_type": "int", "not_null": true},
		"incident_pct":  {"data_type": "int", "not_null": true},
		"income_pct":    {"data_type": "int", "not_null": true},
	},
	# 멘탈 이벤트(면담 · 외출 · 사건 · 기자회견) — 문법은 features/season/mental/README.md.
	"mental_events": {
		"id":           {"data_type": "text", "primary_key": true, "not_null": true},
		"kind":         {"data_type": "text", "not_null": true},
		"manager_type": {"data_type": "int",  "not_null": true},
		"stage":        {"data_type": "int",  "not_null": true},
		"cond":         {"data_type": "text", "not_null": true},
		"effects":      {"data_type": "text", "not_null": true},
		"weight":       {"data_type": "int",  "not_null": true},
	},
	# 멘탈 이벤트 대사 (D6) — slot line / choice / say, choice = 선택지 번호(line 은 빈 칸 → 0, 무시),
	# branch "" / ok / ng (say 만), seq = 그 slot 안 순서. 텍스트는 l10n key.
	"mental_texts": {
		"id":       {"data_type": "text", "primary_key": true, "not_null": true},
		"event_id": {"data_type": "text", "not_null": true},
		"slot":     {"data_type": "text", "not_null": true},
		"choice":   {"data_type": "int",  "not_null": true},
		"branch":   {"data_type": "text", "not_null": true},
		"seq":      {"data_type": "int",  "not_null": true},
		"text_key": {"data_type": "text", "not_null": true},
	},
	# ── M8~M10 ─────────────────────────────────────────────────────────────
	# 감독 특성 — `key` 는 런타임 분기(효과 표는 features/meta/traits/README.md),
	# `polarity` "+" = 긍정(보너스 점수 `bonus_cost` 소모) / "-" = 부정(제공),
	# `layer` outgame / ingame, `unlock` 해금 조건 식(빈 칸 = 조건 없음),
	# `default_owned` 1 = 처음부터 보유, `craft_cost` 특성 재료(0 = 제작 불가).
	"traits": {
		"id":            {"data_type": "int",  "primary_key": true, "not_null": true},
		"key":           {"data_type": "text", "not_null": true},
		"name_key":          {"data_type": "text", "not_null": true},
		"rarity":        {"data_type": "int",  "not_null": true},
		"polarity":      {"data_type": "text", "not_null": true},
		"bonus_cost":    {"data_type": "int",  "not_null": true},
		"layer":         {"data_type": "text", "not_null": true},
		"p1":            {"data_type": "int",  "not_null": true},
		"p2":            {"data_type": "int",  "not_null": true},
		"unlock":        {"data_type": "text", "not_null": true},
		"default_owned": {"data_type": "int",  "not_null": true},
		"craft_cost":    {"data_type": "int",  "not_null": true},
		"desc_key":          {"data_type": "text", "not_null": true},
	},
	# 감독 레벨 1..25 — 그 레벨에 닿는 **누적** 감독 EXP.
	"manager_levels": {
		"level":        {"data_type": "int", "primary_key": true, "not_null": true},
		"exp_required": {"data_type": "int", "not_null": true},
	},
	# Per-pilot rank rows, rank 1..5 (cumulative: reaching rank R applies rows 1..R; several
	# rows may share a rank). `kind` stat_flat (six stats +value) / salary_down (base salary
	# −value) / stat_growth (that pilot's training EXP +value%) / card_swap (value =
	# "slot:card_id", 0-based pilot-card slot). Text = l10n template `breakthrough.kind.*`.
	"pilot_ranks": {
		"id":       {"data_type": "int",  "primary_key": true, "not_null": true},
		"pilot_id": {"data_type": "int",  "not_null": true},
		"rank":     {"data_type": "int",  "not_null": true},
		"kind":     {"data_type": "text", "not_null": true},
		"value":    {"data_type": "text", "not_null": true},
	},
	# 가챠 등급 가중치 — `pool` pilot / trait.
	"gacha_rates": {
		"id":     {"data_type": "int",  "primary_key": true, "not_null": true},
		"pool":   {"data_type": "text", "not_null": true},
		"rarity": {"data_type": "int",  "not_null": true},
		"weight": {"data_type": "int",  "not_null": true},
	},
	# 주간패스(무료) 레벨 보상 — `currency` 는 프로필 재화 키.
	"pass_rewards": {
		"level":    {"data_type": "int",  "primary_key": true, "not_null": true},
		"currency": {"data_type": "text", "not_null": true},
		"amount":   {"data_type": "int",  "not_null": true},
	},
	# §15 A — mech upgrades (돌파형): reaching mastery `level` (3 / 4 / 5) on `mech_id`
	# unlocks this step (cumulative). `target` passive → `param` (p1 | p2) of the mech's
	# passive += `value`; `target` card → mech card `card_id` is swapped for its
	# `mech_cards.upgrade_id` row ("+"). `desc_key` = l10n `mastery.upgrade.{id}.desc`
	# ({from} / {to} = the passive param or the card cost before / after).
	"mech_upgrades": {
		"id":       {"data_type": "int",  "primary_key": true, "not_null": true},
		"mech_id":  {"data_type": "int",  "not_null": true},
		"level":    {"data_type": "int",  "not_null": true},
		"target":   {"data_type": "text", "not_null": true},
		"param":    {"data_type": "text", "not_null": true},
		"card_id":  {"data_type": "int",  "not_null": true},
		"value":    {"data_type": "int",  "not_null": true},
		"desc_key": {"data_type": "text", "not_null": true},
	},
	# ── §14 ───────────────────────────────────────────────────────────────
	# 기벽(런 한정 선수 패시브, 긍정 스탯 보정만) — `grade` 0 일반 / 1 희귀 / 2 영웅,
	# `stats` "stat:n|stat:n" 상시 가산, `cond` 빈 칸 또는 조건식(features/season/quirk/README.md),
	# `cond_stats` 조건 충족 시 추가 가산, `weight` 같은 등급 안 뽑기 가중치.
	"quirks": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name_key":       {"data_type": "text", "not_null": true},
		"grade":      {"data_type": "int",  "not_null": true},
		"stats":      {"data_type": "text", "not_null": true},
		"cond":       {"data_type": "text", "not_null": true},
		"cond_stats": {"data_type": "text", "not_null": true},
		"weight":     {"data_type": "int",  "not_null": true},
		"desc_key":       {"data_type": "text", "not_null": true},
	},
	# 재무 특별 지출(잉여 잔고 사용처) — `kind` 별 p1 · p2 뜻은 features/season/finance/README.md,
	# `weeks` 지속 주(0 = 즉시), `cond` 구매 조건식(빈 칸 = 없음).
	"finance_specials": {
		"id":    {"data_type": "text", "primary_key": true, "not_null": true},
		"name_key":  {"data_type": "text", "not_null": true},
		"kind":  {"data_type": "text", "not_null": true},
		"cost":  {"data_type": "int",  "not_null": true},
		"p1":    {"data_type": "text", "not_null": true},
		"p2":    {"data_type": "text", "not_null": true},
		"weeks": {"data_type": "int",  "not_null": true},
		"cond":  {"data_type": "text", "not_null": true},
		"desc_key":  {"data_type": "text", "not_null": true},
	},
	# §16 — seven facilities per team (`FacilitySystem`); `cost_pct` = % of facilities.csv upgrade_cost.
	"facility_defs": {
		"id":       {"data_type": "text", "primary_key": true, "not_null": true},
		"kind":     {"data_type": "text", "not_null": true},
		"name_key": {"data_type": "text", "not_null": true},
		"desc_key": {"data_type": "text", "not_null": true},
		"stat":     {"data_type": "text", "not_null": true},
		"spot":     {"data_type": "text", "not_null": true},
		"icon":     {"data_type": "text", "not_null": true},
		"cost_pct": {"data_type": "int",  "not_null": true},
	},
	# §16 — research rows per facility (`ResearchSystem`); p1 / p2 meaning per kind (facility/README.md).
	"research": {
		"id":         {"data_type": "text", "primary_key": true, "not_null": true},
		"facility":   {"data_type": "text", "not_null": true},
		"kind":       {"data_type": "text", "not_null": true},
		"name_key":   {"data_type": "text", "not_null": true},
		"desc_key":   {"data_type": "text", "not_null": true},
		"weeks":      {"data_type": "int",  "not_null": true},
		"min_level":  {"data_type": "int",  "not_null": true},
		"repeatable": {"data_type": "int",  "not_null": true},
		"p1":         {"data_type": "text", "not_null": true},
		"p2":         {"data_type": "text", "not_null": true},
		"icon":       {"data_type": "text", "not_null": true},
	},
}


# 전체 CSV 를 검증하고 game.db 를 다시 만든다. 성공하면 빈 문자열, 실패하면
# 사람이 읽을 수 있는 오류 문자열을 돌려준다(어느 CSV 의 어느 컬럼인지 포함).
# 검증은 **전부 통과할 때만** 쓰기로 넘어간다 — 반쯤 갱신된 DB 를 남기지 않는다.
func rebuild(verbose: bool = true) -> String:
	if verbose:
		print("=== Rebuild game.db: starting ===")

	# ── Step 1: Parse and validate all CSV files ──────────────────────────────
	var all_data: Dictionary = {}   # table_name → Array of Dicts
	var errors: Array = []

	for table_name in SCHEMAS.keys():
		var csv_path: String = CSV_DIR + table_name + ".csv"
		var result = parse_csv(csv_path, table_name, SCHEMAS[table_name])
		if result is String:
			errors.append(result)
		else:
			all_data[table_name] = result

	if not errors.is_empty():
		return "game.db NOT rebuilt — validation errors:\n  " + "\n  ".join(errors)

	# ── Step 2: Open DB, drop old tables, insert fresh data ──────────────────
	var db := SQLite.new()
	db.path = DB_PATH
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return "Rebuild game.db: failed to open " + DB_PATH

	for table_name in SCHEMAS.keys():
		# IF EXISTS keeps the first run quiet when a new table was just added.
		db.query("DROP TABLE IF EXISTS " + table_name)
		db.create_table(table_name, TABLE_DEFS[table_name])
		var rows: Array = all_data[table_name]
		for row in rows:
			db.insert_row(table_name, row)
		if verbose:
			print("  ✓ %s — %d rows" % [table_name, rows.size()])

	db.close_db()
	if verbose:
		print("=== game.db rebuilt successfully at %s ===" % DB_PATH)

	# ── Step 3: l10n build dev — 데이터 CSV 의 key 컬럼과 l10n 원본을 함께 검증 ──
	# (docs/localization_design.md §7.1). DB 는 이미 썼다 — 실패해도 지우지 않고 오류만 돌려준다.
	var l10n_err: String = _build_l10n(verbose)
	if l10n_err != "":
		return "game.db rebuilt, but " + l10n_err
	return ""


func _build_l10n(verbose: bool) -> String:
	var l10n = load("res://addons/l10n_tool/core/l10n.gd").open()
	l10n.echo = verbose
	if not l10n.ok():
		return "l10n build dev failed — " + "\n".join(l10n.output)
	var errors: int = l10n.cmd_build("dev")
	if errors > 0:
		return "l10n build dev failed — %d error(s), see res://data/l10n/generated/report.md" % errors
	return ""


## Card tables whose `keyword` column is a `|` list (`CardData.has_keyword`).
const KEYWORD_TABLES: Array = ["cards", "mech_cards"]
## Keyword pairs one card may not carry together. `preserve` (never discarded) and
## `volatile` (vanishes when discarded) answer the same question opposite ways.
const EXCLUSIVE_KEYWORDS: Array = [["preserve", "volatile"]]


# Row-level data rules beyond column / pk checks. Returns "" when the row is fine.
func _check_row(table_name: String, row: Dictionary) -> String:
	if not table_name in KEYWORD_TABLES or not row.has("keyword"):
		return ""
	var kws: PackedStringArray = String(row["keyword"]).split("|", false)
	for pair in EXCLUSIVE_KEYWORDS:
		if kws.has(pair[0]) and kws.has(pair[1]):
			return "has both keywords '%s' and '%s' (mutually exclusive)" % [pair[0], pair[1]]
	return ""


# Returns Array of Dicts on success, or an error String on failure.
func parse_csv(path: String, table_name: String, schema: Dictionary) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Missing CSV: %s" % path

	var header_line: String = file.get_line().strip_edges()
	var headers: Array = split_csv_line(header_line)
	# Trim whitespace from header names
	for i in headers.size():
		headers[i] = (headers[i] as String).strip_edges()

	# Validate required columns
	var req_cols: Array = schema["req"]
	for col in req_cols:
		if not col in headers:
			file.close()
			return "Table '%s': missing required column '%s' in %s" % [table_name, col, path]

	var pk_col: String = schema["pk"]

	var rows: Array = []
	var seen_pks: Dictionary = {}

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var values: Array = split_csv_line(line)
		# Pad or trim to match header count
		while values.size() < headers.size():
			values.append("")
		var row: Dictionary = {}
		for i in headers.size():
			row[headers[i]] = (values[i] as String).strip_edges()

		# Duplicate PK check
		var pk_val: String = row[pk_col]
		if pk_val in seen_pks:
			file.close()
			return "Table '%s': duplicate primary key '%s' = '%s' in %s" % [table_name, pk_col, pk_val, path]
		seen_pks[pk_val] = true

		var rule_err: String = _check_row(table_name, row)
		if rule_err != "":
			file.close()
			return "Table '%s': %s = '%s' %s in %s" % [table_name, pk_col, pk_val, rule_err, path]

		# Cast numeric columns using TABLE_DEFS
		var col_defs: Dictionary = TABLE_DEFS[table_name]
		for col_name in col_defs.keys():
			if col_name in row:
				var dtype: String = col_defs[col_name]["data_type"]
				if dtype == "int":
					row[col_name] = int(row[col_name])
				elif dtype == "real":
					row[col_name] = float(row[col_name])
				# text stays as String

		rows.append(row)

	file.close()
	return rows


# Splits one CSV line into fields. Handles double-quoted fields (so descriptions
# may contain commas) and the standard "" escape for an embedded quote.
# Whitespace inside fields is preserved; outer trimming happens at the call site.
func split_csv_line(line: String) -> Array:
	var result: Array = []
	var i: int = 0
	var n: int = line.length()
	while i <= n:
		var field: String = ""
		if i < n and line[i] == "\"":
			i += 1
			while i < n:
				if line[i] == "\"":
					if i + 1 < n and line[i + 1] == "\"":
						field += "\""
						i += 2
					else:
						i += 1
						break
				else:
					field += line[i]
					i += 1
		else:
			while i < n and line[i] != ",":
				field += line[i]
				i += 1
		result.append(field)
		if i < n and line[i] == ",":
			i += 1
			if i == n:
				# Trailing comma → empty final field.
				result.append("")
				break
		else:
			break
	return result
