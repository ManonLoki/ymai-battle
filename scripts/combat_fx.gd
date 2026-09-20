class_name CombatFx
extends RefCounted

## 战斗表现层共用的特效播放参数。固定节点和形状都在 fighter_view.tscn 里，
## 这里只负责复用已有节点，不在运行时拼场景树。

## 立绘闪一下的染色。粒子色本身已经写进 fighter_view.tscn 的各个 *Fx 节点，
## 这里只留染立绘用的那一份——直接拿粒子色去染立绘会糊成一坨。
const CRIT_TINT := Color(1.0, 0.92, 0.35)
const POISON_TINT := Color(1.0, 0.35, 0.32)
const PARALYZE_TINT := Color(1.0, 0.95, 0.35)
const GUARD_TINT := Color(0.7, 0.95, 1.0)
const REFLECT_TINT := Color(0.85, 0.95, 1.0)
const HEAL_TINT := Color(0.55, 1.0, 0.7)
## 反弹波从盾前方向对手方向射出的位移（Visual 局部 +x，翻转后仍朝向对方）。
const REFLECT_WAVE_TRAVEL := 240.0
## 反弹盾在身前的局部 x，正数表示朝向对手。
const REFLECT_SHIELD_X := 64.0
## 刀光：平时是冷白，暴击那一下换成金的。
const SLASH_COLOR := Color(0.95, 0.95, 1.0, 0.95)
const CRIT_SLASH_COLOR := Color(1.0, 0.85, 0.2, 0.95)

## 从原位到终点一共 3 个形象：两张重影 + 终点的本体。
const AFTERIMAGE_EXTRAS := 2
const GHOST_TOTAL := AFTERIMAGE_EXTRAS + 1
## 闪避后退几个自身身位。身宽按立绘像素 × 基础放大。
const DODGE_BODY_LENGTHS := 1.0
const DODGE_START_ALPHA := 0.5
const DODGE_END_ALPHA := 1.0


## 第 i 张重影的透明度：i=0 在原位最淡，越靠近终点越实。
## 播放和收起两边都要按这条曲线摆，所以只在这里算一次。
static func ghost_alpha(i: int) -> float:
	return lerpf(DODGE_START_ALPHA, DODGE_END_ALPHA, float(i) / float(AFTERIMAGE_EXTRAS))


## 盖在身上闪一下的覆盖层（绝对防御的罩子、幻影刺杀的骷髅）：
## 弹出 → 停一会 → 淡出 → 收起并把 modulate 复位。三种覆盖特效差的只是这几个数，
## 所以形状写在这里一份，调用方只给数值——再加一种覆盖特效不用再抄一遍。
##
## overshoot 大于 0 时先弹过头再收回来，罩子才有“砰”地撑开的感觉。
## 返回这条 Tween，调用方自己保管（下次播之前要先 kill 掉）。
static func pop_fade(
	node: Node2D,
	from_scale: float,
	pop_time: float,
	hold: float,
	fade: float,
	overshoot: float = 0.0,
) -> Tween:
	node.visible = true
	node.modulate = Color.WHITE
	node.scale = Vector2(from_scale, from_scale)
	var tween := node.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if overshoot > 0.0:
		tween.tween_property(node, "scale", Vector2(overshoot, overshoot), pop_time)
		tween.tween_property(node, "scale", Vector2.ONE, pop_time * 0.625)
	else:
		tween.tween_property(node, "scale", Vector2.ONE, pop_time)
	tween.tween_interval(hold)
	tween.tween_property(node, "modulate:a", 0.0, fade)
	tween.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.visible = false
			node.modulate = Color.WHITE
	)
	return tween


## 立绘在屏幕上的显示身宽（不含 Visual 翻转符号）。
static func displayed_body_width(body_scale: float) -> float:
	return float(SpriteFactory.SIZE) * FighterView.BASE_SPRITE_SCALE * absf(body_scale)


## Body 局部坐标系里后退 1 个身位的位移（Visual.scale 再乘一次后等于世界 1 身宽）。
static func dodge_sprite_offset() -> float:
	return -float(SpriteFactory.SIZE) * FighterView.BASE_SPRITE_SCALE * DODGE_BODY_LENGTHS


## 重新喷一次。restart 会把上一轮还没消失的粒子清掉。
static func burst(particles: CPUParticles2D) -> void:
	particles.visible = true
	particles.restart()
	particles.emitting = true


## 沿闪避路径叠当前立绘：原位 50% 透明 → 中点过渡 → 终点由本体承担不透明。
static func spawn_afterimages(source: Sprite2D, parent: Node2D, offset: Vector2) -> void:
	for i in mini(AFTERIMAGE_EXTRAS, parent.get_child_count()):
		var ghost := parent.get_child(i) as Sprite2D
		if ghost == null:
			continue
		ghost.texture = source.texture
		ghost.texture_filter = source.texture_filter
		ghost.flip_h = source.flip_h
		ghost.scale = source.scale
		# i=0 原位，i=1 中点；终点留给正在后撤的本体。
		ghost.position = source.position + offset * (float(i) / float(AFTERIMAGE_EXTRAS))
		ghost.modulate = Color(1.0, 1.0, 1.0, ghost_alpha(i))
		ghost.visible = true
