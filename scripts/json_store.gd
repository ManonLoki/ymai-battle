class_name JsonStore
extends RefCounted

## user:// 下小份 JSON 存档的读写。
##
## 存档读写只有一条策略：**任何一步不对都当作“没有存档”，绝不让游戏打不开**。
## 文件不在、权限不足、内容不是合法 JSON、解析出来不是字典，一律回落到空字典。
## 这条策略以前在战绩和设置里各写了一遍，改一处漏一处，所以收到这里。


## 读一份字典。读不出来就给空字典，调用方只需判断 is_empty 或直接取默认值。
static func read_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## 写一份字典。返回是否写成功；写不进去（磁盘满、只读目录）不该打断游戏，
## 所以只回报结果，要不要 push_warning 由调用方按数据的重要程度决定。
static func write_dict(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true
