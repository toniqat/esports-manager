class_name RoleBadge
extends Panel

# **역할군 배지**(`Tk` / `As` …) — 편성 격자 썸네일(`PilotThumb`), 편성 칸의 상체 일러스트
# (`DraftSlot`), 컬렉션 칸 · 상세(`PilotThumb.add_role_badge` 경유)가 같은 배지를 쓴다.
# 화면마다 자기 배지를 그리면 같은 역할이 화면마다 다른 크기 · 색 · 글자로 서서
# "색으로 알아본다"는 전제가 무너진다.
#
# **모양의 정본은 `RoleBadge.tscn`** (크기 · 글자 크기 · `OnFillLabel`). 색과 글자는 역할이
# 정하는 데이터라 `set_role` 이 넣는다 — 씬의 스타일박스는 에디터 미리보기용 견본이다.

const SCENE_PATH: String = "res://features/meta/run_setup/RoleBadge.tscn"

## 두 글자 약칭. 밴픽 화면의 `ROLE_INITIALS` 와 **같은 표**다 — 같은 역할이
## 화면마다 다른 글자면 색으로 알아본다는 전제가 무너진다.
const ROLE_INITIALS: Array = ["Tk", "Fi", "As", "Su", "Sn"]


static func create() -> RoleBadge:
	return (load(SCENE_PATH) as PackedScene).instantiate() as RoleBadge


## 역할 색 · 약칭을 입힌다. 알 수 없는 역할이면 false (배지는 그대로 숨는다).
func set_role(role: int) -> bool:
	if role < 0 or role >= ROLE_INITIALS.size():
		visible = false
		return false
	visible = true
	var sb := StyleBoxFlat.new()
	# 역할 색은 팔레트가 소유한다 (`OutgameTheme.ROLE_COLORS`).
	sb.bg_color = (OutgameTheme.ROLE_COLORS[role] as Color).darkened(0.15)
	sb.border_color = Color(0, 0, 0, 0.18)
	sb.set_border_width_all(1)
	OutgameTheme.set_corner_radius(sb, 8)
	add_theme_stylebox_override("panel", sb)
	(%Text as Label).text = String(ROLE_INITIALS[role])
	return true
