class_name SilhouetteFx
extends RefCounted

# `resources/shaders/silhouette.gdshader` 를 노드에 물리는 **유일한 배선**.
#
# 쉐이더 자체는 파라미터 일곱 개짜리 순수한 물건이고, 이 파일은 그 위에 두 가지를
# 얹는다 — (1) **기본값 한 벌**(아웃게임 흰 배경에서 읽히는 실루엣 색 · 테두리 색),
# (2) **등장 컷의 박자**(`play_reveal`). 화면마다 `ShaderMaterial.new()` 를 손으로
# 세우면 같은 실루엣이 화면마다 다른 회색으로 그려진다 — `OutgameTheme` 이 색을
# 소유하는 것과 같은 이유다.
#
# **재료는 노드 하나에 한 장씩 만든다.** 공유하면 한 노드의 `reveal` 트윈이 같은
# 재료를 쓰는 다른 노드까지 함께 벗긴다.
#
# 구운 모브 실루엣 PNG(`images/pilot/mob/`)와 헷갈리지 말 것 — 그쪽은 "이 선수는
# 이름 없는 선수다"를 상시로 말하는 **에셋**이고, 이쪽은 한 번 지나가는 **연출**이다.

const SHADER: Shader = preload("res://resources/shaders/silhouette.gdshader")

## 구운 모브 실루엣과 같은 어두운 청회색(38, 42, 60). 두 실루엣이 한 화면에
## 나란히 서는 일이 있으므로 색이 갈리면 안 된다.
const FILL: Color = Color(0.149, 0.165, 0.235, 1.0)
## 테두리는 앰버다 — 아웃게임은 흰 배경이라 흰 테두리가 통째로 사라지고,
## 앰버는 이 게임에서 이미 "지금 여기를 보라"를 뜻하는 색이다.
const OUTLINE: Color = Color(0.961, 0.651, 0.137, 0.92)
## 텍스처 픽셀 단위(쉐이더 규약). 전신 아트(폭 572~756)에서 3 이 화면 위 6~7px.
const OUTLINE_WIDTH: float = 3.0

## 등장 컷 기본 박자 — 아래에서 위로 0.55초. 더 느리면 팝업이 열릴 때마다
## 정보를 기다리게 되고, 더 빠르면 실루엣이 있었는지도 모르고 지나간다.
const REVEAL_SEC: float = 0.55
const REVEAL_DELAY: float = 0.10
const REVEAL_DIR_UP := Vector2(0.0, -1.0)


## 이 노드 하나만을 위한 재료 한 장. `reveal` 은 0(완전한 실루엣)에서 시작한다.
static func make_material(fill: Color = FILL, outline: Color = OUTLINE,
		outline_width: float = OUTLINE_WIDTH,
		reveal_dir: Vector2 = REVEAL_DIR_UP) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("outline_color", outline)
	mat.set_shader_parameter("outline_width", outline_width)
	mat.set_shader_parameter("reveal", 0.0)
	mat.set_shader_parameter("reveal_dir", reveal_dir)
	return mat


## 노드에 실루엣을 씌운다. 돌려주는 재료로 파라미터를 더 만질 수 있다.
static func apply(ci: CanvasItem, fill: Color = FILL, outline: Color = OUTLINE,
		outline_width: float = OUTLINE_WIDTH) -> ShaderMaterial:
	if ci == null:
		return null
	var mat: ShaderMaterial = make_material(fill, outline, outline_width)
	ci.material = mat
	return mat


## 지금 얼마나 벗겨졌는가. 0 = 실루엣, 1 = 원본.
static func set_reveal(ci: CanvasItem, v: float) -> void:
	if ci == null:
		return
	var mat: ShaderMaterial = ci.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("reveal", clampf(v, 0.0, 1.0))


## 등장 컷을 돌린다 — 실루엣으로 한 박자 서 있다가 아래에서 위로 벗겨진다.
## 트윈은 노드가 소유하므로 팝업이 닫히면 함께 사라진다.
static func play_reveal(ci: CanvasItem, dur: float = REVEAL_SEC,
		delay: float = REVEAL_DELAY) -> Tween:
	if ci == null:
		return null
	var mat: ShaderMaterial = ci.material as ShaderMaterial
	if mat == null:
		return null
	# 트리 밖이면 트윈을 만들 수 없다. 그때는 **원본을 그대로 보여 준다** —
	# 실패한 연출이 인물을 영영 실루엣으로 덮어 두는 쪽이 훨씬 나쁜 실패다.
	if not ci.is_inside_tree():
		mat.set_shader_parameter("reveal", 1.0)
		return null
	mat.set_shader_parameter("reveal", 0.0)
	var tw: Tween = ci.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mat, "shader_parameter/reveal", 1.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw


## 실루엣을 걷는다(원본 그대로 그린다).
static func clear(ci: CanvasItem) -> void:
	if ci != null and ci.material is ShaderMaterial \
			and (ci.material as ShaderMaterial).shader == SHADER:
		ci.material = null
