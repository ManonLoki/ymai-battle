extends Node

## 战斗 one-shot 对象池。连击会在 0.12s 里叠多次命中，不能每次 new 播放器。
##
## 总线和播放方式都取 AppSettings 那一份，理由写在那边的常量上：
## 指定 Sample 会让除 Web 外的所有平台静音。

const POOL_SIZE := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for path_key in CombatSfx.CLIP_PATHS:
		var stream := load(str(CombatSfx.CLIP_PATHS[path_key])) as AudioStream
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		_streams[path_key] = stream
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = AppSettings.SFX_BUS
		player.playback_type = AppSettings.PLAYBACK_TYPE
		add_child(player)
		_players.append(player)


func sfx_playback_type() -> int:
	return int(_players[0].playback_type) if _players.size() > 0 else -1


func sfx_bus() -> StringName:
	return _players[0].bus if _players.size() > 0 else &""


func play_clips(clips: PackedStringArray) -> void:
	for clip_name in clips:
		_play_one(str(clip_name))


func _play_one(clip_name: String) -> void:
	if not _streams.has(clip_name):
		return
	var player := _players[_index]
	_index = (_index + 1) % POOL_SIZE
	player.stream = _streams[clip_name]
	player.play()
