class_name ServerRow
extends HBoxContainer

## 设置页「维护服务器」里的一行：可选名称 + 地址 + 保存 + 删除。
##
## 尺寸和按钮样式都在 server_row.tscn 里。这里只把两个按钮翻译成带地址的信号；
## 字段名和长度复用 AppSettings，存盘与业务校验仍归设置页。

## 名称或地址被改写。original 是这一行原本的地址，用来在存档里找回它。
signal save_requested(original: String, text: String, name: String)
## 这一行被删掉。
signal delete_requested(original: String)

## 这一行原本的地址。输入框里的文字会被玩家改掉，所以必须另记一份。
var _original := ""

@onready var address: LineEdit = $Address
@onready var server_name: LineEdit = $Name


## 把两个按钮和输入框的回车都接到自己的信号上。
## 在 _ready 里接而不是让设置页去接：这一行自己知道自己有哪几个控件，
## 外面只需要认识 save_requested / delete_requested 两个信号。
func _ready() -> void:
	$SaveButton.pressed.connect(_emit_save)
	$DeleteButton.pressed.connect(_emit_delete)
	# 遥控器按 OK 收完键盘会发 text_submitted，等同于按“保存”。
	address.text_submitted.connect(func(_text: String) -> void: _emit_save())
	server_name.text_submitted.connect(func(_text: String) -> void: address.grab_focus())
	server_name.max_length = AppSettings.SERVER_NAME_MAX_LENGTH
	server_name.placeholder_text = AppSettings.SERVER_NAME_PLACEHOLDER
	address.placeholder_text = AppSettings.SERVER_PLACEHOLDER


## 填一行。先 add_child 再调它，@onready 才拿得到节点。
func bind(server: Dictionary) -> void:
	_original = str(server.get(AppSettings.SERVER_URL_FIELD, ""))
	address.text = _original
	server_name.text = str(server.get(AppSettings.SERVER_NAME_FIELD, ""))


## 设置页收到通知后会立刻重建整张列表，也就是把这一行删掉——包括此刻正在发信号的
## 自己。释放时机归 NodeUtil.clear_children 兜着（帧末 queue_free），这里照常同步发。
func _emit_save() -> void:
	save_requested.emit(_original, address.text, server_name.text)


## 通知设置页把这一行代表的地址删掉。
func _emit_delete() -> void:
	delete_requested.emit(_original)
