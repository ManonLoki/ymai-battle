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
static var history: Array[PackedStringArray] = []


static func reset() -> void:
	last_clips = PackedStringArray()
	history.clear()


static func clips_for(event: StrikeResult) -> PackedStringArray:
	var clips := PackedStringArray()
	if event == null:
		return clips
	# 反弹宣告、麻痹跳过没有对应的五条之一。
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
	if event.hit:
		clips.append(HIT)
	if event.heal_amount > 0 or event.lifesteal or event.treated:
		clips.append(HEAL)
	if event.revived:
		clips.append(REBIRTH)
	return clips


static func play_event(event: StrikeResult) -> void:
	last_clips = clips_for(event)
	history.append(last_clips.duplicate())
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var pool := tree.root.get_node_or_null("CombatSfxPool")
	if pool != null:
		pool.play_clips(last_clips)
	var music := tree.root.get_node_or_null("MusicManager")
	if music != null:
		music.keep_alive()
		music.call_deferred("keep_alive")
