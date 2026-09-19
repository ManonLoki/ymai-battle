class_name MenuParallax
extends Node2D

## 主菜单的像素风滚动背景：远、中、近三层各自以不同速度向左滚，形成视差。
##
## 每层都放两张首尾相接的同图，滚过一整张宽度就把位置绕回去，
## 于是永远看不到接缝，也不需要额外的图。三层和六张图都预置在 main.tscn，
## 这个脚本只绑定、排版和滚动它们，编辑器里可以直接检查完整节点树。

## main.tscn 给三层配置的贴图依次是：
## res://assets/backgrounds/far.png、res://assets/backgrounds/mid.png、
## res://assets/backgrounds/near.png。
## 三层容器节点的名字，也是从场景树绑定它们的唯一清单。
const LAYER_NAMES: Array[String] = ["FarLayer", "MidLayer", "NearLayer"]
## 三层的滚动速度（像素/秒）。越近越快，视差就是这么来的。
const LAYER_SPEEDS: Array[float] = [22.0, 58.0, 128.0]

## 三层的容器节点，每个下面挂两张首尾相接的 Sprite2D。
var layers: Array[Node2D] = []
## 每层滚过多少像素算一个循环，等于缩放后的贴图宽度。
var wrap_widths: Array[float] = []
## 每层的实际速度，和 layers 一一对应。
var speeds: Array[float] = []


func _ready() -> void:
	_bind_layers()
	_layout_layers()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_layout_layers):
		viewport.size_changed.connect(_layout_layers)


func _process(delta: float) -> void:
	advance_parallax(delta)


## 按 delta 推进一帧。单独拆出来是为了让测试能手动喂一个固定 delta。
func advance_parallax(delta: float) -> void:
	for i in layers.size():
		var node := layers[i]
		var width := wrap_widths[i]
		# 贴图宽度为 0 的层没法取模，直接跳过。
		if width <= 0.0:
			continue
		# 取模一步到位地绕回循环内，不用 while 一圈圈减。
		var x := fmod(node.position.x - speeds[i] * delta, width)
		# fmod 的结果和被除数同号，这里统一归到 (-width, 0]，
		# 保证第二张图始终顶在右边把空隙填满。
		node.position.x = x - width if x > 0.0 else x


## 从场景树绑定预置的三层。缺节点时保留其余层可用，并给编辑器清楚的告警。
func _bind_layers() -> void:
	layers.clear()
	wrap_widths.clear()
	speeds.clear()
	for i in LAYER_NAMES.size():
		var holder := get_node_or_null(NodePath(LAYER_NAMES[i])) as Node2D
		if holder == null:
			push_warning("主菜单视差层缺少节点：%s" % LAYER_NAMES[i])
			continue
		layers.append(holder)
		wrap_widths.append(0.0)
		speeds.append(LAYER_SPEEDS[i])


## 按视口高度等比缩放场景里的六张图，并让每层两张图首尾相接。
func _layout_layers() -> void:
	# 拿不到视口时（比如纯逻辑测试里）按设计分辨率的高度算。
	var view_h := 720.0
	var viewport := get_viewport()
	if viewport != null:
		var visible := viewport.get_visible_rect().size
		if visible.y > 1.0:
			view_h = visible.y
	for i in layers.size():
		wrap_widths[i] = _layout_layer(layers[i], view_h)


## 返回这一层缩放后的单图宽度；只有场景里已有的 Sprite2D 才参与排版。
func _layout_layer(holder: Node2D, view_h: float) -> float:
	var sprites: Array[Sprite2D] = []
	for child in holder.get_children():
		if child is Sprite2D:
			sprites.append(child as Sprite2D)
	if sprites.size() < 2:
		push_warning("主菜单视差层 %s 需要两张带贴图的 Sprite2D" % holder.name)
		return 0.0
	for sprite in sprites:
		if sprite.texture == null:
			push_warning("主菜单视差层 %s 的每张 Sprite2D 都必须带贴图" % holder.name)
			return 0.0
	var texture := sprites[0].texture
	var tex_h := float(texture.get_height())
	var scale_f := view_h / tex_h if tex_h > 0.0 else 1.0
	var wrap := float(texture.get_width()) * scale_f
	for copy in sprites.size():
		var sprite := sprites[copy]
		# 左上角对齐，position 直接就是贴图左边缘，接缝计算才简单。
		sprite.centered = false
		# 像素画必须用最近邻，否则放大后糊成一片。
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(scale_f, scale_f)
		sprite.position = Vector2(float(copy) * wrap, 0.0)
	if wrap > 0.0:
		holder.position.x = fmod(holder.position.x, wrap)
	return wrap
