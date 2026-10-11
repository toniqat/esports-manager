class_name GameDb
extends RefCounted

# ── Game DB 경로 ──────────────────────────────────────────────────────
# SQLite 는 **디스크 위의 진짜 파일**을 열어야 한다. 에디터에서는 `res://` 가
# 그대로 실제 폴더라 그냥 열리지만, 익스포트한 빌드에서는 `res://` 가 `.pck`
# 안으로 들어가 SQLite 가 그 경로를 열 수 없다 — iOS / Android 빌드가
# 타이틀 화면부터 DB 오류로 멈추는 진짜 이유가 이것이다. 그래서 기기에서는
# 패킹된 DB 를 `user://` 로 한 번 뽑아낸 뒤 그 사본을 열어 준다.
#
# Copy only when the user:// copy differs. The DB is read-only at runtime (saves live
# in `user://saves/*.save`), so rewriting ~340KB of flash on every launch is waste.
# The check is a plain byte compare of the pck bytes against the existing copy (size
# first, then contents) — no stamp file, no hash: an old build's DB differs from the
# new build's bytes, so it can never survive an update, and a torn / tampered copy
# differs too and is rewritten. Measured on desktop: hashing (md5 + stamp) was slower
# than this compare, and the compare costs about what the old unconditional write did.
#
# `data/game.db` 는 **리소스가 아니므로** 그냥 두면 pck 에 안 들어간다 —
# `export_presets.cfg` 의 `include_filter` 가 그걸 넣는 자리다.
#
# 오토로드(`GameManager.db_path()`)가 아니라 정적 클래스에 사는 이유:
# `ConstTable` 은 다른 스크립트의 `static var` 초기화 중에 — 즉 오토로드가
# 트리에 붙기 **전**에도 — DB 를 열어야 한다. 경로 결정은 여기 한 곳뿐이고
# `GameManager.db_path()` 는 이 함수를 그대로 돌려준다.

const SOURCE_PATH:  String = "res://data/game.db"
const RUNTIME_PATH: String = "user://data/game.db"

static var _path: String = ""


# 런타임에 SQLite 에 넘길 game.db 경로. 에디터에서는 res:// 그대로,
# 익스포트 빌드에서는 pck 에서 뽑아낸 user:// 사본. 한 실행에 한 번만 확인한다.
static func path() -> String:
	if _path != "":
		return _path
	if OS.has_feature("editor"):
		_path = SOURCE_PATH
	else:
		_path = _extract_to_user()
	return _path


# pck 안의 game.db 를 user:// 로 꺼낸다(이미 같은 사본이면 쓰지 않는다). 실패하면
# 원본 경로를 그대로 돌려준다 — 어차피 열리지 않지만, 호출부마다 있는 open_db
# 실패 경로가 에러를 대신 말해 주므로 여기서 null 을 새로 만들 이유가 없다.
static func _extract_to_user() -> String:
	return RUNTIME_PATH if _sync_copy(SOURCE_PATH, RUNTIME_PATH) else SOURCE_PATH


# Make `target` a byte-identical copy of `source`, writing only when it differs.
# Returns true when `target` holds the source bytes. Paths are parameters so a
# test harness can run it without touching the real user:// DB.
static func _sync_copy(source: String, target: String) -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		push_error("GameDb: %s 가 빌드에 안 들어있다 — export_presets.cfg 의 include_filter 를 확인할 것." % source)
		return false
	if _same_bytes(target, bytes):
		return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target).get_base_dir())
	var f: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		push_error("GameDb: %s 에 쓸 수 없다 (%d)" % [target, FileAccess.get_open_error()])
		return false
	f.store_buffer(bytes)
	f.close()
	return true


# Does `target` exist with exactly `bytes`? Size is checked first so a missing,
# truncated or old-size copy is rejected without reading it.
static func _same_bytes(target: String, bytes: PackedByteArray) -> bool:
	var f: FileAccess = FileAccess.open(target, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() != bytes.size():
		f.close()
		return false
	var existing: PackedByteArray = f.get_buffer(bytes.size())
	f.close()
	return existing == bytes
