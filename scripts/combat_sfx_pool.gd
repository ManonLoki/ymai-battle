extends Node

## 战斗 one-shot 对象池。连击会在 0.12s 里叠多次命中，不能每次 new 播放器。
##
## 总线和播放方式都取 AppSettings 那一份，理由写在那边的常量上：
## 指定 Sample 会让除 Web 外的所有平台静音。

## 池子里备几个播放器。一次三连击最多同时点名“命中+回血+重生”三声，
## 再赶上下一回合的声音还没放完，8 个足够轮，且远小于同时开 8 路音轨的开销。
const POOL_SIZE := 8

## clip 名 -> 已经解码好的 AudioStream。进场时一次性载完，
## 打起来之后不再碰磁盘——战斗中途 load 一个 WAV 会卡出可听见的停顿。
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
## 下一个该轮到谁播。环形推进，见 _play_one。
var _index: int = 0


## 把五条音效全部载进内存，再建好一池播放器。
## 都在进场时做完，打起来之后这个节点只剩“换 stream、按 play”两件事。
func _ready() -> void:
	# 暂停时也要出声：音效和 BGM 一样是表现层，不该跟着战斗协程一起停。
	process_mode = Node.PROCESS_MODE_ALWAYS
	for path_key in CombatSfx.CLIP_PATHS:
		var stream := load(str(CombatSfx.CLIP_PATHS[path_key])) as AudioStream
		# 导入器可能把短 WAV 标成循环，那样一声命中会一直响下去。
		# 这五条都是 one-shot，进池子之前统一掐掉循环标记。
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		_streams[path_key] = stream
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = AppSettings.SFX_BUS
		player.playback_type = AppSettings.PLAYBACK_TYPE
		add_child(player)
		_players.append(player)


## 下面两个是给测试问话用的：池里的播放器是不是都按约定的总线和播放方式建的。
## 只问第 0 个就够——它们是同一个循环里建出来的，测试另有一条断言盯着「每一个都一样」。
func sfx_playback_type() -> int:
	return int(_players[0].playback_type) if _players.size() > 0 else -1


func sfx_bus() -> StringName:
	return _players[0].bus if _players.size() > 0 else &""


## 把一批片段一起放出去。批里的几声是同一瞬间发生的（比如吸血 = 命中+回血），
## 所以不排队、不等前一声放完，各占一个播放器同时响。
func play_clips(clips: PackedStringArray) -> void:
	for clip_name in clips:
		_play_one(str(clip_name))


## 轮到下一个播放器放这一声。
##
## 不找「空闲的那个」而是无脑往后轮：连击在 0.12 秒里能叠好几下，挨个问谁空着
## 既慢又常常一个都没有。轮着用的代价是最老的那一声可能被打断，
## 但 8 个坑轮一圈的时间远长于一条音效的长度，实际听不出来。
func _play_one(clip_name: String) -> void:
	if not _streams.has(clip_name):
		return
	var player := _players[_index]
	_index = (_index + 1) % POOL_SIZE
	player.stream = _streams[clip_name]
	player.play()
