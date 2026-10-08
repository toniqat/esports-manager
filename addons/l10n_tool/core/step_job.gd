@tool
extends RefCounted

## 단계로 나눈 긴 명령 (편집기 진행 창). 단계 = {id, weight, run}: `run.call(job)` 은 그 단계의
## 진행률(0..1)을 돌려주고, 1 이상이면 다음 단계로 넘어간다(아니면 다음 step 에서 다시 부른다).
## 진행 창은 프레임마다 step() 을 몇 번 부르고 progress() · stage() 를 그린다. 헤드리스 · 테스트는
## run_all(). 명령 결과는 `result` (run 이 job 인자로 채운다. 람다가 job 을 잡으면 참조 순환).

var result: Variant = null

var _stages: Array = []
var _i: int = 0
var _part: float = 0.0


func add(id: String, weight: float, run: Callable) -> void:
	_stages.append({"id": id, "weight": weight, "run": run})


## 한 조각 돌린다. 다 끝났으면 true.
func step() -> bool:
	if _i >= _stages.size():
		return true
	_part = float((_stages[_i]["run"] as Callable).call(self))
	if _part >= 1.0:
		_i += 1
		_part = 0.0
	return _i >= _stages.size()


func is_done() -> bool:
	return _i >= _stages.size()


## 지금 단계 id (다 끝났으면 마지막 단계).
func stage() -> String:
	if _stages.is_empty():
		return ""
	return String(_stages[mini(_i, _stages.size() - 1)]["id"])


## 전체 진행률 0..1 (단계 weight 비례).
func progress() -> float:
	var total: float = 0.0
	var got: float = 0.0
	for i in _stages.size():
		var w: float = float(_stages[i]["weight"])
		total += w
		if i < _i:
			got += w
		elif i == _i:
			got += w * clampf(_part, 0.0, 1.0)
	return 1.0 if total <= 0.0 else got / total


## 끝까지 돌리고 result 를 돌려준다.
func run_all() -> Variant:
	while not step():
		pass
	return result
