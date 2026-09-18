class_name MenuParallax
extends Node2D

## Idle menu parallax: each layer scrolls at a different pixels-per-second rate.

const LAYER_TEXTURES: Array[Texture2D] = [
	preload("res://assets/backgrounds/far.png"),
	preload("res://assets/backgrounds/mid.png"),
	preload("res://assets/backgrounds/near.png"),
]
var _layer_names: Array[String] = ["FarLayer", "MidLayer", "NearLayer"]
var _layer_speeds: Array[float] = [22.0, 58.0, 128.0]

var layers: Array[Node2D] = []
var wrap_widths: Array[float] = []
var speeds: Array[float] = []


func _ready() -> void:
	_build_layers()


func _process(delta: float) -> void:
	advance_parallax(delta)


func advance_parallax(delta: float) -> void:
	for i in layers.size():
		var node := layers[i]
		var width := wrap_widths[i]
		if width <= 0.0:
			continue
		node.position.x -= speeds[i] * delta
		while node.position.x <= -width:
			node.position.x += width
		while node.position.x > 0.0:
			node.position.x -= width


func _build_layers() -> void:
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
		holder.name = _layer_names[i]
		var tex_h := float(tex.get_height())
		var scale_f := view_h / tex_h if tex_h > 0.0 else 1.0
		var wrap := float(tex.get_width()) * scale_f
		for copy in 2:
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(scale_f, scale_f)
			sprite.position = Vector2(float(copy) * wrap, 0.0)
			holder.add_child(sprite)
		add_child(holder)
		layers.append(holder)
		wrap_widths.append(wrap)
		speeds.append(_layer_speeds[i] if i < _layer_speeds.size() else _layer_speeds[_layer_speeds.size() - 1])
