class_name ServerRow
extends HBoxContainer

## 设置页「维护服务器」里的一行：地址输入框 + 保存 + 删除。
##
## 尺寸和按钮样式都在 server_row.tscn 里。这里只把两个按钮翻译成带地址的信号，
## 存盘和校验仍归设置页——这一行不认识 AppSettings，也不知道存在哪。

## 地址被改写。original 是这一行原本的地址，用来在存档里找回它。
signal save_requested(original: String, text: String)
## 这一行被删掉。
signal delete_requested(original: String)

## 这一行原本的地址。输入框里的文字会被玩家改掉，所以必须另记一份。
var _original := ""

@onready var address: LineEdit = $Address


func _ready() -> void:
	$SaveButton.pressed.connect(_emit_save)
	$DeleteButton.pressed.connect(_emit_delete)
	# 遥控器按 OK 收完键盘会发 text_submitted，等同于按“保存”。
	address.text_submitted.connect(func(_text: String) -> void: _emit_save())


## 填一行。先 add_child 再调它，@onready 才拿得到节点。
func bind(base: String) -> void:
	_original = base
	address.text = base


## 设置页收到通知后会立刻重建整张列表，也就是把这一行删掉——包括此刻正在发信号的
## 自己。释放时机归 NodeUtil.clear_children 兜着（帧末 queue_free），这里照常同步发。
func _emit_save() -> void:
	save_requested.emit(_original, address.text)


func _emit_delete() -> void:
	delete_requested.emit(_original)
