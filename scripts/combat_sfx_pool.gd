extends Node

## 战斗 one-shot 对象池。连击会在 0.12s 里叠多次命中，不能每次 new 播放器。
##
## 播放方式必须和 BGM 一样是 Stream：Sample 播放只有 Web 的音频驱动实现了，
## CoreAudio / Android 上 AudioServer 只会丢一句
## 「the driver doesn't support sample playback」的 warning，
## 然后 playing 照样是 true、播放位置一直停在 0，扬声器一点声音都没有——
## 也就是说强行指定 Sample 等于在除 Web 外的所有平台上静音。
## 两边都走 Stream 之后也没有「抢 Sample 声部」这回事了。

const POOL_SIZE := 8
## 和 MusicManager 同一条规矩，改一边就得改另一边，所以写成同一个常量名。
const PLAYBACK := AudioServer.PLAYBACK_TYPE_STREAM

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
		player.bus = "SFX"
		player.playback_type = PLAYBACK
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
