class_name GameCursor
extends RefCounted

const ARROW_PATH := "res://assets/cursors/arrow.png"
const PRESSED_PATH := "res://assets/cursors/pressed.png"
const HOTSPOT := Vector2(1, 1)
const _ARROW := preload("res://assets/cursors/arrow.png")
const _PRESSED := preload("res://assets/cursors/pressed.png")

static var arrow_texture: Texture2D
static var pressed_texture: Texture2D
static var applied_texture: Texture2D


static func boot() -> void:
	apply_for_pressed(false)


static func apply_for_pressed(is_down: bool) -> void:
	_ensure_textures()
	applied_texture = pressed_texture if is_down else arrow_texture
	Input.set_custom_mouse_cursor(applied_texture, Input.CURSOR_ARROW, HOTSPOT)


static func handle_event(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse: InputEventMouseButton = event
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP \
			or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN \
			or mouse.button_index == MOUSE_BUTTON_WHEEL_LEFT \
			or mouse.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		return
	apply_for_pressed(mouse.is_pressed())


static func _ensure_textures() -> void:
	if arrow_texture == null:
		arrow_texture = _ARROW
	if pressed_texture == null:
		pressed_texture = _PRESSED
