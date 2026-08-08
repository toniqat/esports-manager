class_name CardData
extends Resource

@export var card_name: String = ""
@export var cost: int = 1
@export var uses: int = 1                 # 0 = unlimited; otherwise charges per match
@export var cast_method: String = "instant"  # range / target / location / instant
@export var target: String = "hand"       # caster / enemy / ally / pilot / hand / location
@export var cast_range: int = 0           # tiles from caster (0 = self, 99 = unbounded)
@export var area: int = 0                 # AoE radius around target (0 = single)
@export var keyword: String = ""          # "" or "exhaust"
@export var effect: String = ""           # semicolon list, e.g. "draw:2;discard:2"
@export var description: String = ""

# Runtime — set when this card is dealt to a pilot's mini-deck. Identifies the
# 시전자 (caster) for effect resolution and drives the owner badge on the UI.
# Not @export'd because PilotData is a transient match-only object.
var owner_pilot: PilotData = null
# Remaining charges for this match. Decrements on play; when it hits 0 the card
# is removed (소멸) instead of returning to the discard pile. uses == 0 means
# unlimited and bypasses the charge counter entirely.
var remaining_uses: int = 1


func _init(p_name: String = "", p_cost: int = 1, p_desc: String = "") -> void:
	card_name = p_name
	cost = p_cost
	description = p_desc
	remaining_uses = uses
