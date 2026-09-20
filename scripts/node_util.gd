class_name NodeUtil
extends RefCounted

## 场景树上的零碎操作。放这儿是因为好几个场景都要用，
## 各自手写一遍容易在 free / queue_free 上写岔。


## 清空一个容器里运行时生成的子节点。
##
## 「立刻腾空」靠的是 remove_child：调用方下一句通常就要往里填新内容，
## 摘下来之后旧节点已经不在容器里，不会和新节点挤在一起。
##
## 真正的释放走 queue_free 而不是 free：这些行上往往挂着按钮和输入框，
## 重建列表的调用链常常就是从某一行的按钮点下去的（比如设置页里删掉一台服务器）。
## 控件在自己发信号期间是锁住的，当场 free 会被引擎拒绝
## （“Attempted to free a locked object”），行删不掉反而会留在内存里。
## 延到帧末释放就没有这个问题，而容器早在上一句就空了。
##
## keep_first 是场景里预置的固定子节点个数（表头、空榜提示这类），
## 它们永远排在最前面，不参与清理。
static func clear_children(parent: Node, keep_first: int = 0) -> void:
	var children := parent.get_children()
	for i in range(keep_first, children.size()):
		var child := children[i]
		# 先排队再摘：节点还在树上时 queue_free 能直接拿到 SceneTree。
		child.queue_free()
		parent.remove_child(child)
