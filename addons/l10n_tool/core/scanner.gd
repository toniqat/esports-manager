@tool
extends RefCounted

## 사용처 스캔 → index.json — 설계서 §9 (+ E051 · W052/E052 · W053/E053 · W054 · E055 · W056 · E057).
##
## 파일 하나를 통째로 정규식 한 번(문자열 리터럴 · 주석 토큰)으로 훑고, 나머지 패턴
## (`tx_…` · `L.X` · 로그 호출 · `tr(`)은 그 토큰 범위와 비교해 판정한다 — 글자 단위
## 루프는 로그 호출의 괄호 짝 찾기에만 쓴다.
##   usage kind : literal · const · data · dynamic
##   orphans    : orphan_code · orphan_scene · preview_leak(+ keys = 그 번역문의 key 목록)
## 고아 검사 제외(D16): 주석, `scan.log_funcs` 호출 인자, `# l10n-ignore` 줄 · 그 주석이
## func 줄에 있으면 함수 전체, `scan.ignore_paths`, NodePath(`^"…"` · `$"…"`) ·
## StringName(`&"…"`) · `%"…"`, 단독 문장인 `"""…"""`(블록 주석 관용구).
## 사용처 기록은 제외 규칙과 무관하게 모든 대상 파일에서 한다.

const Config = preload("res://addons/l10n_tool/core/config.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Keygen = preload("res://addons/l10n_tool/core/keygen.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const TermMatch = preload("res://addons/l10n_tool/core/term_match.gd")

const KIND_LITERAL := "literal"
const KIND_CONST := "const"
const KIND_DATA := "data"
const KIND_DYNAMIC := "dynamic"
const KIND_ORPHAN_CODE := "orphan_code"
const KIND_ORPHAN_SCENE := "orphan_scene"
const KIND_PREVIEW_LEAK := "preview_leak"

# 주석(`#…`) 또는 문자열 리터럴. 접두사 r · & · ^ · $ · % 를 함께 잡는다.
# 왼쪽 우선 매칭이라 문자열 안의 `#` 와 주석 안의 따옴표는 저절로 그 토큰에 묻힌다.
# GDScript 는 "…" 안의 실제 줄바꿈도 받으므로 한 줄 문자열도 줄을 넘을 수 있다.
const TOKEN_PATTERN := "#[^\\n]*|(?<p>(?<![A-Za-z0-9_])r|[&^$%])?(?<q>\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:[^\"\\\\]|\\\\[\\s\\S])*\"|'(?:[^'\\\\]|\\\\[\\s\\S])*')"
const CONST_PATTERN := "\\bL\\.([A-Z][A-Z0-9_]*)"
const DIRECTIVE_PATTERN := "l10n-(?:dynamic|keys)\\s*:(.*)$"
const ALIAS_PAT_PATTERN := "[a-z][a-z0-9_]*(?:\\.[a-z0-9_*]+)+"
const CALL_PATTERN := "(?:\\btr|\\bLoc\\.t)\\s*\\(\\s*"
const TR_TAIL_PATTERN := "(?:\\btr|\\bLoc\\.t)\\s*\\(\\s*$"
const FUNC_LINE_PATTERN := "^([ \\t]*)(?:static[ \\t]+)?func\\b"
const HANGUL_PATTERN := "[\\x{AC00}-\\x{D7A3}\\x{3131}-\\x{318E}]"
const LETTER_PATTERN := "\\p{L}"
# 괄호 짝 찾기 상한 — 닫히지 않은 호출이 파일 끝까지 먹지 않도록.
const MAX_CALL_SPAN := 20000
# Node.AutoTranslateMode (Godot 4.5: INHERIT 0 · ALWAYS 1 · DISABLED 2). 씬에는 기본값(INHERIT)이
# 아닐 때만 노드 섹션에 `auto_translate_mode = <n>` 줄로 저장된다.
const AUTO_TRANSLATE_INHERIT := 0
const AUTO_TRANSLATE_DISABLED := 2


## 한 번의 스캔 동안 쓰는 상태 — 컴파일한 정규식 · 카탈로그 파생 표 · 결과.
class ScanCtx:
	extends RefCounted
	var l
	var cfg: Config
	var cat: Catalog
	var prefix: String = ""
	var strict: bool = false
	var re_key: RegEx
	var re_tok: RegEx
	var re_const: RegEx
	var re_dir: RegEx
	var re_alias_pat: RegEx
	var re_call: RegEx
	var re_tr_tail: RegEx
	var re_func: RegEx
	var re_hangul: RegEx
	var re_letter: RegEx
	var re_log: RegEx = null
	var re_scene: RegEx = null
	var ignore_paths: PackedStringArray = PackedStringArray()
	## L 상수 이름 → key (데이터 alias 제외)
	var const_map: Dictionary = {}
	## [[alias, key]…] — 동적 패턴 매칭용
	var aliases: Array = []
	var pattern_cache: Dictionary = {}
	## 번역문 → [key…] (원문 외 로케일, 빈 값 제외) — E057
	var trans_map: Dictionary = {}
	## 원문 집합 — 원문과 같은 번역문은 누수로 보지 않는다
	var source_set: Dictionary = {}
	## key → [{file, line, kind}]
	var usages: Dictionary = {}
	var seen: Dictionary = {}
	var orphans: Array = []
	var dynamic_bare: Array = []

	func is_ignored_path(path: String) -> bool:
		for p in ignore_paths:
			if path.begins_with(p):
				return true
		return false

	func add_usage(key: String, file: String, line: int, kind: String) -> void:
		var id: String = "%s|%s|%d|%s" % [key, kind, line, file]
		if seen.has(id):
			return
		seen[id] = true
		if not usages.has(key):
			usages[key] = []
		(usages[key] as Array).append({"file": file, "line": line, "kind": kind})

	## alias 패턴(`training.scope.*`)에 맞는 key 목록. `*` = 세그먼트 하나.
	func keys_for_pattern(pat: String) -> PackedStringArray:
		if pattern_cache.has(pat):
			return pattern_cache[pat]
		var body: String = pat.replace(".", "\\.").replace("*", "[a-z0-9_]+")
		var re := RegEx.create_from_string("^" + body + "$")
		var out := PackedStringArray()
		for pair in aliases:
			if re.search(String(pair[0])) != null:
				out.append(String(pair[1]))
		pattern_cache[pat] = out
		return out


## index.json 본문(§9.4)을 돌려주고, 사용처 규칙 위반은 l.issues 에 담는다.
static func scan(l) -> Dictionary:
	var ctx: ScanCtx = _make_ctx(l)
	for f in _collect_files(l.config):
		var text: String = FileAccess.get_file_as_string(f)
		if text.is_empty():
			continue
		var nl: PackedInt32Array = _newlines(text)
		_scan_literal(ctx, f, text, nl)
		if f.ends_with(".gd"):
			_scan_gd(ctx, f, text, nl)
		elif f.ends_with(".tscn") or f.ends_with(".tres"):
			_scan_scene(ctx, f, text, nl)
	_scan_data(ctx)
	_check_catalog(ctx)
	return _build_index(ctx)


## `config.gen_dir/index.json` 을 쓴다(탭 들여쓰기). 오류 문자열 또는 "".
static func write_index(l, index: Dictionary) -> String:
	var dir: String = l.config.gen_dir
	var err: int = DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return "폴더 생성 실패: %s (%d)" % [dir, err]
	var p: String = dir.path_join("index.json")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return "쓰기 실패: %s" % p
	f.store_string(JSON.stringify(index, "\t") + "\n")
	f.close()
	return ""


## `validate --fix-preview-leak` (§11.2): 번역문 → key 가 하나로 정해지는 E057 만
## 씬 값을 key 로 되돌린다. 그 값 부분만 바꾸고 나머지 바이트(BOM · 줄바꿈)는 그대로.
## 돌려주는 값: 고친 개수. l.issues 는 건드리지 않는다.
static func fix_preview_leak(l) -> int:
	var saved: Issues = l.issues
	l.issues = Issues.new()
	var idx: Dictionary = scan(l)
	l.issues = saved
	var by_file: Dictionary = {}
	for o in idx.get("orphans", []):
		if o["kind"] != KIND_PREVIEW_LEAK or (o["keys"] as Array).size() != 1:
			continue
		if not by_file.has(o["file"]):
			by_file[o["file"]] = []
		(by_file[o["file"]] as Array).append(o)
	var re_scene: RegEx = scene_regex(l.config)
	var fixed: int = 0
	for f in by_file.keys():
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(f)
		var bom: bool = bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF
		var text: String = bytes.slice(3 if bom else 0).get_string_from_utf8()
		var nl: PackedInt32Array = _newlines(text)
		var hits: Array = by_file[f]
		# 뒤쪽부터 바꿔야 앞쪽 오프셋이 그대로다.
		hits.sort_custom(func(a, b): return int(a["line"]) > int(b["line"]))
		var n: int = 0
		for h in hits:
			var ls: int = _line_start(nl, int(h["line"]))
			var m: RegExMatch = re_scene.search(text, ls)
			if m == null or m.get_start() != ls or unescape(m.get_string(2)) != String(h["text"]):
				continue
			text = text.substr(0, m.get_start(2)) + String(h["keys"][0]) + text.substr(m.get_end(2))
			n += 1
		if n == 0:
			continue
		var fa := FileAccess.open(f, FileAccess.WRITE)
		if fa == null:
			continue
		if bom:
			fa.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
		fa.store_buffer(text.to_utf8_buffer())
		fa.close()
		fixed += n
	return fixed


# ── 준비 ────────────────────────────────────────────────────────────────

static func _make_ctx(l) -> ScanCtx:
	var ctx := ScanCtx.new()
	var cfg: Config = l.config
	ctx.l = l
	ctx.cfg = cfg
	ctx.cat = l.catalog
	ctx.prefix = cfg.key_prefix
	ctx.strict = cfg.strict_orphans == "error"
	ctx.re_key = RegEx.create_from_string("(?<![A-Za-z0-9_])" + Keygen.pattern(cfg.key_prefix) + "(?![A-Za-z0-9_])")
	ctx.re_tok = RegEx.create_from_string(TOKEN_PATTERN)
	ctx.re_const = RegEx.create_from_string(CONST_PATTERN)
	ctx.re_dir = RegEx.create_from_string(DIRECTIVE_PATTERN)
	ctx.re_alias_pat = RegEx.create_from_string(ALIAS_PAT_PATTERN)
	ctx.re_call = RegEx.create_from_string(CALL_PATTERN)
	ctx.re_tr_tail = RegEx.create_from_string(TR_TAIL_PATTERN)
	ctx.re_func = RegEx.create_from_string(FUNC_LINE_PATTERN)
	ctx.re_hangul = RegEx.create_from_string(HANGUL_PATTERN)
	ctx.re_letter = RegEx.create_from_string(LETTER_PATTERN)
	ctx.re_scene = scene_regex(cfg)
	var logs := PackedStringArray()
	for fn in cfg.scan_list("log_funcs"):
		logs.append(Config._re_escape(String(fn)))
	if not logs.is_empty():
		ctx.re_log = RegEx.create_from_string("(?<![A-Za-z0-9_.])(?:" + "|".join(logs) + ")\\s*\\(")
	for p in cfg.scan_list("ignore_paths"):
		ctx.ignore_paths.append(_resolve(cfg, String(p)))
	for key in ctx.cat.entries.keys():
		if String(key).is_empty():
			continue
		var e: Dictionary = ctx.cat.entries[key]
		var alias: String = e["alias"]
		var src: String = e["source"]
		if src != "":
			ctx.source_set[src] = true
		if alias != "":
			ctx.aliases.append([alias, key])
			if not cfg.is_data_alias(alias):
				var cn: String = Config.const_name(alias)
				if not ctx.const_map.has(cn):
					ctx.const_map[cn] = key
		for loc in cfg.target_locales():
			var t: String = String(e["tr"][loc]["text"])
			if t.is_empty():
				continue
			if not ctx.trans_map.has(t):
				ctx.trans_map[t] = []
			if not (ctx.trans_map[t] as Array).has(key):
				(ctx.trans_map[t] as Array).append(key)
	return ctx


# `<prop> = "<value>"` 줄 — 그룹 1 = 속성, 2 = 이스케이프된 값(여러 줄 가능).
static func scene_regex(cfg: Config) -> RegEx:
	var props := PackedStringArray()
	for p in cfg.scan_list("scene_text_props"):
		props.append(Config._re_escape(String(p)))
	if props.is_empty():
		props.append("text")
	return RegEx.create_from_string("(?m)^(" + "|".join(props) + ") = \"((?:[^\"\\\\]|\\\\[\\s\\S])*)\"")


# res:// · user:// 가 아니면 config 폴더 기준 상대 경로.
static func _resolve(cfg: Config, p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	var out: String = cfg.base_dir.path_join(p)
	return out + "/" if p.ends_with("/") and not out.ends_with("/") else out


static func _collect_files(cfg: Config) -> PackedStringArray:
	var exts: Array = cfg.scan_list("include_ext")
	var excl := PackedStringArray()
	for p in cfg.scan_list("exclude_dirs"):
		excl.append(_resolve(cfg, String(p)))
	excl.append(cfg.gen_dir + "/")
	var out := PackedStringArray()
	var seen: Dictionary = {}
	for root in cfg.scan_list("roots"):
		_walk(_resolve(cfg, String(root)), true, exts, excl, out, seen)
	return out


static func _walk(dir: String, is_root: bool, exts: Array, excl: PackedStringArray, out: PackedStringArray, seen: Dictionary) -> void:
	var slash: String = dir if dir.ends_with("/") else dir + "/"
	if _has_prefix(slash, excl):
		return
	# .gdignore 는 루트 아래 폴더에만 적용 — fixture 루트 자체가 .gdignore 아래에 있다.
	if not is_root and FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	var files: Array = Array(DirAccess.get_files_at(dir))
	files.sort()
	for fn in files:
		var fs: String = fn
		if not exts.has("." + fs.get_extension()):
			continue
		var full: String = dir.path_join(fs)
		if seen.has(full) or _has_prefix(full, excl):
			continue
		seen[full] = true
		out.append(full)
	var dirs: Array = Array(DirAccess.get_directories_at(dir))
	dirs.sort()
	for d in dirs:
		if String(d).begins_with("."):
			continue
		_walk(dir.path_join(d), false, exts, excl, out, seen)


static func _has_prefix(path: String, prefixes: PackedStringArray) -> bool:
	for p in prefixes:
		if path.begins_with(p):
			return true
	return false


# ── 줄 계산 ──────────────────────────────────────────────────────────────

static func _newlines(text: String) -> PackedInt32Array:
	var nl := PackedInt32Array()
	var p: int = text.find("\n")
	while p >= 0:
		nl.append(p)
		p = text.find("\n", p + 1)
	return nl


## 글자 위치 → 줄 번호(1부터).
static func _line_of(nl: PackedInt32Array, pos: int) -> int:
	return nl.bsearch(pos) + 1


static func _line_start(nl: PackedInt32Array, line: int) -> int:
	return 0 if line <= 1 else nl[line - 2] + 1


static func _line_end(text: String, nl: PackedInt32Array, line: int) -> int:
	return nl[line - 1] if line - 1 < nl.size() else text.length()


# ── literal (모든 대상 파일) ───────────────────────────────────────────────

static func _scan_literal(ctx: ScanCtx, f: String, text: String, nl: PackedInt32Array) -> void:
	if not text.contains(ctx.prefix):
		return
	for m in ctx.re_key.search_all(text):
		ctx.add_usage(m.get_string(), f, _line_of(nl, m.get_start()), KIND_LITERAL)


# ── .gd ─────────────────────────────────────────────────────────────────

static func _scan_gd(ctx: ScanCtx, f: String, text: String, nl: PackedInt32Array) -> void:
	var tok_s := PackedInt32Array()
	var tok_e := PackedInt32Array()
	var strings: Array = []          # [start, end, line, prefix, literal]
	var ignore_lines: Dictionary = {}
	var dyn_lines: Dictionary = {}
	var cont_lines: Dictionary = {}  # 여러 줄 문자열의 둘째 줄부터
	for m in ctx.re_tok.search_all(text):
		var s: int = m.get_start()
		var e: int = m.get_end()
		tok_s.append(s)
		tok_e.append(e)
		var line: int = _line_of(nl, s)
		var lit: String = m.get_string("q")
		if lit.is_empty():
			var c: String = m.get_string()
			if not c.contains("l10n-"):
				continue
			if c.contains("l10n-ignore"):
				ignore_lines[line] = true
			var dm: RegExMatch = ctx.re_dir.search(c)
			if dm != null:
				dyn_lines[line] = true
				for pm in ctx.re_alias_pat.search_all(dm.get_string(1)):
					for key in ctx.keys_for_pattern(pm.get_string()):
						ctx.add_usage(key, f, line, KIND_DYNAMIC)
			continue
		strings.append([s, e, line, m.get_string("p"), lit])
		if lit.length() > 2 and text.find("\n", s) < e:
			for ln in range(line + 1, _line_of(nl, e - 1) + 1):
				cont_lines[ln] = true
	# const — 문자열 · 주석 밖의 L.X
	if text.contains("L."):
		for m in ctx.re_const.search_all(text):
			var s: int = m.get_start()
			if _in_ranges(tok_s, tok_e, s):
				continue
			var line: int = _line_of(nl, s)
			var cn: String = m.get_string(1)
			var key: String = String(ctx.const_map.get(cn, ""))
			if key.is_empty():
				if not Config.RESERVED_L_CONSTS.has(cn):
					ctx.l.issues.error("E051", "없는 L 상수: L.%s" % cn, f, line)
			else:
				ctx.add_usage(key, f, line, KIND_CONST)
	if ctx.is_ignored_path(f):
		return
	var func_ign: Dictionary = _ignored_func_lines(ctx, text, nl, ignore_lines, cont_lines)
	var logs: Array = _log_ranges(ctx, text, tok_s, tok_e)
	var log_s: PackedInt32Array = logs[0]
	var log_e: PackedInt32Array = logs[1]
	# orphan_code
	for st in strings:
		var s: int = st[0]
		var line: int = st[2]
		var pfx: String = st[3]
		if pfx != "" and pfx != "r":
			continue
		if ignore_lines.has(line) or func_ign.has(line) or _in_ranges(log_s, log_e, s):
			continue
		var lit: String = st[4]
		var triple: bool = lit.begins_with("\"\"\"") or lit.begins_with("'''")
		var body: String = lit.substr(3, lit.length() - 6) if triple else lit.substr(1, lit.length() - 2)
		if triple and _is_bare_statement(text, nl, s, int(st[1])):
			continue
		var orphan: bool = ctx.re_hangul.search(body) != null
		if not orphan and body != "" and _is_tr_first_arg(ctx, text, nl, s, line):
			orphan = not Keygen.is_valid(body, ctx.prefix)
		if orphan:
			ctx.orphans.append({"file": f, "line": line, "kind": KIND_ORPHAN_CODE, "text": body})
			var code: String = "E053" if ctx.strict else "W053"
			ctx.l.issues.add(code, Issues.ERROR if ctx.strict else Issues.WARN, "코드 고아 텍스트: \"%s\"" % _clip(body), f, line)
	# dynamic_bare — tr( · Loc.t( 의 첫 인자가 리터럴도 L. 상수도 아님
	if not (text.contains("tr") or text.contains("Loc.t")):
		return
	for m in ctx.re_call.search_all(text):
		var s: int = m.get_start()
		if _in_ranges(tok_s, tok_e, s):
			continue
		var line: int = _line_of(nl, s)
		if dyn_lines.has(line) or ignore_lines.has(line) or func_ign.has(line):
			continue
		var before: String = text.substr(_line_start(nl, line), s - _line_start(nl, line)).strip_edges()
		if before.ends_with("func"):
			continue
		var a: int = m.get_end()
		if a >= text.length() or _is_literal_or_const(text, a):
			continue
		ctx.dynamic_bare.append({"file": f, "line": line})
		ctx.l.issues.warn("W054", "주석 없는 동적 key — `# l10n-dynamic: <alias 패턴>` 필요", f, line)


# 첫 인자가 문자열 리터럴 / L.X / 빈 호출인가.
static func _is_literal_or_const(text: String, a: int) -> bool:
	var c: String = text[a]
	if c == "\"" or c == "'" or c == ")":
		return true
	if "&^r%$".contains(c) and a + 1 < text.length() and (text[a + 1] == "\"" or text[a + 1] == "'"):
		return true
	if text.substr(a, 2) == "L." and a + 2 < text.length():
		var u: int = text.unicode_at(a + 2)
		return u >= 65 and u <= 90
	return false


# 위치가 정렬된 (서로 겹치지 않는) 범위 [s, e) 중 하나 안인가.
static func _in_ranges(rs: PackedInt32Array, re: PackedInt32Array, pos: int) -> bool:
	var i: int = rs.bsearch(pos, false) - 1
	return i >= 0 and pos < re[i]


# 문자열이 `tr(` · `Loc.t(` 의 첫 인자인가 (같은 줄에서 여는 괄호 바로 뒤).
static func _is_tr_first_arg(ctx: ScanCtx, text: String, nl: PackedInt32Array, s: int, line: int) -> bool:
	var i: int = s - 1
	while i >= 0 and (text.unicode_at(i) == 32 or text.unicode_at(i) == 9):
		i -= 1
	if i < 0 or text.unicode_at(i) != 40:   # '('
		return false
	var ls: int = _line_start(nl, line)
	return ctx.re_tr_tail.search(text.substr(ls, s - ls)) != null


# 줄에 그 문자열 하나만 있는가 (앞은 공백, 뒤는 공백 · 주석) — `"""…"""` 블록 주석.
static func _is_bare_statement(text: String, nl: PackedInt32Array, s: int, e: int) -> bool:
	var line: int = _line_of(nl, s)
	var ls: int = _line_start(nl, line)
	if not text.substr(ls, s - ls).strip_edges().is_empty():
		return false
	var end_line: int = _line_of(nl, e - 1)
	var tail: String = text.substr(e, _line_end(text, nl, end_line) - e).strip_edges()
	return tail.is_empty() or tail.begins_with("#")


# `# l10n-ignore` 가 func 줄에 있으면 그 함수의 모든 줄 — 다음에 같거나 얕은 들여쓰기의
# (빈 줄 · 주석 · 여러 줄 문자열 연속이 아닌) 줄이 나올 때까지.
static func _ignored_func_lines(ctx: ScanCtx, text: String, nl: PackedInt32Array, ignore_lines: Dictionary, cont_lines: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var total: int = nl.size() + 1
	for fl in ignore_lines.keys():
		var line_txt: String = text.substr(_line_start(nl, fl), _line_end(text, nl, fl) - _line_start(nl, fl))
		var fm: RegExMatch = ctx.re_func.search(line_txt)
		if fm == null:
			continue
		var indent: int = fm.get_string(1).length()
		out[fl] = true
		for ln in range(fl + 1, total + 1):
			if cont_lines.has(ln):
				out[ln] = true
				continue
			var t: String = text.substr(_line_start(nl, ln), _line_end(text, nl, ln) - _line_start(nl, ln))
			var stripped: String = t.strip_edges()
			if stripped.is_empty() or stripped.begins_with("#"):
				out[ln] = true
				continue
			if t.length() - t.strip_edges(true, false).length() <= indent:
				break
			out[ln] = true
	return out


# 로그 함수 호출의 괄호 범위 [여는 괄호, 닫는 괄호+1) — 겹치지 않게 합쳐 정렬.
# 문자열 · 주석 토큰은 건너뛰며 괄호 깊이를 센다(여러 줄 호출도 따라간다).
static func _log_ranges(ctx: ScanCtx, text: String, tok_s: PackedInt32Array, tok_e: PackedInt32Array) -> Array:
	var rs := PackedInt32Array()
	var re := PackedInt32Array()
	if ctx.re_log == null:
		return [rs, re]
	var n: int = text.length()
	var tn: int = tok_s.size()
	for m in ctx.re_log.search_all(text):
		var open: int = m.get_end() - 1
		if _in_ranges(tok_s, tok_e, m.get_start()):
			continue
		if not rs.is_empty() and open < re[re.size() - 1]:
			continue   # 바깥 로그 호출 안 — 이미 덮였다
		var ti: int = tok_s.bsearch(open + 1)
		var depth: int = 1
		var i: int = open + 1
		var limit: int = mini(n, open + MAX_CALL_SPAN)
		while i < limit:
			if ti < tn and tok_s[ti] == i:
				i = tok_e[ti]
				ti += 1
				continue
			var c: int = text.unicode_at(i)
			if c == 40:
				depth += 1
			elif c == 41:
				depth -= 1
				if depth == 0:
					break
			i += 1
		rs.append(open)
		re.append(i + 1)
	return [rs, re]


# ── .tscn · .tres ────────────────────────────────────────────────────────

static func _scan_scene(ctx: ScanCtx, f: String, text: String, nl: PackedInt32Array) -> void:
	if ctx.re_scene == null:
		return
	var ignored: bool = ctx.is_ignored_path(f)
	for sv in parse_scene(ctx.re_scene, text, nl):
		# auto_translate_mode = DISABLED(2, 부모에서 상속 포함) — 스크립트가 덮어쓰는 자리표시 텍스트.
		if sv["disabled"]:
			continue
		var val: String = sv["value"]
		if Keygen.is_valid(val, ctx.prefix) or ctx.re_letter.search(val) == null:
			continue
		var line: int = sv["line"]
		var leak: Array = []
		if ctx.trans_map.has(val) and not ctx.source_set.has(val):
			leak = ctx.trans_map[val]
		if not leak.is_empty():
			ctx.orphans.append({"file": f, "line": line, "kind": KIND_PREVIEW_LEAK, "text": val, "keys": leak.duplicate()})
			var hint: String = "fix-preview-leak 로 되돌릴 수 있음" if leak.size() == 1 else "후보 key %d개 — 수동으로" % leak.size()
			ctx.l.issues.error("E057", "미리보기 누수 — %s 값이 번역문과 같음: \"%s\" (%s)" % [sv["prop"], _clip(val), hint], f, line, String(leak[0]))
			continue
		if ignored:
			continue
		ctx.orphans.append({"file": f, "line": line, "kind": KIND_ORPHAN_SCENE, "text": val, "prop": sv["prop"], "node": sv["node_path"]})
		var code: String = "E052" if ctx.strict else "W052"
		ctx.l.issues.add(code, Issues.ERROR if ctx.strict else Issues.WARN, "씬 고아 텍스트 (%s): \"%s\"" % [sv["prop"], _clip(val)], f, line)


## 씬 · 리소스 텍스트의 `scene_text_props` 값 목록 (extract scenes 와 공유).
##   {start, end: 이스케이프된 값의 글자 범위(따옴표 제외), line, prop, value(언이스케이프),
##    section: "node" · "sub_resource" · "resource", node_name, node_path("." = 루트,
##    그 밖은 루트 기준 "A/B"), section_id(sub_resource id), disabled}
## disabled = 그 노드의 auto_translate_mode 가 DISABLED(2) — INHERIT(0 · 생략)이면 같은 파일
## 안의 부모 노드를 따라 올라가며 처음 만난 명시 값(ALWAYS 1 · DISABLED 2)을 쓴다. 파일에 없는
## 조상(인스턴스한 씬 내부)은 건너뛰고, 끝까지 없으면 번역됨(루트 기본 = ALWAYS).
## re_scene 은 `scene_regex(cfg)`.
static func parse_scene(re_scene: RegEx, text: String, nl: PackedInt32Array = PackedInt32Array()) -> Array:
	if nl.is_empty():
		nl = _newlines(text)
	var vals: Array = []
	var vs := PackedInt32Array()
	var ve := PackedInt32Array()
	for m in re_scene.search_all(text):
		vs.append(m.get_start())
		ve.append(m.get_end())
		vals.append(m)
	# 섹션 헤더 — 여러 줄 값 안의 `[` 줄은 헤더가 아니다.
	var sections: Array = []   # [pos, kind, name, path, id]
	var re_head := RegEx.create_from_string("(?m)^\\[(node|sub_resource|resource|ext_resource|gd_scene|gd_resource|connection|editable)\\b([^\\n]*)\\]\\r?$")
	var re_attr := RegEx.create_from_string("(\\w+)=\"((?:[^\"\\\\]|\\\\.)*)\"")
	for h in re_head.search_all(text):
		if _in_ranges(vs, ve, h.get_start()):
			continue
		var attrs: Dictionary = {}
		for a in re_attr.search_all(h.get_string(2)):
			attrs[a.get_string(1)] = a.get_string(2)
		var kind: String = h.get_string(1)
		var node_path: String = ""
		if kind == "node":
			var nm: String = String(attrs.get("name", ""))
			if not attrs.has("parent"):
				node_path = "."
			else:
				var par: String = String(attrs["parent"])
				node_path = nm if par == "." else par + "/" + nm
		sections.append([h.get_start(), kind, String(attrs.get("name", "")), node_path, String(attrs.get("id", "")), h.get_end()])
	# 노드 경로 → auto_translate_mode (명시된 것만)
	var re_atm := RegEx.create_from_string("(?m)^auto_translate_mode = (\\d+)")
	var modes: Dictionary = {}
	for i in sections.size():
		var sec: Array = sections[i]
		if sec[1] != "node":
			continue
		var end: int = int(sections[i + 1][0]) if i + 1 < sections.size() else text.length()
		var am: RegExMatch = re_atm.search(text, int(sec[5]), end)
		if am != null:
			modes[sec[3]] = int(am.get_string(1))
	var starts := PackedInt32Array()
	for sec in sections:
		starts.append(int(sec[0]))
	var out: Array = []
	for m in vals:
		var si: int = starts.bsearch(m.get_start(), false) - 1
		var sec: Array = sections[si] if si >= 0 else [0, "", "", "", "", 0]
		var kind: String = sec[1]
		out.append({
			"start": m.get_start(2), "end": m.get_end(2), "line": _line_of(nl, m.get_start()),
			"prop": m.get_string(1), "value": unescape(m.get_string(2)),
			"section": kind, "node_name": sec[2], "node_path": sec[3], "section_id": sec[4],
			"disabled": kind == "node" and _translate_disabled(modes, String(sec[3])),
		})
	return out


# 노드 경로의 실효 auto_translate_mode 가 DISABLED 인가 (같은 파일 안 상속).
static func _translate_disabled(modes: Dictionary, path: String) -> bool:
	var p: String = path
	while p != "":
		var mode: int = int(modes.get(p, AUTO_TRANSLATE_INHERIT))
		if mode != AUTO_TRANSLATE_INHERIT:
			return mode == AUTO_TRANSLATE_DISABLED
		if p == ".":
			break
		var cut: int = p.rfind("/")
		p = "." if cut < 0 else p.substr(0, cut)
	return false


## .tscn 문자열 값 언이스케이프. Godot 4.5 는 `\\` · `\"` 만 이스케이프하고 줄바꿈은 그대로
## 쓴다(String.c_escape_multiline). String.c_unescape 는 `\\n`(역슬래시 + n)을 줄바꿈으로 잘못 바꾸므로
## 앞에서부터 한 글자씩 푼다.
static func unescape(s: String) -> String:
	if not s.contains("\\"):
		return s
	var out: String = ""
	var i: int = 0
	var n: int = s.length()
	while i < n:
		var c: String = s[i]
		if c != "\\" or i + 1 >= n:
			out += c
			i += 1
			continue
		var d: String = s[i + 1]
		i += 2
		match d:
			"n": out += "\n"
			"t": out += "\t"
			"r": out += "\r"
			"b": out += char(8)
			"f": out += char(12)
			"a": out += char(7)
			"v": out += char(11)
			"u", "U":
				var w: int = 4 if d == "u" else 6
				var hx: String = s.substr(i, w)
				if hx.length() == w and hx.is_valid_hex_number():
					out += char(hx.hex_to_int())
					i += w
				else:
					out += d
			_: out += d
	return out


# ── 데이터 CSV ───────────────────────────────────────────────────────────

static func _scan_data(ctx: ScanCtx) -> void:
	var tables: Dictionary = {}
	for dc_v in ctx.cfg.data_columns:
		var dc: Dictionary = dc_v
		var p: String = ctx.cfg.data_csv_dir.path_join(String(dc.get("csv", "")))
		if not tables.has(p):
			tables[p] = CsvIo.load_file(p) if FileAccess.file_exists(p) else null
		var t: CsvIo = tables[p]
		if t == null:
			continue
		var ci: int = t.col(String(dc.get("column", "")))
		if ci < 0:
			continue
		for r in t.row_count():
			var v: String = t.get_cell_at(r, ci).strip_edges()
			if v != "" and ctx.cat.has_key(v):
				ctx.add_usage(v, p, t.row_lines[r], KIND_DATA)


# ── 카탈로그 전체: E055 · W056 ─────────────────────────────────────────────

static func _check_catalog(ctx: ScanCtx) -> void:
	for key in ctx.cat.entries.keys():
		if String(key).is_empty():
			continue
		var e: Dictionary = ctx.cat.entries[key]
		var us: Array = ctx.usages.get(key, [])
		if e["status"] == Catalog.STATUS_DEPRECATED and not us.is_empty():
			ctx.l.issues.error("E055", "deprecated key 사용 중 (%s, 사용처 %d곳)" % [e["alias"], us.size()], String(us[0]["file"]), int(us[0]["line"]), key)
		elif e["status"] == Catalog.STATUS_ACTIVE and us.is_empty():
			ctx.l.issues.warn("W056", "사용처 없는 active key (%s)" % e["alias"], String(e["file"]), int(e["line"]), key)


# ── index.json ─────────────────────────────────────────────────────────

static func _build_index(ctx: ScanCtx) -> Dictionary:
	var cfg: Config = ctx.cfg
	# Glossary: [term_id, source-locale TermMatch] — a keyed term uses that key's source text;
	# a match_<source locale> regex wins over the substring rule.
	var terms: Array = []
	for g in ctx.cat.glossary_rows():
		var gk: String = String(g.get("key", "")).strip_edges()
		var term: String = ctx.cat.source_text(gk) if gk != "" else String(g.get(cfg.source_locale, ""))
		term = term.strip_edges()
		if term != "":
			terms.append([String(g.get("term_id", "")), TermMatch.for_row(g, cfg.source_locale, term)])
	var keys: Dictionary = {}
	for key in ctx.cat.entries.keys():
		if String(key).is_empty():
			continue
		var e: Dictionary = ctx.cat.entries[key]
		var src: String = e["source"]
		var trs: Dictionary = {}
		for loc in cfg.target_locales():
			var td: Dictionary = e["tr"][loc]
			trs[loc] = {"text": td["text"], "status": td["status"], "stale": ctx.cat.is_stale(key, loc)}
		var gl: Array = []
		for t in terms:
			if key != "" and TermMatch.found(t[1], src):
				gl.append(t[0])
		keys[key] = {
			"alias": e["alias"], "domain": e["domain"], "status": e["status"],
			"source": {"text": src, "hash": Hasher.hash_text(src)},
			"translations": trs, "glossary": gl, "usages": ctx.usages.get(key, []),
		}
	return {
		"generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"keys": keys, "orphans": ctx.orphans, "dynamic_bare": ctx.dynamic_bare,
	}


static func _clip(s: String) -> String:
	var one: String = s.replace("\r", "").replace("\n", "⏎")
	return one if one.length() <= 60 else one.substr(0, 60) + "…"
