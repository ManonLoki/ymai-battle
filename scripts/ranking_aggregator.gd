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
	# username -> {username, tokens, channels: {channel -> tokens}}
	var by_user: Dictionary = {}
	for raw_row in channel_usage:
		# 服务端偶尔会混进非对象元素，跳过而不是让整份榜单崩掉。
		if typeof(raw_row) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw_row
		# 只要当天的流水，历史数据一律不进榜。
		if str(row.get("date", "")) != date:
			continue
		var username := str(row.get("username", ""))
		# 没名字的行认不出是谁，丢掉。
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
		# 总量累加：这一步就是跨设备、跨渠道的归并。
		rec["tokens"] = int(rec["tokens"]) + gained
		# 同时按渠道分别记一份，后面要按用量给渠道排序。
		var channel := str(row.get("channel", ""))
		var per_channel: Dictionary = rec["channels"]
		per_channel[channel] = int(per_channel.get(channel, 0)) + gained

	# 聚合结果转成 RankedUser。
	var users: Array[RankedUser] = []
	for rec_raw in by_user.values():
		var rec: Dictionary = rec_raw
		var user := RankedUser.new()
		user.username = str(rec["username"])
		user.tokens = int(rec["tokens"])
		user.channels = _channels_by_usage(rec["channels"])
		# 排第一的渠道就是主渠道；一个渠道都没有时留空。
		user.channel = user.channels[0] if user.channels.size() > 0 else ""
		user.agent_name = AgentChannels.agent_display_name(user.channel)
		user.agents = _agent_list(user.channels)
		users.append(user)

	# token 多的在前，然后从 1 开始编名次。
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
	# 字典没法直接排序，先摊成数组。
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
		var display := AgentChannels.agent_display_name(channel)
		# 两个不同 channel 可能映射到同一个展示名，去重免得榜上重复。
		if not display in names:
			names.append(display)
	return names
