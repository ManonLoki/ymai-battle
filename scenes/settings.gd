extends Control

## 设置页：窗口模式 + 榜单服务器地址。
##
## 三个模式按钮和说明文字都预置在 settings.tscn，编辑器里能直接看到完整布局；
## 脚本只把它们绑定到 AppSettings 的模式值，并用 AppSettings 的文案刷新显示。
## 选中的那个用实心主按钮样式，一眼能看出当前是哪种。
##
## 服务器地址那一栏只管收和存，格式怎么算合法、存到哪儿全在 AppSettings；
## 填错了只在状态行报一句，绝不落盘——存进去的地址一定是能用的。

const MAIN_SCENE := "res://scenes/main.tscn"
## “保存 / 还原默认”这两个按钮的尺寸，比主按钮窄，腾地方给输入框。
const SERVER_BUTTON_MIN_SIZE := Vector2(140, 48)

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前选中的模式，按下按钮后立刻更新，用来刷新高亮。
var _mode := AppSettings.DEFAULT_MODE
## mode -> 对应的按钮，刷新高亮时要按模式找回按钮。
var _buttons: Dictionary = {}


func _ready() -> void:
	TvRemote.install()
	ThemeHelper.apply(self, 18)
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%Hint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_back_button(%BackButton)
	%BackButton.pressed.connect(_on_back_pressed)
	_mode = AppSettings.load_mode()
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
	AppSettings.save_mode(_mode)
	AppSettings.apply_mode(_mode)
	_refresh_highlight()


## 绑定场景里的服务器输入框、保存、还原默认和状态行。
## 说明里的格式示例直接取 AppSettings.SERVER_PLACEHOLDER，
## 免得界面上写一套、校验按另一套。
func _bind_server_controls() -> void:
	%ServerTitle.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%ServerHint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	%ServerHint.text = "填 %s 就改从这台服务器取榜单（接口路径不变）；留空保存或按“还原默认”，就用内置地址。" % AppSettings.SERVER_PLACEHOLDER
	ThemeHelper.style_line_edit(%ServerInput)
	%ServerInput.placeholder_text = AppSettings.SERVER_PLACEHOLDER
	# 电视遥控器按 OK 收完键盘会发 text_submitted，等同于按一下保存。
	%ServerInput.text_submitted.connect(_on_server_submitted)
	# 这一栏三个控件挤一行，按钮要比主按钮窄；保存是主按钮，还原默认走描边。
	for button in [%ServerSave, %ServerReset]:
		ThemeHelper.style_button(button, button == %ServerSave, SERVER_BUTTON_MIN_SIZE)
	%ServerSave.pressed.connect(_on_server_save_pressed)
	%ServerReset.pressed.connect(_on_server_reset_pressed)
	_refresh_server_view()


## 把输入框和状态行刷成存档里的现状。note 是这次操作要额外说的一句话。
func _refresh_server_view(note: String = "") -> void:
	# 存档只读这一次，后面两处都用这个值：usage_url() 不传参会自己再读一遍盘。
	var base := AppSettings.load_base_url()
	%ServerInput.text = base
	# 状态行报的是**真正会去请求的那个地址**，而不是输入框里的半成品，
	# 所以默认地址长什么样也不用在这里再写一遍。
	var line := "当前：%s · %s" % ["自定义" if not base.is_empty() else "默认", TokenUsageApi.usage_url(base)]
	_set_server_status(line if note.is_empty() else "%s　%s" % [note, line], ThemeHelper.MUTED)


## 状态行。报错走 DANGER，其余都是灰字。
func _set_server_status(text: String, color: Color) -> void:
	%ServerStatus.text = text
	%ServerStatus.add_theme_color_override("font_color", color)


## 输入框里按回车 / 遥控器 OK，等同于按保存。
func _on_server_submitted(_text: String) -> void:
	_on_server_save_pressed()


## 保存输入框里的地址：空输入当作还原默认，格式不对只提示不落盘。
## 合法与否只问 AppSettings.normalize_base_url 一次——它返回空串就是填错了。
func _on_server_save_pressed() -> void:
	var text := str(%ServerInput.text)
	if text.strip_edges().is_empty():
		_on_server_reset_pressed()
		return
	var base := AppSettings.normalize_base_url(text)
	if base.is_empty():
		_set_server_status("地址格式不对，应该是 %s" % AppSettings.SERVER_PLACEHOLDER, ThemeHelper.DANGER)
		return
	if not AppSettings.save_base_url(base):
		# 存档没写进去，下一次取榜单读到的还是旧值，所以这里不能报“已保存”。
		_set_server_status("存不下来，地址没能生效", ThemeHelper.DANGER)
		return
	_refresh_server_view("已保存。")


## 还原默认：清掉自定义地址，之后又走内置地址。
func _on_server_reset_pressed() -> void:
	if not AppSettings.clear_base_url():
		_set_server_status("存不下来，地址没能还原", ThemeHelper.DANGER)
		return
	_refresh_server_view("已还原默认。")


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)
