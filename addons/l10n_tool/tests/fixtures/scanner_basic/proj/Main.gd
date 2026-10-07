extends Node

const SCOPE_LABELS := {  # l10n-keys: training.scope.*
	"all": L.TRAINING_SCOPE_ALL,
	"role": L.TRAINING_SCOPE_ROLE,
}


func _ready() -> void:
	var a := Loc.t(L.UI_CONFIRM)
	var b := "tx_F7YZ6A7B8C"
	var c := "하드코딩 문구"
	print("로그는 제외 %s" % "이것도")
	push_warning("여러 줄",
		"로그 계속")
	var d := "주석 아님" # "주석 안 한글"
	# 주석 "한글" 전체 L.IN_COMMENT
	var e := "무시" # l10n-ignore
	var f := Loc.t("plain text")
	var g := tr(some_key)
	var h := Loc.t(row.name_key) # l10n-dynamic: card.pilot.*.name
	var i := L.NOT_THERE
	var j := get_node(^"한글/경로")
	var k := &"한글이름"
	var m := """여러
줄 한글"""
	var n := r"원시 문자열"
	var o := 'single 한글'
	var p := "# 해시 안의 문자열 한글"
	var q := tr("tx_D5MN0P1Q2R")
	"""블록 주석 한글"""
	var s := "L.NOT_CONST 문자열 안"


func _fill_preview() -> void:  # l10n-ignore
	var x := "더미 이름"
	var w := """더미
여러 줄"""

	var y := "더미 둘"


func after() -> void:
	var z := "다시 검사"
	assert(z != "", "단언 메시지")
	var r := ["두 줄
문자열", "끝"]
