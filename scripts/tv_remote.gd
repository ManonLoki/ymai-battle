class_name TvRemote
extends RefCounted

## Android 电视遥控器支持。
##
## 引擎在 Android 上会把遥控器的方向键映射成 KEY_UP / KEY_DOWN、OK 键映射成 KEY_ENTER，
## 所以内置的 ui_up / ui_down / ui_accept 开箱就能上下切菜单、按下确认。缺的是两块：
## 一是 BACK 键（KEY_BACK）不在任何内置动作里，二是把自己报成手柄的遥控器按 A/B 时
## 没有对应动作（4.7 默认的 ui_accept / ui_cancel 只绑了键盘）。
## install() 把这些补进输入表，三个场景共用同一套判断。

## 遥控器的返回键。
const BACK_KEY := KEY_BACK
## 把自己报成手柄的遥控器上，A 是确认、B 是返回。
const CONFIRM_BUTTON := JOY_BUTTON_A
const CANCEL_BUTTON := JOY_BUTTON_B


## 电视上要的运行时环境：按键映射 + 屏幕常亮。
## 幂等，每个场景 _ready 里都可以直接调。
static func install() -> void:
	# BACK 键并进 ui_cancel，于是遥控器返回和键盘 Esc 走同一个动作。
	_add_key(&"ui_cancel", BACK_KEY)
	# 手柄式遥控器的 A / B 也并进同两个动作。
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
		# 第二个参数 allow_echo=true：按住不放的连发也算导航。
		if event.is_action_pressed(action, true):
			return true
	return false


## 接住并吃掉 BACK 事件，返回“这一下是不是返回键”。
##
## 吃事件走 viewport：accept_event() 是 Control 才有的，而对战场景是 Node2D，
## 以前两边各写各的，行为就分叉了。这里统一成对两种节点都成立的那一种。
static func consume_back(event: InputEvent, node: Node) -> bool:
	if not is_back(event):
		return false
	var viewport := node.get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	return true


## 没有任何控件持有焦点时，把焦点还给 fallback。
## 电视上没有鼠标，焦点一旦丢了方向键就全哑了，所以每次导航前都补一次。
static func ensure_focus(fallback: Control) -> bool:
	if not is_instance_valid(fallback) or not fallback.is_inside_tree():
		return false
	var viewport := fallback.get_viewport()
	if viewport == null:
		return false
	var focused := viewport.gui_get_focus_owner()
	# 已经有可见控件拿着焦点就什么都不做，别把玩家的选择抢走。
	if focused != null and focused.is_visible_in_tree():
		return false
	fallback.grab_focus()
	return true


## 往某个动作上补一个键盘事件。动作不存在就先建，已经绑过同一个键就跳过。
static func _add_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		var as_key := existing as InputEventKey
		# keycode 和 physical_keycode 都比一遍：不同键盘布局下引擎填的是不同那个。
		if as_key != null and (as_key.keycode == key or as_key.physical_keycode == key):
			return
	var event := InputEventKey.new()
	event.keycode = key
	InputMap.action_add_event(action, event)


## 同上，只是补的是手柄按键。
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
