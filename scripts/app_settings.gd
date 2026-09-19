class_name AppSettings
extends RefCounted

## 全局设置：窗口模式 + 榜单服务器地址。两项共用 user://settings.json 这一份存档，
## 所以也共用一个模块——以前拆成 WindowSettings / ServerSettings 两个类，
## 存档路径就得由其中一个当「主人」、另一个去借，加第三项设置时又要重新挑一次。
##
## 每一项都遵循同一套规矩：
##   1. 读进来的值一律先过一遍消毒（模式回落到默认、地址回落到空串），
##      存档不在 / 读不动 / 是旧版本写的 / 被人手改坏了，都不该让游戏打不开；
##   2. 存的时候只改自己那个字段（JsonStore.patch_dict），不碰别人的；
##   3. 存不下（磁盘满、只读目录）只回报结果，不打断游戏。
##
## 下面按「窗口模式」「榜单服务器地址」两段排，公共的存档位置在最前面。

## 存档位置。和战绩分开存：战绩按天作废，设置要一直留着。
const SAVE_PATH := "user://settings.json"


# ============================== 窗口模式 ==============================
#
# 三种模式对应两类诉求：窗口模式要留系统边框，方便在桌面上拖动和关窗；
# 最大化和全屏都是“看演出”的模式，边框只会碍眼，所以一律去掉。
# 选择由主菜单在启动时读出来应用，所以下次启动依然生效。
#
# Android 电视上这些调用基本是空操作（系统始终全屏），
# 不用为电视单独分支——默认值本来就是最大化。

## 存档里的字段名。
const MODE_KEY := "window_mode"

enum Mode { WINDOWED, MAXIMIZED, FULLSCREEN }

## 默认跟 project.godot 里的初始配置一致：最大化 + 无边框。
const DEFAULT_MODE := Mode.MAXIMIZED

## 界面上的呈现顺序。新增模式时还要在 settings.tscn 摆控件，并在 settings.gd 绑定。
const MODES := [Mode.WINDOWED, Mode.MAXIMIZED, Mode.FULLSCREEN]

## 每种模式的名字和一句说明。
const MODE_LABELS := {
	Mode.WINDOWED: ["窗口", "有系统边框，可以拖动和缩放"],
	Mode.MAXIMIZED: ["最大化", "铺满桌面，无边框"],
	Mode.FULLSCREEN: ["全屏", "独占整个屏幕，无边框"],
}


## 只有窗口模式带系统边框，另外两种都是无边框的沉浸式。
static func has_border(mode: int) -> bool:
	return sanitize_mode(mode) == Mode.WINDOWED


## 菜单上显示的模式名。
static func mode_display_name(mode: int) -> String:
	return str(MODE_LABELS[sanitize_mode(mode)][0])


## 模式名下面那行小字说明。
static func mode_description(mode: int) -> String:
	return str(MODE_LABELS[sanitize_mode(mode)][1])


## 认不出的值一律回落到默认：存档坏了、或者是旧版本写的，都不该让游戏打不开。
static func sanitize_mode(mode: int) -> int:
	return mode if MODE_LABELS.has(mode) else DEFAULT_MODE


## 读出上次选的模式。文件不在 / 读不动 / 不是合法值都给默认。
static func load_mode(path: String = SAVE_PATH) -> int:
	# JSON 里的数字回来是浮点，转成 int 再校验。
	return sanitize_mode(int(JsonStore.read_dict(path).get(MODE_KEY, DEFAULT_MODE)))


## 写下选择。只改自己这一项，同一份存档里还装着服务器地址。
static func save_mode(mode: int, path: String = SAVE_PATH) -> bool:
	return JsonStore.patch_dict(path, {MODE_KEY: sanitize_mode(mode)})


## 把模式应用到当前窗口。先定模式再定边框：
## 反过来的话，从全屏切回窗口时刚设好的边框会被随后的模式切换抹掉。
static func apply_mode(mode: int) -> void:
	var target := sanitize_mode(mode)
	DisplayServer.window_set_mode(window_mode_for(target))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, not has_border(target))


## 本模式对应的 DisplayServer 窗口模式。
static func window_mode_for(mode: int) -> DisplayServer.WindowMode:
	match sanitize_mode(mode):
		Mode.WINDOWED:
			return DisplayServer.WINDOW_MODE_WINDOWED
		Mode.FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_MAXIMIZED


# =========================== 榜单服务器地址 ===========================
#
# 默认走 TokenUsageApi 里写死的那个线上地址；在设置页填一个
# `协议://主机:端口/` 之后，取榜单就改走这台服务器（接口路径不变）。
# 填空 = 还原默认，所以「还原」不需要单独的存档字段。
#
# 只存**基址**，不存整条 URL：接口路径是代码的事，换服务器的人不该也不必知道。

## 存档里的字段名。
const BASE_URL_KEY := "server_base_url"

## 输入框里的灰字示例，同时也是这一项的格式说明，测试照着它对。
const SERVER_PLACEHOLDER := "https://host:port/"

## 允许的基址写法：http/https + 主机（域名、IPv4 或方括号里的 IPv6）+ 可选端口 + 可选结尾斜杠。
## 刻意不收路径、查询串和用户名密码——接口路径由代码拼，
## 放开路径只会让「到底该不该带 /api」变成一个每次都要猜的问题。
const SERVER_URL_PATTERN := "^(?i)(https?)://(\\[[0-9A-Fa-f:.]+\\]|[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?/?$"

## 端口的合法范围，0 和 65536 都不是能连上的端口。
const SERVER_PORT_MIN := 1
const SERVER_PORT_MAX := 65535

## 编译好的表达式。表达式是常量，编译一次就够，
## 而且「填错了」在设置页上是连着按几下就会发生的事。
static var _url_regex: RegEx = RegEx.create_from_string(SERVER_URL_PATTERN)


## 把用户输入整理成规范基址：协议小写、去掉首尾空白和结尾斜杠。
## 空输入和任何不合规的写法都返回空串——**判空就是判合法**，
## 调用方不用自己再解析一遍，也不该另有一套「算不算合法」的说法。
static func normalize_base_url(text: String) -> String:
	var trimmed := text.strip_edges()
	# 表达式真编译不了也当作「填错了」，不能把游戏卡在设置页。
	if trimmed.is_empty() or _url_regex == null:
		return ""
	var found := _url_regex.search(trimmed)
	if found == null:
		return ""
	var port := found.get_string(3)
	if not port.is_empty():
		var value := int(port)
		if value < SERVER_PORT_MIN or value > SERVER_PORT_MAX:
			return ""
	var base := "%s://%s" % [found.get_string(1).to_lower(), found.get_string(2)]
	return base if port.is_empty() else "%s:%d" % [base, int(port)]


## 读出已保存的基址，没设过或存档坏了都给空串（= 用默认地址）。
static func load_base_url(path: String = SAVE_PATH) -> String:
	return normalize_base_url(str(JsonStore.read_dict(path).get(BASE_URL_KEY, "")))


## 存下基址。传空串或不合规的写法都会**清掉**这一项，也就是还原成默认地址。
## 校验在这里再做一遍：设置页之外的调用方（比如以后的命令行参数）也该走同一把尺子。
static func save_base_url(text: String, path: String = SAVE_PATH) -> bool:
	return JsonStore.patch_dict(path, {BASE_URL_KEY: normalize_base_url(text)})


## 还原默认：把自定义地址清掉，之后取榜单又走 TokenUsageApi 里的默认地址。
static func clear_base_url(path: String = SAVE_PATH) -> bool:
	return save_base_url("", path)
