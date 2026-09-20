extends SceneTree

## 出声检查。跑法（注意：**不能加 --headless**，会有声音从扬声器出来）：
##   Godot --path . --script tests/run_audio_check.gd
##
## 只回答一个问题：BGM 和五条战斗音效有没有真的推到总线上。
## headless 用的是 Dummy 驱动，总线峰值永远是 -200 dB，所以这件事测不了；
## 而 Sample 播放只有 Web 的驱动实现了——CoreAudio / Android 上 play() 照样返回、
## playing 照样是 true，扬声器却一点声都没有。这类「静静地不出声」的回归
## 只有拿真驱动量一次总线峰值才抓得到，所以单独放一个脚本。
##
## 任何一步不对就 printerr 一个大写标记并 quit(1)，和 run_launch_smoke.gd 一个套路。

## 判定阈值。真有波形时是 -5 dB 上下，完全静音读回来是 -200 dB，中间宽得很。
const AUDIBLE_DB := -60.0
## 一条 one-shot 最多等多少帧。音频在混音线程上走，play() 当帧量不到峰值。
const SETTLE_FRAMES := 40


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if AudioServer.get_driver_name() == "Dummy":
		printerr("AUDIO_DRIVER_IS_DUMMY")
		quit(1)
		return
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if music_bus < 0 or sfx_bus < 0:
		printerr("AUDIO_BUSES_MISSING")
		quit(1)
		return
	# 量的是「链路通不通」，不是用户当前的混音，所以两条总线都先推满。
	AppSettings.apply_audio(1.0, 1.0)

	var pool: Node = root.get_node_or_null("CombatSfxPool")
	var music: Node = root.get_node_or_null("MusicManager")
	if pool == null or music == null:
		printerr("AUDIO_AUTOLOADS_MISSING")
		quit(1)
		return

	# BGM：autoload 一起来就在播金冠铃。
	var music_peak := await _peak_over(music_bus, SETTLE_FRAMES)
	if music_peak < AUDIBLE_DB:
		printerr("BGM_SILENT peak=%.1f dB" % music_peak)
		quit(1)
		return
	print("BGM_AUDIBLE peak=%.1f dB" % music_peak)

	# 五条 SE 逐条过一遍：漏一条就是漏一条，别拿「至少有一条响了」蒙混过去。
	for clip_name in CombatSfx.CLIP_PATHS:
		var name := str(clip_name)
		var clips := PackedStringArray([name])
		pool.play_clips(clips)
		var peak := await _peak_over(sfx_bus, SETTLE_FRAMES)
		if peak < AUDIBLE_DB:
			printerr("SFX_SILENT clip=%s peak=%.1f dB" % [name, peak])
			quit(1)
			return
		print("SFX_AUDIBLE clip=%s peak=%.1f dB" % [name, peak])
		# 等这条放完再量下一条，否则峰值是上一条的尾巴。
		await _settle(SETTLE_FRAMES)

	# 战斗里真正的入口是 CombatSfx.play_event，组合音（命中+回血）也要出声。
	var lifesteal := StrikeResult.new()
	lifesteal.hit = true
	lifesteal.lifesteal = true
	CombatSfx.play_event(lifesteal)
	var combo_peak := await _peak_over(sfx_bus, SETTLE_FRAMES)
	if combo_peak < AUDIBLE_DB:
		printerr("SFX_EVENT_SILENT peak=%.1f dB" % combo_peak)
		quit(1)
		return
	print("SFX_EVENT_AUDIBLE peak=%.1f dB" % combo_peak)

	# SE 响完之后 BGM 还得在。以前 SE 会把 BGM 的声部抢走。
	if not music.is_playing():
		printerr("BGM_STOPPED_BY_SFX")
		quit(1)
		return

	print("AUDIO_CHECK_OK")
	quit(0)


## 接下来 frames 帧里这条总线的最大峰值（左右取大的那个）。
func _peak_over(bus: int, frames: int) -> float:
	var peak := -200.0
	for i in frames:
		await process_frame
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(bus, 0))
		peak = maxf(peak, AudioServer.get_bus_peak_volume_right_db(bus, 0))
	return peak


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame
