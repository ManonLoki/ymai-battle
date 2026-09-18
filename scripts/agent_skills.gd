class_name AgentSkills
extends RefCounted

## 服务端 channel 标识与展示名的对照表。channel 同时决定角色拿到哪种专属 buff。
##
## 这里只管“怎么显示”，具体每个 channel 换成什么数值的 buff 在 SkillCatalog 里。

# 服务端下发的 channel 原始字符串，四个 agent 各一个。
const CHANNEL_CODEX := "openai.codex"
const CHANNEL_CLAUDE := "anthropic.claude"
const CHANNEL_GROK := "xai.grok"
const CHANNEL_WORKBUDDY := "workbuddy.workbuddy"

## channel → 界面上显示的名字。
const AGENT_NAMES := {
	CHANNEL_CODEX: "CODEX",
	CHANNEL_CLAUDE: "CLAUDE CODE",
	CHANNEL_GROK: "GROK",
	CHANNEL_WORKBUDDY: "WORKBUDDY",
}


## 未收录的 channel 原样返回，排行榜上不至于出现空白。
static func agent_display_name(channel: String) -> String:
	return String(AGENT_NAMES.get(channel, channel))
