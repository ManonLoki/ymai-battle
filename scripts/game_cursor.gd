class_name GameCursor
extends RefCounted

## 自定义鼠标光标：平时是箭头，按下时换成按下态贴图。
##
## 用静态状态而不是节点，是因为换场景时不该重新加载贴图；
## 驱动它的是 autoload CursorController。

## 贴图路径。preload 之外还留一份路径常量，测试要按路径单独 load 一次做比对。
const ARROW_PATH := "res://assets/cursors/arrow.png"
const PRESSED_PATH := "res://assets/cursors/pressed.png"
## 光标热点：箭头尖在贴图的 (1, 1) 像素处。
const HOTSPOT := Vector2(1, 1)
## 滚轮的四个“按键”。滚一下不算按下，要在 handle_event 里直接放过。
const WHEEL_BUTTONS := [
	MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
]
# preload 保证贴图跟着脚本一起进包，不依赖运行时文件系统。
const _ARROW := preload("res://assets/cursors/arrow.png")
const _PRESSED := preload("res://assets/cursors/pressed.png")

## 缓存的两张贴图，第一次用到时才赋值。
static var arrow_texture: Texture2D
static var pressed_texture: Texture2D
## 当前实际生效的那张，测试靠它确认切换是否发生。
static var applied_texture: Texture2D


## 启动时装上默认的箭头光标。
static func boot() -> void:
	apply_for_pressed(false)


## 按下与否决定用哪张贴图，然后交给引擎替换系统光标。
static func apply_for_pressed(is_down: bool) -> void:
	_ensure_textures()
	applied_texture = pressed_texture if is_down else arrow_texture
	Input.set_custom_mouse_cursor(applied_texture, Input.CURSOR_ARROW, HOTSPOT)


## 只认鼠标按键事件；滚轮不算“按下”，否则滚一下光标就闪一次。
static func handle_event(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null:
		return
	if mouse.button_index in WHEEL_BUTTONS:
		return
	apply_for_pressed(mouse.is_pressed())


## 懒加载两张贴图，只在第一次真正用到时赋值。
static func _ensure_textures() -> void:
	if arrow_texture == null:
		arrow_texture = _ARROW
	if pressed_texture == null:
		pressed_texture = _PRESSED
