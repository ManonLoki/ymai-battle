class_name RankedUser
extends RefCounted

## 排行榜上的一名逻辑玩家：同一个 username 在所有设备、所有渠道上的当日汇总。

var rank: int = 0
var username: String = ""
## 跨设备、跨渠道聚合后的 token 总量，同时就是战力。
var tokens: int = 0
## 用量最高的渠道，排行榜用它显示主 agent。
var channel: String = ""
var agent_name: String = ""
## 当天用过的全部渠道，按用量从高到低。每个渠道都会换来一个独立的 buff。
var channels: PackedStringArray = PackedStringArray()
## channels 对应的展示名。
var agents: PackedStringArray = PackedStringArray()
