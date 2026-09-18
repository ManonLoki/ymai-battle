class_name RankingAggregator
extends RefCounted

## 把服务端 /api/v1/token-usage 的 channelUsage 明细压成当日排行榜。
##
## 接口返回的是「设备 × 渠道 × 日期」的流水：同一个人换台机器、换个 agent
## 就会拆成好几行。榜上要显示的是**逻辑玩家**，所以这里一律按 username 归并，
## token 也是跨设备、跨渠道**聚合之后**的总量。
## deviceId / deviceName 只是服务端的去重键，游戏里任何地方都不读。


## 只取指定日期的流水，按 username 聚合后从高到低排名（rank 从 1 开始）。
static func rank_users(channel_usage: Array, date: String) -> Array[RankedUser]:
	var by_user: Dictionary = {}
	for raw_row in channel_usage:
		if typeof(raw_row) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw_row
		if str(row.get("date", "")) != date:
			continue
		var username := str(row.get("username", ""))
		if username.is_empty():
			continue
		if not by_user.has(username):
			by_user[username] = {
				"username": username,
				"tokens": 0,
				"channels": {},
			}
		var rec: Dictionary = by_user[username]
		var gained := _to_tokens(row.get("totalTokens", 0))
		rec["tokens"] = int(rec["tokens"]) + gained
		var channel := str(row.get("channel", ""))
		var per_channel: Dictionary = rec["channels"]
		per_channel[channel] = int(per_channel.get(channel, 0)) + gained

	var users: Array[RankedUser] = []
	for rec_raw in by_user.values():
		var rec: Dictionary = rec_raw
		var user := RankedUser.new()
		user.username = str(rec["username"])
		user.tokens = int(rec["tokens"])
		user.channels = _channels_by_usage(rec["channels"])
		user.channel = user.channels[0] if user.channels.size() > 0 else ""
		user.agent_name = AgentSkills.agent_display_name(user.channel)
		user.agents = _agent_list(user.channels)
		users.append(user)

	users.sort_custom(func(a: RankedUser, b: RankedUser) -> bool: return a.tokens > b.tokens)
	var rank := 1
	for user in users:
		user.rank = rank
		rank += 1
	return users


## totalTokens 允许为 null（当天有记录但没产生用量），按 0 计。
static func _to_tokens(raw: Variant) -> int:
	return 0 if raw == null else int(raw)


## 这名玩家当天用过的渠道，按用量从高到低。排在第一的是主渠道。
static func _channels_by_usage(channels: Dictionary) -> PackedStringArray:
	var items: Array = []
	for channel in channels.keys():
		items.append({"channel": str(channel), "tokens": int(channels[channel])})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tokens"]) > int(b["tokens"]))
	var ordered: PackedStringArray = PackedStringArray()
	for item in items:
		ordered.append(str(item["channel"]))
	return ordered


## 渠道列表对应的展示名，去重后保持原顺序。
static func _agent_list(channels: PackedStringArray) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for channel in channels:
		var display := AgentSkills.agent_display_name(channel)
		if not display in names:
			names.append(display)
	return names
