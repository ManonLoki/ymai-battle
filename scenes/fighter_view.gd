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
## 一个 buff / 技能图标格子。边长、采样、鼠标形状都在这个场景里。
const SKILL_ICON := preload("res://scenes/skill_icon.tscn")
## 改前暴击粒子数，测试拿它对照“大爆炸”。
const LEGACY_CRIT_AMOUNT := 28

@onready var visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Body
@onready var _afterimages: Node2D = $Visual/Afterimages
@onready var _ghosts: Array[Sprite2D] = [
	$Visual/Afterimages/Ghost0,
	$Visual/Afterimages/Ghost1,
]
@onready var _crit_fx: CPUParticles2D = $Visual/CritFx
@onready var _poison_fx: CPUParticles2D = $Visual/PoisonFx
@onready var _paralyze_fx: CPUParticles2D = $Visual/ParalyzeFx
@onready var _stun_fx: Node2D = $Visual/StunFx
@onready var _skull_fx: Node2D = $Visual/SkullFx
@onready var _guard_fx: Node2D = $Visual/GuardFx
@onready var _reflect_fx: Node2D = $Visual/ReflectFx
@onready var _reflect_shield: Node2D = $Visual/ReflectFx/Shield
@onready var _reflect_wave: Node2D = $Visual/ReflectFx/Wave
@onready var _rebirth_fx: Node2D = $Visual/RebirthFx
@onready var _rebirth_fire: CPUParticles2D = $Visual/RebirthFx/FeetFire
@onready var _rebirth_phoenix: Node2D = $Visual/RebirthFx/Phoenix
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var ui: Node2D = $UI
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
@onready var _overlays: Array[Node2D] = [_stun_fx, _skull_fx, _guard_fx, _reflect_fx, _rebirth_fx]
@onready var _bursts: Array[CPUParticles2D] = [_crit_fx, _poison_fx, _paralyze_fx, _rebirth_fire]

## 三种姿势的立绘，bind 时一次性生成好，播动画时直接换。
var _idle_tex: Texture2D
var _attack_tex: Texture2D
var _hurt_tex: Texture2D
## 场景实例最初的变换。常驻复用时，reset_view 要连外层变换一起还原。
var _home_transform := Transform2D.IDENTITY
## 各路特效正在跑的 Tween，按名字存一份。同名的新特效来了要先把旧的 kill 掉，
## 否则两个会抢着改同一个属性（染色最明显）；换人时 _hide_transient_fx 一把全停。
var _tweens: Dictionary = {}
## 治疗粒子仍需按次数动态实例化；单独记住，reset_view 才能中途回收干净。
var _heal_fx_instances: Array[CPUParticles2D] = []


## 记住场景实例最初的位置，然后摆成“没绑人”的干净状态。
##
## _home_transform 必须在这里存：死亡动画会把整个视图转倒、挪开，
## 换下一位上场时得有个原始值可以还原，而那时候已经拿不到“改之前”的样子了。
func _ready() -> void:
	_home_transform = transform
	# 字体和配色来自 project.godot 注册的全局主题，这里不用再套。
	tip_panel.visible = false
	_hide_transient_fx()
	_play(&"idle")


## 把一名角色绑到这个视图上。换人时重复调用，所有状态都要复位。
func bind(fighter: Fighter, face_left: bool) -> void:
	anim_player.stop()
	_hide_transient_fx()
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
	# 体型差放在 Visual 上而不是 Body 上：受击动画会把 Body 的 scale 压扁再弹回
	# 固定值，写在 Body 上会被它覆盖掉。翻转也合并到这里。
	var body := CHAMPION_BODY_SCALE if fighter.is_champion else CHALLENGER_BODY_SCALE
	visual.scale = Vector2(-body if face_left else body, body)
	# 立绘以原点为中心，放大后脚会陷进地里、缩小后浮在半空，按半身高补回来。
	var half_height := float(SpriteFactory.SIZE) * BASE_SPRITE_SCALE * 0.5
	visual.position = Vector2(0, -half_height * (body - 1.0))
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
	transform = _home_transform
	visible = true
	_play(&"idle")


## 重建两行图标：上面一行 agent buff，下面一行本场抽到的技能。
func _fill_icons(fighter: Fighter) -> void:
	NodeUtil.clear_children(buff_row)
	NodeUtil.clear_children(skill_row)
	# 每个 agent 一个 buff 图标，用了几个 agent 就挂几个。
	for buff in fighter.agent_buffs:
		if buff.icon_id.is_empty():
			continue
		_add_icon(buff_row, buff)
	for skill in SkillCatalog.sort_for_display(fighter.skills):
		if skill.icon_id.is_empty():
			continue
		_add_icon(skill_row, skill)
	_fit_row(buff_row)
	_fit_row(skill_row)
	_align_icon_rows_to_hp()


## 图标从左往右排，行宽按内容重算一次。
## 格子大小归 skill_icon.tscn，间距归 fighter_view.tscn 里这一行的 separation——
## 尺寸交给容器自己算，这里不再另存一份数字。
## 两行的父节点是 Node2D 而不是容器，所以行宽只影响自己，不会推挤别的控件。
func _fit_row(row: HBoxContainer) -> void:
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
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


## 往一行里挂一个图标格子，并接上悬停显示说明的回调。
## 格子本身（大小、最近邻采样、不吃焦点、鼠标形状、空 tooltip_text）在
## skill_icon.tscn 里摆好——内置 tooltip 有延迟，这里用自己的即时提示面板顶掉它。
func _add_icon(row: HBoxContainer, skill: SkillDef) -> void:
	var icon: SkillIcon = SKILL_ICON.instantiate()
	# 先进树再 bind：格子自己的 _ready 要先把两个悬停信号接起来。
	row.add_child(icon)
	icon.bind(skill)
	icon.hovered.connect(_show_instant_tip)
	icon.unhovered.connect(_hide_instant_tip)


## 把说明面板挪到图标正下方并显示出来。
func _show_instant_tip(host: Control, skill: SkillDef) -> void:
	tip_label.text = SkillCatalog.tooltip_text(skill)
	tip_panel.visible = true
	# 先显示再 reset_size，才能拿到文字撑出来的真实尺寸。
	tip_panel.reset_size()
	# 图标的全局坐标换算成 UI 层的局部坐标。
	var local := host.global_position - ui.global_position
	tip_panel.position = Vector2(local.x, local.y + host.size.y + 4.0)


## 鼠标移开图标，收起说明面板。只藏不清空——文字留着，
## 下次悬停同一个图标时即使还没来得及重算也不会闪一下空白。
func _hide_instant_tip() -> void:
	tip_panel.visible = false


## 刷新血条和血量文字。max_hp 至少按 1 算，避免除零。
func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = maxi(1, max_hp)
	hp_bar.value = hp
	hp_label.text = "%s / %s" % [NumberFormat.compact(hp), NumberFormat.compact(max_hp)]


## 播一个动画，没建出来就不播。五个播放点都走这里，省得每处都写一遍 has_animation。
func _play(anim: StringName) -> void:
	if anim_player.has_animation(anim):
		anim_player.play(anim)


## 回到站立：换回站立立绘并循环播待机动画。
func play_idle() -> void:
	sprite.texture = _idle_tex
	_play(&"idle")


## 出招：换攻击立绘，亮出从自身砍向对手的剑。
func play_attack() -> void:
	sprite.texture = _attack_tex
	slash.visible = true
	# 每次都重置刀光的颜色和大小，暴击特效可能把它改过。
	slash.color = CombatFx.SLASH_COLOR
	slash.scale = Vector2.ONE
	slash.position = Vector2.ZERO
	_play(&"attack")


## 挨打：换受击立绘（脸上带红痕）。
func play_hurt() -> void:
	sprite.texture = _hurt_tex
	_play(&"hurt")


## 倒下：转倒并淡出，不再回到站立。
func play_death() -> void:
	_play(&"death")


## 闪避 / 凌波微步：后退约 1 个自身身位，原位到终点叠 3 个当前立绘。
func play_dodge() -> void:
	var offset := Vector2(CombatFx.dodge_sprite_offset(), 0.0)
	CombatFx.spawn_afterimages(sprite, _afterimages, offset)
	_play(&"dodge")
	_after(&"dodge", 0.36, func() -> void:
		if is_instance_valid(_afterimages):
			_hide_afterimages()
	)


## 暴击特效：大爆炸粒子 + 金色刀光 + 立绘闪一下金。
func play_crit_fx() -> void:
	CombatFx.burst(_crit_fx)
	slash.visible = true
	slash.color = CombatFx.CRIT_SLASH_COLOR
	_tint(CombatFx.CRIT_TINT, 0.28, true)


## 中毒特效：红色粒子 + 立绘泛红后回白。粒子一轮结束后关掉。
func play_poison_fx() -> void:
	CombatFx.burst(_poison_fx)
	_stop_burst_later(&"poison_stop", _poison_fx)
	_tint(CombatFx.POISON_TINT, 0.35, false)


## 麻痹特效：黄色粒子 + 立绘泛黄后回白。粒子一轮结束后关掉。
func play_paralyze_fx() -> void:
	CombatFx.burst(_paralyze_fx)
	_stop_burst_later(&"paralyze_stop", _paralyze_fx)
	_tint(CombatFx.PARALYZE_TINT, 0.35, false)


## 混乱特效：头顶眩晕星转一圈就收掉，不在过期后还挂着。
func play_confuse_fx() -> void:
	_stun_fx.visible = true
	_stun_fx.rotation = 0.0
	var spin := _own(&"stun", create_tween())
	spin.tween_property(_stun_fx, "rotation", TAU, 0.8)
	spin.tween_callback(_hide_stun)


## 绝对防御：身上罩一层罩子，表示这一下百毒不侵。
func play_guard_fx() -> void:
	# 罩子先弹过头一点再收回来，像“砰”地撑开。
	_own(&"guard", CombatFx.pop_fade(_guard_fx, 0.55, 0.16, 0.28, 0.22, 1.08))
	_tint(CombatFx.GUARD_TINT, 0.32, true)


## 反弹：身前一面反光盾，再朝对手方向射出一道波。
## Visual 已按朝向翻转，局部 +x 始终朝向被反弹方。
func play_reflect_fx() -> void:
	_reflect_fx.visible = true
	_reflect_fx.position = Vector2(CombatFx.REFLECT_SHIELD_X, 0.0)
	_reflect_shield.visible = true
	_reflect_shield.modulate = Color.WHITE
	_reflect_wave.visible = true
	_reflect_wave.position = Vector2.ZERO
	_reflect_wave.modulate = Color.WHITE
	var shield_tw := _own(&"reflect", CombatFx.pop_fade(_reflect_shield, 0.55, 0.12, 0.22, 0.18, 1.12))
	shield_tw.tween_callback(_hide_reflect_if_idle)
	var wave := _own(&"reflect_wave", create_tween())
	wave.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	wave.tween_property(_reflect_wave, "position:x", CombatFx.REFLECT_WAVE_TRAVEL, 0.32)
	wave.parallel().tween_property(_reflect_wave, "modulate:a", 0.0, 0.32)
	wave.tween_callback(func() -> void:
		if is_instance_valid(_reflect_wave):
			_reflect_wave.visible = false
			_reflect_wave.modulate = Color.WHITE
			_reflect_wave.position = Vector2.ZERO
		_hide_reflect_if_idle()
	)
	_tint(CombatFx.REFLECT_TINT, 0.28, true)


## 盾和波是两条各自独立的 Tween，谁先播完都会来敲这里。
## 只有两边都收干净了才把外层容器藏起来，否则先完的那条会把还在飞的另一条一起藏掉。
func _hide_reflect_if_idle() -> void:
	if is_instance_valid(_reflect_shield) and _reflect_shield.visible:
		return
	if is_instance_valid(_reflect_wave) and _reflect_wave.visible:
		return
	if is_instance_valid(_reflect_fx):
		_reflect_fx.visible = false


## 幻影刺杀：在对方身上盖红色画了 X 的骷髅。
func play_assassinate_fx() -> void:
	_own(&"skull", CombatFx.pop_fade(_skull_fx, 0.6, 0.18, 0.45, 0.2))


## 回血特效：一次性粒子场景 + 立绘泛绿后回白。吸血和治疗共用。
func play_heal_fx() -> void:
	var fx := HEAL_FX.instantiate() as CPUParticles2D
	visual.add_child(fx)
	_heal_fx_instances.append(fx)
	fx.restart()
	fx.emitting = true
	# 粒子播完自己删掉，不然一场下来会攒一堆节点。
	# 这条计时故意不具名：两次治疗挨得近时，新的一条不能把上一个 fx 的回收计时顶掉。
	_after(&"", 0.7, func() -> void:
		_heal_fx_instances.erase(fx)
		if is_instance_valid(fx):
			fx.queue_free()
	)
	_tint(CombatFx.HEAL_TINT, 0.35, false)


## 浴火重生：脚底火焰 + 头顶凤凰。毒跳血复活也走这一套。
func play_rebirth_fx() -> void:
	_rebirth_fx.visible = true
	_rebirth_phoenix.visible = true
	CombatFx.burst(_rebirth_fire)
	_stop_burst_later(&"rebirth_fire_stop", _rebirth_fire)
	_own(&"phoenix", CombatFx.pop_fade(_rebirth_phoenix, 0.4, 0.18, 0.4, 0.28, 1.18))
	_tint(Color(1.0, 0.55, 0.2), 0.4, true)


## 立绘染色：立刻变成 from，再在 duration 内回到白。
## 具名成 tint，所以下一个特效来的时候会把上一条染色停掉，两边不会抢同一个 modulate。
func _tint(from: Color, duration: float, ease_out: bool) -> void:
	var tween := _own(&"tint", create_tween())
	if ease_out:
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sprite.modulate = from
	tween.tween_property(sprite, "modulate", Color.WHITE, duration)


## 记下一条具名 Tween，并把同名的上一条停掉。名字就是“哪种特效”。
func _own(key: StringName, tween: Tween) -> Tween:
	_kill(key)
	_tweens[key] = tween
	return tween


## 停掉并忘掉一条具名 Tween。没有这个名字就什么都不做。
func _kill(key: StringName) -> void:
	var tween: Tween = _tweens.get(key)
	if tween:
		tween.kill()
	_tweens.erase(key)


## 等 seconds 秒再做一件事。key 为空表示这条计时不具名，
## 谁也不会把它顶掉，也不会在换人时被停——用于必须跑完的收尾（比如回收粒子节点）。
func _after(key: StringName, seconds: float, action: Callable) -> Tween:
	var tween := create_tween()
	if not key.is_empty():
		_own(key, tween)
	tween.tween_interval(seconds)
	tween.tween_callback(action)
	return tween


## 把常驻视图还原成“尚未绑定角色”的场景状态并隐藏。
## battle 在下一轮直接复用同一实例，因此动态节点、动画写过的属性和特效都必须在这里收口。
func reset_view() -> void:
	anim_player.stop()
	_hide_transient_fx()
	for fx in _heal_fx_instances:
		if is_instance_valid(fx):
			fx.emitting = false
			fx.visible = false
			fx.queue_free()
	_heal_fx_instances.clear()
	NodeUtil.clear_children(buff_row)
	NodeUtil.clear_children(skill_row)
	_idle_tex = null
	_attack_tex = null
	_hurt_tex = null
	transform = _home_transform
	modulate = Color.WHITE
	visual.transform = Transform2D.IDENTITY
	visual.modulate = Color.WHITE
	visual.visible = true
	sprite.texture = null
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.flip_h = false
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.scale = Vector2(BASE_SPRITE_SCALE, BASE_SPRITE_SCALE)
	sprite.modulate = Color.WHITE
	sprite.visible = true
	ui.visible = true
	name_label.text = "—"
	hp_bar.max_value = 1.0
	hp_bar.value = 0.0
	hp_label.text = "0 / 0"
	tip_label.text = ""
	tip_panel.visible = false
	visible = false


## 测试拿它核对五种动画都建出来了。直接问 AnimationPlayer 要，
## 而不是另抄一份名字——抄的那份可以在动画库其实是空的时候照样通过。
func animation_names() -> PackedStringArray:
	return PackedStringArray(anim_player.get_animation_list())


## 当前显示身宽（像素），闪避位移按它的 1 倍算。
func displayed_body_width() -> float:
	return CombatFx.displayed_body_width(visual.scale.x)


## 含本体在内的重影个数。闪避播放后应为 3。
func dodge_ghost_count() -> int:
	var visible_ghosts := 0
	for ghost in _ghosts:
		if ghost.visible:
			visible_ghosts += 1
	return 1 + visible_ghosts


## 换人前把所有还在跑的特效收干净：具名 Tween 全停，覆盖层全收起，粒子全停喷。
func _hide_transient_fx() -> void:
	for key in _tweens.keys():
		_kill(key)
	_hide_afterimages()
	for overlay in _overlays:
		if is_instance_valid(overlay):
			overlay.visible = false
			overlay.modulate = Color.WHITE
			overlay.scale = Vector2.ONE
			overlay.rotation = 0.0
	if is_instance_valid(_reflect_shield):
		_reflect_shield.visible = true
		_reflect_shield.modulate = Color.WHITE
		_reflect_shield.scale = Vector2.ONE
	if is_instance_valid(_reflect_wave):
		_reflect_wave.visible = false
		_reflect_wave.modulate = Color.WHITE
		_reflect_wave.position = Vector2.ZERO
	for fx in _bursts:
		if is_instance_valid(fx):
			fx.emitting = false
			fx.visible = false
	slash.visible = false
	slash.position = Vector2.ZERO
	slash.rotation = 0.0
	slash.scale = Vector2.ONE
	slash.modulate = Color.WHITE
	slash.color = CombatFx.SLASH_COLOR
	sprite.modulate = Color.WHITE


## 重影是场景内固定的两张 Ghost 精灵；收起时只清运行时贴图和变换，不删节点。
func _hide_afterimages() -> void:
	for i in _ghosts.size():
		var ghost := _ghosts[i]
		ghost.visible = false
		ghost.texture = null
		ghost.flip_h = false
		ghost.position = Vector2.ZERO
		ghost.rotation = 0.0
		ghost.scale = Vector2.ONE
		ghost.modulate = Color(1.0, 1.0, 1.0, CombatFx.ghost_alpha(i))


## 眩晕星转完一圈就收起来，并把角度归零。
## 不归零的话下次再晕会从上次停下的角度接着转，看起来像卡住了。
func _hide_stun() -> void:
	if is_instance_valid(_stun_fx):
		_stun_fx.visible = false
		_stun_fx.rotation = 0.0


## 一次性爆发播完就停喷，下一轮再 restart。
func _stop_burst_later(key: StringName, particles: CPUParticles2D) -> void:
	_after(key, particles.lifetime, func() -> void:
		if is_instance_valid(particles):
			particles.emitting = false
			particles.visible = false
	)
