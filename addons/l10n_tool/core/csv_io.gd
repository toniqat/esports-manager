@tool
extends RefCounted

## 원본 CSV 읽기 · 쓰기 — 설계서 §4.1 · §12.3.
##
## **바뀐 행만 다시 쓴다.** 읽을 때 레코드마다 원래 텍스트를 들고 있다가, 저장할 때
## 손대지 않은 레코드는 그 텍스트를 그대로, 바뀐 레코드만 다시 직렬화한다. 다시
## 직렬화할 때도 원래 따옴표로 감싸져 있던 셀은 계속 감싼다. BOM 유무와 줄바꿈
## (CRLF / LF)은 파일 단위로 보존한다. 빈 줄도 제자리에 남는다.
##
## 셀 안의 줄바꿈은 프로젝트 규칙상 리터럴 `\n` 두 글자지만(§4.1), RFC 4180 의
## 따옴표 안 실제 줄바꿈도 읽는다 — 그런 레코드는 여러 줄에 걸치며 `row_lines` 는
## 레코드가 **시작하는** 줄이다.

const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")

var path: String = ""
var headers: PackedStringArray = PackedStringArray()
## Array[PackedStringArray] — 데이터 행(헤더 제외). 길이는 헤더와 다를 수 있다.
var rows: Array = []
## 행마다 그 레코드가 시작하는 파일 줄 번호(1부터). 새로 붙인 행은 저장 전까지 0.
var row_lines: PackedInt32Array = PackedInt32Array()
var bom: bool = false
var eol: String = "\n"
## 파일이 줄바꿈으로 끝났는지 — 저장할 때 그대로 따른다.
var trailing_eol: bool = true
## 읽기 오류 — `{code, line, msg}`. code 는 E001(파싱) · E002(인코딩).
var errors: Array = []

# 레코드 순서 그대로: {raw: String, row: int(-1 = 헤더/빈 줄), kind: "header"|"row"|"blank"}
var _records: Array = []
# 행마다 원래 따옴표로 감싸져 있던 셀 인덱스 집합 (Dictionary[int, true]).
var _quoted: Array = []
var _dirty: Dictionary = {}       # row → true
var _header_dirty: bool = false
var _header_quoted: Dictionary = {}


## 파일을 읽는다. 파일이 없으면 errors 에 E001 하나를 남긴 빈 표를 돌려준다.
static func load_file(file_path: String) -> CsvIo:
	var t: CsvIo = CsvIo.new()
	t.path = file_path
	if not FileAccess.file_exists(file_path):
		t.errors.append({"code": "E001", "line": 0, "msg": "파일 없음: %s" % file_path})
		return t
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	t._parse_bytes(bytes)
	return t


## 새 표 — 아직 디스크에 없다. `save()` 하면 만들어진다.
static func create(file_path: String, header_cols: PackedStringArray) -> CsvIo:
	var t: CsvIo = CsvIo.new()
	t.path = file_path
	t.headers = header_cols.duplicate()
	# 저장소 `.gitattributes` 가 eol=lf — 기존 원본과 같게 OS 와 무관하게 LF.
	t.eol = "\n"
	t.bom = false
	t.trailing_eol = true
	t._records = [{"raw": "", "row": -1, "kind": "header"}]
	t._header_dirty = true
	return t


func ok() -> bool:
	return errors.is_empty()


func row_count() -> int:
	return rows.size()


## 헤더 이름 → 열 번호. 없으면 -1.
func col(col_name: String) -> int:
	return headers.find(col_name)


func has_column(col_name: String) -> bool:
	return headers.has(col_name)


func get_cell(row: int, col_name: String) -> String:
	var c: int = col(col_name)
	if c < 0 or row < 0 or row >= rows.size():
		return ""
	var r: PackedStringArray = rows[row]
	return r[c] if c < r.size() else ""


func get_cell_at(row: int, c: int) -> String:
	if c < 0 or row < 0 or row >= rows.size():
		return ""
	var r: PackedStringArray = rows[row]
	return r[c] if c < r.size() else ""


## 셀 값을 바꾼다. 값이 같으면 아무것도 하지 않는다(행이 dirty 가 되지 않는다).
## 없는 컬럼이면 false.
func set_cell(row: int, col_name: String, value: String) -> bool:
	var c: int = col(col_name)
	if c < 0 or row < 0 or row >= rows.size():
		return false
	var r: PackedStringArray = rows[row]
	if c < r.size() and r[c] == value:
		return true
	while r.size() <= c:
		r.append("")
	r[c] = value
	rows[row] = r
	# 값이 바뀐 셀은 원래 따옴표 스타일을 따르지 않는다 — 필요할 때만 감싼다
	# (설명문 → key 로 바뀐 셀이 `"tx_…"` 로 남지 않도록).
	(_quoted[row] as Dictionary).erase(c)
	_dirty[row] = true
	return true


## 행 하나를 파일 끝에 붙인다(§0.4 — 새 행은 끝에). values 의 키는 헤더 이름.
## 돌려주는 값은 새 행 번호.
func append_row(values: Dictionary) -> int:
	var r := PackedStringArray()
	r.resize(headers.size())
	for i in headers.size():
		r[i] = String(values.get(headers[i], ""))
	rows.append(r)
	row_lines.append(0)
	_quoted.append({})
	var idx: int = rows.size() - 1
	_records.append({"raw": "", "row": idx, "kind": "row"})
	_dirty[idx] = true
	return idx


## 컬럼을 끝에 붙인다. 모든 행이 바뀌므로 파일 전체가 다시 쓰인다(따옴표 스타일은 유지).
func add_column(col_name: String, default_value: String = "") -> bool:
	if has_column(col_name):
		return false
	headers.append(col_name)
	_header_dirty = true
	for i in rows.size():
		var r: PackedStringArray = rows[i]
		while r.size() < headers.size() - 1:
			r.append("")
		r.append(default_value)
		rows[i] = r
		_dirty[i] = true
	return true


## 헤더 이름만 바꾼다(데이터 행은 그대로).
func rename_column(old_name: String, new_name: String) -> bool:
	var c: int = col(old_name)
	if c < 0 or has_column(new_name):
		return false
	headers[c] = new_name
	_header_dirty = true
	return true


## 컬럼을 지운다. 모든 행이 다시 쓰인다.
func remove_column(col_name: String) -> bool:
	var c: int = col(col_name)
	if c < 0:
		return false
	headers.remove_at(c)
	_header_dirty = true
	var hq: Dictionary = {}
	for k in _header_quoted.keys():
		if int(k) < c:
			hq[k] = true
		elif int(k) > c:
			hq[int(k) - 1] = true
	_header_quoted = hq
	for i in rows.size():
		var r: PackedStringArray = rows[i]
		if c < r.size():
			r.remove_at(c)
		rows[i] = r
		var q: Dictionary = {}
		for k in (_quoted[i] as Dictionary).keys():
			if int(k) < c:
				q[k] = true
			elif int(k) > c:
				q[int(k) - 1] = true
		_quoted[i] = q
		_dirty[i] = true
	return true


## 첫 번째로 col_name == value 인 행. 없으면 -1.
func find_row(col_name: String, value: String) -> int:
	var c: int = col(col_name)
	if c < 0:
		return -1
	for i in rows.size():
		if get_cell_at(i, c) == value:
			return i
	return -1


## 행 하나를 {헤더: 값} 사전으로.
func row_dict(row: int) -> Dictionary:
	var d: Dictionary = {}
	for i in headers.size():
		d[headers[i]] = get_cell_at(row, i)
	return d


func is_dirty() -> bool:
	return _header_dirty or not _dirty.is_empty()


## 저장. 바뀐 것이 없으면 쓰지 않는다. 실패하면 오류 문자열, 성공하면 "".
func save() -> String:
	if not is_dirty() and FileAccess.file_exists(path):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for rec in _records:
		var kind: String = rec["kind"]
		if kind == "header":
			parts.append(_serialize(headers, _header_quoted) if _header_dirty or String(rec["raw"]).is_empty() else String(rec["raw"]))
		elif kind == "row":
			var ri: int = int(rec["row"])
			if _dirty.has(ri) or String(rec["raw"]).is_empty():
				parts.append(_serialize(rows[ri], _quoted[ri]))
			else:
				parts.append(String(rec["raw"]))
		else:
			parts.append(String(rec["raw"]))
	var text: String = eol.join(parts)
	if trailing_eol:
		text += eol
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "쓰기 실패: %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	if bom:
		f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_buffer(text.to_utf8_buffer())
	f.close()
	# 저장한 내용을 새 원본으로 — 다음 저장은 다시 바뀐 행만 쓴다.
	for rec in _records:
		if rec["kind"] == "header":
			rec["raw"] = _serialize(headers, _header_quoted)
		elif rec["kind"] == "row":
			rec["raw"] = _serialize(rows[int(rec["row"])], _quoted[int(rec["row"])]) if _dirty.has(int(rec["row"])) or String(rec["raw"]).is_empty() else rec["raw"]
	_dirty.clear()
	_header_dirty = false
	_recount_lines()
	return ""


## 셀 하나를 CSV 표기로. 쉼표 · 따옴표 · 줄바꿈이 있거나 원래 감싸져 있었으면 감싼다.
static func quote_cell(value: String, force: bool = false) -> String:
	var need: bool = force or value.contains(",") or value.contains("\"") or value.contains("\n") or value.contains("\r")
	if not need:
		return value
	return "\"" + value.replace("\"", "\"\"") + "\""


func _serialize(cells: PackedStringArray, quoted: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for i in cells.size():
		out.append(quote_cell(cells[i], quoted.has(i)))
	return ",".join(out)


func _recount_lines() -> void:
	var line: int = 1
	for rec in _records:
		if rec["kind"] == "row":
			row_lines[int(rec["row"])] = line
		line += String(rec["raw"]).count("\n") + 1


func _parse_bytes(bytes: PackedByteArray) -> void:
	var start: int = 0
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bom = true
		start = 3
	var body: PackedByteArray = bytes.slice(start)
	var text: String = body.get_string_from_utf8()
	# 유효한 UTF-8 이면 다시 인코딩한 바이트가 원본과 같다 (E002).
	if text.to_utf8_buffer() != body:
		errors.append({"code": "E002", "line": 0, "msg": "UTF-8 이 아닌 인코딩 (Excel 은 'CSV UTF-8' 로 저장): %s" % path})
		return
	eol = "\r\n" if text.contains("\r\n") else "\n"
	trailing_eol = text.ends_with("\n")
	_parse_text(text)


func _parse_text(text: String) -> void:
	var n: int = text.length()
	var i: int = 0
	var line: int = 1
	var first: bool = true
	while i < n:
		var rec_start: int = i
		var rec_line: int = line
		var cells := PackedStringArray()
		var quoted: Dictionary = {}
		var cell: String = ""
		var in_q: bool = false
		var cell_was_q: bool = false
		var done: bool = false
		while i < n and not done:
			var ch: String = text[i]
			if in_q:
				if ch == "\"":
					if i + 1 < n and text[i + 1] == "\"":
						cell += "\""
						i += 2
						continue
					in_q = false
					i += 1
					continue
				if ch == "\n":
					line += 1
				cell += ch
				i += 1
				continue
			if ch == "\"":
				if cell.is_empty() and not cell_was_q:
					in_q = true
					cell_was_q = true
				else:
					errors.append({"code": "E001", "line": rec_line, "msg": "따옴표가 셀 중간에 있음 (%s:%d)" % [path, rec_line]})
					cell += ch
				i += 1
			elif ch == ",":
				if cell_was_q:
					quoted[cells.size()] = true
				cells.append(cell)
				cell = ""
				cell_was_q = false
				i += 1
			elif ch == "\r" and i + 1 < n and text[i + 1] == "\n":
				i += 2
				done = true
			elif ch == "\n":
				i += 1
				done = true
			else:
				cell += ch
				i += 1
		if in_q:
			errors.append({"code": "E001", "line": rec_line, "msg": "닫히지 않은 따옴표 (%s:%d)" % [path, rec_line]})
		if cell_was_q:
			quoted[cells.size()] = true
		cells.append(cell)
		line += 1
		var raw_end: int = i
		if done:
			raw_end -= 2 if (i >= 2 and text[i - 2] == "\r" and text[i - 1] == "\n") else 1
		var raw: String = text.substr(rec_start, raw_end - rec_start)
		if first:
			if raw.is_empty():
				# 첫 줄이 비어 있으면 헤더가 없는 파일이다.
				errors.append({"code": "E001", "line": 1, "msg": "헤더 없음: %s" % path})
				_records.append({"raw": raw, "row": -1, "kind": "blank"})
				continue
			headers = cells
			_header_quoted = quoted
			_records.append({"raw": raw, "row": -1, "kind": "header"})
			first = false
			continue
		if raw.is_empty():
			_records.append({"raw": raw, "row": -1, "kind": "blank"})
			continue
		if cells.size() > headers.size():
			errors.append({"code": "E001", "line": rec_line, "msg": "셀 수(%d) > 헤더 수(%d) (%s:%d)" % [cells.size(), headers.size(), path, rec_line]})
		rows.append(cells)
		row_lines.append(rec_line)
		_quoted.append(quoted)
		_records.append({"raw": raw, "row": rows.size() - 1, "kind": "row"})
