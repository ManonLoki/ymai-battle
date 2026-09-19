class_name WindowSettings
extends RefCounted

## 窗口模式的存取与应用。
##
## 三种模式对应两类诉求：窗口模式要留系统边框，方便在桌面上拖动和关窗；
## 最大化和全屏都是“看演出”的模式，边框只会碍眼，所以一律去掉。
## 选择存在 user:// 下，由主菜单在启动时读出来应用，所以下次启动依然生效。
##
## Android 电视上这些调用基本是空操作（系统始终全屏），
## 不用为电视单独分支——默认值本来就是最大化。

## 存档位置。和战绩分开存：战绩按天作废，设置要一直留着。
const SAVE_PATH := "user://settings.json"
## 存档里的字段名。
const MODE_KEY := "window_mode"

enum Mode { WINDOWED, MAXIMIZED, FULLSCREEN }

## 默认跟 project.godot 里的初始配置一致：最大化 + 无边框。
const DEFAULT_MODE := Mode.MAXIMIZED

## 界面上的呈现顺序，也是唯一一份模式清单——加一种模式只要往这里补一行。
const MODES := [Mode.WINDOWED, Mode.MAXIMIZED, Mode.FULLSCREEN]

## 每种模式的名字和一句说明。
const MODE_LABELS := {
	Mode.WINDOWED: ["窗口", "有系统边框，可以拖动和缩放"],
	Mode.MAXIMIZED: ["最大化", "铺满桌面，无边框"],
	Mode.FULLSCREEN: ["全屏", "独占整个屏幕，无边框"],
}


## 只有窗口模式带系统边框，另外两种都是无边框的沉浸式。
static func has_border(mode: int) -> bool:
	return sanitize(mode) == Mode.WINDOWED


## 菜单上显示的模式名。
static func display_name(mode: int) -> String:
	return str(MODE_LABELS[sanitize(mode)][0])


## 模式名下面那行小字说明。
static func description(mode: int) -> String:
	return str(MODE_LABELS[sanitize(mode)][1])


## 认不出的值一律回落到默认：存档坏了、或者是旧版本写的，都不该让游戏打不开。
static func sanitize(mode: int) -> int:
	return mode if MODE_LABELS.has(mode) else DEFAULT_MODE


## 读出上次选的模式。文件不在 / 读不动 / 不是合法值都给默认。
static func load_mode(path: String = SAVE_PATH) -> int:
	if not FileAccess.file_exists(path):
		return DEFAULT_MODE
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DEFAULT_MODE
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return DEFAULT_MODE
	var data: Dictionary = parsed
	# JSON 里的数字回来是浮点，转成 int 再校验。
	return sanitize(int(data.get(MODE_KEY, DEFAULT_MODE)))


## 写下选择。整份设置一起重写，目前也就这一项。
static func save_mode(mode: int, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	# 存不下就算了（磁盘满、只读目录），不值得为此打断游戏。
	if file == null:
		return
	file.store_string(JSON.stringify({MODE_KEY: sanitize(mode)}))
	file.close()


## 把模式应用到当前窗口。先定模式再定边框：
## 反过来的话，从全屏切回窗口时刚设好的边框会被随后的模式切换抹掉。
static func apply(mode: int) -> void:
	var target := sanitize(mode)
	DisplayServer.window_set_mode(window_mode_for(target))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, not has_border(target))


## 本模式对应的 DisplayServer 窗口模式。
static func window_mode_for(mode: int) -> DisplayServer.WindowMode:
	match sanitize(mode):
		Mode.WINDOWED:
			return DisplayServer.WINDOW_MODE_WINDOWED
		Mode.FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_MAXIMIZED
