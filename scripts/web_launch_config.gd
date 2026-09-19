class_name WebLaunchConfig
extends Node

## Web 启动参数的唯一入口。
##
## 页面可以在 Godot 启动前提供：
##   window.YMAIBattleConfig = {
##     BaseURL: ["https://a.example", "https://b.example"],
##     CloseMenu: ["ranking", "settings", "quit"],
##   };
##
## URL 查询串里重复出现的同名键会逐字段覆盖全局对象，例如：
##   ?BaseURL=https%3A%2F%2Fa.example&BaseURL=https%3A%2F%2Fb.example
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
const MAX_BASE_URL_LENGTH := 2048

static var _has_base_urls_override := false
static var _base_urls: Array[String] = []
static var _closed_menus: Dictionary = {}


func _enter_tree() -> void:
	reset()
	if OS.has_feature("web"):
		_configure_from_browser()


## 测试和浏览器适配层共用的注入口。base_urls_present 必须单独传入，因为
## “完全没提供 BaseURL”要回落到本地列表，而“显式提供了空数组”不能回落。
static func configure(base_urls_present: bool, base_urls: Variant = [], close_menus: Variant = []) -> void:
	_has_base_urls_override = base_urls_present
	_base_urls = normalize_base_urls(base_urls)
	_closed_menus.clear()
	for menu_id in normalize_close_menus(close_menus):
		_closed_menus[menu_id] = true


## 清掉注入状态。headless 测试可以在每个用例前调用，避免用例之间串数据。
static func reset() -> void:
	_has_base_urls_override = false
	_base_urls.clear()
	_closed_menus.clear()


static func has_base_urls_override() -> bool:
	return _has_base_urls_override


## 当前设置页该展示的服务器候选。Web 明确提供 BaseURL（包括空数组）时，
## 它完全取代本地候选；否则继续使用 user://settings.json 里的列表。
static func active_base_urls(settings_path: String = AppSettings.SAVE_PATH) -> Array[String]:
	if _has_base_urls_override:
		return _copy_strings(_base_urls)
	return normalize_base_urls(AppSettings.load_base_urls(settings_path))


## 当前真正生效的基址。空串表示走 TokenUsageApi 的内置默认地址。
## 无论候选来自 Web 还是本地，持久化选择都必须仍在当前候选里；这样一次 Web
## 会话选过的注入地址，不会在下次未带参数启动时越过本地数据源继续生效。
static func effective_base_url(settings_path: String = AppSettings.SAVE_PATH) -> String:
	var selected := AppSettings.normalize_base_url(AppSettings.load_base_url(settings_path))
	if selected.is_empty():
		return ""
	return selected if active_base_urls(settings_path).has(selected) else ""


static func is_menu_closed(menu_id: String) -> bool:
	return _closed_menus.has(menu_id.strip_edges().to_lower())


## 纯归一化函数：只接受字符串容器，逐项复用 AppSettings 的 URL 规则，
## 丢弃空值/非法值并去重；第一次出现的顺序就是下拉框顺序。
static func normalize_base_urls(values: Variant) -> Array[String]:
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
		var text := str(value)
		if text.length() > MAX_BASE_URL_LENGTH:
			continue
		var base := AppSettings.normalize_base_url(text)
		if not base.is_empty() and not normalized.has(base):
			normalized.append(base)
	return normalized


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
				base_urls = _copy_js_string_array(global_config[BASE_URL_PARAM], array_api, BASE_URL_PARAM)
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
				base_urls = _copy_js_string_array(params.getAll(BASE_URL_PARAM), array_api, "query.%s" % BASE_URL_PARAM)
			if bool(params.has(CLOSE_MENU_PARAM)):
				close_menus = _copy_js_string_array(params.getAll(CLOSE_MENU_PARAM), array_api, "query.%s" % CLOSE_MENU_PARAM)

	configure(has_base_urls, base_urls, close_menus)


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


static func _is_supported_array(values: Variant) -> bool:
	return typeof(values) == TYPE_ARRAY or typeof(values) == TYPE_PACKED_STRING_ARRAY


static func _copy_strings(values: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	copied.assign(values)
	return copied
