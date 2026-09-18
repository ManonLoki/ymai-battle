class_name RankedUser
extends RefCounted

## 排行榜上的一名逻辑玩家：同一个 username 在所有设备、所有渠道上的当日汇总。
##
## 纯数据容器，由 RankingAggregator 填好后交给排行榜界面和 Fighter.from_ranked。

## 名次，从 1 开始；由 RankingAggregator 按 tokens 降序排完再写入。
var rank: int = 0
## 玩家名，也是跨设备归并的唯一键。
var username: String = ""
## 跨设备、跨渠道聚合后的 token 总量，同时就是战力。
var tokens: int = 0
## 用量最高的渠道，排行榜用它显示主 agent。
var channel: String = ""
## channel 对应的展示名，例如 "CLAUDE CODE"。
var agent_name: String = ""
## 当天用过的全部渠道，按用量从高到低。每个渠道都会换来一个独立的 buff。
var channels: PackedStringArray = PackedStringArray()
## channels 对应的展示名。
var agents: PackedStringArray = PackedStringArray()
