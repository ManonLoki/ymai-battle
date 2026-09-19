class_name NodeUtil
extends RefCounted

## 场景树上的零碎操作。放这儿是因为好几个场景都要用，
## 各自手写一遍容易在 free / queue_free 上写岔。


## 清空一个容器里运行时生成的子节点。
##
## 走 free() 而不是 queue_free()：调用方下一句通常就要往里填新内容，必须立刻腾空，
## 用 queue_free 的话旧节点要等到帧末才消失，中间会和新节点挤在一起。
##
## keep_first 是场景里预置的固定子节点个数（表头、空榜提示这类），
## 它们永远排在最前面，不参与清理。
static func clear_children(parent: Node, keep_first: int = 0) -> void:
	var children := parent.get_children()
	for i in range(keep_first, children.size()):
		var child := children[i]
		parent.remove_child(child)
		child.free()
