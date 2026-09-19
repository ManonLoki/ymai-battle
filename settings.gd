extends Control

## 设置页：目前只有窗口模式一项。
##
## 三个模式按钮是按 WindowSettings.MODES 现生成的，加一种模式只要动那份清单。
## 选中的那个用实心主按钮样式，一眼能看出当前是哪种。

const MAIN_SCENE := "res://main.tscn"
## 模式按钮下面那行小字的字号。
const NOTE_FONT_PX := 14

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


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)
