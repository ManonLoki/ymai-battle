class_name RollSource
extends RefCounted

## 战斗用的随机源。可以先 push 一串固定点数，测试就能精确指定
## “这一击掷到 0.0”“下一击掷到 0.999”；队列空了才回到种子随机。

var _rng := RandomNumberGenerator.new()
var _queue: Array[float] = []


func _init(p_seed: int = -1) -> void:
	if p_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = p_seed


func push(values: Array) -> void:
	for value in values:
		_queue.append(float(value))


func randf() -> float:
	if not _queue.is_empty():
		return float(_queue.pop_front())
	return _rng.randf()


func randi_range(from: int, to: int) -> int:
	if not _queue.is_empty():
		return clampi(int(_queue.pop_front()), from, to)
	return _rng.randi_range(from, to)
