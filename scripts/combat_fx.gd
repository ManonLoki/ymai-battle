class_name CombatFx
extends RefCounted

## 战斗表现层共用的特效构建。中毒 / 麻痹只换颜色，闪避和凌波微步共用重影，
## 普攻和凌波还击共用斩击。调用方反复 restart，不要为每种状态复制一份实现。

const POISON_COLOR := Color(0.92, 0.12, 0.14, 1.0)
const PARALYZE_COLOR := Color(1.0, 0.9, 0.12, 1.0)
const HEAL_COLOR := Color(0.45, 1.0, 0.62, 1.0)
const CRIT_COLOR := Color(1.0, 0.55, 0.08, 1.0)
const SKULL_COLOR := Color(0.92, 0.08, 0.1, 1.0)
const STUN_COLOR := Color(1.0, 0.92, 0.25, 1.0)
const GUARD_FILL := Color(0.45, 0.88, 1.0, 0.28)
const GUARD_RIM := Color(0.78, 0.96, 1.0, 0.95)

## 暴击粒子数，明显大于改前的 28。
const CRIT_AMOUNT := 96
const STATUS_AMOUNT := 18
## 从原位到终点一共 3 个形象：两张重影 + 终点的本体。
const AFTERIMAGE_EXTRAS := 2
const GHOST_TOTAL := AFTERIMAGE_EXTRAS + 1
## 闪避后退几个自身身位。身宽按立绘像素 × 基础放大。
const DODGE_BODY_LENGTHS := 1.0
const DODGE_START_ALPHA := 0.5
const DODGE_END_ALPHA := 1.0


## 立绘在屏幕上的显示身宽（不含 Visual 翻转符号）。
static func displayed_body_width(body_scale: float) -> float:
	return float(SpriteFactory.SIZE) * FighterView.BASE_SPRITE_SCALE * absf(body_scale)


## Sprite2D 局部坐标系里后退 1 个身位的位移（Visual.scale 再乘一次后等于世界 1 身宽）。
static func dodge_sprite_offset() -> float:
	return -float(SpriteFactory.SIZE) * FighterView.BASE_SPRITE_SCALE * DODGE_BODY_LENGTHS


## 建一组一次性爆发粒子。中毒 / 麻痹 / 暴击都走这里，只改颜色和数量。
static func make_burst(color: Color, amount: int, grav: Vector2, scale_max: float = 5.0) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.94
	particles.amount = amount
	particles.lifetime = 0.48
	particles.direction = Vector2(0, -1)
	particles.spread = 80.0
	particles.gravity = grav
	particles.initial_velocity_min = 50.0
	particles.initial_velocity_max = 160.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = scale_max
	particles.color = color
	particles.local_coords = true
	return particles


## 重新喷一次。restart 会把上一轮还没消失的粒子清掉。
static func burst(particles: CPUParticles2D) -> void:
	particles.restart()
	particles.emitting = true


## 沿闪避路径叠当前立绘：原位 50% 透明 → 中点过渡 → 终点由本体承担不透明。
static func spawn_afterimages(source: Sprite2D, parent: Node2D, offset: Vector2) -> void:
	NodeUtil.clear_children(parent)
	for i in AFTERIMAGE_EXTRAS:
		var ghost := Sprite2D.new()
		ghost.texture = source.texture
		ghost.texture_filter = source.texture_filter
		ghost.flip_h = source.flip_h
		ghost.scale = source.scale
		# i=0 原位，i=1 中点；终点留给正在后撤的本体。
		var t := float(i) / float(AFTERIMAGE_EXTRAS)
		ghost.position = source.position + offset * t
		ghost.modulate = Color(1.0, 1.0, 1.0, lerpf(DODGE_START_ALPHA, DODGE_END_ALPHA, t))
		parent.add_child(ghost)


## 头顶眩晕：三颗星绕一圈。调用方负责显隐和旋转。
static func make_stun(name: String = "StunFx") -> Node2D:
	var root := Node2D.new()
	root.name = name
	root.visible = false
	root.position = Vector2(0, -48)
	for i in 3:
		var star := Polygon2D.new()
		star.color = STUN_COLOR
		star.polygon = PackedVector2Array([
			Vector2(0, -7), Vector2(2, -2), Vector2(7, 0), Vector2(2, 2),
			Vector2(0, 7), Vector2(-2, 2), Vector2(-7, 0), Vector2(-2, -2),
		])
		var angle := TAU * float(i) / 3.0
		star.position = Vector2(cos(angle), sin(angle)) * 16.0
		root.add_child(star)
	return root


## 绝对防御罩子：半透明椭圆罩，表示这一下百毒不侵。
static func make_guard(name: String = "GuardFx") -> Node2D:
	var root := Node2D.new()
	root.name = name
	root.visible = false
	root.z_index = 7
	var fill := Polygon2D.new()
	fill.name = "Fill"
	fill.color = GUARD_FILL
	fill.polygon = _ellipse_points(0.0, -6.0, 78.0, 108.0, 28)
	root.add_child(fill)
	var rim := Line2D.new()
	rim.name = "Rim"
	rim.width = 5.0
	rim.default_color = GUARD_RIM
	rim.closed = true
	rim.joint_mode = Line2D.LINE_JOINT_ROUND
	for point in fill.polygon:
		rim.add_point(point)
	root.add_child(rim)
	var inner := Line2D.new()
	inner.name = "Inner"
	inner.width = 2.0
	inner.default_color = Color(1.0, 1.0, 1.0, 0.55)
	inner.closed = true
	for point in _ellipse_points(0.0, -6.0, 62.0, 90.0, 24):
		inner.add_point(point)
	root.add_child(inner)
	# 顶部一点高光，读起来像罩子而不是色块。
	var gleam := Polygon2D.new()
	gleam.name = "Gleam"
	gleam.color = Color(1.0, 1.0, 1.0, 0.45)
	gleam.polygon = PackedVector2Array([
		Vector2(-18, -92), Vector2(18, -92), Vector2(10, -78), Vector2(-10, -78),
	])
	root.add_child(gleam)
	return root


static func _ellipse_points(cx: float, cy: float, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var angle := TAU * float(i) / float(n)
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	return pts


## 红色画了 X 的骷髅。优先贴图，没有贴图就用多边形兜底，测试都能看到红 X。
static func make_skull(name: String = "SkullFx") -> Node2D:
	var root := Node2D.new()
	root.name = name
	root.visible = false
	root.z_index = 8
	var tex := _load_skull_texture()
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(2.5, 2.5)
		root.add_child(sprite)
	else:
		root.add_child(_drawn_skull())
	return root


static func _load_skull_texture() -> Texture2D:
	var path := "res://assets/fx/skull_x.png"
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is Texture2D:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func _drawn_skull() -> Node2D:
	var drawn := Node2D.new()
	drawn.name = "Drawn"
	var head := Polygon2D.new()
	head.color = SKULL_COLOR
	head.polygon = PackedVector2Array([
		Vector2(-18, -8), Vector2(-12, -20), Vector2(12, -20), Vector2(18, -8),
		Vector2(14, 8), Vector2(8, 16), Vector2(-8, 16), Vector2(-14, 8),
	])
	drawn.add_child(head)
	for jaw_x in [-8, 0, 8]:
		var tooth := Polygon2D.new()
		tooth.color = Color(0.55, 0.04, 0.06, 1.0)
		tooth.polygon = PackedVector2Array([
			Vector2(jaw_x - 3, 10), Vector2(jaw_x + 3, 10), Vector2(jaw_x, 16),
		])
		drawn.add_child(tooth)
	# 两笔红 X 盖在骷髅上。
	for sign_x in [-1.0, 1.0]:
		var arm := Polygon2D.new()
		arm.color = Color(1.0, 0.15, 0.12, 1.0)
		arm.polygon = PackedVector2Array([
			Vector2(-4, -22), Vector2(4, -22), Vector2(22, 18), Vector2(14, 22),
			Vector2(-4, -10),
		])
		arm.scale = Vector2(sign_x, 1.0)
		drawn.add_child(arm)
	return drawn
