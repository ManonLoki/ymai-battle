# 设计拆解图

`docs/architecture.html` 是一张总览。这里是按关注点拆细的七张，每张都能单独打开
（自带主题切换、搜索、聚焦、导出，不依赖网络）。

图的内容都对着仓库里的真实代码写，不是示意。改了对应实现记得回来改图。

| 图 | 讲什么 | 对应代码 |
|---|---|---|
| [榜单数据链路](ranking-pipeline.html) | 看板 JSON 怎么一路变成角色血量 | `token_usage_api.gd` · `ranking_aggregator.gd` · `ranked_user.gd` |
| [一次出手的判定阶梯](strike-resolution.html) | 中毒到还手，十几道判定的先后顺序和互斥关系 | `combat_resolver.gd` |
| [车轮战的一生](wheel-war.html) | 开场定型、换人、两种终局 | `wheel_war.gd` · `skill_grant.gd` |
| [一条战报事件怎么被演出来](playback.html) | 判定和演出如何分成两拍 | `battle.gd` · `fighter_view.gd` · `combat_sfx.gd` |
| [界面是怎么拼出来的](ui-composition.html) | 全局主题 + 三个可复用的行场景 | `ui_theme.tres` · `theme_helper.gd` · `*_row.tscn` |
| [本地存档](local-storage.html) | 两份 JSON 的读写策略和跨天作废 | `json_store.gd` · `round_record.gd` · `day_clock.gd` |
| [网页参数接管一次会话](web-launch-config.html) | URL 参数怎么进来、怎么被当成不可信输入 | `web_launch_config.gd` |

## 怎么改

每张图的源是同名 `.json`（`<名字>.<类型>.json`），用 archify 重新生成：

```bash
# 校验（showcase 档会连排版一起查）
node <archify>/bin/archify.mjs validate <类型> docs/diagrams/<源>.json --quality showcase

# 生成 HTML
node <archify>/bin/archify.mjs deliver <类型> docs/diagrams/<源>.json docs/diagrams/<名字>.html --quality showcase
```

`ui-composition` 那张在组件上标了源码路径，所以两条命令都要加
`--repo-root .`，archify 会核对这些文件真的存在。

生成完可以再跑一次 `visual-check <名字>.html` 拿浏览器实测证据。它会在旁边落一堆
`*.visual-check.*` 截图和 receipt——那些是可随时重生成的中间产物，已经在 `.gitignore` 里。
