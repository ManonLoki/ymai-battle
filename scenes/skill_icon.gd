class_name SkillIcon
extends TextureRect

## 角色头上 buff / 技能行里的一个图标格子。
##
## 边长、最近邻采样、鼠标形状都在 skill_icon.tscn 里摆好。
## 悬停说明面板是整个 FighterView 共用的一块，所以这里只发信号报告“鼠标进/出了我”，
## 由 FighterView 决定面板挪到哪、写什么。

## 鼠标移到这个格子上。带上自己，方便调用方把面板摆到正下方。
signal hovered(icon: Control, skill: SkillDef)
signal unhovered

var _skill: SkillDef


func _ready() -> void:
	mouse_entered.connect(func() -> void: hovered.emit(self, _skill))
	mouse_exited.connect(func() -> void: unhovered.emit())


## 装上一条技能 / buff。先 add_child 再调它。
func bind(skill: SkillDef) -> void:
	_skill = skill
	texture = SkillCatalog.load_icon(skill.icon_id)
