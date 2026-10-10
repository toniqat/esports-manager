@tool
class_name ScenarioWipe
extends ColorRect

# Black brush / wind wipe of `ScenarioSelectView` — drives `ScenarioWipe.gdshader` (the scene gives
# this node a ShaderMaterial with it; the look — streaks, soft tail, flow — lives in the shader).
# Last child of the view: over all of its UI, under the lobby's top bar.
#
#   progress 0 → 1 : wipe IN  — black sweeps in from the start edge until the screen is black
#   progress 1     : fully black on every pixel (the view swaps the art here)
#   progress 1 → 2 : wipe OUT — the black keeps travelling the same way and leaves off the far edge
#
# `from_right` = travels right → left (starts at the right edge: › / next), else left → right.
# Maps onto the shader's black-via mode: shader progress = progress / 2, direction = ∓1.

@export_range(0.0, 2.0, 0.001) var progress: float = 0.0:
	set(v):
		progress = clampf(v, 0.0, 2.0)
		_sync()
@export var from_right: bool = true:
	set(v):
		from_right = v
		_sync()


func _ready() -> void:
	resized.connect(_sync)
	_sync()


func _sync() -> void:
	visible = progress > 0.0 and progress < 2.0
	var m := material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter(&"progress", progress * 0.5)
	m.set_shader_parameter(&"direction", -1.0 if from_right else 1.0)
	m.set_shader_parameter(&"via_black", true)
	m.set_shader_parameter(&"aspect", size.x / maxf(1.0, size.y))
