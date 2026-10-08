@tool
extends RefCounted

## 원본 규칙 검증 + report.md — 설계서 §13 (E05x · W05x 사용처 규칙은 scanner 몫).
##
## 형식 규칙(E003 status · E010 ~ E013 · E031 · W003)은 deprecated 포함 모든 행,
## 번역 품질 규칙(W031 · W032 · E033 · E035 · W034 · W035 · W071 · W072)은 active 행만.
## 읽기 오류(E001 · E002)와 헤더 E003 은 catalog 가 이미 l.issues 에 넣었다.
## W041 = data_columns 의 CSV · 컬럼이 아직 없음(이행 전) — 사양 외 추가 경고.

const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const Config = preload("res://addons/l10n_tool/core/config.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Keygen = preload("res://addons/l10n_tool/core/keygen.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")
const Tokens = preload("res://addons/l10n_tool/core/tokens.gd")
const TermMatch = preload("res://addons/l10n_tool/core/term_match.gd")
const KeyRefs = preload("res://addons/l10n_tool/core/key_refs.gd")

const MODE_RELEASE := "release"
const JOSA_SCRIPT := "res://resources/StrategyIcon.gd"
const TERM_ID_PATTERN := "^[a-z][a-z0-9_]*$"
const TR_STATUSES := ["", Catalog.TR_DRAFT, Catalog.TR_APPROVED]
const ENTRY_STATUSES := [Catalog.STATUS_ACTIVE, Catalog.STATUS_DEPRECATED]

## 보고서 범례 — 나온 코드만 쓴다.
const LEGEND := {
	"E001": "CSV 파싱 실패", "E002": "UTF-8 이 아닌 인코딩",
	"E003": "필수 컬럼 누락 / 알 수 없는 status 값 / locales 와 컬럼 불일치",
	"E004": "tokens.josa_tags ≠ StrategyIcon.JOSA 키",
	"W003": "분해된 한글 자모(U+1100–U+11FF)",
	"E010": "key 형식 위반", "E011": "key 중복", "E012": "alias 형식 · 도메인 · 중복",
	"E013": "L 상수 이름 충돌",
	"E031": "approved 인데 해시 없음", "W031": "stale 번역", "W032": "번역 없이 status 만 있음",
	"E033": "값 자리표시자 집합 불일치", "E034": "카드 참조 [x] 불일치", "E035": "원문 외 로케일에 조사 태그",
	"E036": "참조 이름 중복",
	"E037": "key 참조 {tx_…} 가 없는 key", "E038": "key 참조 {tx_…} 가 deprecated", "E039": "key 참조 순환", "E040": "복수 태그 {plural:…} 형식 · 형태 수", "E043": "이름 key 에 key 참조 {tx_…} (용어집 낱말 포함)", "W034": "BBCode 태그 짝 불일치", "W035": "max_len 초과",
	"E041": "data_columns 셀이 없는 key", "E042": "data_columns key 의 alias 가 규칙과 다름",
	"W041": "data_columns 의 CSV · 컬럼이 아직 없음 (이행 전)",
	"E051": "없는 L 상수", "W052": "씬 고아 텍스트", "E052": "씬 고아 텍스트",
	"W053": "코드 고아 텍스트", "E053": "코드 고아 텍스트", "W054": "주석 없는 동적 key",
	"E055": "deprecated key 사용 중", "W056": "사용처 없는 active key", "E057": "미리보기 누수",
	"E061": "(release) fallback 번역이 approved · 비-stale 아님",
	"W071": "용어집 금지 표기", "W072": "용어 표준 표기 누락",
	"E072": "용어집 key 와 언어 값 중복 / 없는 key", "E073": "용어집 term_id 중복 · 형식",
	"E074": "용어집 match_<loc> 정규식 오류",
}


## l = core/l10n.gd 인스턴스. l.catalog · l.config 를 읽고 l.issues 에 담는다.
static func validate(l, mode: String) -> void:
	var iss: Issues = l.issues
	_check_josa_tags(l, iss)
	_check_format(l, iss)
	_check_translations(l, iss)
	KeyRefs.check(l.catalog, iss)
	_check_plurals(l, iss)
	l.resolve_refs(iss)
	_check_data_columns(l, iss)
	_check_glossary(l, iss)
	if mode == MODE_RELEASE:
		_check_release(l, iss)


# ── E004 ────────────────────────────────────────────────────────────────

static func _check_josa_tags(l, iss: Issues) -> void:
	if not FileAccess.file_exists(JOSA_SCRIPT):
		return
	var scr: Script = load(JOSA_SCRIPT) as Script
	if scr == null:
		return
	var josa: Variant = scr.get_script_constant_map().get("JOSA", null)
	if typeof(josa) != TYPE_DICTIONARY:
		return
	var want: Array = (josa as Dictionary).keys()
	var got: Array = l.config.josa_tags.duplicate()
	want.sort()
	got.sort()
	if want != got:
		iss.error("E004", "tokens.josa_tags %s ≠ StrategyIcon.JOSA 키 %s" % [str(got), str(want)], l.config.path)


# ── 형식: E003 status · W003 · E010 · E011 · E012 · E013 · E031 ──────────

static func _check_format(l, iss: Issues) -> void:
	var cfg: Config = l.config
	var cat: Catalog = l.catalog
	var alias_re := RegEx.create_from_string(Catalog.ALIAS_PATTERN)
	var seen_key: Dictionary = {}      # key → 첫 엔트리
	var seen_alias: Dictionary = {}    # alias → 첫 엔트리
	var consts: Dictionary = {}        # 상수 이름 → 첫 alias
	for e in cat.all_entries:
		var key: String = e["key"]
		var alias: String = e["alias"]
		var f: String = e["file"]
		var ln: int = int(e["line"])
		if not ENTRY_STATUSES.has(e["status"]):
			iss.error("E003", "알 수 없는 status '%s' (active / deprecated)" % e["status"], f, ln, key)
		for loc in cfg.target_locales():
			var tr_st: String = String(e["tr"][loc]["status"])
			if not TR_STATUSES.has(tr_st):
				iss.error("E003", "알 수 없는 %s_status '%s' (빈 값 / draft / approved)" % [loc, tr_st], f, ln, key)
			var tr_d: Dictionary = e["tr"][loc]
			if tr_st == Catalog.TR_APPROVED and String(tr_d["hash"]).is_empty():
				iss.error("E031", "%s approved 인데 %s_hash 가 비어 있음 — approve 명령으로 승인" % [loc, loc], f, ln, key)
		for txt in _texts(cfg, e):
			if Tokens.has_decomposed_jamo(txt):
				iss.warn("W003", "분해된 한글 자모 포함: %s" % txt, f, ln, key)
		if not Keygen.is_valid(key, cfg.key_prefix):
			iss.error("E010", "key 형식 위반: '%s'" % key, f, ln, key)
		if key != "":
			if seen_key.has(key):
				var first: Dictionary = seen_key[key]
				iss.error("E011", "key 중복 (이 행 alias %s) — 처음: %s:%d" % [alias, first["file"], int(first["line"])], f, ln, key)
			else:
				seen_key[key] = e
		if alias_re.search(alias) == null:
			iss.error("E012", "alias 형식 위반: '%s'" % alias, f, ln, key)
		elif alias.get_slice(".", 0) != e["domain"]:
			iss.error("E012", "alias 첫 세그먼트 ≠ domain '%s': %s" % [e["domain"], alias], f, ln, key)
		if alias != "":
			if seen_alias.has(alias):
				var first_a: Dictionary = seen_alias[alias]
				iss.error("E012", "alias 중복 '%s' — 처음: %s (%s:%d)" % [alias, first_a["key"], first_a["file"], int(first_a["line"])], f, ln, key)
				continue
			seen_alias[alias] = e
			if not cfg.is_data_alias(alias):
				var cn: String = Config.const_name(alias)
				if Config.RESERVED_L_CONSTS.has(cn):
					iss.error("E013", "L 상수 이름 %s 는 예약어 — alias '%s'" % [cn, alias], f, ln, key)
				elif consts.has(cn):
					iss.error("E013", "L 상수 이름 %s 충돌 — '%s' 와 '%s'" % [cn, consts[cn], alias], f, ln, key)
				else:
					consts[cn] = alias


# 원문 + 비어 있지 않은 번역문 전부.
static func _texts(cfg: Config, e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray([String(e["source"])])
	for loc in cfg.target_locales():
		var t: String = String(e["tr"][loc]["text"])
		if t != "":
			out.append(t)
	return out


# ── 번역 품질: W031 · W032 · E033 · E035 · W034 · W035 (active 만) ──────

static func _check_translations(l, iss: Issues) -> void:
	var cfg: Config = l.config
	var josa: Array = cfg.josa_tags
	var bb: Array = cfg.bbcode_tags
	for e in l.catalog.all_entries:
		if e["status"] != Catalog.STATUS_ACTIVE:
			continue
		var key: String = e["key"]
		var f: String = e["file"]
		var ln: int = int(e["line"])
		var src: String = e["source"]
		var src_hash: String = Hasher.hash_text(src)
		# 자리표시자는 key 참조를 펼친 문장으로 판정한다 (참조는 언어마다 선택 사항).
		var src_ph: PackedStringArray = Tokens.placeholder_set(KeyRefs.expand(l.catalog, src, cfg.source_locale, "dev"), josa)
		var src_bb: Array = _bb_sorted(src, bb)
		var max_len: int = -1
		var ml: String = String(e["max_len"]).strip_edges()
		if ml != "":
			if ml.is_valid_int():
				max_len = int(ml)
			else:
				iss.warn("W035", "max_len 이 정수가 아님: '%s'" % ml, f, ln, key)
		if not _bb_balanced(src, bb):
			iss.warn("W034", "%s 원문의 BBCode 태그 짝이 맞지 않음" % cfg.source_locale, f, ln, key)
		if max_len >= 0 and src.length() > max_len:
			iss.warn("W035", "%s %d자 > max_len %d" % [cfg.source_locale, src.length(), max_len], f, ln, key)
		for loc in cfg.target_locales():
			var tr_d: Dictionary = e["tr"][loc]
			var t: String = tr_d["text"]
			var st: String = tr_d["status"]
			if t.is_empty():
				if st != "":
					iss.warn("W032", "%s 번역이 없는데 %s_status = %s" % [loc, loc, st], f, ln, key)
				continue
			var h: String = tr_d["hash"]
			if h != src_hash:
				var why: String = "해시 없음 — sync 필요" if h.is_empty() else "원문이 바뀜"
				iss.warn("W031", "%s 번역 stale (%s)" % [loc, why], f, ln, key)
			var t_exp: String = KeyRefs.expand(l.catalog, t, loc, "dev")
			var ph: PackedStringArray = Tokens.placeholder_set(t_exp, josa)
			if t_exp != "" and ph != src_ph:
				iss.error("E033", "%s 자리표시자 %s ≠ 원문 %s" % [loc, str(ph), str(src_ph)], f, ln, key)
			var jt: PackedStringArray = Tokens.josa(t, josa)
			if not jt.is_empty():
				iss.error("E035", "%s 번역에 조사 태그 %s — 원문 로케일에만 허용" % [loc, str(jt)], f, ln, key)
			if not _bb_balanced(t, bb) or _bb_sorted(t, bb) != src_bb:
				iss.warn("W034", "%s BBCode 태그 %s ≠ 원문 %s" % [loc, str(Tokens.bbcode(t, bb)), str(Tokens.bbcode(src, bb))], f, ln, key)
			if max_len >= 0 and t.length() > max_len:
				iss.warn("W035", "%s %d자 > max_len %d" % [loc, t.length(), max_len], f, ln, key)


static func _bb_sorted(text: String, bb: Array) -> Array:
	var arr: Array = Array(Tokens.bbcode(text, bb))
	arr.sort()
	return arr


# 여는 태그 · 닫는 태그가 스택 순서로 짝이 맞는가.
static func _bb_balanced(text: String, bb: Array) -> bool:
	var stack: Array = []
	for tag in Tokens.bbcode(text, bb):
		if tag.begins_with("/"):
			if stack.is_empty() or stack.back() != tag.substr(1):
				return false
			stack.pop_back()
		else:
			stack.append(tag)
	return stack.is_empty()


# ── 복수 태그: E040 (active 만) ──────────────────────────────────────────
# `{plural:name|…}` 는 로케일 규칙표(`Loc.plural_index`)의 형태 수만큼 형태를 가져야 한다.
# 지금은 모든 로케일이 one · other 두 형태. 닫히지 않은 태그도 E040.
const PLURAL_FORMS := 2

static func _check_plurals(l, iss: Issues) -> void:
	var cfg: Config = l.config
	for e in l.catalog.all_entries:
		if e["status"] != Catalog.STATUS_ACTIVE:
			continue
		var texts: Dictionary = {cfg.source_locale: String(e["source"])}
		for loc in cfg.target_locales():
			texts[loc] = String(e["tr"][loc]["text"])
		for loc in texts.keys():
			var t: String = texts[loc]
			var found: Array = Tokens.plurals(t)
			if t.count("{plural:") != found.size():
				iss.error("E040", "%s 복수 태그 형식 오류 (`{plural:이름|단수|복수}`)" % loc, String(e["file"]), int(e["line"]), String(e["key"]))
			for p in found:
				if (p["forms"] as PackedStringArray).size() != PLURAL_FORMS:
					iss.error("E040", "%s 복수 태그 {plural:%s} 형태 %d개 (필요 %d)" % [loc, p["name"], (p["forms"] as PackedStringArray).size(), PLURAL_FORMS], String(e["file"]), int(e["line"]), String(e["key"]))


# ── 데이터 테이블: E041 · E042 · W041 ─────────────────────────────────────

static func _check_data_columns(l, iss: Issues) -> void:
	var cfg: Config = l.config
	var cat: Catalog = l.catalog
	var tables: Dictionary = {}    # csv 파일명 → CsvIo
	for dc_v in cfg.data_columns:
		var dc: Dictionary = dc_v
		var csv_name: String = String(dc.get("csv", ""))
		var column: String = String(dc.get("column", ""))
		var tpl: String = String(dc.get("alias", ""))
		var p: String = cfg.data_csv_dir.path_join(csv_name)
		if not tables.has(csv_name):
			if not FileAccess.file_exists(p):
				tables[csv_name] = null
			else:
				var loaded: CsvIo = CsvIo.load_file(p)
				for err in loaded.errors:
					iss.error(String(err["code"]), String(err["msg"]), p, int(err["line"]))
				tables[csv_name] = loaded
		var t: CsvIo = tables[csv_name]
		if t == null:
			iss.warn("W041", "data_columns %s 파일 없음 — 아직 이행 전 (%s)" % [csv_name, column], p)
			continue
		if not t.ok():
			continue
		if not t.has_column(column):
			iss.warn("W041", "data_columns %s 에 컬럼 %s 없음 — 아직 이행 전" % [csv_name, column], p, 1)
			continue
		for r in t.row_count():
			var cell: String = t.get_cell(r, column).strip_edges()
			if cell.is_empty():
				continue
			var ln: int = t.row_lines[r]
			if not cat.has_key(cell):
				iss.error("E041", "%s.%s 의 key 가 원본에 없음: %s" % [csv_name, column, cell], p, ln, cell)
				continue
			var want: String = Config.expand_alias(tpl, t.row_dict(r))
			var got: String = String(cat.entry(cell)["alias"])
			if got != want:
				iss.error("E042", "%s.%s key 의 alias '%s' ≠ 규칙 '%s'" % [csv_name, column, got, want], p, ln, cell)


# ── 용어집: E072 · E073 · W071 · W072 ─────────────────────────────────────

static func _check_glossary(l, iss: Issues) -> void:
	var cfg: Config = l.config
	var cat: Catalog = l.catalog
	var rows: Array = cat.glossary_rows()
	if rows.is_empty():
		return
	var gp: String = cfg.glossary_path()
	var term_re := RegEx.create_from_string(TERM_ID_PATTERN)
	var seen: Dictionary = {}
	# 용어 하나 = {id, std: {loc: 표준 표기}, forbidden: {loc: [표기…]}, match: {loc: TermMatch}}
	var terms: Array = []
	for g in rows:
		var tid: String = String(g.get("term_id", ""))
		var ln: int = int(g["line"])
		if term_re.search(tid) == null:
			iss.error("E073", "term_id 형식 위반: '%s'" % tid, gp, ln)
		elif seen.has(tid):
			iss.error("E073", "term_id 중복: %s (처음 %d줄)" % [tid, int(seen[tid])], gp, ln)
		else:
			seen[tid] = ln
		var gkey: String = String(g.get("key", "")).strip_edges()
		var key_ok: bool = gkey != ""
		if gkey != "":
			if not cat.has_key(gkey):
				iss.error("E072", "용어 %s 의 key 가 원본에 없음: %s" % [tid, gkey], gp, ln, gkey)
				key_ok = false
			for loc in cfg.locales:
				if String(g.get(loc, "")).strip_edges() != "":
					iss.error("E072", "용어 %s 에 key 와 %s 값이 함께 있음 — 언어 값은 key 에서 읽는다" % [tid, loc], gp, ln, gkey)
					break
		var dnt: bool = String(g.get("dnt", "")).strip_edges() == "1"
		var std: Dictionary = {}
		var forbidden: Dictionary = {}
		for loc in cfg.locales:
			if gkey != "":
				std[loc] = cat.text(gkey, loc).strip_edges() if key_ok else ""
			else:
				std[loc] = String(g.get(loc, "")).strip_edges()
			var fb := PackedStringArray()
			for w in String(g.get("forbidden_" + loc, "")).split("|", false):
				if w.strip_edges() != "":
					fb.append(w.strip_edges())
			forbidden[loc] = fb
		if dnt:
			for loc in cfg.locales:
				std[loc] = std[cfg.source_locale]
		var matchers: Dictionary = {}
		for loc in cfg.locales:
			var m: Dictionary = TermMatch.for_row(g, loc, std[loc])
			if m["error"] != "":
				iss.error("E074", "용어 %s 의 match_%s — %s" % [tid, loc, m["error"]], gp, ln)
			matchers[loc] = m
		terms.append({"id": tid, "key": gkey, "std": std, "forbidden": forbidden, "match": matchers})
	_check_terms(l, iss, terms)


static func _check_terms(l, iss: Issues, terms: Array) -> void:
	var cfg: Config = l.config
	var src_loc: String = cfg.source_locale
	for e in l.catalog.all_entries:
		if e["status"] != Catalog.STATUS_ACTIVE:
			continue
		var key: String = e["key"]
		var f: String = e["file"]
		var ln: int = int(e["line"])
		var texts: Dictionary = {src_loc: _expanded(l, String(e["source"]), src_loc)}
		for loc in cfg.target_locales():
			texts[loc] = _expanded(l, String(e["tr"][loc]["text"]), loc)
		for term in terms:
			for loc in texts.keys():
				var t: String = texts[loc]
				if t.is_empty():
					continue
				for w in term["forbidden"].get(loc, PackedStringArray()):
					if _contains(t, w):
						iss.warn("W071", "%s 에 용어 %s 의 금지 표기 '%s'" % [loc, term["id"], w], f, ln, key)
			if key == term["key"]:
				continue
			var src_term: String = term["std"].get(src_loc, "")
			if src_term.is_empty() or not TermMatch.found(term["match"][src_loc], texts[src_loc]):
				continue
			for loc in cfg.target_locales():
				var t: String = texts[loc]
				var want: String = term["std"].get(loc, "")
				if t.is_empty() or want.is_empty():
					continue
				if not TermMatch.found(term["match"][loc], t):
					iss.warn("W072", "원문에 용어 %s('%s')가 있는데 %s 번역에 '%s' 없음" % [term["id"], src_term, loc, want], f, ln, key)


# Substring, case-insensitive — forbidden forms only. Standard forms go through TermMatch
# (a match_<loc> regex wins over the substring rule).
# 용어 검사용 문장: key 참조를 펼치고(펼칠 수 없으면 원래 문장. 그 오류는 E037 ~ E039),
# 값 자리표시자 · 조사 태그 `{name}` 는 지운다 (`{skill_opportunist_rounds}` 의 "round" 오탐 방지).
static func _expanded(l, text: String, loc: String) -> String:
	var x: String = KeyRefs.expand(l.catalog, text, loc, "dev")
	if x == "" and text != "":
		x = text
	if x.find("{") < 0:
		return x
	if _re_name_token == null:
		_re_name_token = RegEx.create_from_string("\\{[a-z][a-z0-9_]*\\}")
	x = _re_name_token.sub(x, " ", true)
	# 복수 태그 이름(`{plural:skill_siege_rounds|…}`)도 낱말이 아니다. 형태만 남긴다.
	if _re_plural_name == null:
		_re_plural_name = RegEx.create_from_string("\\{plural:[a-z][a-z0-9_]*")
	return _re_plural_name.sub(x, "{", true)


static var _re_plural_name: RegEx = null


static var _re_name_token: RegEx = null


static func _contains(text: String, word: String) -> bool:
	return text.findn(word) >= 0


# ── E061 (release) ─────────────────────────────────────────────────────

static func _check_release(l, iss: Issues) -> void:
	var cfg: Config = l.config
	var fb: String = cfg.fallback_locale
	if fb == cfg.source_locale or not cfg.target_locales().has(fb):
		return
	var used: Dictionary = (l.index as Dictionary).get("keys", {})
	for e in l.catalog.all_entries:
		if e["status"] != Catalog.STATUS_ACTIVE:
			continue
		var key: String = e["key"]
		if not used.is_empty():
			var u: Dictionary = used.get(key, {})
			if (u.get("usages", []) as Array).is_empty():
				continue
		var tr_d: Dictionary = e["tr"][fb]
		var why: String = ""
		if String(tr_d["text"]).is_empty():
			why = "번역 없음"
		elif tr_d["status"] != Catalog.TR_APPROVED:
			why = "status '%s'" % tr_d["status"]
		elif tr_d["hash"] != Hasher.hash_text(String(e["source"])):
			why = "stale"
		if why != "":
			iss.error("E061", "release: %s 폴백 번역이 approved · 비-stale 아님 (%s)" % [fb, why], String(e["file"]), int(e["line"]), key)


# ── report.md ──────────────────────────────────────────────────────────

## l.config.gen_dir/report.md 를 쓴다. 오류 문자열 또는 "".
static func write_report(l, mode: String) -> String:
	var cfg: Config = l.config
	var iss: Issues = l.issues
	var md := PackedStringArray()
	md.append("# L10n 검증 보고서 — %s" % mode)
	md.append("")
	md.append("생성: %s · Error **%d** · Warn **%d**" % [Time.get_datetime_string_from_system(false, true), iss.error_count(), iss.warn_count()])
	md.append("")
	md.append("## 진행률")
	md.append("")
	md.append("| locale | total | 미착수 | draft | approved | stale | 진행률 |")
	md.append("|---|---|---|---|---|---|---|")
	for row in progress(l):
		md.append("| %s | %d | %d | %d | %d | %d | %.1f%% |" % [row["locale"], row["total"], row["untouched"], row["draft"], row["approved"], row["stale"], row["percent"]])
	md.append("")
	md.append("진행률 = approved 이면서 stale 아닌 번역 / active 원문 수. 텍스트는 있는데 status 가 비면 draft 로 센다.")
	md.append("")
	var codes_used: Array = []
	for level in [Issues.ERROR, Issues.WARN]:
		var by_code: Dictionary = {}
		for it in iss.items:
			if it["level"] != level:
				continue
			if not by_code.has(it["code"]):
				by_code[it["code"]] = []
			(by_code[it["code"]] as Array).append(it)
		var title: String = "Error" if level == Issues.ERROR else "Warn"
		var n: int = 0
		for c in by_code.values():
			n += (c as Array).size()
		md.append("## %s (%d)" % [title, n])
		md.append("")
		if by_code.is_empty():
			md.append("없음")
			md.append("")
			continue
		var codes: Array = by_code.keys()
		codes.sort()
		for code in codes:
			if not codes_used.has(code):
				codes_used.append(code)
			for it in by_code[code]:
				md.append(_report_line(l, it))
		md.append("")
	if not codes_used.is_empty():
		codes_used.sort()
		md.append("## 범례")
		md.append("")
		for code in codes_used:
			md.append("- **%s** — %s" % [code, LEGEND.get(code, "")])
		md.append("")
	var err: int = DirAccess.make_dir_recursive_absolute(cfg.gen_dir)
	if err != OK:
		return "폴더 생성 실패: %s (%d)" % [cfg.gen_dir, err]
	var p: String = cfg.gen_dir.path_join("report.md")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return "쓰기 실패: %s" % p
	f.store_string("\n".join(md))
	f.close()
	return ""


## 진행표 (§8) — 원문 외 로케일마다
## {locale, total, untouched, draft, approved, stale, percent}. 도크도 쓸 수 있다.
static func progress(l) -> Array:
	var cfg: Config = l.config
	var out: Array = []
	for loc in cfg.target_locales():
		var row: Dictionary = {"locale": loc, "total": 0, "untouched": 0, "draft": 0, "approved": 0, "stale": 0, "percent": 0.0}
		var done: int = 0
		for e in l.catalog.all_entries:
			if e["status"] != Catalog.STATUS_ACTIVE:
				continue
			row["total"] += 1
			var tr_d: Dictionary = e["tr"][loc]
			if String(tr_d["text"]).is_empty():
				row["untouched"] += 1
				continue
			var stale: bool = tr_d["hash"] != Hasher.hash_text(String(e["source"]))
			if stale:
				row["stale"] += 1
			if tr_d["status"] == Catalog.TR_APPROVED:
				row["approved"] += 1
				if not stale:
					done += 1
			else:
				row["draft"] += 1
		if int(row["total"]) > 0:
			row["percent"] = 100.0 * done / float(row["total"])
		out.append(row)
	return out


static func _report_line(l, it: Dictionary) -> String:
	var s: String = "- **%s**" % it["code"]
	var f: String = it["file"]
	if f != "":
		s += " `%s`" % (f if int(it["line"]) <= 0 else "%s:%d" % [f, int(it["line"])])
	var key: String = it["key"]
	if key != "":
		s += " `%s`" % key
		var alias: String = String(l.catalog.entry(key).get("alias", ""))
		if alias != "":
			s += " (%s)" % alias
	return s + " — " + String(it["msg"])
