@tool
class_name FloatingBarButton
extends Button

# One floating capsule of an outgame bottom action bar (`UI_Comp_FloatingBarButton.tscn`).
# The colour / font come from the `Bar*Button` theme variation (`BarPrimaryButton` orange,
# `BarDarkButton` secondary); this script only owns the **drop shadow**, exposed as inspector
# sliders. Change the defaults on the component scene's root to retune every bottom button;
# a host instance may override them for one button.
#
# Hosts instance the scene (node `FloatingBarButton_<Role>`), pick the variation, and place the
# row with `OutgameTheme.fit_bottom_bar`. Code-built rows use `create()` (`add_bottom_bar`).

const SCENE_PATH: String = "res://resources/UI_Comp_FloatingBarButton.tscn"

## Shadow opacity (0 = no shadow).
@export_range(0.0, 1.0, 0.01) var shadow_strength: float = 0.18:
	set(v):
		shadow_strength = v
		refresh_style()
## Shadow blur size in px.
@export_range(0, 48, 1) var shadow_size: int = 18:
	set(v):
		shadow_size = v
		refresh_style()
## Shadow drop (downward offset) in px.
@export_range(0, 24, 1) var shadow_offset_y: int = 6:
	set(v):
		shadow_offset_y = v
		refresh_style()

# Variation + shadow values the current overrides were built from — skips the
# THEME_CHANGED our own overrides fire.
var _applied_key: String = ""


static func create() -> FloatingBarButton:
	return (load(SCENE_PATH) as PackedScene).instantiate() as FloatingBarButton


func _ready() -> void:
	refresh_style()
	if not Engine.is_editor_hint() and UiPreview.is_standalone(self):
		_fill_preview()


# The shadowed boxes are rebuilt at runtime / in the editor — never written into a scene
# (no local StyleBoxes in scenes): strip storage from the stylebox override slots.
func _validate_property(property: Dictionary) -> void:
	if String(property.name).begins_with("theme_override_styles/"):
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		refresh_style()


## Rebuilds the per-state boxes: the variation's box with this button's shadow. Call after
## switching `theme_type_variation` (`OutgameTheme.fit_bar_button` does).
func refresh_style() -> void:
	if not is_inside_tree():
		return
	var key: String = "%s|%s|%d|%d" % [theme_type_variation, shadow_strength, shadow_size,
			shadow_offset_y]
	if key == _applied_key:
		return
	_applied_key = key
	for n in OutgameTheme.BUTTON_STATES:
		remove_theme_stylebox_override(n)
	for n in OutgameTheme.BUTTON_STATES:
		if n == "focus" or n == "disabled":
			continue
		var sb := get_theme_stylebox(n) as StyleBoxFlat
		if sb == null:
			continue
		var box := sb.duplicate() as StyleBoxFlat
		box.shadow_color = Color(OutgameTheme.SHADOW, shadow_strength)
		box.shadow_size = shadow_size if shadow_strength > 0.0 else 0
		box.shadow_offset = Vector2(0, shadow_offset_y)
		add_theme_stylebox_override(n, box)


# Run alone (F6): the scene's caption is already a preview; show the secondary look below it.
func _fill_preview() -> void:
	var twin: FloatingBarButton = create()
	twin.theme_type_variation = &"BarDarkButton"
	twin.position = position + Vector2(0, size.y + 40.0)
	twin.size = size
	get_parent().add_child.call_deferred(twin)
