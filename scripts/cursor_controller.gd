extends Node

## 全局光标控制器（project.godot 里注册为 autoload）。
##
## 换场景时 autoload 不会被卸载，所以光标贴图只在这里装一次，
## 三个场景都不用各自操心；具体贴图逻辑在 GameCursor 里。


func _ready() -> void:
	# 暂停时也要响应：光标是纯表现层，不该跟着游戏逻辑一起停。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 装上默认的箭头贴图。
	GameCursor.boot()


func _input(event: InputEvent) -> void:
	# 每个输入事件都过一遍，按下 / 抬起时切换箭头与按下态贴图。
	GameCursor.handle_event(event)
