class_name MenuParallax
extends Node2D

## 主菜单的像素风滚动背景：远、中、近三层各自以不同速度向左滚，形成视差。
##
## 每层都放两张首尾相接的同图，滚过一整张宽度就把位置绕回去，
## 于是永远看不到接缝，也不需要额外的图。

## 三层贴图，由远及近。preload 保证它们跟着脚本一起进包。
const LAYER_TEXTURES: Array[Texture2D] = [
	preload("res://assets/backgrounds/far.png"),
	preload("res://assets/backgrounds/mid.png"),
	preload("res://assets/backgrounds/near.png"),
]
## 三层容器节点的名字，方便在远程场景树里认出来。
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
	_build_layers()


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


## 建三层容器，每层两张首尾相接的贴图，按视口高度等比缩放。
func _build_layers() -> void:
	# 拿不到视口时（比如纯逻辑测试里）按设计分辨率的高度算。
	var view_h := 720.0
	var viewport := get_viewport()
	if viewport != null:
		var visible := viewport.get_visible_rect().size
		if visible.y > 1.0:
			view_h = visible.y
	for i in LAYER_TEXTURES.size():
		var tex: Texture2D = LAYER_TEXTURES[i]
		if tex == null:
			continue
		var holder := Node2D.new()
		holder.name = LAYER_NAMES[i]
		# 等比缩放到刚好铺满视口高度，宽度跟着一起放大。
		var tex_h := float(tex.get_height())
		var scale_f := view_h / tex_h if tex_h > 0.0 else 1.0
		var wrap := float(tex.get_width()) * scale_f
		# 两张：一张在屏内，一张顶在它右边，滚出去的那张绕回来时正好接上。
		for copy in 2:
			var sprite := Sprite2D.new()
			sprite.texture = tex
			# 左上角对齐，position 直接就是贴图左边缘，接缝计算才简单。
			sprite.centered = false
			# 像素画必须用最近邻，否则放大后糊成一片。
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(scale_f, scale_f)
			sprite.position = Vector2(float(copy) * wrap, 0.0)
			holder.add_child(sprite)
		add_child(holder)
		layers.append(holder)
		wrap_widths.append(wrap)
		speeds.append(LAYER_SPEEDS[i])
