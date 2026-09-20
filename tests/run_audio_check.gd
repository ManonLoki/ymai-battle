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
## 一次测量的窗口。音频在混音线程上走，play() 当帧量不到峰值。
const MEASURE_FRAMES := 40
## 等总线安静下来的上限。五条 WAV 都是 2 秒长，60fps 下 4 秒足够放完。
const QUIET_TIMEOUT_FRAMES := 240


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if AudioServer.get_driver_name() == "Dummy":
		printerr("AUDIO_DRIVER_IS_DUMMY")
		quit(1)
		return
	var music_bus := AudioServer.get_bus_index(AppSettings.MUSIC_BUS)
	var sfx_bus := AudioServer.get_bus_index(AppSettings.SFX_BUS)
	if music_bus < 0 or sfx_bus < 0:
		printerr("AUDIO_BUSES_MISSING")
		quit(1)
		return
	# 量的是「链路通不通」，不是用户当前的混音，所以两条总线都先推满。
	AppSettings.apply_mix(1.0, 1.0)

	var pool: Node = root.get_node_or_null("CombatSfxPool")
	var music: Node = root.get_node_or_null("MusicManager")
	if pool == null or music == null:
		printerr("AUDIO_AUTOLOADS_MISSING")
		quit(1)
		return

	# BGM：autoload 一起来就在播金冠铃。
	if not await _require_audible(music_bus, "BGM"):
		return

	# 五条 SE 逐条过一遍：漏一条就是漏一条，别拿「至少有一条响了」蒙混过去。
	for clip_name in CombatSfx.CLIP_PATHS:
		var name := str(clip_name)
		pool.play_clips(PackedStringArray([name]))
		if not await _require_audible(sfx_bus, "SFX", "clip=%s" % name):
			return
		await _await_quiet(sfx_bus)

	# 战斗里真正的入口是 CombatSfx.play_event，组合音（命中+回血）也要出声。
	var lifesteal := StrikeResult.new()
	lifesteal.hit = true
	lifesteal.lifesteal = true
	CombatSfx.play_event(lifesteal)
	if not await _require_audible(sfx_bus, "SFX_EVENT"):
		return

	# SE 响完之后 BGM 还得在。以前 SE 会把 BGM 的声部抢走。
	if not music.is_playing():
		printerr("BGM_STOPPED_BY_SFX")
		quit(1)
		return

	print("AUDIO_CHECK_OK")
	quit(0)


## 量一段窗口里的峰值：出声打一行标记，静音就 printerr 并退 1。
## 返回是否继续往下跑，调用方一律 `if not await ...: return`。
func _require_audible(bus: int, marker: String, detail: String = "") -> bool:
	var peak := await _peak_over(bus, MEASURE_FRAMES)
	var tail := (" %s" % detail if not detail.is_empty() else "") + (" peak=%.1f dB" % peak)
	if peak < AUDIBLE_DB:
		printerr("%s_SILENT%s" % [marker, tail])
		quit(1)
		return false
	print("%s_AUDIBLE%s" % [marker, tail])
	return true


## 接下来 frames 帧里这条总线的最大峰值（左右取大的那个）。
func _peak_over(bus: int, frames: int) -> float:
	var peak := -200.0
	for i in frames:
		await process_frame
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(bus, 0))
		peak = maxf(peak, AudioServer.get_bus_peak_volume_right_db(bus, 0))
	return peak


## 等这条总线真的安静下来再量下一条。固定等若干帧是不够的：
## 五条 WAV 都是 2 秒长，上一条的尾巴会把下一条托过阈值，静音的片段也就蒙混过关了。
func _await_quiet(bus: int) -> void:
	for i in QUIET_TIMEOUT_FRAMES:
		await process_frame
		if AudioServer.get_bus_peak_volume_left_db(bus, 0) < AUDIBLE_DB and AudioServer.get_bus_peak_volume_right_db(bus, 0) < AUDIBLE_DB:
			return
