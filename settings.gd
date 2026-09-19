extends Control

## 设置页：窗口模式 + 榜单服务器地址。
##
## 三个模式按钮是按 WindowSettings.MODES 现生成的，加一种模式只要动那份清单。
## 选中的那个用实心主按钮样式，一眼能看出当前是哪种。
##
## 服务器地址那一栏只管收和存，格式怎么算合法、存到哪儿全在 ServerSettings；
## 填错了只在状态行报一句，绝不落盘——存进去的地址一定是能用的。

const MAIN_SCENE := "res://main.tscn"
## 模式按钮下面那行小字的字号。
const NOTE_FONT_PX := 14
## 服务器那一栏的说明和状态行的字号，和模式说明一样小一号。
const SERVER_NOTE_FONT_PX := 14
## “保存 / 还原默认”这两个按钮的尺寸，比主按钮窄，腾地方给输入框。
const SERVER_BUTTON_MIN_SIZE := Vector2(140, 48)

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前选中的模式，按下按钮后立刻更新，用来刷新高亮。
var _mode := WindowSettings.DEFAULT_MODE
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
	_mode = WindowSettings.load_mode()
	_build_mode_buttons()
	_refresh_highlight()
	_build_server_section()
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


## 按 WindowSettings.MODES 的顺序摆一排按钮，每个下面跟一行说明。
func _build_mode_buttons() -> void:
	NodeUtil.clear_children(%ModeList)
	_buttons.clear()
	for mode in WindowSettings.MODES:
		var button := Button.new()
		button.text = WindowSettings.display_name(mode)
		# bind 把模式带进回调，三个按钮共用同一个处理函数。
		button.pressed.connect(_on_mode_pressed.bind(mode))
		%ModeList.add_child(button)
		_buttons[mode] = button
		%ModeList.add_child(ThemeHelper.make_label(WindowSettings.description(mode), ThemeHelper.MUTED, NOTE_FONT_PX))


## 选中的那个是实心主按钮，其余走描边。样式里带着最小尺寸，所以每次都要重套。
func _refresh_highlight() -> void:
	for mode in _buttons:
		ThemeHelper.style_button(_buttons[mode] as Button, mode == _mode)


func _on_mode_pressed(mode: int) -> void:
	_mode = WindowSettings.sanitize(mode)
	# 先存后应用：万一 apply 在某个平台上出岔子，选择也已经落盘了。
	WindowSettings.save_mode(_mode)
	WindowSettings.apply(_mode)
	_refresh_highlight()


## 服务器那一栏：输入框 + 保存 + 还原默认 + 一行状态。
## 说明里的格式示例直接取 ServerSettings.PLACEHOLDER，
## 免得界面上写一套、校验按另一套。
func _build_server_section() -> void:
	%ServerTitle.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%ServerHint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	%ServerHint.add_theme_font_size_override("font_size", SERVER_NOTE_FONT_PX)
	%ServerHint.text = "填 %s 就改从这台服务器取榜单（接口路径不变）；留空保存或按“还原默认”，就用内置地址。" % ServerSettings.PLACEHOLDER
	%ServerStatus.add_theme_font_size_override("font_size", SERVER_NOTE_FONT_PX)
	ThemeHelper.style_line_edit(%ServerInput)
	%ServerInput.placeholder_text = ServerSettings.PLACEHOLDER
	# 电视遥控器按 OK 收完键盘会发 text_submitted，等同于按一下保存。
	%ServerInput.text_submitted.connect(_on_server_submitted)
	for button in [%ServerSave, %ServerReset]:
		# style_button 会盖上主按钮的最小尺寸，这一栏三个控件挤一行，随后改窄。
		ThemeHelper.style_button(button, button == %ServerSave)
		button.custom_minimum_size = SERVER_BUTTON_MIN_SIZE
	%ServerSave.pressed.connect(_on_server_save_pressed)
	%ServerReset.pressed.connect(_on_server_reset_pressed)
	_refresh_server_view()


## 把输入框和状态行刷成存档里的现状。note 是这次操作要额外说的一句话。
func _refresh_server_view(note: String = "") -> void:
	var base := ServerSettings.load_base_url()
	%ServerInput.text = base
	# 状态行报的是**真正会去请求的那个地址**，而不是输入框里的半成品，
	# 所以默认地址长什么样也不用在这里再写一遍。
	var line := "当前：%s · %s" % ["自定义" if not base.is_empty() else "默认", TokenUsageApi.usage_url()]
	_set_server_status(line if note.is_empty() else "%s　%s" % [note, line], ThemeHelper.MUTED)


## 状态行。报错走 DANGER，其余都是灰字。
func _set_server_status(text: String, color: Color) -> void:
	%ServerStatus.text = text
	%ServerStatus.add_theme_color_override("font_color", color)


## 输入框里按回车 / 遥控器 OK，等同于按保存。
func _on_server_submitted(_text: String) -> void:
	_on_server_save_pressed()


## 保存输入框里的地址：空输入当作还原默认，格式不对只提示不落盘。
func _on_server_save_pressed() -> void:
	var text := str(%ServerInput.text)
	if text.strip_edges().is_empty():
		_on_server_reset_pressed()
		return
	if not ServerSettings.is_valid(text):
		_set_server_status("地址格式不对，应该是 %s" % ServerSettings.PLACEHOLDER, ThemeHelper.DANGER)
		return
	if not ServerSettings.save_base_url(text):
		# 存档没写进去，下一次取榜单读到的还是旧值，所以这里不能报“已保存”。
		_set_server_status("存不下来，地址没能生效", ThemeHelper.DANGER)
		return
	_refresh_server_view("已保存。")


## 还原默认：清掉自定义地址，之后又走内置地址。
func _on_server_reset_pressed() -> void:
	if not ServerSettings.clear():
		_set_server_status("存不下来，地址没能还原", ThemeHelper.DANGER)
		return
	_refresh_server_view("已还原默认。")


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)
