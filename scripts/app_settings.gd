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

## 背景音乐默认拉满。两首 OGG 本身就混得很轻（满音量时总线峰值才 -10 dB 上下），
## 再往下压就只剩底噪了。
const DEFAULT_MUSIC_VOLUME := 1.0
## 音效默认 25%。五条 SE 是顶着满刻度做的短 WAV（单条峰值 -4 ~ -0.5 dB，
## 命中+回血叠在一起直接顶到 0 dB），不压下来会盖掉 BGM、连招时还发炸。
const DEFAULT_SFX_VOLUME := 0.25
const MUSIC_VOLUME_KEY := "music_volume"
const SFX_VOLUME_KEY := "sfx_volume"
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
## 滑到 0 时的静音，linear_to_db(0) 是 -inf，不能拿去 set_bus_volume_db。
const VOLUME_SILENCE_DB := -80.0
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
## 所有音频播放器的播放方式。Sample 播放只有 Web 的驱动实现了：CoreAudio / Android 上
## AudioServer 只 warning 一句就把这次播放丢掉，而 playing 仍是 true、位置停在 0，
## 也就是整台机器听不到声音。project.godot 的 default_playback_type.web 默认恰恰是
## Sample，所以不能省掉这行交给默认值——那样 Web 上 BGM 又会被 SE 抢走声部。
const PLAYBACK_TYPE := AudioServer.PLAYBACK_TYPE_STREAM


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

## 界面上的呈现顺序。设置页会按这个列表动态生成下拉选项。
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


## 启动时一次性套上窗口模式和音量。两项都幂等。
static func apply() -> void:
	apply_mode(load_mode())
	apply_audio()


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
# 用户可以保存多个 {url, name} 服务器项，另外用一个字段记住当前选中哪个 URL。
# 选中空值 = 还原默认；空值是界面上的虚拟选项，不放进候选列表。
#
# 只存**基址**，不存整条 URL：接口路径是代码的事，换服务器的人不该也不必知道。

## 存档里的当前选择。沿用旧字段名，旧版存档不需要改写就能继续用。
const BASE_URL_KEY := "server_base_url"
## 本地维护的候选服务器列表。新格式和 Web 启动参数统一为 {url, name}；读取时
## 仍兼容旧版字符串数组，下一次增删改就会按新格式写回。
const BASE_URLS_KEY := "server_base_urls"
const SERVER_URL_FIELD := "url"
const SERVER_NAME_FIELD := "name"

## 输入框里的灰字示例，同时也是这一项的格式说明，测试照着它对。
const SERVER_PLACEHOLDER := "https://host:port/"
const SERVER_NAME_PLACEHOLDER := "名称（可选）"
const SERVER_URL_MAX_LENGTH := 2048
const SERVER_NAME_MAX_LENGTH := 128

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


## 从合法基址中取浏览器语义下的 Host（主机名 + 可选端口），供没有自定义名称的
## 服务器选项显示。先走同一套 URL 归一化，避免显示层偷偷接受请求层会拒绝的地址。
static func base_url_host(text: String) -> String:
	var normalized := normalize_base_url(text)
	if normalized.is_empty() or _url_regex == null:
		return ""
	var found := _url_regex.search(normalized)
	if found == null:
		return ""
	var host := found.get_string(2)
	var port := found.get_string(3)
	return host if port.is_empty() else "%s:%d" % [host, int(port)]


## 把一项服务器整理为统一的 {url, name}。正常调用只接受对象；读取旧存档时可
## 显式允许字符串，把它迁移成 name 为空的对象。
static func normalize_server(value: Variant, allow_legacy_string: bool = false) -> Dictionary:
	var url_value: Variant
	var name_value: Variant = ""
	if typeof(value) == TYPE_DICTIONARY:
		var item: Dictionary = value
		url_value = item.get(SERVER_URL_FIELD, null)
		name_value = item.get(SERVER_NAME_FIELD, "")
	elif allow_legacy_string and typeof(value) == TYPE_STRING:
		url_value = value
	else:
		return {}
	if typeof(url_value) != TYPE_STRING or typeof(name_value) != TYPE_STRING:
		return {}
	var url_text := str(url_value)
	var name := str(name_value).strip_edges()
	if url_text.length() > SERVER_URL_MAX_LENGTH or name.length() > SERVER_NAME_MAX_LENGTH:
		return {}
	var base := normalize_base_url(url_text)
	if base.is_empty():
		return {}
	return {SERVER_URL_FIELD: base, SERVER_NAME_FIELD: name}


## 整理对象列表并按 URL 去重。名称和顺序都以第一次出现的项为准。
static func normalize_servers(values: Variant, allow_legacy_strings: bool = false) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if typeof(values) != TYPE_ARRAY and typeof(values) != TYPE_PACKED_STRING_ARRAY:
		return normalized
	var seen_urls: Dictionary = {}
	for value in values:
		var server := normalize_server(value, allow_legacy_strings)
		if server.is_empty():
			continue
		var base := str(server.get(SERVER_URL_FIELD, ""))
		if seen_urls.has(base):
			continue
		seen_urls[base] = true
		normalized.append(server)
	return normalized


## 一项服务器给人看的标题：有名称用名称，否则用 URL 的 Host。
static func server_display_name(server: Dictionary) -> String:
	var name := str(server.get(SERVER_NAME_FIELD, "")).strip_edges()
	return name if not name.is_empty() else base_url_host(str(server.get(SERVER_URL_FIELD, "")))


## 整理一份候选列表：过滤非法项和空值，规范化，再按首次出现的顺序去重。
## 参数故意收 Variant：JSON 读回来是普通 Array，界面则更适合传 PackedStringArray。
static func normalize_base_urls(urls: Variant) -> PackedStringArray:
	var normalized := PackedStringArray()
	if typeof(urls) != TYPE_ARRAY and typeof(urls) != TYPE_PACKED_STRING_ARRAY:
		return normalized
	for raw: Variant in urls:
		var base := normalize_base_url(str(raw))
		if not base.is_empty() and not normalized.has(base):
			normalized.append(base)
	return normalized


## 读出已保存的基址，没设过或存档坏了都给空串（= 用默认地址）。
static func load_base_url(path: String = SAVE_PATH) -> String:
	return normalize_base_url(str(JsonStore.read_dict(path).get(BASE_URL_KEY, "")))


## 读出本地候选对象。旧字符串数组和更旧的单一 server_base_url 都在这里迁移；
## 但只要列表字段存在（即使是空数组），它就是权威数据，不再用选择值补回去。
static func load_servers(path: String = SAVE_PATH) -> Array[Dictionary]:
	var data := JsonStore.read_dict(path)
	if data.has(BASE_URLS_KEY):
		return normalize_servers(data.get(BASE_URLS_KEY, []), true)
	var servers: Array[Dictionary] = []
	var legacy := normalize_base_url(str(data.get(BASE_URL_KEY, "")))
	if not legacy.is_empty():
		servers.append({SERVER_URL_FIELD: legacy, SERVER_NAME_FIELD: ""})
	return servers


## 只需要 URL 的旧调用仍可使用这个投影；权威数据结构是 load_servers()。
static func load_base_urls(path: String = SAVE_PATH) -> PackedStringArray:
	var urls := PackedStringArray()
	for server in load_servers(path):
		urls.append(str(server.get(SERVER_URL_FIELD, "")))
	return urls


## 存下基址。传空串或不合规的写法都会**清掉**这一项，也就是还原成默认地址。
## 校验在这里再做一遍：设置页之外的调用方（比如以后的命令行参数）也该走同一把尺子。
static func save_base_url(text: String, path: String = SAVE_PATH) -> bool:
	return JsonStore.patch_dict(path, {BASE_URL_KEY: normalize_base_url(text)})


## 一次存下统一对象列表和当前选择，避免只写成其中一项的中间状态。
## 选择不在整理后的列表里时自动回到默认；Web 注入列表的选择只应调 save_base_url。
static func save_servers(servers: Variant, selected: String = "", path: String = SAVE_PATH) -> bool:
	# allow_legacy_strings 只为兼容旧调用；落盘永远是对象数组。
	var normalized := normalize_servers(servers, true)
	var normalized_selected := normalize_base_url(selected)
	var urls := PackedStringArray()
	for server in normalized:
		urls.append(str(server.get(SERVER_URL_FIELD, "")))
	if not normalized_selected.is_empty() and not urls.has(normalized_selected):
		normalized_selected = ""
	var stored_servers: Array = []
	for server in normalized:
		stored_servers.append(server.duplicate(true))
	return JsonStore.patch_dict(path, {
		BASE_URLS_KEY: stored_servers,
		BASE_URL_KEY: normalized_selected,
	})


## 兼容只传 URL 的旧调用；写回时仍统一为 {url, name}。
static func save_base_urls(urls: Variant, selected: String = "", path: String = SAVE_PATH) -> bool:
	return save_servers(urls, selected, path)


## 把一项合法服务器加入本地列表并立即选中；重复 URL 会更新名称而不产生第二行。
## 列表和选择同一次落盘，不会破坏共用 settings.json 里的窗口模式。
static func add_and_select_server(url_text: String, name: String = "", path: String = SAVE_PATH) -> bool:
	var added := normalize_server({SERVER_URL_FIELD: url_text, SERVER_NAME_FIELD: name})
	if added.is_empty():
		return false
	var servers := load_servers(path)
	var base := str(added.get(SERVER_URL_FIELD, ""))
	var replaced := false
	for index in range(servers.size()):
		if str(servers[index].get(SERVER_URL_FIELD, "")) == base:
			servers[index] = added
			replaced = true
			break
	if not replaced:
		servers.append(added)
	return save_servers(servers, base, path)


## 兼容旧接口：没有名称就按空名称保存。
static func add_and_select_base_url(text: String, path: String = SAVE_PATH) -> bool:
	return add_and_select_server(text, "", path)


## 界面层的简写别名：“添加”的产品语义就是添加并选中。
static func add_base_url(text: String, path: String = SAVE_PATH) -> bool:
	return add_and_select_base_url(text, path)


## 把已保存的一项改成新的 {url, name} 并落盘。
## 旧地址不在列表里或新地址不合法都失败；改的是当前选择时选择跟着走。
## 新地址已经在列表里则删掉旧的、选中既有项，避免出现重复候选。
static func replace_server(old_text: String, new_text: String, name: String = "", path: String = SAVE_PATH) -> bool:
	var old_base := normalize_base_url(old_text)
	var replacement := normalize_server({SERVER_URL_FIELD: new_text, SERVER_NAME_FIELD: name})
	if old_base.is_empty() or replacement.is_empty():
		return false
	var new_base := str(replacement.get(SERVER_URL_FIELD, ""))
	var servers := load_servers(path)
	var index := -1
	var duplicate_index := -1
	for candidate_index in range(servers.size()):
		var candidate_url := str(servers[candidate_index].get(SERVER_URL_FIELD, ""))
		if candidate_url == old_base:
			index = candidate_index
		if candidate_url == new_base:
			duplicate_index = candidate_index
	if index < 0:
		return false
	if duplicate_index >= 0 and duplicate_index != index:
		servers[duplicate_index] = replacement
		servers.remove_at(index)
	else:
		servers[index] = replacement
	var selected := load_base_url(path)
	if selected == old_base:
		selected = new_base
	return save_servers(servers, selected, path)


## 兼容旧接口：保留原来的名称，只改 URL。
static func replace_base_url(old_text: String, new_text: String, path: String = SAVE_PATH) -> bool:
	var name := ""
	var old_base := normalize_base_url(old_text)
	for server in load_servers(path):
		if str(server.get(SERVER_URL_FIELD, "")) == old_base:
			name = str(server.get(SERVER_NAME_FIELD, ""))
			break
	return replace_server(old_text, new_text, name, path)


## 从本地列表删除指定基址。删的是当前选择才回到默认；删除其他候选时保留选择。
## 不存在的地址视为幂等成功，也不会意外清空当前选择。
static func remove_base_url(text: String, path: String = SAVE_PATH) -> bool:
	var base := normalize_base_url(text)
	if base.is_empty():
		return false
	var servers := load_servers(path)
	var index := -1
	for candidate_index in range(servers.size()):
		if str(servers[candidate_index].get(SERVER_URL_FIELD, "")) == base:
			index = candidate_index
			break
	if index < 0:
		return true
	servers.remove_at(index)
	var selected := load_base_url(path)
	if selected == base:
		selected = ""
	return save_servers(servers, selected, path)


## 还原默认：把自定义地址清掉，之后取榜单又走 TokenUsageApi 里的默认地址。
static func clear_base_url(path: String = SAVE_PATH) -> bool:
	return save_base_url("", path)


# ============================== 音量 ==============================
#
# 线性 0–1 存档，真正推到 AudioServer 时转 dB。0 是静音，1 是总线 0 dB。
# 默认 BGM 明显高于 SE：差的不是重要程度，是两边素材的响度——
# 循环 OGG 混得轻，五条命中 WAV 本来就顶着满刻度。


## 把外面来的值夹回 0–1。存档可能被手改坏，NaN / 无穷会一路传到 AudioServer
## 把总线彻底搞哑，所以先在这里挡掉——每一条读写路径都要先过它。
static func sanitize_volume(value: float) -> float:
	if is_nan(value) or is_inf(value):
		return VOLUME_MIN
	return clampf(value, VOLUME_MIN, VOLUME_MAX)


## 线性音量转 dB，推总线之前的最后一步。
## 0 不能直接换算（数学上是 -inf，AudioServer 和 Tween 都处理不了），
## 所以贴近 0 的一律返回约定的“静音 dB”。
static func volume_to_db(linear: float) -> float:
	var value := sanitize_volume(linear)
	if value <= 0.0001:
		return VOLUME_SILENCE_DB
	return linear_to_db(value)


## 线性音量转界面上显示的百分比。滑块是 0–100 的整数刻度，存档是 0–1 的小数，
## 换算只在这里做一次。
static func volume_percent(linear: float) -> int:
	return int(round(sanitize_volume(linear) * 100.0))


## 从一份已经读出来的存档里取一个音量。收 Dictionary 而不是 path，
## apply_audio 才能两个音量共用一次 read_dict。
static func _volume_from(data: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = data.get(key, fallback)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return sanitize_volume(fallback)
	return sanitize_volume(float(raw))


## 下面四个是两个音量各自的读写。写走 patch_dict（只改自己那个键，
## 不会把同一份存档里的窗口模式、服务器地址顺手冲掉）。
## 设置页开着的时候一次只动一个滑块，所以单独读单独写；
## 启动时要两个一起用的场合走 apply_audio，那边只读一次盘。
static func load_music_volume(path: String = SAVE_PATH) -> float:
	return _volume_from(JsonStore.read_dict(path), MUSIC_VOLUME_KEY, DEFAULT_MUSIC_VOLUME)


static func load_sfx_volume(path: String = SAVE_PATH) -> float:
	return _volume_from(JsonStore.read_dict(path), SFX_VOLUME_KEY, DEFAULT_SFX_VOLUME)


static func save_music_volume(value: float, path: String = SAVE_PATH) -> bool:
	return JsonStore.patch_dict(path, {MUSIC_VOLUME_KEY: sanitize_volume(value)})


static func save_sfx_volume(value: float, path: String = SAVE_PATH) -> bool:
	return JsonStore.patch_dict(path, {SFX_VOLUME_KEY: sanitize_volume(value)})


## 把存档里的混音推到两条总线。整份存档只读一次，不是一个音量读一遍。
static func apply_audio(path: String = SAVE_PATH) -> void:
	var data := JsonStore.read_dict(path)
	apply_mix(
		_volume_from(data, MUSIC_VOLUME_KEY, DEFAULT_MUSIC_VOLUME),
		_volume_from(data, SFX_VOLUME_KEY, DEFAULT_SFX_VOLUME),
	)


## 把两个线性音量直接推到总线，不碰存档。滑块调整走这条：
## 值就在手上，没理由存完再从盘上读回来。
static func apply_mix(music: float, sfx: float) -> void:
	_set_bus_volume(MUSIC_BUS, music)
	_set_bus_volume(SFX_BUS, sfx)


## 把一条总线的音量设成给定的线性值。
## 总线是 default_bus_layout.tres 里配的，名字对不上就直接放弃——
## headless 测试和某些平台上总线可能压根没建起来，这时候静默跳过比报错合理。
static func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, volume_to_db(linear))
