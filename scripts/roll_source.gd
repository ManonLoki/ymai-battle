class_name RollSource
extends RefCounted

## 战斗用的随机源。可以先 push 一串固定点数，测试就能精确指定
## “这一击掷到 0.0”“下一击掷到 0.999”；队列空了才回到种子随机。
##
## 结算器里每一次掷骰都必须走这里，否则测试就没法复现同一场战斗。

## 队列耗尽后兜底的真随机源。
var _rng := RandomNumberGenerator.new()
## 预设点数队列，先进先出。
var _queue: Array[float] = []


## 传负数（默认）表示每次都换一批随机数；传非负数则固定种子，同种子必然复现同一场。
func _init(p_seed: int = -1) -> void:
	if p_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = p_seed


## 排队一串预设点数，按顺序被后续的 randf / randi_range 取走。
func push(values: Array) -> void:
	for value in values:
		_queue.append(float(value))


## 取一个 [0, 1) 的点数：队列里还有就用队列的，没有才真随机。
func randf() -> float:
	if not _queue.is_empty():
		return float(_queue.pop_front())
	return _rng.randf()


## 取一个 [from, to] 的整数。预设点数按整数解释，并夹回区间内。
func randi_range(from: int, to: int) -> int:
	if not _queue.is_empty():
		return clampi(int(_queue.pop_front()), from, to)
	return _rng.randi_range(from, to)


## Fisher-Yates 原地洗牌。掷点走自己，所以同种子必然复现同样的顺序，
## 出场顺序和发牌才能在测试里精确重放。
##
## self. 不能省：@GlobalScope 里也有一个同名的 randi_range，不写 self
## 会调到那个全局真随机上去，队列里的预设点数一个都不消耗，
## 于是整场战斗表面上还能跑，实际已经不可复现了。
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := self.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
