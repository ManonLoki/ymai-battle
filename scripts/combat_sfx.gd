class_name CombatSfx
extends RefCounted

## 战斗音效只此五条，按 StrikeResult 现成字段组合，不按技能各做一条。
## 例如吸血 = 命中+回血，凌波微步 = 闪避那一下 dodge、反击那一下 hit。

const HIT := "hit"
const DODGE := "dodge"
const GUARD := "guard"
const HEAL := "heal"
const REBIRTH := "rebirth"

const CLIP_PATHS := {
	HIT: "res://assets/audio/se_hit.wav",
	DODGE: "res://assets/audio/se_dodge.wav",
	GUARD: "res://assets/audio/se_guard.wav",
	HEAL: "res://assets/audio/se_heal.wav",
	REBIRTH: "res://assets/audio/se_rebirth.wav",
}

## 最近一次 play_event 实际点名的片段，headless 测组合不测扬声器。
static var last_clips: PackedStringArray = PackedStringArray()
## 从上次 reset 起点过的每一批片段，按顺序攒着。
## 测「一次连击到底响了几下、分别是什么」要看整串，只看最后一批看不出来。
static var history: Array[PackedStringArray] = []


## 把点名记录清空。每个用例开头调一次，免得读到上一个用例留下的声音。
static func reset() -> void:
	last_clips = PackedStringArray()
	history.clear()


## 一条战斗事件该响哪几声。
##
## 下面是一道**优先级阶梯**，从上往下第一个对上的就定了：因为一次行动在听感上
## 只有一件事最该被听见——被闪开了就是「唰」，被挡住了就是「铛」，
## 至于这一下本来想打多少伤害，耳朵是分不出来的。
##
## 所以前半段每个分支都直接 return（互斥），只有最后一段允许叠：
## 真的打中了，才可能同时听到「命中 + 回血」（吸血）或「命中 + 重生」（打死又爬起来）。
static func clips_for(event: StrikeResult) -> PackedStringArray:
	var clips := PackedStringArray()
	if event == null:
		return clips
	# 反弹宣告、麻痹跳过没有对应的五条之一。
	# 反弹那一下只是「宣告弹回去了」，真正的响声落在随后那条命中事件上，这里先不出声。
	if event.reflected and not event.hit:
		return clips
	if event.skip_reason == StrikeResult.SKIP_PARALYZE:
		return clips
	if event.skip_reason == StrikeResult.SKIP_HEAL:
		clips.append(HEAL)
		return clips
	# 毒跳血不是挥击；浴火重生仍走重生音。
	if event.poison_tick:
		if event.revived:
			clips.append(REBIRTH)
		return clips
	if event.dodged or event.lingbo:
		clips.append(DODGE)
		return clips
	if event.guarded:
		clips.append(GUARD)
		return clips
	# 到这里说明是一次正常挥击。以下三条可以同时成立，依次叠着响：
	# 砍中一下、这一下顺带回了血（吸血/治疗）、挨打的那位当场爬了起来。
	if event.hit:
		clips.append(HIT)
	if event.heal_amount > 0 or event.lifesteal or event.treated:
		clips.append(HEAL)
	if event.revived:
		clips.append(REBIRTH)
	return clips


## 播一条事件的声音，并把这次点名记进 last_clips / history。
##
## 记录在前、播放在后，而且没有播放器也照记：headless 测试跑的是哑音频驱动，
## 场上根本没有 CombatSfxPool 这个 autoload，但「这一下该响什么」的判断照样要能验。
static func play_event(event: StrikeResult) -> void:
	last_clips = clips_for(event)
	history.append(last_clips.duplicate())
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# 按 autoload 的节点名去场景树上找池子。这里刻意不 preload 那个脚本：
	# 音效判定是纯逻辑，不该为了发声反过来依赖一个必须挂在树上的节点。
	var pool := tree.root.get_node_or_null("CombatSfxPool")
	if pool != null:
		pool.play_clips(last_clips)
