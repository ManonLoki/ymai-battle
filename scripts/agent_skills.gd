class_name AgentSkills
extends RefCounted

## 服务端 channel 标识与展示名的对照表。channel 同时决定角色拿到哪种专属 buff。

const CHANNEL_CODEX := "openai.codex"
const CHANNEL_CLAUDE := "anthropic.claude"
const CHANNEL_GROK := "xai.grok"
const CHANNEL_WORKBUDDY := "workbuddy.workbuddy"

const AGENT_NAMES := {
	CHANNEL_CODEX: "CODEX",
	CHANNEL_CLAUDE: "CLAUDE CODE",
	CHANNEL_GROK: "GROK",
	CHANNEL_WORKBUDDY: "WORKBUDDY",
}


## 未收录的 channel 原样返回，排行榜上不至于出现空白。
static func agent_display_name(channel: String) -> String:
	return String(AGENT_NAMES.get(channel, channel))
