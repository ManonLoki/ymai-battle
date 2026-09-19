class_name FighterAnims
extends RefCounted

## FighterView 那五种动画的关键帧数据。场景文件里不存动画，全在这里用代码建。
##
## 单独一个文件是因为这里没有一行是“播放”：它只产出 Animation 资源，
## 不碰节点、也不读 FighterView 的状态。轨道路径写的是 FighterView 内部的节点路径
## （Visual/Sprite2D，"." 指 FighterView 自己），所以这两个文件的结构是配套的。


## 五种动画打包成一个库，交给 AnimationPlayer 装上。
## base_scale 是立绘的基础放大倍数：受击和闪避的关键帧写的是**绝对** scale，
## 必须和 FighterView.BASE_SPRITE_SCALE 对得上，所以由调用方传进来。
static func library(base_scale: float) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle_anim())
	lib.add_animation(&"attack", _attack_anim())
	lib.add_animation(&"hurt", _hurt_anim(base_scale))
	lib.add_animation(&"death", _death_anim())
	lib.add_animation(&"dodge", _dodge_anim(base_scale))
	return lib


## 待机：整个人上下浮动，循环播放。
static func _idle_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.8
	anim.loop_mode = Animation.LOOP_LINEAR
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath("Visual/Sprite2D:position:y"))
	anim.track_insert_key(track, 0.0, 0.0)
	anim.track_insert_key(track, 0.4, -8.0)
	anim.track_insert_key(track, 0.8, 0.0)
	return anim


## 出招：前冲 + 微微转身 + 剑从自身砍向对手。
static func _attack_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	# 往前冲出去再收回来。
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, 48.0)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	# 顺带扭一点角度，冲劲更足。
	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, NodePath("Visual/Sprite2D:rotation"))
	anim.track_insert_key(rot_track, 0.0, 0.0)
	anim.track_insert_key(rot_track, 0.12, 0.18)
	anim.track_insert_key(rot_track, 0.36, 0.0)
	# 剑只在最前面那一下亮，并往对手方向送出去。
	var slash_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_track, NodePath("Visual/Slash:modulate:a"))
	anim.track_insert_key(slash_track, 0.0, 0.0)
	anim.track_insert_key(slash_track, 0.08, 1.0)
	anim.track_insert_key(slash_track, 0.36, 0.0)
	var slash_pos := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_pos, NodePath("Visual/Slash:position:x"))
	anim.track_insert_key(slash_pos, 0.0, 0.0)
	anim.track_insert_key(slash_pos, 0.14, 90.0)
	anim.track_insert_key(slash_pos, 0.36, 40.0)
	var slash_vis := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_vis, NodePath("Visual/Slash:visible"))
	anim.track_insert_key(slash_vis, 0.0, true)
	anim.track_insert_key(slash_vis, 0.36, false)
	return anim


## 受击：往后弹一下，同时闪红。
static func _hurt_anim(base_scale: float) -> Animation:
	var anim := Animation.new()
	anim.length = 0.28
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.08, -22.0)
	anim.track_insert_key(pos_track, 0.28, 0.0)
	var mod_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(mod_track, NodePath("Visual/Sprite2D:modulate"))
	anim.track_insert_key(mod_track, 0.0, Color.WHITE)
	anim.track_insert_key(mod_track, 0.06, Color("ff6b6b"))
	anim.track_insert_key(mod_track, 0.28, Color.WHITE)
	return anim


## 闪避：往后撤约 1 个身位，顺便压扁一点表示发力。
static func _dodge_anim(base_scale: float) -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	var dodge_x := CombatFx.dodge_sprite_offset()
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, dodge_x)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	# 关键帧写的是绝对 scale，所以必须和传进来的 base_scale 对得上。
	var scale_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(scale_track, NodePath("Visual/Sprite2D:scale"))
	var base := base_scale
	anim.track_insert_key(scale_track, 0.0, Vector2(base, base))
	anim.track_insert_key(scale_track, 0.12, Vector2(base - 0.8, base + 0.4))
	anim.track_insert_key(scale_track, 0.36, Vector2(base, base))
	return anim


## 倒下：转倒 + 整体淡到很暗 + 往下沉，结束后停在这个状态不再复位。
static func _death_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.5
	anim.loop_mode = Animation.LOOP_NONE
	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, NodePath("Visual/Sprite2D:rotation"))
	anim.track_insert_key(rot_track, 0.0, 0.0)
	anim.track_insert_key(rot_track, 0.5, 1.2)
	# "." 指 FighterView 自己：连名字血条一起淡下去。
	var mod_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(mod_track, NodePath(".:modulate:a"))
	anim.track_insert_key(mod_track, 0.0, 1.0)
	anim.track_insert_key(mod_track, 0.5, 0.15)
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:y"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.5, 40.0)
	return anim
