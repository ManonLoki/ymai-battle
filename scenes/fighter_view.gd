class_name FighterView
extends Node2D

## 场上一名角色的表现层：立绘、血条、buff / 技能图标和悬停说明。
## 只负责播放 battle.gd 交代的动画，不参与任何战斗判定。

## 立绘基础放大倍数（32px 的像素画放到 224px）。
const BASE_SPRITE_SCALE := 7.0
## 擂主比挑战者大一圈，一眼看出谁是榜一。
## 体型不只是观感：Fighter 那边按它给了先天闪避 / 减伤的差异。
const CHAMPION_BODY_SCALE := 1.1
const CHALLENGER_BODY_SCALE := 0.9
## 回血特效场景，吸血和治疗共用同一个。
const HEAL_FX := preload("res://scenes/heal_fx.tscn")
## buff / 技能图标的边长和间距，_fit_row 算行宽时要用。
const ICON_PX := 20
const ICON_GAP := 4

@onready var sprite: Sprite2D = $Visual/Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var status_row: HBoxContainer = $UI/StatusRow
@onready var name_label: Label = $UI/StatusRow/NameLabel
@onready var hp_wrap: Control = $UI/StatusRow/HpWrap
@onready var hp_bar: ProgressBar = $UI/StatusRow/HpWrap/HpBar
@onready var hp_label: Label = $UI/StatusRow/HpWrap/HpLabel
@onready var buff_row: HBoxContainer = $UI/BuffRow
@onready var skill_row: HBoxContainer = $UI/SkillRow
@onready var tip_panel: PanelContainer = $UI/TipPanel
@onready var tip_label: Label = $UI/TipPanel/TipLabel
@onready var slash: Polygon2D = $Visual/Slash

## 三种姿势的立绘，bind 时一次性生成好，播动画时直接换。
var _idle_tex: Texture2D
var _attack_tex: Texture2D
var _hurt_tex: Texture2D
## 节点一开始所在的位置，动画结束后要归位。
var _home: Vector2 = Vector2.ZERO
## 暴击的金色粒子。
var _crit_fx: CPUParticles2D
## 中毒的绿色粒子。
var _poison_fx: CPUParticles2D
## 当前正在跑的染色 Tween。新特效来了要先把旧的 kill 掉，否则颜色会打架。
var _fx_tween: Tween


func _ready() -> void:
	_home = position
	_build_animations()
	# 刀光平时藏着，出招动画里才亮一下。
	slash.visible = false
	# 两组粒子只建一次，之后反复 restart。
	_crit_fx = _make_burst(Color(1.0, 0.82, 0.15, 1.0), 28, Vector2(0, 20))
	_poison_fx = _make_burst(Color(0.35, 0.95, 0.28, 1.0), 16, Vector2(0, 40))
	$Visual.add_child(_crit_fx)
	$Visual.add_child(_poison_fx)
	# 这几个 Label 是场景里摆好的，得单独套上中文字体。
	for label in [name_label, hp_label, tip_label]:
		label.add_theme_font_override("font", ThemeHelper.UI_FONT)
	tip_panel.visible = false
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


## 把一名角色绑到这个视图上。换人时重复调用，所有状态都要复位。
func bind(fighter: Fighter, face_left: bool) -> void:
	# 三种姿势的立绘现场生成，擂主那张自带王冠。
	_idle_tex = SpriteFactory.make_texture(fighter.appearance_id, "idle", fighter.is_champion)
	_attack_tex = SpriteFactory.make_texture(fighter.appearance_id, "attack", fighter.is_champion)
	_hurt_tex = SpriteFactory.make_texture(fighter.appearance_id, "hurt", fighter.is_champion)
	sprite.texture = _idle_tex
	# 像素画必须最近邻，放大后才不糊。
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 上一场的动画可能把这几项改过，全部复位。
	sprite.scale = Vector2(BASE_SPRITE_SCALE, BASE_SPRITE_SCALE)
	sprite.flip_h = false
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	# 体型差放在 Visual 上而不是 Sprite2D 上：受击动画会把 Sprite2D 的 scale 压扁再弹回
	# 固定值，写在 Sprite2D 上会被它覆盖掉。翻转也合并到这里。
	var body := CHAMPION_BODY_SCALE if fighter.is_champion else CHALLENGER_BODY_SCALE
	$Visual.scale = Vector2(-body if face_left else body, body)
	# 立绘以原点为中心，放大后脚会陷进地里、缩小后浮在半空，按半身高补回来。
	var half_height := float(SpriteFactory.SIZE) * BASE_SPRITE_SCALE * 0.5
	$Visual.position = Vector2(0, -half_height * (body - 1.0))
	name_label.text = fighter.username
	hp_bar.max_value = fighter.max_hp
	# step=0 让血条平滑变化，不按整数档跳。
	hp_bar.step = 0.0
	set_hp(fighter.hp, fighter.max_hp)
	_fill_icons(fighter)
	_align_icon_rows_to_hp()
	# 布局要等容器算完尺寸才准，所以下一帧再对齐一次。
	call_deferred("_align_icon_rows_to_hp")
	# 上一位可能是死着退场的（死亡动画把 modulate 调暗、转了角度）。
	modulate = Color.WHITE
	rotation = 0.0
	position = _home
	visible = true
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


## 重建两行图标：上面一行 agent buff，下面一行本场抽到的技能。
func _fill_icons(fighter: Fighter) -> void:
	_clear_row(buff_row)
	_clear_row(skill_row)
	# 每个 agent 一个 buff 图标，用了几个 agent 就挂几个。
	for buff in fighter.agent_buffs:
		if buff.icon_id.is_empty():
			continue
		buff_row.add_child(_icon_rect(buff))
	for skill in fighter.skills:
		if skill.icon_id.is_empty():
			continue
		skill_row.add_child(_icon_rect(skill))
	_fit_row(buff_row)
	_fit_row(skill_row)
	_align_icon_rows_to_hp()


## 清空一行图标。用 free 而不是 queue_free：下一句就要重新排版，不能等到帧末。
func _clear_row(row: HBoxContainer) -> void:
	NodeUtil.clear_children(row)


## 把一行的尺寸收紧到刚好装下现有图标，免得空 HBox 撑开布局。
func _fit_row(row: HBoxContainer) -> void:
	var count := row.get_child_count()
	# n 个图标之间有 n-1 个间隙。
	var width := float(count * ICON_PX + maxi(0, count - 1) * ICON_GAP)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	# 至少留一个图标宽，空行也不会塌成 0。
	row.custom_minimum_size = Vector2(maxi(int(width), ICON_PX), ICON_PX)
	row.size = row.custom_minimum_size
	row.reset_size()


## 两行图标的左边缘对齐血条，而不是对齐名字，看起来才是一列。
func _align_icon_rows_to_hp() -> void:
	status_row.reset_size()
	var left := hp_wrap.position.x
	# 布局还没算出来时 position 会是 0，这时按“名字宽度 + 间距”估一个。
	if left <= 1.0:
		left = name_label.custom_minimum_size.x + float(status_row.get_theme_constant("separation"))
	for row in [buff_row, skill_row]:
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.offset_left = left
		row.position.x = left
		row.reset_size()


## 建一个图标格子，并接上悬停显示说明的回调。
func _icon_rect(skill: SkillDef) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = SkillCatalog.load_icon(skill.icon_id)
	# 清掉内置 tooltip：它有延迟，这里改用自己的即时提示面板。
	rect.tooltip_text = ""
	rect.focus_mode = Control.FOCUS_NONE
	# STOP 才收得到 mouse_entered。
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rect.mouse_entered.connect(_show_instant_tip.bind(rect, skill))
	rect.mouse_exited.connect(_hide_instant_tip)
	return rect


## 把说明面板挪到图标正下方并显示出来。
func _show_instant_tip(host: Control, skill: SkillDef) -> void:
	tip_label.text = SkillCatalog.tooltip_text(skill)
	tip_panel.visible = true
	# 先显示再 reset_size，才能拿到文字撑出来的真实尺寸。
	tip_panel.reset_size()
	# 图标的全局坐标换算成 UI 层的局部坐标。
	var ui := $UI as Node2D
	var local := host.global_position - ui.global_position
	tip_panel.position = Vector2(local.x, local.y + host.size.y + 4.0)


func _hide_instant_tip() -> void:
	tip_panel.visible = false


## 刷新血条和血量文字。max_hp 至少按 1 算，避免除零。
func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = maxi(1, max_hp)
	hp_bar.value = hp
	hp_label.text = "%s / %s" % [ThemeHelper.compact(hp), ThemeHelper.compact(max_hp)]


## 回到站立：换回站立立绘并循环播待机动画。
func play_idle() -> void:
	sprite.texture = _idle_tex
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


## 出招：换攻击立绘，亮出刀光。
func play_attack() -> void:
	sprite.texture = _attack_tex
	slash.visible = true
	# 每次都重置刀光的颜色和大小，暴击特效可能把它改过。
	slash.color = Color(1, 1, 1, 0.85)
	slash.scale = Vector2.ONE
	if anim_player.has_animation(&"attack"):
		anim_player.play(&"attack")


## 挨打：换受击立绘（脸上带红痕）。
func play_hurt() -> void:
	sprite.texture = _hurt_tex
	if anim_player.has_animation(&"hurt"):
		anim_player.play(&"hurt")


## 倒下：转倒并淡出，不再回到站立。
func play_death() -> void:
	if anim_player.has_animation(&"death"):
		anim_player.play(&"death")


## 闪避：往后撤一步。
func play_dodge() -> void:
	if anim_player.has_animation(&"dodge"):
		anim_player.play(&"dodge")


## 暴击特效：金色粒子 + 金色刀光 + 立绘闪一下金。
func play_crit_fx() -> void:
	_burst(_crit_fx)
	slash.visible = true
	slash.color = Color(1.0, 0.85, 0.2, 0.95)
	_fx_tween = _restart_tint(Color(1.0, 0.92, 0.35), Color.WHITE, 0.28, true)


## 中毒特效：绿色粒子 + 立绘泛绿，而且绿色不会完全褪掉（还在中毒里）。
func play_poison_fx() -> void:
	_burst(_poison_fx)
	_fx_tween = _restart_tint(Color(0.45, 1.0, 0.4), Color(0.7, 1.0, 0.65), 0.35, false)


## 回血特效：一次性粒子场景 + 立绘泛绿后回白。吸血和治疗共用。
func play_heal_fx() -> void:
	var fx := HEAL_FX.instantiate()
	$Visual.add_child(fx)
	fx.restart()
	fx.emitting = true
	# 粒子播完自己删掉，不然一场下来会攒一堆节点。
	var life := create_tween()
	life.tween_interval(0.7)
	life.tween_callback(fx.queue_free)
	_fx_tween = _restart_tint(Color(0.55, 1.0, 0.7), Color.WHITE, 0.35, false)


## 立绘染色：立刻变成 from，再在 duration 内过渡到 to。
## 每次都先 kill 掉上一个 Tween，否则两个特效会抢着改同一个 modulate。
func _restart_tint(from: Color, to: Color, duration: float, ease_out: bool) -> Tween:
	if _fx_tween:
		_fx_tween.kill()
	var tween := create_tween()
	if ease_out:
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sprite.modulate = from
	tween.tween_property(sprite, "modulate", to, duration)
	return tween


## 测试拿它核对五种动画都建出来了。
func animation_names() -> PackedStringArray:
	return PackedStringArray(["idle", "attack", "hurt", "death", "dodge"])


## 建一组一次性爆发粒子。grav 决定粒子是往上飘还是往下落。
func _make_burst(color: Color, amount: int, grav: Vector2) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	# 接近 1 表示所有粒子几乎同时喷出，是“爆”不是“流”。
	particles.explosiveness = 0.94
	particles.amount = amount
	particles.lifetime = 0.42
	particles.direction = Vector2(0, -1)
	particles.spread = 80.0
	particles.gravity = grav
	particles.initial_velocity_min = 50.0
	particles.initial_velocity_max = 140.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	particles.color = color
	# 跟着节点走，角色移动时粒子不会掉队。
	particles.local_coords = true
	return particles


## 重新喷一次。restart 会把上一轮还没消失的粒子清掉。
func _burst(particles: CPUParticles2D) -> void:
	particles.restart()
	particles.emitting = true


## 五种动画全部用代码建，场景文件里不存动画数据。
## 已经建过就直接返回（场景被复用时会重复调）。
func _build_animations() -> void:
	if anim_player.has_animation(&"idle"):
		return
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle_anim())
	lib.add_animation(&"attack", _attack_anim())
	lib.add_animation(&"hurt", _hurt_anim())
	lib.add_animation(&"death", _death_anim())
	lib.add_animation(&"dodge", _dodge_anim())
	# 空字符串表示默认库，动画名前面就不用带库名前缀。
	anim_player.add_animation_library(&"", lib)


## 待机：整个人上下浮动，循环播放。
func _idle_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.8
	anim.loop_mode = Animation.LOOP_LINEAR
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath("Visual/Sprite2D:position:y"))
	anim.track_insert_key(track, 0.0, 0.0)
	anim.track_insert_key(track, 0.4, -8.0)
	anim.track_insert_key(track, 0.8, 0.0)
	return anim


## 出招：前冲 + 微微转身 + 刀光淡入淡出。
func _attack_anim() -> Animation:
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
	# 刀光只在最前面那一下亮。
	var slash_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_track, NodePath("Visual/Slash:modulate:a"))
	anim.track_insert_key(slash_track, 0.0, 0.0)
	anim.track_insert_key(slash_track, 0.1, 1.0)
	anim.track_insert_key(slash_track, 0.36, 0.0)
	return anim


## 受击：往后弹一下，同时闪红。
func _hurt_anim() -> Animation:
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


## 闪避：往后撤一大步，顺便压扁一点表示发力。
func _dodge_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, -72.0)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	# 关键帧写的是绝对 scale，所以必须和 BASE_SPRITE_SCALE 对得上。
	var scale_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(scale_track, NodePath("Visual/Sprite2D:scale"))
	var base := BASE_SPRITE_SCALE
	anim.track_insert_key(scale_track, 0.0, Vector2(base, base))
	anim.track_insert_key(scale_track, 0.12, Vector2(base - 0.8, base + 0.4))
	anim.track_insert_key(scale_track, 0.36, Vector2(base, base))
	return anim


## 倒下：转倒 + 整体淡到很暗 + 往下沉，结束后停在这个状态不再复位。
func _death_anim() -> Animation:
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
