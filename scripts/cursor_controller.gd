extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameCursor.boot()


func _input(event: InputEvent) -> void:
	GameCursor.handle_event(event)
