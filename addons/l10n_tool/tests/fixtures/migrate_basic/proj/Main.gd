extends Node

func _ready() -> void:
	var a := "한글 하나"
	print("로그는 제외")
	var b := tr("plain")
	# "주석"
	var c := "english only"
