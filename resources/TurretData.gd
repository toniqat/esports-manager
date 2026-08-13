class_name TurretData
extends RefCounted

var team: int
var grid_pos: Vector2i
var hp: int
var max_hp: int
var atk: int
var tier: int
var lane: int
var alive: bool = true

# ─── UI 연출 상태 (시뮬레이션은 절대 읽지 않는다) ─────────────────────────────
## 피격 연출 타이머. `BattleSim.anim_turret_hit` 가 켜고
## `BattleSim._advance_turret_animations` 가 소모한다. `dur > 0` 인 동안
## 포탑 스프라이트가 흔들리며 붉게 번쩍이고, HP 바도 같은 오프셋으로 흔들린다.
var anim_hit_t: float   = 0.0
var anim_hit_dur: float = 0.0

func _init(p_team: int, p_pos: Vector2i, p_tier: int, p_lane: int,
		p_hp: int, p_atk: int) -> void:
	team     = p_team
	grid_pos = p_pos
	tier     = p_tier
	lane     = p_lane
	hp       = p_hp
	max_hp   = p_hp
	atk      = p_atk
