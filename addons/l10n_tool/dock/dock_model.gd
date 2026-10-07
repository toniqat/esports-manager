@tool
extends RefCounted

## 조회 도크의 UI 없는 로직 — 설계서 §11.1 · §11.2(D12). 검색 · 필터 · 상세 · 용어집 ·
## 씬 미리보기 행. 화면(`l10n_dock.gd`)은 이 결과를 그리기만 한다 — 헤드리스 테스트 대상.
##
## 입력: config · catalog(원본) · index(index.json 본문, 없으면 {}) · 마지막 validate 의
## issues 항목. 행 하나 = catalog 엔트리 + 로케일별 상태 · stale + 용어 + 사용처.

const Keygen = preload("res://addons/l10n_tool/core/keygen.gd")
const TermMatch = preload("res://addons/l10n_tool/core/term_match.gd")

const ST_NONE := "미착수"
const ST_DRAFT := "draft"
const ST_APPROVED := "approved"
const GLOSSARY_CODES := ["W071", "W072"]
const KIND_SCRIPT := "script"
const KIND_SCENE := "scene"
const KIND_RESOURCE := "resource"
const KIND_COPY := "copy"

var config
var catalog
## index.json 본문(§9.4). 스캔 전 · 파일 없음이면 {}.
var index: Dictionary = {}
## 마지막 validate 의 issues.items — 용어집 위반(W071 · W072) 필터에 쓴다.
var issue_items: Array = []
## 검증을 한 번이라도 돌렸나 — 용어집 위반 필터가 비어 있는 이유를 구분한다.
var validated: bool = false
## 표시 행 (catalog 파일 순서).
var rows: Array = []

var _by_key: Dictionary = {}
var _terms: Array = []


func setup(cfg, cat, idx: Dictionary) -> void:
	config = cfg
	catalog = cat
	index = idx
	rebuild()


func set_issues(items: Array) -> void:
	issue_items = items
	validated = true


## config · catalog · index 로 행과 용어 목록을 다시 만든다.
func rebuild() -> void:
	rows.clear()
	_by_key.clear()
	_terms = _build_terms()
	if catalog == null:
		return
	for e in catalog.entries.values():
		var r: Dictionary = _make_row(e)
		rows.append(r)
		_by_key[r["key"]] = r


## index.json 을 읽는다. 없거나 깨졌으면 {}.
static func read_index(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## 사용처 데이터가 있나 — index 가 없거나 usages 가 전부 비면 false("scan 을 실행하세요").
func has_usage_data() -> bool:
	var keys: Dictionary = index.get("keys", {})
	for k in keys:
		if not ((keys[k] as Dictionary).get("usages", []) as Array).is_empty():
			return true
	return false


func target_locales() -> PackedStringArray:
	return config.target_locales() if config != null else PackedStringArray()


func domains() -> PackedStringArray:
	return catalog.domains() if catalog != null else PackedStringArray()


# ── 검색 · 필터 ─────────────────────────────────────────────────────────

## query = 부분 문자열(대소문자 무시) — key · alias · 원문 · 모든 번역 · 용어 term_id.
## filters: {domain, locale, status(ST_*), stale, unused, glossary} — 빈 값 · false 는 조건 없음.
## locale 을 주면 status · stale 은 그 로케일만, 아니면 status 는 아무 로케일, stale 은 어느 로케일이든.
func search(query: String, filters: Dictionary = {}) -> Array:
	var q: String = query.strip_edges().to_lower()
	var dom: String = String(filters.get("domain", ""))
	var loc: String = String(filters.get("locale", ""))
	var st: String = String(filters.get("status", ""))
	var stale_only: bool = bool(filters.get("stale", false))
	var unused_only: bool = bool(filters.get("unused", false))
	var gloss_only: bool = bool(filters.get("glossary", false))
	var gloss_keys: Dictionary = glossary_violation_keys() if gloss_only else {}
	var locs: PackedStringArray = PackedStringArray([loc]) if loc != "" else target_locales()
	var out: Array = []
	for r in rows:
		if dom != "" and r["domain"] != dom:
			continue
		if q != "" and not String(r["haystack"]).contains(q):
			continue
		if st != "" and not _any_locale(r, locs, func(t: Dictionary) -> bool: return t["status"] == st):
			continue
		if stale_only and not _any_locale(r, locs, func(t: Dictionary) -> bool: return t["stale"]):
			continue
		if unused_only and not is_unused(r):
			continue
		if gloss_only and not gloss_keys.has(r["key"]):
			continue
		out.append(r)
	return out


## active 인데 사용처가 없다.
static func is_unused(r: Dictionary) -> bool:
	return r["status"] == "active" and (r["usages"] as Array).is_empty()


## 용어집 위반(W071 · W072)이 걸린 key 집합.
func glossary_violation_keys() -> Dictionary:
	var out: Dictionary = {}
	for it in issue_items:
		if GLOSSARY_CODES.has(String(it.get("code", ""))) and String(it.get("key", "")) != "":
			out[String(it["key"])] = true
	return out


## index 의 고아 텍스트 [{file, line, kind, text}].
func orphans() -> Array:
	return index.get("orphans", []) as Array


func row_of(key: String) -> Dictionary:
	return _by_key.get(key, {})


# ── 상세 ────────────────────────────────────────────────────────────────

## 상세 패널 데이터 — 행 + 그 key 에 걸린 검증 항목. 없는 key 면 {}.
func detail(key: String) -> Dictionary:
	var r: Dictionary = row_of(key)
	if r.is_empty():
		return {}
	var d: Dictionary = r.duplicate(true)
	d.erase("haystack")
	var its: Array = []
	for it in issue_items:
		if String(it.get("key", "")) == key:
			its.append(it)
	d["issues"] = its
	return d


## 상세 패널 본문(사용처 제외 — 그건 목록으로 그린다).
func detail_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("alias: %s" % d["alias"])
	lines.append("domain: %s · status: %s" % [d["domain"], d["status"]])
	if String(d["context"]) != "":
		lines.append("context: %s" % d["context"])
	if String(d["max_len"]) != "":
		lines.append("max_len: %s" % d["max_len"])
	if String(d["note"]) != "":
		lines.append("note: %s" % d["note"])
	lines.append("파일: %s:%d" % [d["file"], int(d["line"])])
	lines.append("")
	lines.append("[%s] %s" % [config.source_locale, d["source"]])
	for loc in target_locales():
		var t: Dictionary = (d["tr"] as Dictionary).get(loc, {})
		lines.append("[%s] (%s) %s" % [loc, status_cell(t), String(t.get("text", ""))])
	if not (d["glossary"] as Array).is_empty():
		lines.append("")
		lines.append("용어: " + ", ".join(PackedStringArray(d["glossary"])))
	if not (d["issues"] as Array).is_empty():
		lines.append("")
		for it in d["issues"]:
			lines.append("%s %s" % [it["code"], it["msg"]])
	return "\n".join(lines)


## 목록 · 상세의 로케일 상태 칸 — "draft" · "approved · stale" · "미착수".
static func status_cell(t: Dictionary) -> String:
	var s: String = String(t.get("status", ST_NONE))
	return s + " · stale" if bool(t.get("stale", false)) else s


# ── 용어집 ──────────────────────────────────────────────────────────────

## 용어 행 [{term_id, key, texts{loc}, forbidden{loc: [..]}, dnt, note, line}].
## key 가 있는 용어는 각 언어 값을 그 key 에서 읽는다(§4.5). dnt 는 원문 표기를 모든 언어에.
func glossary_terms() -> Array:
	return _terms


## 원문에 그 용어(원문 표기)가 들어간 key 들.
func keys_with_term(term_id: String) -> Array:
	var out: Array = []
	for r in rows:
		if (r["glossary"] as Array).has(term_id):
			out.append(r["key"])
	return out


func _build_terms() -> Array:
	var out: Array = []
	if catalog == null or config == null:
		return out
	var src: String = config.source_locale
	for g in catalog.glossary_rows():
		var gkey: String = String(g.get("key", ""))
		var dnt: bool = String(g.get("dnt", "")) == "1"
		var texts: Dictionary = {}
		var forbidden: Dictionary = {}
		for loc in config.locales:
			var v: String = catalog.text(gkey, loc) if gkey != "" else String(g.get(loc, ""))
			texts[loc] = v
			var fb: PackedStringArray = PackedStringArray()
			for part in String(g.get("forbidden_" + loc, "")).split("|", false):
				fb.append(part.strip_edges())
			forbidden[loc] = fb
		if dnt:
			for loc in config.locales:
				if loc != src and String(texts[loc]) == "":
					texts[loc] = texts.get(src, "")
		out.append({"term_id": String(g.get("term_id", "")), "key": gkey, "texts": texts,
			"forbidden": forbidden, "dnt": dnt, "note": String(g.get("note", "")), "line": int(g.get("line", 0)),
			"match": TermMatch.for_row(g, src, String(texts.get(src, "")).strip_edges())})
	return out


## Term ids found in the source text — TermMatch (match_<source locale> regex, else substring).
func _match_terms(source: String) -> Array:
	var out: Array = []
	for t in _terms:
		if TermMatch.found(t["match"] as Dictionary, source):
			out.append(t["term_id"])
	return out


# ── 사용처 이동 ─────────────────────────────────────────────────────────

## 사용처 하나 → 이동 방법 {kind, path, line, label}. .gd = 스크립트 줄, .tscn = 씬 열기,
## .tres = 리소스 열기, 그 밖(데이터 CSV 등) = `path:line` 복사.
static func usage_action(u: Dictionary) -> Dictionary:
	var path: String = String(u.get("file", ""))
	var line: int = int(u.get("line", 0))
	var kind: String = KIND_COPY
	match path.get_extension().to_lower():
		"gd":
			kind = KIND_SCRIPT
		"tscn", "scn":
			kind = KIND_SCENE
		"tres", "res":
			kind = KIND_RESOURCE
	return {"kind": kind, "path": path, "line": line, "label": "%s:%d" % [path, line]}


## 사용처 목록 한 줄 — "kind  path:line".
static func usage_label(u: Dictionary) -> String:
	var s: String = "%s:%d" % [u.get("file", ""), int(u.get("line", 0))]
	var kind: String = String(u.get("kind", ""))
	return ("[%s] %s" % [kind, s]) if kind != "" else s


# ── 씬 미리보기 (D12) ───────────────────────────────────────────────────

## 편집 중인 씬 root 아래 모든 노드에서 props 값이 key 인 것 → 행
## [{path, prop, key, alias, text, missing}]. path = root 기준 NodePath 문자열(root 는 ".").
## 노드는 읽기만 한다 — 속성을 절대 쓰지 않는다(누수 방지).
static func scene_rows(root: Node, props: Array, cat, locale: String, prefix: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		for p in props:
			var v: Variant = n.get(StringName(p))
			if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
				continue
			var key: String = String(v)
			if not Keygen.is_valid(key, prefix):
				continue
			var e: Dictionary = cat.entry(key) if cat != null else {}
			var txt: String = cat.text(key, locale) if cat != null else ""
			out.append({"path": String(root.get_path_to(n)), "prop": String(p), "key": key,
				"alias": String(e.get("alias", "")), "text": txt, "known": not e.is_empty(), "missing": txt == ""})
		var kids: Array = n.get_children()
		for i in range(kids.size() - 1, -1, -1):
			stack.push_front(kids[i])
	return out


# ── 내부 ────────────────────────────────────────────────────────────────

func _make_row(e: Dictionary) -> Dictionary:
	var key: String = String(e["key"])
	var ix: Dictionary = (index.get("keys", {}) as Dictionary).get(key, {})
	var src: String = String(e["source"])
	var trs: Dictionary = {}
	var hay: PackedStringArray = PackedStringArray([key, String(e["alias"]), src])
	for loc in target_locales():
		var t: Dictionary = (e["tr"] as Dictionary).get(loc, {})
		var txt: String = String(t.get("text", ""))
		var st: String = String(t.get("status", ""))
		trs[loc] = {"text": txt, "status": st if st != "" else ST_NONE, "stale": catalog.is_stale(key, loc)}
		hay.append(txt)
	var terms: Array = _match_terms(src)
	for t in ix.get("glossary", []):
		if not terms.has(t):
			terms.append(t)
	for t in terms:
		hay.append(String(t))
	return {
		"key": key, "alias": String(e["alias"]), "domain": String(e["domain"]), "status": String(e["status"]),
		"context": String(e["context"]), "max_len": String(e["max_len"]), "note": String(e["note"]),
		"file": String(e["file"]), "line": int(e["line"]), "source": src, "tr": trs, "glossary": terms,
		"usages": (ix.get("usages", []) as Array).duplicate(), "haystack": "\n".join(hay).to_lower(),
	}


func _any_locale(r: Dictionary, locs: PackedStringArray, pred: Callable) -> bool:
	for loc in locs:
		var t: Dictionary = (r["tr"] as Dictionary).get(loc, {})
		if not t.is_empty() and pred.call(t):
			return true
	return false
