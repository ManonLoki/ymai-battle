#!/usr/bin/env python3
"""把 Android 预设里的关键项强制写回 export_presets.cfg。

Godot 每次导出结束会重写这个文件，实测会把包名、架构、leanback、过滤器
这些手改过的值刷回模板默认（还出现过凭空多写一份同名预设）。
所以不指望手改能留住，改成每次构建前由脚本对齐一次。
"""
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg"

WANTED = {
    "include_filter": '"*.png,*.woff2,*.ogg,*.wav"',
    # 非运行时资源一律挡在包外：导出产物、文档、测试脚本，以及测试每轮
    # 生成的 assets/characters 预览图（只给人肉看和 bake_chrome 用，运行时
    # 的立绘是 SpriteFactory 现画的）。
    "exclude_filter": '"Release/*,docs/*,tests/*,assets/characters/*"',
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

# 找到 Android 预设的区间：从 [preset.N] 段里 platform="Android" 的那个，
# 一直到下一个 [preset.M]（不含 .options 子段）为止。
starts = [i for i, l in enumerate(lines) if re.fullmatch(r"\[preset\.\d+\]", l)]
if not starts:
    sys.exit("export_presets.cfg 里没有任何预设")
bounds = []
for n, i in enumerate(starts):
    end = starts[n + 1] if n + 1 < len(starts) else len(lines)
    bounds.append((i, end))
target = None
for i, end in bounds:
    if any(l.strip() == 'platform="Android"' for l in lines[i:end]):
        if target is not None:
            sys.exit("export_presets.cfg 里有不止一个 Android 预设，先手动删掉多余的")
        target = (i, end)
if target is None:
    sys.exit("export_presets.cfg 里找不到 Android 预设")

start, end = target
changed = []
seen = set()
for i in range(start, end):
    key = lines[i].split("=", 1)[0] if "=" in lines[i] else None
    if key in WANTED:
        seen.add(key)
        if lines[i] != "%s=%s" % (key, WANTED[key]):
            changed.append(key)
            lines[i] = "%s=%s" % (key, WANTED[key])

missing = [k for k in WANTED if k not in seen]
if missing:
    # 缺的键补在 .options 段末尾（也就是该预设区间的最后一行非空行之后）。
    tail = end
    while tail > start and lines[tail - 1].strip() == "":
        tail -= 1
    for k in missing:
        lines.insert(tail, "%s=%s" % (k, WANTED[k]))
        tail += 1
    changed += missing

open(PATH, "w", encoding="utf-8").write("\n".join(lines))
print("预设已对齐" + ("（修正 %d 项：%s）" % (len(changed), ", ".join(changed)) if changed else "（无需改动）"))
