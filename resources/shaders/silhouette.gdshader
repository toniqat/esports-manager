shader_type canvas_item;
render_mode blend_mix;

// 캐릭터 실루엣 — **알파는 그대로 두고 RGB 만 단색으로 덮은 뒤 윤곽을 따라
// 테두리 한 겹**을 두른다. 파이썬으로 구워 둔 모브 초상화(`make_mob_silhouettes.py`)
// 와 같은 규칙이지만 이쪽은 런타임이라 (1) 색을 프레임마다 바꿀 수 있고
// (2) `reveal` 로 실루엣 ↔ 원본 사이를 오갈 수 있다 — 그 둘이 이 쉐이더가
// 구운 PNG 를 대신하는 것이 아니라 **등장 컷**을 위해 따로 있는 이유다.
//
// 규약 셋.
//   · `reveal = 1.0` 이면 결과가 원본 텍스처 그대로다(위의 물림만큼 안으로
//     들어간 자리에 그려진다 — 전신 아트 기준 0.5%). 그래서 재료를 붙여 둔 채
//     잊어도 화면이 달라지지 않는다.
//   · `outline_width` 의 단위는 **텍스처 픽셀**이다. 노드가 커지면 테두리도
//     같이 두꺼워진다 — 같은 아트가 상세 패널(1400px)과 썸네일(200px)에서
//     같은 굵기의 선으로 읽혀야 하기 때문이다.
//   · 테두리는 윤곽 **바깥**에 그리고, 그 자리는 **아트를 안으로 물려서** 만든다.
//     안쪽에 그리면 실루엣을 파먹어 어깨선이 얇아지는데, 그렇다고 바깥에 그리기만
//     하면 그릴 픽셀이 없다 — 파일럿 전신 아트 40장은 **네 변에 인물이 닿아
//     있어서**(실측: 인물 상단 y = 0, 좌우 여백 0) 머리 위 테두리가 통째로 잘렸다.
//     그래서 텍스처를 `outline_width` 만큼 안쪽에 그려 테두리가 설 띠를 만든다.
//     **폭이 0 이면 물림도 0** 이라, 테두리를 안 쓰면 아트는 픽셀 그대로다.

// ─── 실루엣 ─────────────────────────────────────────────────────────────────
uniform vec4  fill_color    : source_color = vec4(0.149, 0.165, 0.235, 1.0);
uniform vec4  outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);
/// 텍스처 픽셀 단위. 0 이면 테두리를 아예 안 그린다(샘플링도 건너뛴다).
uniform float outline_width : hint_range(0.0, 24.0) = 3.0;

// ─── 등장 컷 (reveal) ───────────────────────────────────────────────────────
/// 0 = 실루엣, 1 = 원본. 그 사이는 `reveal_dir` 방향으로 쓸고 지나가는 경계다.
uniform float reveal        : hint_range(0.0, 1.0) = 0.0;
/// 경계의 흐린 폭(진행도 0~1 기준). 0 에 가까우면 칼로 자른 듯한 경계가 된다.
uniform float reveal_soft   : hint_range(0.005, 0.6) = 0.18;
/// 쓸고 지나가는 방향. (0,-1) = 아래에서 위로, (1,0) = 왼쪽에서 오른쪽으로.
uniform vec2  reveal_dir    = vec2(0.0, -1.0);
/// 경계에 얹히는 빛. 실루엣이 벗겨지는 자리를 눈이 따라가게 하는 것이 전부라
/// **경계가 화면 밖으로 나가면(reveal 0 또는 1) 저절로 꺼진다**.
uniform vec4  sweep_color   : source_color = vec4(1.0, 0.92, 0.72, 0.7);
uniform float sweep_width   : hint_range(0.0, 0.5) = 0.05;

// 노드의 modulate 를 프래그먼트로 나른다. `MODULATE` 내장은 이 버전의
// canvas_item 프래그먼트에 **없고**(실측: `Unknown identifier 'MODULATE'`),
// `COLOR` 는 이미 텍스처가 곱해진 채 들어오므로 거기서 되뽑을 수도 없다.
// 정점 단계의 `COLOR` 가 곧 modulate 다.
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

const float TAU12 = 0.523598776;   // 2π / 12 — 테두리 샘플 열두 방향

// **테두리 샘플링은 `fragment()` 안에 인라인으로 있다.** `TEXTURE` 와
// `TEXTURE_PIXEL_SIZE` 는 프래그먼트 단계의 내장 이름이라 전역 함수 안에서는
// `Unknown identifier in expression: 'TEXTURE'` 로 컴파일이 깨진다(실측) —
// 헬퍼로 빼려면 샘플러를 인자로 넘겨야 하는데, 그 한 겹을 얻자고 읽기 어려워질
// 만한 코드가 아니다.

void fragment() {
	// **아트를 테두리 폭만큼 안으로 물린다.** 그리는 사각형은 그대로 두고 그
	// 안에서 텍스처만 좁혀 그리므로, 네 변에 인물이 닿은 아트에도 테두리가 설
	// 띠가 생긴다. 물림이 없으면 머리 위 · 어깨 옆 테두리가 잘려 나간다.
	vec2 pad = TEXTURE_PIXEL_SIZE * outline_width;
	vec2 inner = max(vec2(0.0001), vec2(1.0) - pad * 2.0);
	vec2 uv = (UV - pad) / inner;

	vec4 src = (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
			? vec4(0.0) : texture(TEXTURE, uv);
	float own = src.a;

	// ── 실루엣 한 장 (채움 + 바깥 테두리) ──────────────────────────────────
	// 반지름 `outline_width`(텍스처 픽셀) 링에서 가장 진한 알파를 찾는다.
	// 텍스처 밖은 알파 0 으로 읽는다 — 캔버스 아이템의 repeat 설정에 기대면
	// 인물이 프레임에 닿은 자리에서 반대편 픽셀이 테두리로 말려 들어온다.
	float ring = 0.0;
	if (outline_width > 0.0) {
		vec2 step_uv = TEXTURE_PIXEL_SIZE * outline_width;
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * TAU12;
			vec2 uv2 = uv + vec2(cos(ang), sin(ang)) * step_uv;
			if (uv2.x < 0.0 || uv2.x > 1.0 || uv2.y < 0.0 || uv2.y > 1.0) {
				continue;
			}
			ring = max(ring, texture(TEXTURE, uv2).a);
		}
	}
	float edge = clamp(ring - own, 0.0, 1.0) * outline_color.a;
	float body = own * fill_color.a;
	float sil_a = max(body, edge);
	// 채움이 진한 곳은 채움 색, 테두리만 있는 곳은 테두리 색.
	vec3 sil_rgb = mix(outline_color.rgb, fill_color.rgb,
			(sil_a > 0.0001) ? body / sil_a : 0.0);

	// ── 경계 ──────────────────────────────────────────────────────────────
	// p = 진행 축 위의 위치(0 = 먼저 벗겨지는 쪽). front 는 그 축을 쓸고 간다.
	vec2 dir = normalize((length(reveal_dir) > 0.0001) ? reveal_dir : vec2(0.0, -1.0));
	float p = dot(UV - vec2(0.5), dir) + 0.5;
	float front = mix(-reveal_soft, 1.0 + reveal_soft, reveal);
	// **경계는 반드시 오름차순으로 넘긴다** — `smoothstep(front, front - soft, p)`
	// 처럼 edge0 > edge1 로 부르면 GLSL 규격상 결과가 정의되지 않는다. 실제로
	// 그렇게 썼더니 화면 전체가 어중간한 m 을 받아 실루엣이 덮인 것이 아니라
	// **원본에 반쯤 섞인** 그림이 나왔다(이목구비가 그대로 읽혔다).
	float m = 1.0 - smoothstep(front - reveal_soft, front, p);   // 1 = 이미 벗겨짐

	vec4 col = mix(vec4(sil_rgb, sil_a), src, m);

	// 경계의 빛 — 인물 위에만, 그리고 애니메이션 중에만.
	float live = step(0.001, reveal) * step(reveal, 0.999);
	float g = 1.0 - clamp(abs(p - front) / max(sweep_width, 0.0001), 0.0, 1.0);
	float glow = g * g * live * own * sweep_color.a;
	col.rgb = mix(col.rgb, sweep_color.rgb, glow);
	col.a = max(col.a, glow);

	// **`COLOR` 에 곱하지 말 것.** canvas_item 프래그먼트의 `COLOR` 는 들어올 때
	// 이미 `texture(TEXTURE, UV) × modulate` 로 채워져 있다 — `COLOR = col * COLOR`
	// 로 쓰면 평평해야 할 실루엣에 원본이 한 번 더 곱해져 **이목구비가 그대로
	// 읽힌다**(실측: 순수 빨강 채움이 (170,0,0), 남색 채움이 (11,9,13) 로 픽셀마다
	// 다르게 나왔다). modulate 만 정점 단계에서 받아 온다.
	COLOR = col * v_modulate;
}
