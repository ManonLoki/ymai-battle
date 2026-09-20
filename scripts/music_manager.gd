extends Node

## 全局 BGM（project.godot 里注册为 autoload）。
##
## 换场景时 autoload 不会被卸载，所以两首曲子只在这里播：
## 金冠铃是菜单 / 排行 / 设置的共用曲，Tournament Clash 只在战斗场景。
## 同一首正在播时再请求一次是空操作，主菜单进出排行、设置才不会从头再来一遍。

const LOUNGE := preload("res://assets/audio/gold_crown_bell.ogg")
const BATTLE := preload("res://assets/audio/tournament_clash.ogg")
## 切场景时的交叉淡化。太短会跳，太长两首叠在一起发糊。
const CROSSFADE := 0.8
## 线性静音近似值；0 转 dB 是 -inf，tween 不能用。
## 和滑块拉到 0 时的静音是同一个数，所以取 AppSettings 那一份，别再写一遍。
const SILENCE_DB := AppSettings.VOLUME_SILENCE_DB

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	# 暂停时也要继续：BGM 跟光标一样是表现层，不该跟着战斗协程一起停。
	process_mode = Node.PROCESS_MODE_ALWAYS
	AppSettings.apply_audio()
	_player_a = _make_player()
	_player_b = _make_player()
	_active_player = _player_a
	play_lounge()


func _input(event: InputEvent) -> void:
	# Web 浏览器会拦住自动播放，_ready 里那次 play() 是静默失败的。
	# 第一次手势把已选中的曲子接着播，不从头再来。这是 keep_alive 现在唯一的用处：
	# SE 曾经会抢走 BGM 的 Sample 声部，但两边都改走 Stream 之后那条路不存在了。
	if event.is_pressed():
		keep_alive()


## 被浏览器拦下时 playing 是 false，但 stream 还在。从当前位置接着播，不要切回金冠铃。
func keep_alive() -> void:
	if _active_player == null or _active_player.stream == null or _active_player.playing:
		return
	var pos := _active_player.get_playback_position()
	if pos < 0.0:
		pos = 0.0
	_active_player.play(pos)


func play_lounge() -> void:
	_play(LOUNGE)


func play_battle() -> void:
	_play(BATTLE)


func current_stream() -> AudioStream:
	return _active_player.stream if _active_player != null else null


func is_lounge() -> bool:
	return current_stream() == LOUNGE


func is_battle() -> bool:
	return current_stream() == BATTLE


func is_playing() -> bool:
	return _active_player != null and _active_player.playing


func music_playback_type() -> int:
	return int(_active_player.playback_type) if _active_player != null else -1


func music_bus() -> StringName:
	return _active_player.bus if _active_player != null else &""


func playback_position() -> float:
	return _active_player.get_playback_position() if is_playing() else 0.0


func _play(stream: AudioStream) -> void:
	if stream == null or _active_player == null:
		return
	_enable_loop(stream)
	# 已经在播同一首就别动，否则进出排行/设置会把金冠铃掐回开头。
	# 被浏览器拦下时 playing 为 false：从当前位置续上，不要 play() 从头再来。
	if _active_player.stream == stream:
		if not _active_player.playing:
			keep_alive()
		return
	if not _active_player.playing or _active_player.stream == null:
		_active_player.stream = stream
		_active_player.volume_db = 0.0
		_active_player.play()
		return
	_crossfade_to(stream)


func _crossfade_to(stream: AudioStream) -> void:
	if _fade != null:
		_fade.kill()
		_fade = null
	var outgoing := _active_player
	var incoming := _player_b if outgoing == _player_a else _player_a
	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(outgoing, "volume_db", SILENCE_DB, CROSSFADE)
	_fade.tween_property(incoming, "volume_db", 0.0, CROSSFADE)
	_fade.chain().tween_callback(func() -> void:
		if is_instance_valid(outgoing):
			outgoing.stop()
			outgoing.volume_db = SILENCE_DB
	)
	_active_player = incoming


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = AppSettings.MUSIC_BUS
	player.volume_db = SILENCE_DB
	# 播放方式的理由写在 AppSettings.PLAYBACK_TYPE 上，CombatSfxPool 取的是同一个值。
	player.playback_type = AppSettings.PLAYBACK_TYPE
	player.max_polyphony = 2
	add_child(player)
	return player


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
