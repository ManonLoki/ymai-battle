#!/usr/bin/env bash
# 打 Android / Android TV 发布包。
#
# 签名密码不写进 export_presets.cfg（那个文件是要跟着项目走的），
# 而是从 android/keystore.properties 读出来，用 Godot 认的环境变量临时注入。
# 用法：tools/build_android.sh [输出路径]
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROPS="$PROJECT_DIR/android/keystore.properties"
OUT="${1:-$PROJECT_DIR/Release/Android/YMAIBattle.apk}"

if [[ ! -f "$PROPS" ]]; then
	echo "缺少 $PROPS —— 发布签名 key 的位置和密码都记在那里" >&2
	exit 1
fi

prop() { grep -E "^$1=" "$PROPS" | head -n 1 | cut -d= -f2-; }

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PROJECT_DIR/$(prop storeFile)"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$(prop storeAlias)"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(prop storePassword)"

EXTRA=()  # macOS 自带的 bash 3.2 下，空数组展开会被 set -u 判成未定义，见下面的 ${EXTRA[@]+...}
# Android TV 的 leanback 入口只有 Gradle 自定义构建才会写进清单，
# 而自定义构建要先把模板装进 android/build。第一次构建（或升级 Godot 后）带上：
#   INSTALL_BUILD_TEMPLATE=1 tools/build_android.sh
if [[ "${INSTALL_BUILD_TEMPLATE:-0}" == "1" ]]; then
	EXTRA+=(--install-android-build-template)
fi

# Godot 会在导出后重写 export_presets.cfg，把手改过的值刷回默认，所以每次先对齐。
python3 "$PROJECT_DIR/tools/fix_android_preset.py" "$PROJECT_DIR/export_presets.cfg"

mkdir -p "$(dirname "$OUT")"
"$GODOT" --headless --path "$PROJECT_DIR" ${EXTRA[@]+"${EXTRA[@]}"} --export-release "Android" "$OUT"
echo "APK: $OUT"
