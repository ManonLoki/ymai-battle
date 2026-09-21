class_name WebLaunchConfig
extends Node

## Web 启动参数的唯一入口。
##
## 页面可以在 Godot 启动前提供：
##   window.YMAIBattleConfig = {
##     BaseURL: [
##       {url: "https://a.example", name: "华东"},
##       {url: "https://b.example", name: ""},
##     ],
##     CloseMenu: ["ranking", "settings", "quit"],
##   };
##
## URL 查询串里的 BaseURL 值是逐项 JSON 编码的同一对象格式；重复出现的同名键
## 会逐字段覆盖全局对象，例如：
##   ?BaseURL=%7B%22url%22%3A%22https%3A%2F%2Fa.example%22%2C%22name%22%3A%22A%22%7D
##   &CloseMenu=ranking&CloseMenu=settings
##
## 这里只在 Web 导出里读取浏览器一次。后续场景只访问已经复制到 GDScript
## 容器里的快照，既没有异步竞态，也不会让网页在运行中偷偷改变游戏配置。

const GLOBAL_CONFIG_NAME := "YMAIBattleConfig"
const BASE_URL_PARAM := "BaseURL"
const CLOSE_MENU_PARAM := "CloseMenu"

## Battle 是产品的核心入口，不能被 Web 参数关闭；其余三个名字是稳定的公共 ID，
## 不依赖按钮上的中文文案或场景节点名。
const CLOSEABLE_MENU_IDS := [&"ranking", &"settings", &"quit"]

## 查询串和页面全局对象都属于不可信输入。上限主要用于避免异常页面塞进一个
## 巨大的 JS 数组，而不是限制正常部署。
const MAX_ARRAY_ITEMS := 64

static var _has_base_urls_override := false
static var _servers: Array[Dictionary] = []
static var _closed_menus: Dictionary = {}


## autoload 一进树就先把上一次会话的注入清空，再看这次是不是跑在浏览器里。
## 只有 Web 版有启动参数可读；桌面和安卓跑到这里就结束，一切回落到本地存档。
func _enter_tree() -> void:
	reset()
	if OS.has_feature("web"):
		_configure_from_browser()


## 测试和浏览器适配层共用的注入口。base_urls_present 必须单独传入，因为
## “完全没提供 BaseURL”要回落到本地列表，而“显式提供了空数组”不能回落。
static func configure(base_urls_present: bool, base_urls: Variant = [], close_menus: Variant = []) -> void:
	_has_base_urls_override = base_urls_present
	_servers = normalize_servers(base_urls)
	_closed_menus.clear()
	for menu_id in normalize_close_menus(close_menus):
		_closed_menus[menu_id] = true


## 清掉注入状态。headless 测试可以在每个用例前调用，避免用例之间串数据。
static func reset() -> void:
	_has_base_urls_override = false
	_servers.clear()
	_closed_menus.clear()


## 这次启动到底有没有被网页参数接管服务器列表。
## 设置页拿它决定列表是只读还是可增删——注意“提供了空数组”也算接管。
static func has_base_urls_override() -> bool:
	return _has_base_urls_override


## 当前设置页该展示的服务器候选。外部与本地候选都统一成 {url, name}；
## 任一路的空名称都由显示层回退为 URL 的 Host。
static func active_servers(settings_path: String = AppSettings.SAVE_PATH) -> Array[Dictionary]:
	if _has_base_urls_override:
		return _copy_servers(_servers)
	return AppSettings.load_servers(settings_path)


## 请求和存档仍只认 URL。名称纯属展示信息，绝不进入网络层或持久化选择值。
static func active_base_urls(settings_path: String = AppSettings.SAVE_PATH) -> Array[String]:
	var urls: Array[String] = []
	for server in active_servers(settings_path):
		urls.append(str(server.get("url", "")))
	return urls


## 某个候选给人看的名称。传入名称优先；空名称严格回退到 URL 的 Host。
static func base_url_display_name(base: String, settings_path: String = AppSettings.SAVE_PATH) -> String:
	var normalized := AppSettings.normalize_base_url(base)
	if normalized.is_empty():
		return "默认"
	for server in active_servers(settings_path):
		if str(server.get("url", "")) == normalized:
			return AppSettings.server_display_name(server)
	return AppSettings.base_url_host(normalized)


## 当前真正生效的基址。空串表示走 TokenUsageApi 的内置默认地址。本地列表只在
## 保存选择仍有效时生效；外部列表非空时则以它为唯一来源，选择失效就用第一项。
static func effective_base_url(settings_path: String = AppSettings.SAVE_PATH) -> String:
	var active := active_base_urls(settings_path)
	if active.is_empty():
		return ""
	var selected := AppSettings.normalize_base_url(AppSettings.load_base_url(settings_path))
	if active.has(selected):
		return selected
	# 外部数组是本次会话唯一的数据源：未选过或旧选择不在数组里时，第一项生效。
	return active[0] if _has_base_urls_override else ""


## 这个菜单入口是不是被网页参数关掉了。
## 比对前统一去空白转小写，免得 ?CloseMenu=Ranking 和 =ranking 表现不一样。
static func is_menu_closed(menu_id: String) -> bool:
	return _closed_menus.has(menu_id.strip_edges().to_lower())


## 纯归一化函数：只接受 {url: String, name: String} 项。name 可省略或为空；
## URL 非法、字段类型错误和重复 URL 都丢弃，第一次出现的项决定名称和顺序。
static func normalize_servers(values: Variant) -> Array[Dictionary]:
	if not _is_supported_array(values):
		return []
	var limited: Array = []
	var count := 0
	for value in values:
		if count >= MAX_ARRAY_ITEMS:
			break
		count += 1
		limited.append(value)
	return AppSettings.normalize_servers(limited)


## 兼容现有请求侧调用名，但输入格式已经是对象数组；返回值只投影 URL。
static func normalize_base_urls(values: Variant) -> Array[String]:
	var urls: Array[String] = []
	for server in normalize_servers(values):
		urls.append(str(server.get("url", "")))
	return urls


## 纯归一化函数：菜单 ID 不区分大小写、忽略首尾空白，未知 ID（包括 battle）
## 一律丢弃，并保持首次出现的顺序。
static func normalize_close_menus(values: Variant) -> Array[String]:
	var normalized: Array[String] = []
	if not _is_supported_array(values):
		return normalized
	var count := 0
	for value in values:
		if count >= MAX_ARRAY_ITEMS:
			break
		count += 1
		if typeof(value) != TYPE_STRING:
			continue
		var menu_id := str(value).strip_edges().to_lower()
		if CLOSEABLE_MENU_IDS.has(StringName(menu_id)) and not normalized.has(menu_id):
			normalized.append(menu_id)
	return normalized


## 浏览器适配层：全局对象先提供默认值，查询串里“出现过”的字段再整体覆盖。
## 使用 URLSearchParams.getAll() 保留重复键数组，不 eval，也不手写百分号解码。
static func _configure_from_browser() -> void:
	var array_api: Variant = JavaScriptBridge.get_interface("Array")
	var reflect_api: Variant = JavaScriptBridge.get_interface("Reflect")
	var global_config: Variant = JavaScriptBridge.get_interface(GLOBAL_CONFIG_NAME)

	var has_base_urls := false
	var base_urls: Array = []
	var close_menus: Array = []

	if global_config != null:
		if typeof(global_config) == TYPE_OBJECT and reflect_api != null:
			if bool(reflect_api.has(global_config, BASE_URL_PARAM)):
				has_base_urls = true
				base_urls = _copy_js_server_array(global_config[BASE_URL_PARAM], array_api, reflect_api, BASE_URL_PARAM)
			if bool(reflect_api.has(global_config, CLOSE_MENU_PARAM)):
				close_menus = _copy_js_string_array(global_config[CLOSE_MENU_PARAM], array_api, CLOSE_MENU_PARAM)
		else:
			push_warning("window.%s 必须是对象，已忽略" % GLOBAL_CONFIG_NAME)

	var window: Variant = JavaScriptBridge.get_interface("window")
	if window != null:
		var params: Variant = JavaScriptBridge.create_object("URLSearchParams", str(window.location.search))
		if params != null:
			if bool(params.has(BASE_URL_PARAM)):
				has_base_urls = true
				var encoded_servers := _copy_js_string_array(params.getAll(BASE_URL_PARAM), array_api, "query.%s" % BASE_URL_PARAM)
				base_urls = _parse_server_query_values(encoded_servers)
			if bool(params.has(CLOSE_MENU_PARAM)):
				close_menus = _copy_js_string_array(params.getAll(CLOSE_MENU_PARAM), array_api, "query.%s" % CLOSE_MENU_PARAM)

	configure(has_base_urls, base_urls, close_menus)


## 把页面对象数组复制成普通 Dictionary，断开和 JavaScript 活对象的关系。
static func _copy_js_server_array(value: Variant, array_api: Variant, reflect_api: Variant, label: String) -> Array:
	var copied: Array = []
	if value == null or array_api == null or reflect_api == null or not bool(array_api.isArray(value)):
		push_warning("Web 启动配置 %s 必须是对象数组，已忽略" % label)
		return copied
	var length := mini(maxi(int(value.length), 0), MAX_ARRAY_ITEMS)
	for index in range(length):
		var item: Variant = value[index]
		if item == null or typeof(item) != TYPE_OBJECT or not bool(reflect_api.has(item, "url")):
			continue
		var url_value: Variant = item["url"]
		var name_value: Variant = item["name"] if bool(reflect_api.has(item, "name")) else ""
		if typeof(url_value) == TYPE_STRING and typeof(name_value) == TYPE_STRING:
			copied.append({"url": str(url_value), "name": str(name_value)})
	return copied


## 查询参数没有对象类型，因此每个 BaseURL 值必须是一个 JSON 对象字符串。
## URLSearchParams 已经完成百分号解码，这里只负责 JSON 解码和形状过滤。
static func _parse_server_query_values(values: Array) -> Array:
	var parsed: Array = []
	for text in values:
		var item: Variant = JSON.parse_string(str(text))
		if typeof(item) == TYPE_DICTIONARY:
			parsed.append(item)
	return parsed


## 把浏览器那边的 JS 数组一项项抄成 GDScript 数组。
##
## 不能直接拿来用：JS 对象是跨引擎的活引用，页面随时可能改它，而且里面什么类型都可能有。
## 所以逐项检查、只留字符串，并且封顶 MAX_ARRAY_ITEMS——参数来自 URL，
## 谁都能往里塞一万项，不封顶就等于让页面决定我们分配多少内存。
static func _copy_js_string_array(value: Variant, array_api: Variant, label: String) -> Array:
	var copied: Array = []
	if value == null or array_api == null or not bool(array_api.isArray(value)):
		push_warning("Web 启动配置 %s 必须是数组，已忽略" % label)
		return copied
	var length := mini(maxi(int(value.length), 0), MAX_ARRAY_ITEMS)
	for index in range(length):
		var item: Variant = value[index]
		if typeof(item) == TYPE_STRING:
			copied.append(str(item))
	return copied


## 能不能当列表遍历。服务器对象来自普通 Array；PackedStringArray 只保留给
## 旧的字符串辅助调用，不代表 BaseURL 还接受字符串项。
static func _is_supported_array(values: Variant) -> bool:
	return typeof(values) == TYPE_ARRAY or typeof(values) == TYPE_PACKED_STRING_ARRAY


## 复制一份再交出去。内部那份 _servers 是静态状态，
## 直接返回的话调用方一改就把全局配置改了。
static func _copy_servers(values: Array[Dictionary]) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for server in values:
		copied.append(server.duplicate(true))
	return copied
