class_name RankingAggregator
extends RefCounted

## 把 v2 看板 `data.ranking` 的逻辑用户桶映成当日排行榜。
##
## 服务端已经按 LOGICAL_DEVICE 聚合、按 TOTAL_TOKENS 降序排好。
## 这里不再读设备 × 渠道明细，只把桶上的展示名、十进制 token、渠道码写成 RankedUser。


## ranking 是 data.ranking 数组。非对象、缺名字的桶跳过；名次按战力降序从 1 起。
static func rank_users(ranking: Array) -> Array[RankedUser]:
	var users: Array[RankedUser] = []
	for raw_row in ranking:
		if typeof(raw_row) != TYPE_DICTIONARY:
			continue
		var bucket: Dictionary = raw_row
		var key_raw: Variant = bucket.get("key", {})
		if typeof(key_raw) != TYPE_DICTIONARY:
			continue
		var key: Dictionary = key_raw
		var username := str(key.get("logicalDeviceName", "")).strip_edges()
		if username.is_empty():
			continue
		var metrics_raw: Variant = bucket.get("metrics", {})
		var metrics: Dictionary = metrics_raw if typeof(metrics_raw) == TYPE_DICTIONARY else {}
		var user := RankedUser.new()
		user.username = username
		user.tokens = _to_tokens(metrics.get("totalTokens", 0))
		user.channels = _channels_from(bucket.get("channels", []))
		user.channel = user.channels[0] if user.channels.size() > 0 else ""
		user.agent_name = AgentChannels.agent_display_name(user.channel)
		user.agents = _agent_list(user.channels)
		users.append(user)

	users.sort_custom(func(a: RankedUser, b: RankedUser) -> bool: return a.tokens > b.tokens)
	var rank := 1
	for user in users:
		user.rank = rank
		rank += 1
	return users


## totalTokens 是十进制字符串，避免 JS 安全整数截断。null / 空 / 非法按 0。
static func _to_tokens(raw: Variant) -> int:
	if raw == null:
		return 0
	if typeof(raw) == TYPE_INT:
		return maxi(0, int(raw))
	var text := str(raw).strip_edges()
	if text.is_empty() or not text.is_valid_int():
		return 0
	return maxi(0, int(text))


## 看板 channels 已按渠道码升序。空项丢掉，重复项只留第一次。
static func _channels_from(raw: Variant) -> PackedStringArray:
	var ordered := PackedStringArray()
	if typeof(raw) != TYPE_ARRAY:
		return ordered
	for item in raw:
		var channel := str(item).strip_edges()
		if channel.is_empty() or channel in ordered:
			continue
		ordered.append(channel)
	return ordered


## 渠道列表对应的展示名，去重后保持原顺序。
static func _agent_list(channels: PackedStringArray) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for channel in channels:
		var display := AgentChannels.agent_display_name(channel)
		if not display in names:
			names.append(display)
	return names
