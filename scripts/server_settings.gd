class_name ServerSettings
extends RefCounted

## 榜单服务器地址的存取与校验。
##
## 默认走 TokenUsageApi 里写死的那个线上地址；在设置页填一个
## `协议://主机:端口/` 之后，取榜单就改走这台服务器（接口路径不变）。
## 填空 = 还原默认，所以「还原」不需要单独的存档字段。
##
## 只存**基址**，不存整条 URL：接口路径是代码的事，换服务器的人不该也不必知道。

## 和窗口模式共用同一份设置存档，别让设置散成两个文件。
const SAVE_PATH := WindowSettings.SAVE_PATH
## 存档里的字段名。
const BASE_URL_KEY := "server_base_url"

## 输入框里的灰字示例，同时也是这一项的格式说明，测试照着它对。
const PLACEHOLDER := "https://host:port/"

## 允许的基址写法：http/https + 主机（域名、IPv4 或方括号里的 IPv6）+ 可选端口 + 可选结尾斜杠。
## 刻意不收路径、查询串和用户名密码——接口路径由代码拼，
## 放开路径只会让「到底该不该带 /api」变成一个每次都要猜的问题。
const PATTERN := "^(?i)(https?)://(\\[[0-9A-Fa-f:.]+\\]|[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?/?$"

## 端口的合法范围，0 和 65536 都不是能连上的端口。
const PORT_MIN := 1
const PORT_MAX := 65535


## 把用户输入整理成规范基址：协议小写、去掉首尾空白和结尾斜杠。
## 空输入和任何不合规的写法都返回空串——调用方只要判空，不用自己再解析一遍。
static func normalize(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return ""
	var regex := RegEx.new()
	# 表达式是常量，编译不出错；真编译不了也当作「填错了」，不能把游戏卡在设置页。
	if regex.compile(PATTERN) != OK:
		return ""
	var found := regex.search(trimmed)
	if found == null:
		return ""
	var port := found.get_string(3)
	if not port.is_empty():
		var value := int(port)
		if value < PORT_MIN or value > PORT_MAX:
			return ""
	var base := "%s://%s" % [found.get_string(1).to_lower(), found.get_string(2)]
	return base if port.is_empty() else "%s:%d" % [base, int(port)]


## 这串输入能不能当服务器地址用。空串不算合法输入（它表示「还原默认」，另有入口）。
static func is_valid(text: String) -> bool:
	return not normalize(text).is_empty()


## 读出已保存的基址，没设过或存档坏了都给空串（= 用默认地址）。
static func load_base_url(path: String = SAVE_PATH) -> String:
	return normalize(str(JsonStore.read_dict(path).get(BASE_URL_KEY, "")))


## 存下基址。传空串或不合规的写法都会**清掉**这一项，也就是还原成默认地址。
## 校验在这里再做一遍：设置页之外的调用方（比如以后的命令行参数）也该走同一把尺子。
## 返回是否真的落盘成功，存不下（磁盘满、只读目录）不值得打断游戏。
static func save_base_url(text: String, path: String = SAVE_PATH) -> bool:
	return JsonStore.patch_dict(path, {BASE_URL_KEY: normalize(text)})


## 还原默认：把自定义地址清掉，之后取榜单又走 TokenUsageApi 里的默认地址。
static func clear(path: String = SAVE_PATH) -> bool:
	return save_base_url("", path)


## 有没有正在用自定义服务器。设置页拿它决定状态那行小字怎么写。
static func has_override(path: String = SAVE_PATH) -> bool:
	return not load_base_url(path).is_empty()
