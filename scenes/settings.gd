extends Control

## 设置页：窗口模式 + 音量 + 榜单服务器列表。
##
## 窗口模式用一个下拉框选择；选项按 AppSettings.MODES 的顺序生成，metadata
## 保存真实模式值，不把下拉索引当成模式。选择后立即保存、应用并刷新说明。
##
## 服务器下拉紧挨窗口模式下拉下方。本地列表的增删改都在「维护」面板里完成；
## Web 注入列表只读，不能改本地存档。

const MAIN_SCENE := "res://scenes/main.tscn"
## 维护面板里的一行（地址 + 保存 + 删除）。行长什么样归 server_row.tscn。
const SERVER_ROW := preload("res://scenes/server_row.tscn")
const DEFAULT_SERVER_LABEL := "使用默认服务器"

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前选中的模式，用来刷新说明。
var _mode := AppSettings.DEFAULT_MODE
## 两个滑块当前的线性音量。留着是为了推总线时不必再读一次存档——
## 值本来就在 value_changed 的参数里，另一路的值也只在进页面时读过一次。
var _music_linear := AppSettings.DEFAULT_MUSIC_VOLUME
var _sfx_linear := AppSettings.DEFAULT_SFX_VOLUME
## 测试可在节点入树前换成隔离存档；正式运行使用全局设置文件。
var settings_path: String = AppSettings.SAVE_PATH


## 三块设置各自绑好（窗口模式 / 音量 / 服务器），最后把焦点给第一个下拉框。
## 页面没有“保存”按钮——每一项都是改完立刻落盘并生效，见各自的 _on_*_changed。
func _ready() -> void:
	TvRemote.install()
	# 设置页也走共用曲；从战斗返回主菜单再进这里时，由主菜单切回金冠铃。
	MusicManager.play_lounge()
	# 配色、字体、按钮和输入框的样式全在 ui_theme.tres 和 settings.tscn 里；
	# 这里只接线和填数据。
	%BackButton.pressed.connect(_on_back_pressed)
	_mode = AppSettings.load_mode(settings_path)
	_bind_mode_controls()
	_bind_audio_controls()
	_bind_server_controls()
	# 电视上没有鼠标，一进来就让窗口模式下拉框拿焦点。
	%ModeSelect.grab_focus()


## 电视遥控器的返回键。
func _notification(what: int) -> void:
	# 电视遥控器 BACK 键。
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


## 返回键，以及焦点掉了之后的兜底。
## 兜底要分两种情况：维护面板开着时焦点该回到面板里的“关闭”，
## 不然方向键会把焦点带到面板背后那些看得见但点不到的控件上。
func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.consume_back(event, self):
		_on_back_pressed()
	elif TvRemote.is_navigation(event):
		# 焦点万一掉了，方向键会全哑，这里补回去。
		if %MaintainOverlay.visible:
			TvRemote.ensure_focus(%MaintainClose)
		else:
			TvRemote.ensure_focus(%BackButton)


## 用 AppSettings 的定义填充模式下拉框。metadata 存真实模式值，
## 以后即使模式枚举不再连续，选择也不会因索引错位。
func _bind_mode_controls() -> void:
	_fill_select(
		%ModeSelect,
		AppSettings.MODES,
		AppSettings.mode_display_name,
		AppSettings.mode_description,
		_mode,
	)
	_refresh_mode_description()
	%ModeSelect.item_selected.connect(_on_mode_selected)


## 按 values 重建一个下拉框：文字取 label_of，悬浮提示取 tooltip_of，
## metadata 存原值本身，并选中值等于 current 的那一项（找不到就落回第一项）。
##
## 「下拉索引不等于业务值」这条规矩只在这里写一遍，两个下拉都从这里过。
func _fill_select(
	select: OptionButton,
	values: Array,
	label_of: Callable,
	tooltip_of: Callable,
	current: Variant,
) -> void:
	select.clear()
	var selected_index := 0
	for value in values:
		select.add_item(str(label_of.call(value)))
		var index: int = select.item_count - 1
		select.set_item_metadata(index, value)
		select.set_item_tooltip(index, str(tooltip_of.call(value)))
		if value == current:
			selected_index = index
	select.select(selected_index)


## 下拉框底下那行小字，跟着当前选中的模式走。
func _refresh_mode_description() -> void:
	%ModeDescription.text = AppSettings.mode_description(_mode)


## 选了一个窗口模式。值从 metadata 里取而不是拿下拉索引当模式用。
func _on_mode_selected(index: int) -> void:
	_mode = AppSettings.sanitize_mode(int(%ModeSelect.get_item_metadata(index)))
	# 先存后应用：万一 apply 在某个平台上出岔子，选择也已经落盘了。
	AppSettings.save_mode(_mode, settings_path)
	AppSettings.apply_mode(_mode)
	_refresh_mode_description()


## 背景音乐 / 音效两个滑块。0–100，步进 5，电视上左右键就是调音量。
func _bind_audio_controls() -> void:
	_music_linear = AppSettings.load_music_volume(settings_path)
	_sfx_linear = AppSettings.load_sfx_volume(settings_path)
	%MusicSlider.set_value_no_signal(float(AppSettings.volume_percent(_music_linear)))
	%SfxSlider.set_value_no_signal(float(AppSettings.volume_percent(_sfx_linear)))
	_refresh_audio_labels()
	%MusicSlider.value_changed.connect(_on_music_volume_changed)
	%SfxSlider.value_changed.connect(_on_sfx_volume_changed)
	AppSettings.apply_mix(_music_linear, _sfx_linear)


## 两个滑块左边的文字。百分比直接读滑块当前值，不另外算一遍。
func _refresh_audio_labels() -> void:
	%MusicLabel.text = "背景音乐 %d%%" % int(%MusicSlider.value)
	%SfxLabel.text = "音效 %d%%" % int(%SfxSlider.value)


## 拖背景音乐滑块：存档、推总线、刷新文字。
## 滑块给的是 0–100，存档里存的是 0–1，除法在这里做。
func _on_music_volume_changed(value: float) -> void:
	_music_linear = value / 100.0
	AppSettings.save_music_volume(_music_linear, settings_path)
	AppSettings.apply_mix(_music_linear, _sfx_linear)
	_refresh_audio_labels()


## 拖音效滑块。和背景音乐那条一样，外加一声试听。
func _on_sfx_volume_changed(value: float) -> void:
	_sfx_linear = value / 100.0
	AppSettings.save_sfx_volume(_sfx_linear, settings_path)
	AppSettings.apply_mix(_music_linear, _sfx_linear)
	_refresh_audio_labels()
	# 音效滑块自带试听：调完立刻听到这一档是什么响度，不用退出去打一场。
	var preview := StrikeResult.new()
	preview.hit = true
	CombatSfx.play_event(preview)


## 绑定服务器下拉、维护面板和状态行。Web 参数提供列表时，列表是只读数据源；
## 没提供时才允许维护本地列表。
func _bind_server_controls() -> void:
	%ServerAddInput.placeholder_text = AppSettings.SERVER_PLACEHOLDER
	%ServerAddName.placeholder_text = AppSettings.SERVER_NAME_PLACEHOLDER
	%ServerAddName.max_length = AppSettings.SERVER_NAME_MAX_LENGTH
	%ServerSelect.item_selected.connect(_on_server_selected)
	%ServerMaintain.pressed.connect(_on_server_maintain_pressed)
	%MaintainClose.pressed.connect(_close_maintain_panel)
	# 电视遥控器按 OK 收完键盘会发 text_submitted，等同于按“添加”。
	%ServerAddInput.text_submitted.connect(_on_server_add_submitted)
	%ServerAddName.text_submitted.connect(_on_server_add_name_submitted)
	%ServerAdd.pressed.connect(_on_server_add_pressed)
	var injected := WebLaunchConfig.has_base_urls_override()
	%ServerAddRow.visible = not injected
	%ServerAddInput.editable = not injected
	%ServerAddName.editable = not injected
	%ServerAdd.disabled = injected
	%ServerMaintain.visible = not injected
	%ServerMaintain.disabled = injected
	%ServerHint.text = (
		(
			"服务器列表完全由网页启动参数提供；未选择或原选择失效时使用第一项。"
			if not WebLaunchConfig.active_base_urls(settings_path).is_empty()
			else "网页启动参数没有可用服务器，将使用内置地址。"
		)
		if injected
		else "从下拉框选择服务器；选择空项使用内置地址。点维护可增删改本地服务器。"
	)
	_refresh_server_view()


## 用当前数据源重建下拉，状态行只显示主机或「默认」，不把接口路径摊给用户。
func _refresh_server_view(note: String = "", is_error: bool = false) -> void:
	var selected := WebLaunchConfig.effective_base_url(settings_path)
	var active_bases := WebLaunchConfig.active_base_urls(settings_path)
	var bases: Array = []
	# 本地列表保留“内置地址”；外部列表非空时纯粹以它为准，不混入虚拟默认项。
	if not WebLaunchConfig.has_base_urls_override() or active_bases.is_empty():
		bases.append("")
	for raw_base in active_bases:
		bases.append(str(raw_base))
	_fill_select(
		%ServerSelect,
		bases,
		func(base: Variant) -> String: return DEFAULT_SERVER_LABEL if str(base).is_empty() else WebLaunchConfig.base_url_display_name(str(base), settings_path),
		func(base: Variant) -> String: return "使用内置服务器" if str(base).is_empty() else str(base),
		selected,
	)
	var line := "当前：%s" % WebLaunchConfig.base_url_display_name(selected, settings_path)
	_set_server_status(line if note.is_empty() else "%s　%s" % [note, line], is_error)
	if %MaintainOverlay.visible:
		_refresh_maintain_list()


## 状态行。报错标红；其余去掉覆盖，回到场景里的次要说明色。
func _set_server_status(text: String, is_error: bool) -> void:
	%ServerStatus.text = text
	%MaintainStatus.text = text
	if is_error:
		%ServerStatus.add_theme_color_override("font_color", ThemeHelper.DANGER)
		%MaintainStatus.add_theme_color_override("font_color", ThemeHelper.DANGER)
	else:
		%ServerStatus.remove_theme_color_override("font_color")
		%MaintainStatus.remove_theme_color_override("font_color")


## 下拉选择立即落盘。本地数据源的第一项是内置服务器；外部数据源没有虚拟项。
func _on_server_selected(index: int) -> void:
	var base := str(%ServerSelect.get_item_metadata(index))
	if not AppSettings.save_base_url(base, settings_path):
		_refresh_server_view("选择未能保存。", true)
		return
	_refresh_server_view("已切换。")


## 打开维护面板。列表被网页参数接管时这里直接不响应——
## 按钮那时本来就是隐藏且 disabled 的，这一道是防手动调用。
func _on_server_maintain_pressed() -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	%MaintainOverlay.visible = true
	_refresh_maintain_list()
	%ServerAddInput.grab_focus()


## 关掉维护面板，并把焦点还给下拉框——不还的话焦点会落在已经隐藏的控件上，
## 方向键就全哑了。
func _close_maintain_panel() -> void:
	%MaintainOverlay.visible = false
	%ServerSelect.grab_focus()


## 维护面板顶部的列表：每一行可改可删。
func _refresh_maintain_list() -> void:
	NodeUtil.clear_children(%ServerList)
	if WebLaunchConfig.has_base_urls_override():
		return
	var servers := AppSettings.load_servers(settings_path)
	%ServerListTitle.text = "已保存服务器（%d）" % servers.size()
	%EmptyServerList.visible = servers.is_empty()
	for server in servers:
		var row: ServerRow = SERVER_ROW.instantiate()
		# 先进树再 bind：行自己的 @onready 要先拿到子节点。
		%ServerList.add_child(row)
		row.bind(server)
		row.save_requested.connect(_on_server_row_save_pressed)
		row.delete_requested.connect(_on_server_row_delete_pressed)


## 某一行改了名称或地址。original 是原地址，用来在存档里找回它。
func _on_server_row_save_pressed(original: String, text: String, name: String) -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	if not AppSettings.replace_server(original, text, name, settings_path):
		_set_server_status("名称过长、地址格式不对或存不下来，服务器未修改", true)
		return
	_refresh_server_view("已修改。")


## 某一行被删掉。删的是地址本身而不是行号：列表随时可能因为别处的改动重建，
## 行号会串，地址不会。
func _on_server_row_delete_pressed(base: String) -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	if not AppSettings.remove_base_url(base, settings_path):
		_set_server_status("存不下来，服务器未删除", true)
		return
	_refresh_server_view("已删除。")


## 输入框回车 / 遥控器 OK 等同于按“添加”。
func _on_server_add_submitted(_text: String) -> void:
	_on_server_add_pressed()


## 名称是可选项；在名称框按确认时转到必填的 URL，不会误提交空地址。
func _on_server_add_name_submitted(_text: String) -> void:
	%ServerAddInput.grab_focus()


## 本地模式增加一台服务器并立即选中；Web 注入模式下即使手动调用也不改存档。
func _on_server_add_pressed() -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	var text := str(%ServerAddInput.text)
	var name := str(%ServerAddName.text)
	if AppSettings.normalize_base_url(text).is_empty():
		_set_server_status("地址格式不对，应该是 %s" % AppSettings.SERVER_PLACEHOLDER, true)
		return
	if not AppSettings.add_and_select_server(text, name, settings_path):
		_set_server_status("名称过长或存不下来，服务器未添加", true)
		return
	%ServerAddInput.clear()
	%ServerAddName.clear()
	_refresh_server_view("已添加并切换。")
	%ServerAddInput.grab_focus()


## 返回键的两级行为：维护面板开着就只关面板，关着才真的回主菜单。
func _on_back_pressed() -> void:
	if %MaintainOverlay.visible:
		_close_maintain_panel()
		return
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)
