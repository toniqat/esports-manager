class_name PilotData
extends RefCounted

# Source pilot id from the players.csv pool (0..39), or 100..119 for INTL
# pilots. -1 when the battle was launched standalone (no match_ctx) — in that
# case the renderer falls back to a placeholder circle. Currently consumed by
# BattleRenderer to look up the pilot's circle portrait.
var pilot_id: int = -1
var role: int
var hp: int
var max_hp: int
var atk: int
var team: int
var grid_pos: Vector2i
var alive: bool           = true
# Turns until the pilot walks back out of their HQ. **사망 전용** — counts down
# in SimulationCore.process_respawns. 복귀(본진 귀환)는 전장을 비우지 않으므로
# 이 타이머를 쓰지 않는다: 죽지 않는 한 파일럿은 항상 전장 위에 있다.
var respawn_timer: int    = 0
# 이번 매치의 처치 수 / 사망 수. `BattleSim.mark_pilot_dead` 한 곳에서만 오른다.
# 킬로그와 성장치는 각자 다른 표를 쓰므로(피해 장부 / 킬 피드) 이 둘은 순수한
# 누적 카운터이고, 지금은 경쟁 심리(파일럿 스킬)가 상대 라이너와 견주는 데 쓴다.
var kills: int            = 0
var deaths: int           = 0
# 본진 복귀한 그 턴에는 HQ 에 서 있기만 하고 움직이지 않는다는 표시.
# RecallSystem.return_to_hq 가 켜고, 다음 이동 패스(SimulationCore.resolve_movement)
# 가 한 턴을 걸러 내면서 스스로 끈다 — 그래서 "복귀 → 다음 턴부터 레인으로".
var recall_hold: bool     = false
var lane: int             = GameEnums.LanePosition.GUERRILLA
var is_guerrilla: bool    = false
var waypoint_idx: int     = 0
# **`prev_grid_pos` 는 삭제됐다.** 전장 초상화가 "지나온 쪽"에 앉던 시절
# (BattleRenderer 의 이동 방향 배치)의 유일한 소비자였고, 초상화 자리가 팀 고정
# (아래 진영 = 아래 / 위 진영 = 위)으로 바뀌면서 아무도 읽지 않게 됐다. 아래의
# `anim_move_path` 와 헷갈리지 말 것 — 저쪽은 연출용 경로이고 렌더러가 소비하며
# 비운다.
var move_range: int       = 1                # cells advanced per minute
var jungle_start_pref: int = -1              # GameEnums.JungleStartDir or -1 (none)
# Sticky roam destination for junglers, (-1,-1) = none yet. Held across turns by
# SimulationCore._jungle_goal_for so the roam target cannot flip mid-route.
var jungle_roam_target: Vector2i = Vector2i(-1, -1)
# 전장 명중 / 회피 — `SimulationCore.roll_hit` 이 읽는다
# (`PlayerData.field_hit` / `field_eva` 에서 온다).
var hit: int              = 50
var evasion: int          = 50
# 교전 명중 / 회피 — `TurnEngageSim` 이 읽는다
# (`PlayerData.engage_hit` / `engage_eva` 에서 온다). 전장과 **따로 사는**
# 것이 요점이다: 같은 선수가 라인전에서 강한 것과 한타에서 강한 것은
# 다른 일이라, 그 둘을 가르는 것이 훈련판의 선택지가 된다.
var engage_hit: int       = 50
var engage_eva: int       = 50
# 성장 계수 배율 — `BattleSim.refresh_growth_stats` 가 `GROWTH_ATK_PER_SCORE` /
# `GROWTH_HP_PER_SCORE` 에 곱한다. 1.0 이 기준(`PlayerData.GROWTH_STAT_BASE` = 50).
# **스탯을 직접 밀지 않고 성장률을 민다** — 전자는 재계산 한 번에 지워지고,
# 훈련이 바꾸는 것은 개시 스탯이 아니라 경기가 흘랬가는 기울기다.
var atk_growth_mult: float = 1.0
var hp_growth_mult: float  = 1.0
# 존재감 — 전투 개시(engage)에서만 참조. 근접 메크 4, 원거리 메크 2.
# 피격 가중치(높을수록 자주 표적이 됨).
#
# **속도(speed)는 삭제됐다** — 교전이 라운드 기반 턴제가 되면서 라운드마다
# 전원이 한 번씩 행동하므로 행동 빈도를 가르는 스탯이 없다. 되살리지 말 것.
var presence: int         = 4
# 보호막. Granted by the 보호 card; removed on 본진 복귀 (RecallSystem clears it).
# Damage absorption isn't wired into SimulationCore yet — this field is the
# data hook for future integration so card effects can build up the value now.
var shield: int           = 0

# ─── 메크가 거는 지속 상태 ────────────────────────────────────────────────────
# 아래 필드는 전부 **메크 패시브와 메크 카드**(`mech_passives` / `mech_cards`)가
# 만든다. `MechSkillSystem` 이 켜고 끄며, 소비자는 그 값을 원래 계산하던 자리
# (`SimulationCore` 의 피해·명중, `BattleSim.refresh_growth_stats`,
# `TurnEngageSim`)다 — 파일럿 스킬과 같은 규칙이다.

## 취약 — **1마다 받는 피해 +1%.** 원딜 A(취약 각인)가 쌓는다. 누적되며 상한이
## 없고, 자기 작전 단계가 끝나면 걷힌다(각인 자체가 "이번 작전 단계 동안"이다).
var vulnerable: int = 0
## 반응 장갑 — **공격을 한 번 받을 때마다 그 피해를 90% 줄이고 1 소모한다.**
## 탱커 G 의 패시브와 두 카드가 쌓는다. 보호막과 달리 값이 아니라 **횟수**다.
var reactive_armor: int = 0
## 받는 피해 배율 가산분(죽음의 손가락 +0.25). 전장 이탈(복귀/사망)까지 남는다.
var damage_taken_bonus: float = 0.0
## 현상금 — 지원 V 가 찍는다. [확신] 이 이 값의 몇 %를 피해로 바꾼다.
var bounty: float = 0.0
## 목표 — 이 파일럿을 지목한 시전자와 그가 얹는 피해 배율(단계 A: +0.15).
## 한 명만 지목할 수 있다: 새로 찍으면 앞의 것을 덮는다.
var marked_by: PilotData = null
var marked_bonus: float = 0.0
## 추적 — `[{"pilot": PilotData, "expire_turn": int}, …]`. 이 파일럿이 전투에
## 참여하면 목록의 파일럿도 함께 끌려 들어간다(탱커 E 의 [추적]).
var tracked_by: Array = []
## 결속 — 시전자가 전투에 참여할 때 함께 들어가는 아군(원딜 I 의 [결속]).
var engage_link: PilotData = null
## 탈진 — 이번 작전 단계 동안 전투에 참여할 수 없다(지원 S 의 [탈진]).
var engage_locked: bool = false
## 강타 — 다음 교전에서 이 파일럿이 피해를 준 적을 그 라운드 동안 기절시킨다.
var stun_charge: bool = false
## 기절 — 이 라운드 동안 행동 불능(교전 무대 전용).
var stunned_rounds: int = 0
## 매혹 — 이 파일럿이 버는 성장치를 그대로 복사해 가는 상대와 그 만료 턴.
var growth_link_to: PilotData = null
var growth_link_expire_turn: int = -1
## 예약이 없다는 표시. 실제 셀과 절대 겹치지 않도록 격자 밖 좌표를 쓴다.
const NO_RETURN := Vector2i(-9999, -9999)
## 자리 되돌리기 — [질풍]이 이 파일럿을 적 칸으로 던지기 **직전**의 칸.
## 자기 작전 단계가 끝나면 `MechSkillSystem.on_phase_end` 가 여기로 되돌린다.
## `NO_RETURN` 이면 예약이 없다 — 사망 / 복귀는 예약을 함께 지운다(그 둘이
## 이미 자리를 옮긴 뒤라, 되돌리면 방금 일어난 일을 무르는 꼴이 된다).
var phase_return_cell: Vector2i = NO_RETURN

# ─── 영구 스탯 보정 (메크가 쌓는 몫) ──────────────────────────────────────────
# `BattleSim.refresh_growth_stats` 가 `base_atk` / `base_max_hp` 에서 스탯을 **다시
# 계산**하므로, 메크가 얹는 증가분은 `atk` / `max_hp` 를 직접 밀면 그 재계산
# 한 번에 지워진다. 그래서 카드의 일시 공격력(`atk_buff`)과 같은 이유로 별도
# 필드로 산다 — 이쪽은 만료가 없는 **영구** 몫이라는 점만 다르다.
## 공격력 고정 가산(조준 보정 +1/명중, [녹색 병] +2).
var bonus_atk_flat: int = 0
## 공격력 배율 가산(영혼 수확 +1%/타).
var bonus_atk_mult: float = 0.0
## 최대 체력 고정 가산([몸집 불리기] +20, [붉은 가루] +20, 영혼 수확 +5/타,
## 고통과 쾌감 패시브의 피해 20%).
var bonus_max_hp: int = 0

# ─── 성장 (인게임 누적) ───────────────────────────────────────────────────────
# **성장은 시간이 아니라 성장치(`score`)가 만든다.** 예전에는 살아 있기만 하면
# 매 턴 `BattleSim.GROWTH_PER_TURN` 만큼 `atk` 와 `max_hp` 가 함께 늘었는데,
# 둘이 **같은 비율**로 자라면 "몇 대 맞아야 죽는가"가 수학적으로 영원히 그대로다
# — 50턴에 둘 다 ×1.5 여도 교전 타수는 1타도 줄지 않는다. 성장이 안 보인 게
# 아니라 구조상 보일 수 없었다.
#
# 지금은 둘이 갈라져 있다. `growth` 는 공격력, `growth_hp` 는 최대 체력이고
# 둘 다 `score` 에서 파생된다(`BattleSim.refresh_growth_stats`) — 공격력이
# 4배 빠르게 자라므로 성장치가 쌓일수록 TTK 가 실제로 줄어든다.
#
# `base_atk` / `base_max_hp` 는 `_init` 이 채운다. 스폰 시점의 메크 스탯 주입
# (`SimulationCore._stats_for`)이 생성자를 거치므로, 성장 이전의 원본은 언제나
# 여기 남는다. 성장은 파일럿에 붙어 있으므로 **사망·리스폰으로 초기화되지 않는다**.
var base_atk: int         = 0
var base_max_hp: int      = 0
## 공격력 성장 배율분. `atk = base_atk × (1 + growth) + atk_buff`.
var growth: float         = 0.0
## 최대 체력 성장 배율분. 공격력의 1/4 속도로 자란다.
var growth_hp: float      = 0.0
# 카드가 거는 **일시적** 공격력 가산(전투 준비 등). `atk` 를 직접 밀면 성장
# 재계산이 그 사이에 끼었을 때 가산분이 통째로 지워지거나 두 번 빠진다 —
# 성장은 이제 점수가 바뀔 때마다(= 턴 한가운데서도) 다시 계산되므로 별도
# 필드로 들고 있어야 한다.
var atk_buff: int         = 0
# 성장치 **획득** 배율. 안전한 파밍(+10% → 1.10) / 완벽한 마무리(+25% → 1.25).
# 예전에는 성장 배율이었지만 성장이 점수에서 파생되면서 적립 배율이 됐다 —
# 결과는 같고(더 번 만큼 더 큰다) 배선이 한 겹 준다.
# 두 카드는 같은 필드를 쓰므로 **나중에 건 쪽이 덮어쓴다**(합산 아님).
var growth_rate_mult: float = 1.0
# 턴 만료형 적립 배율의 만료 턴. -1 = 없음. (안전한 파밍)
var growth_rate_expire_turn: int = -1
# 작전 단계 만료형 적립 배율 표시. (완벽한 마무리) — 다음 작전 단계 진입 시 해제.
var growth_until_phase: bool = false
# **영구 적립 배율 가산분.** 용 보상(`growth_perm:10`)이 얹는다. 위의 세 필드와
# 달리 만료도 해제도 없고 **누적된다** — 같은 파일럿에게 용 보상을 두 장 쓰면
# +20% 다. 별도 필드인 이유가 그 누적이다: `growth_rate_mult` 은 카드끼리 덮어
# 쓰는 슬롯이라(안전한 파밍 ↔ 완벽한 마무리) 거기에 얹으면 라인전 카드 한 장이
# 오브젝트 보상을 지워 버린다. 최종 배율은 `BattleSim.add_score` 에서
# `growth_rate_mult + growth_rate_bonus` 로 합쳐진다.
var growth_rate_bonus: float = 0.0

# ─── 지속 효과 장부 (카드 한 장 단위) ────────────────────────────────────────
# **누가 걸었는가**를 들고 있는 표. 위의 `growth_rate_bonus` / `bonus_max_hp` /
# `bonus_atk_flat` 은 여러 카드가 함께 쌓는 **합계 슬롯**이라, 상세 패널이 그
# 숫자만 읽으면 [용 보상]과 [핫핸드]가 한 칸에 뭉쳐 `+10%` 로만 보인다 —
# 무엇을 더 먹어야 하고 무엇이 이미 걸려 있는지가 그 한 칸에서 사라진다.
#
# 그래서 계산은 그대로 합계 슬롯이 하고(성장 재계산이 읽는 곳은 한 군데여야
# 한다) **표시만** 이 장부를 읽는다. 항목은 `(src, kind)` 로 합쳐지므로 같은
# 카드를 두 번 쓰면 한 줄에서 값이 커진다.
#
#   src   카드 이름 그대로 ([용 보상] · [핫핸드] · [파란 약] …)
#   kind  FX_GROWTH_RATE(적립 배율 %) / FX_MAX_HP(최대 체력) / FX_ATK(공격력)
#
# 장부에 없는 몫(메크 패시브가 직접 미는 영혼 수확 · 조준 보정 …)은 상세
# 패널이 **잔여분**으로 따로 한 줄 세운다 — 합계와 장부가 어긋나면 화면이
# 조용히 거짓말을 하게 되므로.
const FX_GROWTH_RATE := "growth_rate"
const FX_MAX_HP      := "max_hp"
const FX_ATK         := "atk"
var persistent_fx: Array = []   # Array[Dictionary] {src, kind, amount}


## 장부에 한 줄 적는다(같은 카드 · 같은 종류면 합친다). 실제 스탯은 부르는
## 쪽이 이미 밀었다 — 이 함수는 표시용 기록만 남긴다.
func log_persistent_fx(src: String, kind: String, amount: float) -> void:
	if src.is_empty() or is_zero_approx(amount):
		return
	for raw in persistent_fx:
		var e := raw as Dictionary
		if String(e["src"]) == src and String(e["kind"]) == kind:
			e["amount"] = float(e["amount"]) + amount
			return
	persistent_fx.append({"src": src, "kind": kind, "amount": amount})


## 장부가 기록한 그 종류의 합계. 상세 패널이 잔여분을 내는 데 쓴다.
func persistent_fx_total(kind: String) -> float:
	var total: float = 0.0
	for raw in persistent_fx:
		var e := raw as Dictionary
		if String(e["kind"]) == kind:
			total += float(e["amount"])
	return total


# ─── 성장치 (파일럿 점수) ─────────────────────────────────────────────────────
# 개시 1.00k 에서 시작해 경기 내내 누적되는 파일럿의 성장 통화 — MOBA 의 골드에
# 해당한다. 50턴 평균 25.00k, 잘 큰 캐리는 40.00k 을 넘긴다. 파일럿 스트립에
# 숫자로 찍히고 팀 점수는 팀원 합산이며 상한이 없다.
#
# **`growth` 는 여기서 파생된다** — 위의 성장 절 참조. 예전에는 둘이 완전히
# 무관해서(성장은 시간, 성장치는 기록) 킬을 따도 타워를 밀어도 스탯이 1도
# 변하지 않았다.
#
# 적립처는 셋이다: **전선 체류**(턴당), **정글 캠프**(정글러), **처치 현상금**
# (라스트힛 + 피해 비례 어시스트). 규칙과 상수는 전부 `BattleSim` 의 `SCORE_*`
# 절에 있고, 변동은 `BattleSim.add_score` 한 곳만 지난다.
var score: float          = 1.0   # = BattleSim.SCORE_START

# 이번 생에 **나를 때린 사람들**의 피해 기록. `PilotData attacker →
# Array[Vector2i]` 이고 각 항목은 `(때린 턴, 그 턴의 피해 합)` 이다 — 같은 턴에
# 들어온 피해는 한 항목으로 합쳐지므로 항목 수는 어시스트 창(15턴)을 넘지 않는다.
# 내가 쓰러질 때 `BattleSim.mark_pilot_dead` 가 이걸 읽어 현상금을 라스트힛과
# 어시스트에게 나눠 주고 비운다. 피해가 굴려지는 그 지점에서 쌓으므로
# (`BattleSim.record_pilot_damage`) 전장·교전 무대·공격 카드가 같은 표를 쓴다.
#
# **턴 도장을 찍는 이유는 만료 때문이다** — `BattleSim.SCORE_ASSIST_WINDOW_TURNS`
# 보다 오래된 피해는 어시스트 배분에서도 킬로그 명단에서도 빠진다. 그 판정은
# `BattleSim.live_damage_credit(victim)` 한 곳에서만 하고, 읽는 김에 만료된
# 항목을 실제로 지운다 — 이 사전을 직접 훑는 코드가 있으면 안 된다.
var damage_credit: Dictionary = {}

# ─── 라인전 스탯 ──────────────────────────────────────────────────────────────
# **전장 명중 판정 전용** 배율 (+0.10 / −0.10). `SimulationCore.roll_hit` 이
# 공격자의 `hit` 과 방어자의 `evasion` 에 각각 곱한다. `atk` / `max_hp` 는 건드리지
# 않는다 — 그쪽은 성장이 담당한다. 교전 무대(TurnEngageSim)는 자기 명중률
# 구간을 따로 쓰므로 이 값을 읽지 않는다.
var lane_stat_mod: float  = 0.0
var lane_stat_expire_turn: int = -1   # -1 = 없음

# ─── Animation state (UI-only; SimulationCore does NOT read these) ────────────
# 이동 연출의 **경로**. `[출발 칸, …, 도착 칸]` 이고, 두 칸 이상 움직인 턴에는
# 실제로 밟은 칸이 순서대로 들어 있다(정글러 move_range 2, 전진 카드 advance:N).
# 렌더러가 이 경로를 따라 초상화를 미끄러뜨리므로 2칸 이동이 중간 칸을 스쳐
# 지나가지 않고 **꺾여서** 간다.
#
# **렌더러가 소비하며 비운다** — `BattleRenderer._sync_glide` 가 경로를 읽어
# 글라이드를 시작한 뒤 `clear()` 한다. 그래서 같은 프레임에 여러 걸음이 들어오면
# (전진 카드의 N틱) `BattleSim.anim_pilot_move` 가 이어 붙일 수 있고, 턴을 넘긴
# 다음 이동은 빈 배열에서 새로 시작한다.
#
# 연출 **시간**은 여기 없다 — 타이머는 렌더러(`BattleRenderer._glide`)가 쥐고
# 있다. 예전의 `anim_prev_grid_pos` / `anim_move_t` / `anim_move_dur` 는 삭제됐다:
# 칸 이동만 트윈하고 슬롯 변화는 순간이동이라 "칸은 미끄러지는데 초상화는 튀는"
# 그림이 남았고, 지금은 **마커 좌표 자체**를 렌더러가 한 곳에서 보간한다.
var anim_move_path: Array[Vector2i] = []
# Damage shake: short horizontal jitter.
# 진폭은 **흔들림마다 다르다** — 전장 자동 교전은 `BattleSim.ANIM_SHAKE_AMP_PX`,
# 공격 카드 명중은 `ANIM_SHAKE_CARD_AMP_PX`(훨씬 크다)로 들어온다. 상수를 하나로
# 두고 렌더러가 읽던 시절에는 둘 중 하나만 맞출 수 있었다.
var anim_shake_t: float   = 0.0
var anim_shake_dur: float = 0.0
var anim_shake_amp: float = 0.0
# Recall sequence: 0 = none, 1 = fade-out + rise at anim_recall_orig,
# 2 = fade-in + descend at grid_pos (HQ). Respawn skips straight to phase 2.
var anim_recall_phase: int   = 0
var anim_recall_t: float     = 0.0
var anim_recall_dur: float   = 0.0
var anim_recall_orig: Vector2i = Vector2i.ZERO

# 사망 연출: 0 = 없음, 1 = 제자리에서 딤드된 채 대기, 2 = 투명해지며 위로 상승.
# 로직상 파일럿은 이미 alive == false 지만, 이 타이머가 도는 동안에는 렌더러가
# anim_death_cell 에 계속 그려 준다.
var anim_death_phase: int    = 0
var anim_death_t: float      = 0.0
var anim_death_dur: float    = 0.0
var anim_death_cell: Vector2i = Vector2i.ZERO

# 공격 카드 시전 연출 — **시전자 초상 위로 하얗게 솟아오르는 빛**. 예전의
# 돌진(`anim_lunge_*`, 시전자가 대상 초상까지 파고들었다 돌아오던 몸통
# 박치기)을 대체한다: 시전자는 이제 제자리에 서 있고 화면에서 움직이는 것은
# 빛뿐이라, 같은 칸의 적을 때릴 때 방향이 뒤집히거나 파고든 얼굴이 대상을
# 가리는 문제가 구조적으로 사라졌다.
var anim_cast_t: float   = 0.0
var anim_cast_dur: float = 0.0

func _init(p_role: int, p_team: int, p_pos: Vector2i, stats: Dictionary) -> void:
	role     = p_role
	team     = p_team
	grid_pos = p_pos
	hp       = stats["hp"]
	max_hp   = stats["hp"]
	atk      = stats["atk"]
	if stats.has("move_range"):
		move_range = max(1, int(stats["move_range"]))
	if stats.has("hit"):
		hit = int(stats["hit"])
	if stats.has("evasion"):
		evasion = int(stats["evasion"])
	if stats.has("presence"):
		presence = int(stats["presence"])
	if stats.has("engage_hit"):
		engage_hit = int(stats["engage_hit"])
	if stats.has("engage_eva"):
		engage_eva = int(stats["engage_eva"])
	if stats.has("atk_growth_mult"):
		atk_growth_mult = float(stats["atk_growth_mult"])
	if stats.has("hp_growth_mult"):
		hp_growth_mult = float(stats["hp_growth_mult"])
	# 성장 계산의 원본. 생성자에서 잡아 두는 것이 요점이다 — 메크 스탯 주입은
	# 이 생성자를 통해 들어오므로 어떤 스폰 경로를 타도 원본이 비지 않는다.
	base_atk    = atk
	base_max_hp = max_hp


# ─── 명중 확률 ──────────────────────────────────────────────────
## 명중 확률은 **상대값이 정한다** — `hit/(hit+eva)` 를
## [`HIT_MIN`, `HIT_MAX`] 구간에 선형으로 엹는다. 둘이 대등하면 90%,
## 한쪽으로 완전히 기울어야 80% / 100% 에 닿는다.
##
## **전장과 교전이 같은 공식을 쓴다** — 입력만 다르다(전장은
## `hit`/`evasion`, 교전은 `engage_hit`/`engage_eva`). 예전에는 전장이
## 비율을 그대로 확률로 썼고(대등 = 50%) 교전만 이 리맵을 했는데,
## 그러면 같은 스탯 차이가 두 무대에서 전혀 다른 크기로 읽혔다.
##
## 구간을 바닥까지 안 내리는 이유: 스탯이 훈련으로 100 을 넘어 계속
## 자라므로 비율 그대로를 확률로 쓰면 상대적 격차가 명중을 0 근처까지
## 끜어내려 한 팀이 아무것도 못 하는 경기가 난다.
const HIT_MIN: float = 0.80
const HIT_MAX: float = 1.00

## 거리 계수 자리. 지금은 전장이 **같은 칸 교전**뿐이라 거리라는
## 개념이 없어 항상 1.0 을 넘긴다. 사거리 규칙이 생기면 호출부가 이
## 인자에 계수를 실어 보내면 된다 — 공식 자체는 건드리지 않는다.
static func hit_chance(hit_stat: int, eva_stat: int, range_mult: float = 1.0) -> float:
	var total: float = float(maxi(1, hit_stat + eva_stat))
	var base: float = clampf(float(hit_stat) / total, 0.0, 1.0)
	return clampf((HIT_MIN + (HIT_MAX - HIT_MIN) * base) * range_mult, 0.0, 1.0)
