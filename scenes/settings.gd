extends Control

## 设置页：窗口模式 + 榜单服务器列表。
##
## 三个模式按钮和说明文字都预置在 settings.tscn，编辑器里能直接看到完整布局；
## 脚本只把它们绑定到 AppSettings 的模式值，并用 AppSettings 的文案刷新显示。
## 选中的那个用实心主按钮样式，一眼能看出当前是哪种。
##
## 服务器那一栏把 Web 启动参数或本地存档解析出的列表摆进下拉框；选空项走内置
## 地址，选某一项就把它记作当前服务器。本地列表可以增删，Web 注入列表只读。

const MAIN_SCENE := "res://scenes/main.tscn"
## “增加 / 删除选中”按钮比主按钮窄，给地址和下拉框留空间。
const SERVER_BUTTON_MIN_SIZE := Vector2(140, 48)
const DEFAULT_SERVER_LABEL := "使用默认服务器"

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前选中的模式，按下按钮后立刻更新，用来刷新高亮。
var _mode := AppSettings.DEFAULT_MODE
## mode -> 对应的按钮，刷新高亮时要按模式找回按钮。
var _buttons: Dictionary = {}
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
	_refresh_highlight()
	_bind_server_controls()
	# 电视上没有鼠标，一进来就得有个控件拿着焦点；给当前选中的那个。
	var focused: Button = _buttons.get(_mode)
	if focused != null:
		focused.grab_focus()
	else:
		%BackButton.grab_focus()


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


## 把场景里的三个固定按钮及说明绑定到对应模式。文字仍以 AppSettings 为准，
## 避免场景预览文案和真正运行时的模式定义各维护一套。
func _bind_mode_controls() -> void:
	_buttons = {
		AppSettings.Mode.WINDOWED: %WindowedButton,
		AppSettings.Mode.MAXIMIZED: %MaximizedButton,
		AppSettings.Mode.FULLSCREEN: %FullscreenButton,
	}
	var descriptions := {
		AppSettings.Mode.WINDOWED: %WindowedDescription,
		AppSettings.Mode.MAXIMIZED: %MaximizedDescription,
		AppSettings.Mode.FULLSCREEN: %FullscreenDescription,
	}
	for mode in AppSettings.MODES:
		var button := _buttons.get(mode) as Button
		var description := descriptions.get(mode) as Label
		if button == null or description == null:
			push_warning("设置页缺少窗口模式控件：%s" % AppSettings.mode_display_name(mode))
			continue
		button.text = AppSettings.mode_display_name(mode)
		description.text = AppSettings.mode_description(mode)
		description.add_theme_color_override("font_color", ThemeHelper.MUTED)
		# bind 把模式带进回调，三个按钮共用同一个处理函数。
		button.pressed.connect(_on_mode_pressed.bind(mode))


## 选中的那个是实心主按钮，其余走描边。样式里带着最小尺寸，所以每次都要重套。
func _refresh_highlight() -> void:
	for mode in _buttons:
		ThemeHelper.style_button(_buttons[mode] as Button, mode == _mode)


func _on_mode_pressed(mode: int) -> void:
	_mode = AppSettings.sanitize_mode(mode)
	# 先存后应用：万一 apply 在某个平台上出岔子，选择也已经落盘了。
	AppSettings.save_mode(_mode, settings_path)
	AppSettings.apply_mode(_mode)
	_refresh_highlight()


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
	%ServerSelect.clear()
	%ServerSelect.add_item(DEFAULT_SERVER_LABEL)
	%ServerSelect.set_item_metadata(0, "")
	var selected_index := 0
	for raw_base in WebLaunchConfig.active_base_urls(settings_path):
		var base := str(raw_base)
		%ServerSelect.add_item(base)
		var index: int = %ServerSelect.item_count - 1
		%ServerSelect.set_item_metadata(index, base)
		%ServerSelect.set_item_tooltip(index, TokenUsageApi.usage_url(base))
		if base == selected:
			selected_index = index
	%ServerSelect.select(selected_index)
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
