class_name CardImages
extends RefCounted

# 카드 한 장의 **일러스트 조회**. `PilotImages` / `MechImages` 와 같은 자리이고,
# 규칙도 같다 — 그림을 어디서 가져오는지는 이 파일 하나만 안다.
#
# 카드는 **표시 이름이 아니라 식별자**(`CardData.card_uid()` — `pilot:<cards.id>` /
# `mech:<mech_cards.id>`)로 찾는다. 이름은 언어마다 다르고 바뀔 수 있다(l10n).
#
#   images/card/<uid>.png    — 그 카드 전용 아트(`:` → `_`, 예: `pilot_12.png`. 있으면 언제나 이쪽이 이긴다)
#   images/ground/deadlock_items/<타입>_<아이템>.png — `ITEM_ART` 가 카드 식별자에 짝지은
#                              Deadlock 아이템 아이콘(효과가 비슷한 아이템으로 골랐다).
#                              접두사 `wpn_` / `spt_` / `vit_` 는 deadlock.wiki/Items 의
#                              Weapon / Spirit / Vitality 분류 — 카드 타입(`type_for`)의 근거다
#   images/ground/N.png      — 위 둘 다 없는 카드(표에 없는 새 카드)가 나눠 쓰는 **배경 5종**
#
# **배경은 카드 식별자로 고른다**(`uid.hash()`). 무작위로 고르면 같은 카드가
# 뽑을 때마다 다른 그림을 달고 나와 "이 그림이 이 카드"라는 연결이 서지 않고,
# 순번으로 고르면 손패에 들어온 순서가 그림을 정해 같은 카드가 자리마다 달라진다.
# 식별자 해시는 실행과 무관하게 같은 답을 주므로, 전용 아트가 채워지기 전까지도
# 카드 한 장이 자기 그림을 계속 들고 다닌다.
#
# **`load()` 를 그냥 부르지 않는다** — 파일이 없으면 Godot 이 에러를 뱉으며 null 을
# 돌려주므로 `ResourceLoader.exists()` 로 먼저 묻는다(`MechImages` 와 같은 이유).

const CARD_DIR: String = "res://resources/images/card/"
const GROUND_DIR: String = "res://resources/images/ground/"
const ITEM_DIR: String = "res://resources/images/ground/deadlock_items/"
## 카드 식별자(`CardData.card_uid()`) → Deadlock 아이템 파일명(확장자 없이, 타입 접두사 포함).
## cards.csv + mech_cards.csv 107장 전부(줄 끝 주석 = 카드 이름), 한 아이템은 한 카드에만 쓴다.
## 카드를 더하면 여기도 고친다
## (빠지면 조용히 배경 5종으로 떨어진다).
const ITEM_ART: Dictionary = {
	"pilot:1": "wpn_Opening Rounds",  # 교전 개시
	"pilot:2": "vit_Cloak of Opportunity",  # 완벽한 기회
	"pilot:3": "wpn_Point Blank",  # 결투
	"pilot:5": "wpn_Active Reload",  # 전투 준비
	"pilot:6": "wpn_Kinetic Dash",  # 정밀 이동
	"pilot:7": "wpn_Rapid Rounds",  # 찌르기
	"pilot:8": "wpn_Sharpshooter",  # 정밀 공격
	"pilot:9": "wpn_Burst Fire",  # 연속 공격
	"pilot:11": "wpn_Fleetfoot",  # 전진
	"pilot:12": "spt_Quicksilver Reload",  # 교환
	"pilot:13": "spt_Compress Cooldown",  # 조정
	"pilot:14": "spt_Focus Lens",  # 임기응변
	"pilot:15": "spt_Rapid Recharge",  # 재빠른 사고
	"pilot:16": "spt_Superior Cooldown",  # 집중
	"pilot:17": "spt_Transcendent Cooldown",  # 사전 준비
	"pilot:18": "vit_Fury Trance",  # 아드레날린
	"pilot:19": "wpn_Headhunter",  # 계획 살인
	"pilot:21": "vit_Rescue Beam",  # 복귀
	"pilot:22": "vit_Grit",  # 보호
	"pilot:23": "spt_Spirit Snatch",  # 약탈
	"pilot:24": "vit_Battle Vest",  # 소극적인 태세
	"pilot:25": "wpn_Close Quarters",  # 공격적인 라인전
	"pilot:26": "spt_Refresher",  # 재고
	"pilot:27": "vit_Eternal Gift",  # 완벽한 마무리
	"pilot:28": "spt_Duration Extender",  # 계획 중시
	"pilot:29": "wpn_Titanic Magazine",  # 과감한 정리
	"pilot:30": "wpn_Glass Cannon",  # 솔로 퍼포먼스
	"pilot:31": "wpn_Monster Rounds",  # 정글 파밍
	"pilot:32": "spt_Tankbuster",  # 전령 제압
	"pilot:33": "vit_Trophy Collector",  # 용 보상
	"pilot:34": "wpn_Lucky Shot",  # 핫핸드
	"pilot:35": "vit_Sprint Boots",  # 이동
	"pilot:36": "wpn_Intensifying Magazine",  # 골드러시
	"pilot:37": "wpn_Berserker",  # 몰입
	"pilot:38": "vit_Extra Stamina",  # 워밍업
	"pilot:39": "spt_Superior Duration",  # 신중한 예산
	"pilot:40": "spt_Extra Charge",  # 성장 가속
	"pilot:41": "vit_Shadow Strike",  # 대결
	"pilot:42": "wpn_Shadow Weave",  # 매복
	"pilot:43": "vit_Return Fire",  # 무모한 돌격
	"pilot:44": "wpn_Headshot Booster",  # 자신감
	"pilot:45": "vit_Dispel Magic",  # 맑은 정신
	"pilot:46": "wpn_Capacitor",  # 준비 태세
	"mech:1": "spt_Lightning Scroll",  # 천둥 폭풍
	"mech:2": "spt_Spirit Strike",  # 천공의 일격
	"mech:3": "wpn_Tesla Bullets",  # 꿰뚫는 번개
	"mech:4": "spt_Golden Goose Egg",  # 캐시
	"mech:5": "spt_Decay",  # 스캐빈저
	"mech:6": "wpn_Crushing Fists",  # 로켓 펀치
	"mech:7": "wpn_Alchemical Fire",  # 미사일
	"mech:8": "wpn_Extended Magazine",  # 미사일 준비
	"mech:9": "wpn_Split Shot",  # 정밀 폭격
	"mech:10": "wpn_Ricochet",  # 전장 강타
	"mech:11": "spt_Mystic Reverb",  # 계시
	"mech:12": "wpn_Heroic Aura",  # 결속
	"mech:13": "wpn_Haunting Shot",  # 락온
	"mech:14": "spt_Torment Pulse",  # 테러
	"mech:15": "spt_Mystic Burst",  # 파괴
	"mech:16": "vit_Celestial Blessing",  # 승전보
	"mech:17": "wpn_Melee Charge",  # 돌격
	"mech:18": "wpn_Recharging Rush",  # 질주
	"mech:19": "wpn_Armor Piercer",  # 철거
	"mech:20": "vit_Juggernaut",  # 우세한 전장
	"mech:21": "vit_Unstoppable",  # 격렬한 돌진
	"mech:22": "wpn_Crippling Headshot",  # 처형
	"mech:23": "wpn_Swift Striker",  # 일격
	"mech:24": "spt_Cold Front",  # 휩쓸기
	"mech:25": "vit_Phantom Strike",  # 유령의 올가미
	"mech:26": "spt_Cursed Relic",  # 전쟁의 사슬
	"mech:27": "vit_Leech",  # 영혼 포식
	"mech:28": "vit_Colossus",  # 몸집 불리기
	"mech:29": "wpn_Hunter's Aura",  # 추적 개시
	"mech:30": "vit_Majestic Leap",  # 강습
	"mech:31": "vit_Reactive Barrier",  # 최첨단 보호
	"mech:32": "spt_Surge of Power",  # 초고출력
	"mech:33": "spt_Arctic Blast",  # 개시
	"mech:34": "vit_Rebuttal",  # 주먹다짐
	"mech:35": "wpn_Blood Tribute",  # 고통과 쾌감
	"mech:36": "spt_Suppressor",  # 제압 전투
	"mech:37": "spt_Omnicharge Signet",  # 리부트
	"mech:38": "spt_Mystic Vulnerability",  # 단계 A
	"mech:39": "wpn_Spirit Rend",  # 단계 B
	"mech:40": "spt_Boundless Spirit",  # 단계 C
	"mech:41": "wpn_Stalker",  # 약자 멸시
	"mech:42": "vit_Electric Slippers",  # 전격전
	"mech:43": "wpn_Runed Gauntlets",  # 즉발 베기
	"mech:44": "spt_Mystic Regeneration",  # 명상
	"mech:45": "vit_Warp Stone",  # 질풍
	"mech:46": "wpn_Frenzy",  # 신속
	"mech:47": "spt_Slowing Hex",  # 최면
	"mech:48": "spt_Vortex Web",  # 매혹적인 침공
	"mech:49": "vit_Siphon Bullets",  # 매혹
	"mech:50": "vit_Healing Nova",  # 공격 명령
	"mech:51": "wpn_Cultist Sacrifice",  # 투자
	"mech:52": "wpn_Mystic Shot",  # 간보기
	"mech:53": "vit_Guardian Ward",  # 지원 보호
	"mech:54": "vit_Divine Barrier",  # 수호
	"mech:55": "spt_Knockdown",  # 강타
	"mech:56": "spt_Disarming Hex",  # 탈진
	"mech:57": "spt_Unstable Concoction",  # 변덕
	"mech:58": "vit_Infuser",  # 밸런스
	"mech:59": "spt_Improved Spirit",  # 파란 약
	"mech:60": "vit_Extra Health",  # 붉은 가루
	"mech:61": "wpn_Hollow Point",  # 녹색 병
	"mech:62": "spt_Escalating Exposure",  # 죽음의 손가락
	"mech:63": "spt_Mercurial Magnum",  # 확신
	"mech:64": "spt_Scourge",  # 사형 선고
}
## 카드 타입 — 아이템 파일명의 접두사. 이름판 색(`Card.TYPE_COLORS`)이 이것을 읽는다.
const TYPE_WEAPON: String = "wpn"
const TYPE_SPIRIT: String = "spt"
const TYPE_VITALITY: String = "vit"
## `images/ground/` 에 들어 있는 배경 장수. 파일을 더하면 이 수만 올린다.
const GROUND_COUNT: int = 5


## 이 카드가 걸칠 아트(`uid` = `CardData.card_uid()`). 전용 아트 → 아이템 아이콘 →
## 식별자로 고른 배경 순으로 찾고, 둘 다 없으면 null(호출자는 그때 빈 자리를 그대로 둔다).
static func art_for(uid: String) -> Texture2D:
	if uid.is_empty():
		return null
	uid = base_uid(uid)
	var own: String = CARD_DIR + uid.replace(":", "_") + ".png"
	if ResourceLoader.exists(own):
		return load(own) as Texture2D
	var item: Texture2D = item_for(uid)
	if item != null:
		return item
	return ground_for(uid)


## `ITEM_ART` 가 이 카드에 짝지은 아이템 아이콘. 표에 없거나 파일이 없으면 null.
static func item_for(uid: String) -> Texture2D:
	var item_name: String = ITEM_ART.get(uid, "")
	if item_name.is_empty():
		return null
	var path: String = ITEM_DIR + item_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 이 카드의 타입(`TYPE_*`). `ITEM_ART` 에 없는 카드는 빈 문자열 — 호출자가 중립색을 쓴다.
## 전용 아트(`images/card/`)가 생겨도 타입은 짝지은 아이템을 따른다.
static func type_for(uid: String) -> String:
	var item_name: String = ITEM_ART.get(base_uid(uid), "")
	var prefix: String = item_name.get_slice("_", 0)
	if prefix in [TYPE_WEAPON, TYPE_SPIRIT, TYPE_VITALITY]:
		return prefix
	return ""


## An upgraded ("+") pilot card (§15 C, `cards.upgrade_id`) wears its base card's art and
## type: `pilot:101` → `pilot:1`. Any other uid comes back unchanged.
static func base_uid(uid: String) -> String:
	if not uid.begins_with("pilot:"):
		return uid
	var tree := Engine.get_main_loop() as SceneTree
	var gm: Node = tree.root.get_node_or_null("GameManager") if tree != null else null
	if gm == null or not gm.has_method("card_upgrade_base"):
		return uid
	var base: int = int(gm.card_upgrade_base(int(uid.get_slice(":", 1))))
	return "pilot:%d" % base if base >= 0 else uid


## 식별자 해시로 고른 배경 한 장. 전용 아트를 건너뛰고 배경만 필요할 때 쓴다.
static func ground_for(uid: String) -> Texture2D:
	if GROUND_COUNT <= 0:
		return null
	var idx: int = absi(uid.hash()) % GROUND_COUNT + 1
	var path: String = GROUND_DIR + "%d.png" % idx
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
