extends Control

## 设置页：窗口模式 + 榜单服务器列表。
##
## 窗口模式用一个下拉框选择；选项按 AppSettings.MODES 的顺序生成，metadata
## 保存真实模式值，不把下拉索引当成模式。选择后立即保存、应用并刷新说明。
##
## 服务器那一栏把 Web 启动参数或本地存档解析出的列表摆进下拉框；选空项走内置
## 地址，选某一项就把它记作当前服务器。本地列表可以增删，Web 注入列表只读。

const MAIN_SCENE := "res://scenes/main.tscn"
## “增加 / 删除选中”按钮比主按钮窄，给地址和下拉框留空间。
const SERVER_BUTTON_MIN_SIZE := Vector2(140, 48)
const DEFAULT_SERVER_LABEL := "使用默认服务器"

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前选中的模式，用来刷新说明。
var _mode := AppSettings.DEFAULT_MODE
## 测试可在节点入树前换成隔离存档；正式运行使用全局设置文件。
var settings_path: String = AppSettings.SAVE_PATH


func _ready() -> void:
	TvRemote.install()
	ThemeHelper.apply(self, 18)
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%Hint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_back_button(%BackButton)
	%BackButton.pressed.connect(_on_back_pressed)
	_mode = AppSettings.load_mode(settings_path)
	_bind_mode_controls()
	_bind_server_controls()
	# 电视上没有鼠标，一进来就让窗口模式下拉框拿焦点。
	%ModeSelect.grab_focus()


func _notification(what: int) -> void:
	# 电视遥控器 BACK 键。
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.consume_back(event, self):
		_on_back_pressed()
	elif TvRemote.is_navigation(event):
		# 焦点万一掉了，方向键会全哑，这里补回去。
		TvRemote.ensure_focus(%BackButton)


## 用 AppSettings 的定义填充模式下拉框。metadata 存真实模式值，
## 以后即使模式枚举不再连续，选择也不会因索引错位。
func _bind_mode_controls() -> void:
	ThemeHelper.style_button(%ModeSelect, true)
	%ModeDescription.add_theme_color_override("font_color", ThemeHelper.MUTED)
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


func _refresh_mode_description() -> void:
	%ModeDescription.text = AppSettings.mode_description(_mode)


func _on_mode_selected(index: int) -> void:
	if index < 0 or index >= %ModeSelect.item_count:
		return
	_mode = AppSettings.sanitize_mode(int(%ModeSelect.get_item_metadata(index)))
	# 先存后应用：万一 apply 在某个平台上出岔子，选择也已经落盘了。
	AppSettings.save_mode(_mode, settings_path)
	AppSettings.apply_mode(_mode)
	_refresh_mode_description()


## 绑定服务器下拉、增加、删除和状态行。Web 参数提供列表时，列表是只读数据源；
## 没提供时才允许维护本地列表。
func _bind_server_controls() -> void:
	%ServerTitle.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%ServerHint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_button(%ServerSelect, true)
	ThemeHelper.style_button(%ServerDelete, false, SERVER_BUTTON_MIN_SIZE)
	ThemeHelper.style_line_edit(%ServerAddInput)
	ThemeHelper.style_button(%ServerAdd, false, SERVER_BUTTON_MIN_SIZE)
	%ServerAddInput.placeholder_text = AppSettings.SERVER_PLACEHOLDER
	%ServerSelect.item_selected.connect(_on_server_selected)
	# 电视遥控器按 OK 收完键盘会发 text_submitted，等同于按“增加”。
	%ServerAddInput.text_submitted.connect(_on_server_add_submitted)
	%ServerAdd.pressed.connect(_on_server_add_pressed)
	%ServerDelete.pressed.connect(_on_server_delete_pressed)
	var injected := WebLaunchConfig.has_base_urls_override()
	%ServerAddRow.visible = not injected
	%ServerAddInput.editable = not injected
	%ServerAdd.disabled = injected
	%ServerDelete.visible = not injected
	%ServerHint.text = (
		"服务器列表由网页启动参数提供；选择空项使用内置地址。"
		if injected
		else "从下拉框选择服务器；选择空项使用内置地址。输入 %s 可增加本地服务器。" % AppSettings.SERVER_PLACEHOLDER
	)
	_refresh_server_view()


## 用当前数据源重建下拉，并把状态行刷成真正会访问的 endpoint。
func _refresh_server_view(note: String = "", color: Color = ThemeHelper.MUTED) -> void:
	var selected := WebLaunchConfig.effective_base_url(settings_path)
	# 空串那一项代表“用内置地址”，和真实地址一样把值存进 metadata。
	var bases: Array = [""]
	for raw_base in WebLaunchConfig.active_base_urls(settings_path):
		bases.append(str(raw_base))
	_fill_select(
		%ServerSelect,
		bases,
		func(base: Variant) -> String: return DEFAULT_SERVER_LABEL if str(base).is_empty() else str(base),
		func(base: Variant) -> String: return TokenUsageApi.usage_url(str(base)),
		selected,
	)
	%ServerDelete.disabled = WebLaunchConfig.has_base_urls_override() or selected.is_empty()
	var label := "默认" if selected.is_empty() else selected
	var line := "当前：%s · %s" % [label, TokenUsageApi.usage_url(selected)]
	_set_server_status(line if note.is_empty() else "%s　%s" % [note, line], color)


## 状态行。报错走 DANGER，其余都是灰字。
func _set_server_status(text: String, color: Color) -> void:
	%ServerStatus.text = text
	%ServerStatus.add_theme_color_override("font_color", color)


## 下拉选择立即落盘；选第一项就是清空覆盖、恢复内置服务器。
func _on_server_selected(index: int) -> void:
	var base := str(%ServerSelect.get_item_metadata(index))
	if not AppSettings.save_base_url(base, settings_path):
		_refresh_server_view("选择未能保存。", ThemeHelper.DANGER)
		return
	_refresh_server_view("已切换。")


## 输入框回车 / 遥控器 OK 等同于按“增加”。
func _on_server_add_submitted(_text: String) -> void:
	_on_server_add_pressed()


## 本地模式增加一台服务器并立即选中；Web 注入模式下即使手动调用也不改存档。
func _on_server_add_pressed() -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	var text := str(%ServerAddInput.text)
	if AppSettings.normalize_base_url(text).is_empty():
		_set_server_status("地址格式不对，应该是 %s" % AppSettings.SERVER_PLACEHOLDER, ThemeHelper.DANGER)
		return
	if not AppSettings.add_and_select_base_url(text, settings_path):
		_set_server_status("存不下来，服务器未增加", ThemeHelper.DANGER)
		return
	%ServerAddInput.clear()
	_refresh_server_view("已增加并切换。")


## 删除本地当前项；AppSettings 同时清空选择，因此请求立即回到默认地址。
func _on_server_delete_pressed() -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	var base := WebLaunchConfig.effective_base_url(settings_path)
	if base.is_empty():
		return
	if not AppSettings.remove_base_url(base, settings_path):
		_set_server_status("存不下来，服务器未删除", ThemeHelper.DANGER)
		return
	_refresh_server_view("已删除，改用默认服务器。")
	%ServerSelect.grab_focus()


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)
