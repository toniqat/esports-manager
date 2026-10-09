class_name StaffImages
extends RefCounted

# Staff / manager thumbnail lookup — only this file knows where a staff portrait comes from.
#
#   images/staff/staff_bust.svg   — **temporary** upper-body pictogram shared by every staff member
#   images/staff/manager_bust.svg — the same bust in amber with a tie, for the manager
#
# Real per-staff art later: add `staff_<id>.<ext>` and look it up here first.

const DIR: String = "res://resources/images/staff/"
const MANAGER: String = "manager"


## `who` = `"manager"` or a staff id (as in `FacilitySystem.assign`).
static func portrait(who: String) -> Texture2D:
	var path: String = DIR + ("manager_bust.svg" if who == MANAGER else "staff_bust.svg")
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
