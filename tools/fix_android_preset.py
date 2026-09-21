#!/usr/bin/env python3
"""把导出预设里的关键项强制写回 export_presets.cfg。

Godot 每次导出结束会重写这个文件，实测会把包名、架构、leanback、过滤器
这些手改过的值刷回模板默认（还出现过凭空多写一份同名预设）。
所以不指望手改能留住，改成每次构建前由脚本对齐一次。

两类键分开处理：

* SHARED —— 「什么进包、什么不进包」这条策略，**四个预设必须完全一致**。
  以前只有 Android 排除了 docs / tests / assets/characters，结果 Windows、
  macOS、Web 的包里一直躺着 192 张角色检视图；`include_filter` 里的 `*.png`
  还会主动把 docs 下的截图也拉进去。策略写在一处、套到所有预设，才不会再次走散。
* ANDROID_ONLY —— 包名、架构、签名这些只有 Android 有的键。

跑法：python3 tools/fix_android_preset.py [export_presets.cfg]
任何一次导出之前都该跑，不只是 Android。
"""
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg"

# 四个预设共用的打包策略。**这是唯一一份**，改哪些东西进包只改这里。
SHARED = {
    # include_filter 会把 Godot 不认识的原始文件也**主动拉进**包里。
    # 这里要 *.png 是为了图标和光标，但它同时会捞走 docs 下的截图，
    # 所以下面那条排除必须跟着一起维护，两者是一对。
    "include_filter": '"*.png,*.woff2,*.ogg,*.wav"',
    # 非运行时资源一律挡在包外：导出产物、文档（含 archify 出的图和它的
    # 校验截图）、测试脚本，以及测试每轮生成的 assets/characters 预览图
    # （只给人肉看和 bake_chrome 用，运行时的立绘是 SpriteFactory 现画的）。
    # 注意每一项都要带 /*：写成 "docs/" 是匹配不上的，Web 预设以前就是这么漏的。
    "exclude_filter": '"Release/*,docs/*,tests/*,assets/characters/*"',
}

ANDROID_ONLY = {
    "architectures/armeabi-v7a": "true",
    "architectures/arm64-v8a": "true",
    "gradle_build/use_gradle_build": "true",
    "gradle_build/compress_native_libraries": "true",
    "package/unique_name": '"com.ymai.battle"',
    "package/show_in_android_tv": "true",
    "screen/immersive_mode": "true",
    "permissions/internet": "true",
    "permissions/access_network_state": "true",
    "permissions/wake_lock": "true",
    "keystore/release": '"android/ymai-release.keystore"',
    "keystore/release_user": '"ymai"',
}

lines = open(PATH, encoding="utf-8").read().split("\n")

# 切出每个预设的区间：[preset.N] 到下一个 [preset.M] 之间（含它的 .options 子段）。
starts = [i for i, l in enumerate(lines) if re.fullmatch(r"\[preset\.\d+\]", l)]
if not starts:
    sys.exit("export_presets.cfg 里没有任何预设")
bounds = [(i, starts[n + 1] if n + 1 < len(starts) else len(lines)) for n, i in enumerate(starts)]


def preset_name(start, end):
    """预设区间里的 name="..."，只用于打日志。"""
    for line in lines[start:end]:
        if line.startswith("name="):
            return line[len("name="):].strip('"')
    return "?"


def align(start, end, wanted):
    """把 wanted 里的键强制写成期望值；缺的补在区间末尾。返回改动过的键名。"""
    changed = []
    seen = set()
    for i in range(start, end):
        key = lines[i].split("=", 1)[0] if "=" in lines[i] else None
        if key in wanted:
            seen.add(key)
            if lines[i] != "%s=%s" % (key, wanted[key]):
                changed.append(key)
                lines[i] = "%s=%s" % (key, wanted[key])
    missing = [k for k in wanted if k not in seen]
    if missing:
        # 缺的键补在该预设区间最后一行非空行之后。
        tail = end
        while tail > start and lines[tail - 1].strip() == "":
            tail -= 1
        for k in missing:
            lines.insert(tail, "%s=%s" % (k, wanted[k]))
            tail += 1
        changed += missing
    return changed


# 先找 Android，顺带守住“只能有一个”这条——重复预设是 Godot 出过的老毛病。
android = None
for start, end in bounds:
    if any(l.strip() == 'platform="Android"' for l in lines[start:end]):
        if android is not None:
            sys.exit("export_presets.cfg 里有不止一个 Android 预设，先手动删掉多余的")
        android = (start, end)
if android is None:
    sys.exit("export_presets.cfg 里找不到 Android 预设")

report = []
# 插入会让后面的行号整体后移，所以从后往前对齐，前面区间的边界才不会失效。
for start, end in reversed(bounds):
    wanted = dict(SHARED)
    if (start, end) == android:
        wanted.update(ANDROID_ONLY)
    changed = align(start, end, wanted)
    if changed:
        report.append("%s：%s" % (preset_name(start, end), ", ".join(changed)))

open(PATH, "w", encoding="utf-8").write("\n".join(lines))
if report:
    print("预设已对齐（%d 个有改动）" % len(report))
    for line in reversed(report):
        print("  " + line)
else:
    print("预设已对齐（无需改动）")
