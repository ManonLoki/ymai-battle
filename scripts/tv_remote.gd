class_name TvRemote
extends RefCounted

## Android 电视遥控器支持。
##
## 引擎在 Android 上会把遥控器的方向键映射成 KEY_UP / KEY_DOWN、OK 键映射成 KEY_ENTER，
## 所以内置的 ui_up / ui_down / ui_accept 开箱就能上下切菜单、按下确认。缺的是两块：
## 一是 BACK 键（KEY_BACK）不在任何内置动作里，二是把自己报成手柄的遥控器按 A/B 时
## 没有对应动作（4.7 默认的 ui_accept / ui_cancel 只绑了键盘）。
## install() 把这些补进输入表，三个场景共用同一套判断。

const BACK_KEY := KEY_BACK
const CONFIRM_BUTTON := JOY_BUTTON_A
const CANCEL_BUTTON := JOY_BUTTON_B


## 电视上要的运行时环境：按键映射 + 屏幕常亮。
## 幂等，每个场景 _ready 里都可以直接调。
static func install() -> void:
	_add_key(&"ui_cancel", BACK_KEY)
	_add_joy(&"ui_accept", CONFIRM_BUTTON)
	_add_joy(&"ui_cancel", CANCEL_BUTTON)
	# 一场接一场自动打，中途没人碰遥控器，系统会自动熄屏/进屏保。
	# 工程设置里已经开了常亮，这里切场景时再确认一次，从后台回来也补得上。
	DisplayServer.screen_set_keep_on(true)


## 返回 / 退出：遥控器 BACK、手柄 B、键盘 Esc 都走这里。
static func is_back(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel")


## 会移动焦点或确认的输入。焦点掉了的时候用它兜一下。
static func is_navigation(event: InputEvent) -> bool:
	for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]:
		if event.is_action_pressed(action, true):
			return true
	return false


## 没有任何控件持有焦点时，把焦点还给 fallback。
## 电视上没有鼠标，焦点一旦丢了方向键就全哑了，所以每次导航前都补一次。
static func ensure_focus(fallback: Control) -> bool:
	if not is_instance_valid(fallback) or not fallback.is_inside_tree():
		return false
	var viewport := fallback.get_viewport()
	if viewport == null:
		return false
	var focused := viewport.gui_get_focus_owner()
	if focused != null and focused.is_visible_in_tree():
		return false
	fallback.grab_focus()
	return true


static func _add_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		var as_key := existing as InputEventKey
		if as_key != null and (as_key.keycode == key or as_key.physical_keycode == key):
			return
	var event := InputEventKey.new()
	event.keycode = key
	InputMap.action_add_event(action, event)


static func _add_joy(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		var as_button := existing as InputEventJoypadButton
		if as_button != null and as_button.button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
