class_name StrategyIcon
extends RefCounted

# 전략 점수의 **모양** — 정팔각형. 두 가지 자세가 있다:
#   • 위아래가 뾰족한 자세(`flat = false`) — 양 팀 게이지(`CostDonut`) 전용.
#     꼭짓점 0 이 12시 방향이고 시계 방향으로 45° 씩 돌므로 면 0 은 **우측 상단
#     면**(12시 → 1시 반)이고, 게이지가 그 면부터 차오른다.
#   • 윗변 · 아랫변이 평평한 자세(`flat = true`) — **점수 인디케이터**. 작은 크기
#     에서 뾰족한 자세는 원처럼 읽혀서, 설명문 안의 "전략 점수" 아이콘이 이쪽을
#     쓴다. 검은 알맹이 + 두꺼운 파란 테두리.
#
# 설명문 안의 "비용" 앞 아이콘(세로로 긴 직각사다리꼴)은 `CostRibbon` 이, 공격 ·
# 교전 · 사거리 같은 키워드 아이콘은 `KeywordIcon` 이 정의하고, 아이콘을 설명문에
# 끼워 넣는 일(`fill_rich`)은 전부 여기서 한다.

const SIDES := 8
## 기본 배지 · 테두리 색. 플레이어 게이지(`HudBuilder.DONUT_FILL_PLAYER`)와 같다.
const COLOR := Color(0.25, 0.60, 1.00)
## 인디케이터 알맹이 색.
const INDICATOR_FILL := Color(0.02, 0.02, 0.04, 1.0)
## 인디케이터 테두리 두께 — 꼭짓점 반지름에 대한 비율(아이콘 크기에 따라 같이 큰다).
const INDICATOR_RIM_RATIO := 0.26
const KEYWORD := "전략 점수"
const COST_KEYWORD := "비용"
const NBSP := "\u00a0"
## `_tokens` 의 특수 키워드 조각 종류 — `[이름]` 의 안쪽 글자.
const SPECIAL := "special"

static var _tex_cache: Dictionary = {}


## 중심 `c`, 꼭짓점 반지름 `r` 의 팔각형 꼭짓점 8개 — 시계 방향. `flat` 이면
## 22.5° 돌려 윗변 · 아랫변이 평평하다.
static func points(c: Vector2, r: float, flat: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var start: float = -PI * 0.5 + (PI / float(SIDES) if flat else 0.0)
	for i in SIDES:
		var a: float = start + TAU * float(i) / float(SIDES)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## 채운 팔각형. `rim_w > 0` 이면 테두리를 두르고, 아니면 같은 색 얇은 선으로
## 가장자리만 안티앨리어싱한다(`draw_colored_polygon` 은 AA 가 없다).
static func draw(ci: CanvasItem, c: Vector2, r: float, fill: Color,
		rim: Color = Color(0, 0, 0, 0), rim_w: float = 0.0, flat: bool = false) -> void:
	var pts: PackedVector2Array = points(c, r, flat)
	ci.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	if rim_w > 0.0:
		ci.draw_polyline(loop, rim, rim_w, true)
	else:
		ci.draw_polyline(loop, fill, 1.0, true)


## 숫자를 얹은 팔각형 배지 — `parent` 안의 `center` 에 반지름 `r` 로 선다.
static func make_badge(parent: Node, center: Vector2, r: float, fill: Color,
		text: String, font_size: int, text_color: Color,
		rim: Color = Color(0, 0, 0, 0), rim_w: float = 0.0) -> Control:
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = center - Vector2(r, r)
	badge.size = Vector2(r, r) * 2.0
	badge.draw.connect(func() -> void:
		draw(badge, badge.size * 0.5, r, fill, rim, rim_w))
	parent.add_child(badge)
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	badge.add_child(lbl)
	lbl.position = Vector2.ZERO
	lbl.size = badge.size
	return badge


## `px` 픽셀 정사각형 안에 꽉 찬 인디케이터 텍스처(평평한 윗변 · 검은 알맹이 ·
## 두꺼운 파란 테두리). 설명문 인라인 아이콘용.
static func texture(px: int) -> Texture2D:
	var key: String = "oct:%d" % px
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var r: float = float(px) * 0.5
	# 평평한 자세는 변까지 거리(내접원)가 r·cos(22.5°) 라 윗변이 텍스처 끝에
	# 닿지 않는다 — 꼭짓점 반지름을 키워 윗변 · 옆변이 정사각형을 꽉 채우게 한다.
	var vr: float = r / cos(PI / float(SIDES))
	var pts: PackedVector2Array = points(Vector2(r, r), vr, true)
	var tex := raster_convex(px, px, pts, INDICATOR_FILL, COLOR,
			float(px) * 0.5 * INDICATOR_RIM_RATIO)
	_tex_cache[key] = tex
	return tex


## 볼록 다각형 `pts`(시계 방향, 픽셀 좌표)를 `w`×`h` 텍스처로 굽는다 — 알맹이
## `fill`, 안쪽으로 `rim_w` 두께의 테두리 `rim`. 가장자리는 1px 로 안티앨리어싱.
## 변마다 바깥 법선과의 내적 최댓값이 볼록 다각형의 부호 거리다.
static func raster_convex(w: int, h: int, pts: PackedVector2Array, fill: Color,
		rim: Color, rim_w: float) -> Texture2D:
	var n: int = pts.size()
	var normals: Array[Vector2] = []
	var offsets: Array[float] = []
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		# 시계 방향(y 아래) 다각형의 바깥 법선은 변 방향을 반시계로 90° 돌린 것.
		var nrm: Vector2 = Vector2(b.y - a.y, a.x - b.x).normalized()
		normals.append(nrm)
		offsets.append(nrm.dot(a))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = -INF
			for i in n:
				d = maxf(d, normals[i].dot(p) - offsets[i])
			var cov: float = clampf(0.5 - d, 0.0, 1.0)
			if cov <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rim_t: float = clampf(d + rim_w + 0.5, 0.0, 1.0)
			var col: Color = fill.lerp(rim, rim_t)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * cov))
	return ImageTexture.create_from_image(img)


## Korean particle tags → the form that fits the previous syllable.
## `{eul}` 을/를 · `{eun}` 은/는 · `{i}` 이/가 · `{wa}` 과/와.
const JOSA := {
	"eul": ["을", "를"],
	"eun": ["은", "는"],
	"i": ["이", "가"],
	"wa": ["과", "와"],
}


## Description text as stored in CSV → display text: the literal two-char `\n`
## becomes a real newline, and every particle tag (`JOSA`) is resolved by the
## previous visible character, skipping closing `]` (`[아드레날린]{eul}` looks at
## `린`). A Hangul syllable with a final consonant takes the first form
## (을 · 은 · 이 · 과); anything else — open syllable or non-Hangul — the second.
static func resolve_josa(text: String) -> String:
	text = text.replace("\\n", "\n")
	if text.find("{") < 0:
		return text
	var out: String = ""
	var i: int = 0
	var n: int = text.length()
	while i < n:
		if text[i] == "{":
			var close: int = text.find("}", i)
			if close > i:
				var tag: String = text.substr(i + 1, close - i - 1)
				if JOSA.has(tag):
					var forms: Array = JOSA[tag] as Array
					out += String(forms[0] if _has_batchim(out) else forms[1])
					i = close + 1
					continue
		out += text[i]
		i += 1
	return out


## Whether the last visible character of `s` (skipping `]`) is a Hangul syllable
## with a final consonant.
static func _has_batchim(s: String) -> bool:
	var j: int = s.length() - 1
	while j >= 0 and s[j] == "]":
		j -= 1
	if j < 0:
		return false
	var code: int = s.unicode_at(j)
	if code < 0xAC00 or code > 0xD7A3:
		return false
	return (code - 0xAC00) % 28 != 0


## 설명문을 조각으로 — 평문 `String` 과 아이콘 `[kind, 낱말]` 이 번갈아 선다.
## kind 는 `"strategy"` · `"cost"` · `SPECIAL`(`[이름]` → 이름) · `KeywordIcon` 키("3턴"
## 같은 지속시간 포함).
## 같은 자리에서 시작하는
## 낱말은 긴 쪽이 이긴다("공격력" > "공격"). **대괄호 안(`[공격 명령]` 같은 카드
## 이름)은 통째로 특수 키워드 한 조각이다** — 이름 한가운데 아이콘이 서지 않는다.
static func _tokens(text: String) -> Array:
	text = resolve_josa(text)
	var words: Array = [[KEYWORD, "strategy"], [COST_KEYWORD, "cost"]]
	for w in KeywordIcon.WORDS:
		words.append([String((w as Array)[0]), String((w as Array)[1])])
	var out: Array = []
	var plain: String = ""
	var i: int = 0
	var n: int = text.length()
	while i < n:
		if text[i] == "[":
			var close: int = text.find("]", i)
			if close > i:
				if not plain.is_empty():
					out.append(plain)
					plain = ""
				out.append([SPECIAL, text.substr(i + 1, close - i - 1)])
				i = close + 1
				continue
		# 지속시간 — "3턴" · "(…)턴" 앞에 모래시계. 숫자의 첫 자리에서만 잡는다.
		var dur_end: int = _duration_end(text, i)
		if dur_end > i:
			if not plain.is_empty():
				out.append(plain)
				plain = ""
			out.append([KeywordIcon.DURATION, text.substr(i, dur_end - i)])
			i = dur_end
			continue
		var hit_word: String = ""
		var hit_kind: String = ""
		for w in words:
			var word: String = String((w as Array)[0])
			if word.length() > hit_word.length() and text.substr(i, word.length()) == word:
				hit_word = word
				hit_kind = String((w as Array)[1])
		if hit_word.is_empty():
			plain += text[i]
			i += 1
			continue
		if not plain.is_empty():
			out.append(plain)
			plain = ""
		out.append([hit_kind, hit_word])
		i += hit_word.length()
	if not plain.is_empty():
		out.append(plain)
	return out


## `i` 에서 시작하는 지속시간 표기("3턴" 또는 "(사용 횟수)턴")의 끝 — 아니면 `i`.
## 숫자 한가운데(앞 글자도 숫자)에서는 잡지 않는다.
static func _duration_end(text: String, i: int) -> int:
	var n: int = text.length()
	var j: int = i
	if text[i] == "(":
		var close: int = text.find(")", i)
		if close < 0:
			return i
		j = close + 1
	elif text[i].is_valid_int() and (i == 0 or not text[i - 1].is_valid_int()):
		while j < n and text[j].is_valid_int():
			j += 1
	else:
		return i
	if j < n and text[j] == "턴":
		return j + 1
	return i


## 카드 설명문을 `RichTextLabel` 로 — "전략 점수" 앞마다 팔각형 인디케이터,
## "비용" 앞마다 비용 리본(`CostRibbon`), 그 밖의 키워드(공격 · 교전 · 사거리 …)
## 앞마다 `KeywordIcon` 을 끼운다. BBCode 를 쓰지 않고 `add_text` / `add_image`
## 로 쌓으므로 설명문의 `[캐시]` 같은 대괄호가 태그로 먹히지 않는다.
##
## `icon_color` 는 키워드 아이콘 색, `knock` 은 판 바탕색(필중의 원을 파낸다),
## `target_color` 는 대상 아이콘 색(카드가 겨누는 편), `target_key` 는 "대상" 앞에
## 설 아이콘(사람 `TARGET` / 타일 `TILE` — `CardDescBox.target_info`).
static func fill_rich(rtl: RichTextLabel, text: String, font_size: int,
		icon_color: Color = Color(0.55, 0.85, 1.0),
		knock: Color = Color(0.08, 0.08, 0.12),
		target_color: Color = KeywordIcon.TARGET_ANY_COLOR,
		target_key: String = KeywordIcon.TARGET,
		special_color: Color = KeywordIcon.SPECIAL_COLOR_DARK,
		card_costs: Dictionary = {}, card_meta: bool = false) -> void:
	rtl.clear()
	var icon_px: int = int(round(float(font_size) * 1.1))
	var rib_h: int = int(round(float(font_size) * 1.2))
	var rib_w: int = int(round(float(rib_h) * CostRibbon.ICON_ASPECT))
	# A particle right after a coloured `[name]` ("아드레날린" + "을") is a separate
	# add_text, and RichTextLabel may break between two items — glue it on with a
	# word joiner, as `keep_words` does inside one string.
	var after_special: bool = false
	for tok in _tokens(text):
		if tok is String:
			var plain: String = tok as String
			if after_special and not plain.is_empty() and plain[0] != " " and plain[0] != "\n":
				plain = "\u2060" + plain
			rtl.add_text(UiHelpers.keep_words(plain))
			after_special = false
			continue
		var kind: String = String((tok as Array)[0])
		var word: String = String((tok as Array)[1])
		after_special = kind == SPECIAL
		if kind == SPECIAL:
			# 대괄호는 찍지 않는다 — 색이 경계를 대신한다. 효과 용어면 그 아이콘이
			# 앞에 선다(키워드 아이콘 색).
			var sp_key: String = String(KeywordIcon.SPECIAL_ICONS.get(word, ""))
			if not sp_key.is_empty():
				var sp_tex: Texture2D = KeywordIcon.texture(sp_key, icon_px * 2, icon_color, knock)
				if sp_tex != null:
					rtl.add_image(sp_tex, icon_px, icon_px, Color.WHITE, INLINE_ALIGNMENT_CENTER)
					rtl.add_text(NBSP)
			elif card_costs.has(word):
				# A card name — its cost on a miniature card-face ribbon in front.
				# `card_meta`: ribbon + name become one meta span (data = card name)
				# so the caller can find which card a press landed on.
				if card_meta:
					rtl.push_meta(word, RichTextLabel.META_UNDERLINE_NEVER)
				var cost_h: int = int(round(float(font_size) * 1.2))
				var cost_w: int = int(round(float(cost_h) * 0.78))
				rtl.add_image(CostRibbon.number_texture(str(int(card_costs[word])),
						cost_w * 2, cost_h * 2), cost_w, cost_h, Color.WHITE,
						INLINE_ALIGNMENT_CENTER)
				rtl.add_text(NBSP)
			rtl.push_color(special_color)
			rtl.add_text(UiHelpers.keep_words(word.replace(" ", NBSP)))
			rtl.pop()
			if card_meta and sp_key.is_empty() and card_costs.has(word):
				rtl.pop()
			continue
		if kind == "cost":
			rtl.add_image(CostRibbon.icon_texture(rib_w * 2, rib_h * 2), rib_w, rib_h,
					Color.WHITE, INLINE_ALIGNMENT_CENTER)
		elif kind == "strategy":
			rtl.add_image(texture(icon_px * 2), icon_px, icon_px, Color.WHITE,
					INLINE_ALIGNMENT_CENTER)
		else:
			if kind == KeywordIcon.TARGET:
				kind = target_key
			var tex: Texture2D = KeywordIcon.texture(kind, icon_px * 2,
					KeywordIcon.color_for(kind, icon_color, target_color), knock)
			if tex != null:
				rtl.add_image(tex, icon_px, icon_px, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		# 줄 안 끊김 공백 — 아이콘과 그 낱말이 다른 줄로 갈리지 않는다.
		rtl.add_text(NBSP + UiHelpers.keep_words(word.replace(" ", NBSP)))


## `fill_rich` 로 채운 설명 라벨 하나. 크기는 부르는 쪽이 정한다.
static func make_rich_label(text: String, font_size: int, color: Color,
		icon_color: Color = Color(0.55, 0.85, 1.0),
		knock: Color = Color(0.08, 0.08, 0.12),
		target_color: Color = KeywordIcon.TARGET_ANY_COLOR,
		target_key: String = KeywordIcon.TARGET,
		special_color: Color = KeywordIcon.SPECIAL_COLOR_DARK,
		card_costs: Dictionary = {}, card_meta: bool = false) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.scroll_active = false
	# 인라인 이미지가 낀 줄은 RichTextLabel 의 줄바꿈 폭 계산이 몇 px 어긋나
	# 마지막 글자가 rect 경계에서 잘린다 — 판의 여백 안이므로 잘라내지 않는다.
	rtl.clip_contents = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", font_size)
	rtl.add_theme_color_override("default_color", color)
	rtl.add_theme_constant_override("line_separation", 0)
	fill_rich(rtl, text, font_size, icon_color, knock, target_color, target_key,
			special_color, card_costs, card_meta)
	return rtl


## 높이 측정용 대역 문자열 — 아이콘 한 개가 차지하는 폭을 글자로 친다(정사각
## 아이콘은 두 개, 리본은 한 개). `get_multiline_string_size` 는 이미지를 모르므로,
## 아이콘이 들어간 줄이 접히는 자리를 맞추려면 그만큼의 폭을 미리 넣어 재야 한다.
## 줄바꿈 규칙(`keep_words` · 줄 안 끊김 공백)도 `fill_rich` 와 같아야 한다.
static func measure_text(text: String, card_costs: Dictionary = {}) -> String:
	var t: String = ""
	for tok in _tokens(text):
		if tok is String:
			t += tok as String
			continue
		var kind: String = String((tok as Array)[0])
		if kind == SPECIAL:
			var term: String = String((tok as Array)[1])
			if KeywordIcon.SPECIAL_ICONS.has(term):
				t += "\u0001" + NBSP
			elif card_costs.has(term):
				t += "\u0002" + NBSP
			t += term.replace(" ", NBSP)
			continue
		t += ("\u0002" if kind == "cost" else "\u0001") + NBSP \
				+ String((tok as Array)[1]).replace(" ", NBSP)
	return UiHelpers.keep_words(t).replace("\u0001", "00").replace("\u0002", "0")


## Height a `make_rich_label` label of width `width` needs for `text` — measures
## `measure_text(text, card_costs)` the same way `CardDescBox._text_height` does.
static func rich_height(text: String, width: float, font_size: int,
		card_costs: Dictionary = {}) -> float:
	var f: Font = ThemeDB.fallback_font
	var t: String = measure_text(text, card_costs)
	if f == null or t.is_empty():
		return float(font_size) * 1.4
	var brk: int = (TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			| TextServer.BREAK_ADAPTIVE | TextServer.BREAK_TRIM_EDGE_SPACES)
	return ceilf(f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT,
			width, font_size, -1, brk).y) + 4.0
