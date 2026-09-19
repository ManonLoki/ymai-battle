class_name NodeUtil
extends RefCounted

## 场景树上的零碎操作。放这儿是因为好几个场景都要用，
## 各自手写一遍容易在 free / queue_free 上写岔。


## 清空一个容器的所有子节点。
##
## 默认走 free()：调用方下一句通常就要往里填新内容，必须立刻腾空，
## 用 queue_free 的话旧节点要等到帧末才消失，中间会和新节点挤在一起。
## 正在演出的子树（比如带着 await 的立绘）得传 deferred=true，
## 立刻释放会让还挂在等待点上的协程碰到已经没了的节点。
static func clear_children(parent: Node, deferred: bool = false) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		if deferred:
			child.queue_free()
		else:
			child.free()
