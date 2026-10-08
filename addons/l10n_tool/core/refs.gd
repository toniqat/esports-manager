@tool
extends RefCounted

## 설명문 `[x]` 참조 해석 (설계서 §5 · D2 · D4).
##
## 참조 대상 = alias 가 `config.ref_aliases` 패턴에 맞는 엔트리
## (`card.**.name` → `card.pilot.6.name`, `term.keyword.*` → `term.keyword.track`).
## `[x]` 의 x 는 그 key 를 가리키는 key 참조 `{tx_…}` 로 적는다(build 가 로케일마다 그 이름으로
## 펼친다). 이름을 직접 적은 `[이름]` 은 원문 이름 → key 역색인으로 찾되 W036 경고를 낸다.
## 모든 엔트리 원문의 `[x]` 를 등장 순서대로 key 로 바꾼 결과를 build 가 `generated/refs.json`
## 으로 쓰고(D4) 런타임은 텍스트 매칭 없이 그 목록으로 카드 · 키워드를 찾는다. validator 는 같은
## 함수로 E034 · E036 · W036 을 낸다.

const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Tokens = preload("res://addons/l10n_tool/core/tokens.gd")
const KeyRefs = preload("res://addons/l10n_tool/core/key_refs.gd")


## 원문 이름 → [key…] (ref_aliases 패턴 순서, 파일 순서). active 를 deprecated 보다 앞에.
static func name_index(cat: Catalog) -> Dictionary:
	var idx: Dictionary = {}
	for pass_i in 2:
		for rank in cat.config.ref_aliases.size():
			for e in cat.all_entries:
				if cat.config.ref_rank(String(e["alias"])) != rank:
					continue
				var active: bool = e["status"] == Catalog.STATUS_ACTIVE
				if (pass_i == 0) != active:
					continue
				var nm: String = String(e["source"]).strip_edges()
				if nm.is_empty():
					continue
				if not idx.has(nm):
					idx[nm] = []
				if not (idx[nm] as Array).has(e["key"]):
					(idx[nm] as Array).append(e["key"])
	return idx


## key → [참조 key…] (원문의 `[x]` 등장 순서). `[x]` 가 없는 엔트리는 빠진다.
## issues 를 넘기면 E034(참조 대상 아님 · 이름 없음 · 번역 참조 불일치) · E036(이름 중복) ·
## W036(이름을 직접 적음)을 담는다. 없는 · deprecated key 참조는 KeyRefs.check(E037 · E038) 몫이라 건너뛴다.
## 같은 이름이 둘 이상이면 첫 후보(active · ref_aliases 순서 · 파일 순서)로 정한다(D15).
static func resolve(cat: Catalog, issues: Issues = null) -> Dictionary:
	var idx: Dictionary = name_index(cat)
	var bb: Array = cat.config.bbcode_tags
	if issues != null:
		for nm in idx.keys():
			var ks: Array = idx[nm]
			if ks.size() > 1:
				var first: Dictionary = cat.entry(ks[0])
				issues.error("E036", "참조 도메인에 같은 원문 이름 '%s' 의 key 가 %d개: %s" % [nm, ks.size(), ", ".join(PackedStringArray(ks))],
						String(first.get("file", "")), int(first.get("line", 0)), String(ks[0]))
	var out: Dictionary = {}
	for e in cat.all_entries:
		var names: PackedStringArray = Tokens.refs(String(e["source"]), bb)
		if names.is_empty():
			continue
		var keys: Array = []
		for nm in names:
			var k: String = tag_key(nm)
			if not k.is_empty():
				var target: Dictionary = cat.entry(k)
				if target.is_empty():
					continue
				if cat.config.ref_rank(String(target["alias"])) < 0:
					if issues != null:
						issues.error("E034", "참조 [%s] (%s) 가 참조 대상(%s)이 아님" % [nm, target["alias"], ", ".join(cat.config.ref_aliases)],
								String(e["file"]), int(e["line"]), String(e["key"]))
					continue
				keys.append(k)
				continue
			if not idx.has(nm):
				if issues != null:
					issues.error("E034", "참조 [%s] 가 참조 대상(%s)의 이름에 없음" % [nm, ", ".join(cat.config.ref_aliases)],
							String(e["file"]), int(e["line"]), String(e["key"]))
				continue
			var found: String = String((idx[nm] as Array)[0])
			if issues != null:
				issues.warn("W036", "참조 [%s] 를 이름으로 적음: [{%s}] (%s) 로 바꾼다" % [nm, found, cat.entry(found)["alias"]],
						String(e["file"]), int(e["line"]), String(e["key"]))
			keys.append(found)
		if keys.is_empty():
			continue
		out[e["key"]] = keys
		if issues != null:
			_check_translations(cat, e, keys, bb, issues)
	return out


## `[x]` 의 x 가 key 참조 하나(`{tx_…}`)뿐이면 그 key, 아니면 "".
static func tag_key(inner: String) -> String:
	var ks: PackedStringArray = KeyRefs.keys_in(inner)
	if ks.size() == 1 and inner.strip_edges() == "{%s}" % ks[0]:
		return ks[0]
	return ""


# 번역문의 `[x]` 는 같은 참조 key 들의 그 언어 이름이어야 한다(순서 무관, 개수 포함). key 참조
# `[{tx_…}]` 는 그 key 의 그 언어 이름으로 친다. 참조 대상에 그 언어 번역이 아직 없으면 판정하지 않는다.
static func _check_translations(cat: Catalog, e: Dictionary, keys: Array, bb: Array, issues: Issues) -> void:
	for loc in cat.config.target_locales():
		var t: String = String((e["tr"] as Dictionary).get(loc, {}).get("text", ""))
		if t.is_empty():
			continue
		var expected: Array = []
		var complete: bool = true
		for k in keys:
			var nm: String = cat.text(k, loc).strip_edges()
			if nm.is_empty():
				complete = false
				break
			expected.append(nm)
		if not complete:
			continue
		var got: Array = []
		for nm in Tokens.refs(t, bb):
			var k: String = tag_key(nm)
			if k.is_empty():
				got.append(nm)
				if expected.has(nm):
					issues.warn("W036", "%s 번역의 참조 [%s] 를 이름으로 적음: key 참조로 바꾼다" % [loc, nm],
							String(e["file"]), int(e["line"]), String(e["key"]))
			else:
				got.append(cat.text(k, loc).strip_edges())
		expected.sort()
		got.sort()
		if got != expected:
			issues.error("E034", "%s 번역의 참조 %s ≠ 기대 %s" % [loc, str(got), str(expected)],
					String(e["file"]), int(e["line"]), String(e["key"]))
