class_name RankedUser
extends RefCounted

## 排行榜上的一名逻辑玩家：服务端 LOGICAL_DEVICE 桶已经按逻辑用户聚合。
##
## 纯数据容器，由 RankingAggregator 填好后交给排行榜界面和 Fighter.from_ranked。

## 名次，从 1 开始；由 RankingAggregator 按 tokens 降序排完再写入。
var rank: int = 0
## 玩家名，来自看板 key.logicalDeviceName。
var username: String = ""
## 战力，来自 metrics.totalTokens 十进制字符串。
var tokens: int = 0
## 主 agent 渠道，取 channels 的第一项（看板按渠道码升序）。
var channel: String = ""
## channel 对应的展示名，例如 "CLAUDE CODE"。
var agent_name: String = ""
## 当天贡献过的渠道，顺序与看板一致。每个渠道都会换来一个独立的 buff。
var channels: PackedStringArray = PackedStringArray()
## channels 对应的展示名。
var agents: PackedStringArray = PackedStringArray()
