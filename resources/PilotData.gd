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
# 본진 복귀한 그 턴에는 HQ 에 서 있기만 하고 움직이지 않는다는 표시.
# RecallSystem.return_to_hq 가 켜고, 다음 이동 패스(SimulationCore.resolve_movement)
# 가 한 턴을 걸러 내면서 스스로 끈다 — 그래서 "복귀 → 다음 턴부터 레인으로".
var recall_hold: bool     = false
var lane: int             = GameEnums.LanePosition.GUERRILLA
var is_guerrilla: bool    = false
var waypoint_idx: int     = 0
var move_range: int       = 1                # cells advanced per minute
var jungle_start_pref: int = -1              # GameEnums.JungleStartDir or -1 (none)
# Sticky roam destination for junglers, (-1,-1) = none yet. Held across turns by
# SimulationCore._jungle_goal_for so the roam target cannot flip mid-route.
var jungle_roam_target: Vector2i = Vector2i(-1, -1)
# Hit/evasion drive paired combat rolls (PlayerData.mechanics → hit, gamesense → evasion).
var hit: int              = 50
var evasion: int          = 50
# 존재감 — 전투 개시(engage)에서만 참조. 근접 메크 4, 원거리 메크 2.
# 공격 순서(높을수록 먼저)와 피격 가중치(높을수록 자주 표적이 됨).
var presence: int         = 4
# 보호막. Granted by the 보호 card; removed on 본진 복귀 (RecallSystem clears it).
# Damage absorption isn't wired into SimulationCore yet — this field is the
# data hook for future integration so card effects can build up the value now.
var shield: int           = 0

# ─── Animation state (UI-only; SimulationCore does NOT read these) ────────────
# Move tween: cell-to-cell pixel interpolation from anim_prev_grid_pos to grid_pos.
var anim_prev_grid_pos: Vector2i = Vector2i.ZERO
var anim_move_t: float    = 0.0
var anim_move_dur: float  = 0.0
# Damage shake: short horizontal jitter.
var anim_shake_t: float   = 0.0
var anim_shake_dur: float = 0.0
# Recall sequence: 0 = none, 1 = fade-out + rise at anim_recall_orig,
# 2 = fade-in + descend at grid_pos (HQ). Respawn skips straight to phase 2.
var anim_recall_phase: int   = 0
var anim_recall_t: float     = 0.0
var anim_recall_dur: float   = 0.0
var anim_recall_orig: Vector2i = Vector2i.ZERO

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
