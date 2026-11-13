#!/usr/bin/env bash
# 分段安装会话：绕开 BBK 定制框架钩住的 `pm install` / runinstall。
#
# 背景：定制安装器把 PackageInstallerActivity 的安装按钮隐藏；命令行安装
# 走到 PackageManagerShellCommand: runinstall getRemoteUsbState →
# BBKCustomizedDelegate 时，若白名单服务不可用会静默退出（exit 255 无输出）。
# install-create / install-write 未被钩子拦截；install-commit 仍可能返回 255，
# 但 PMS 往往已异步完成安装 —— 绝不能以 exit code 判断成败。
#
# 用法：
#   ./install_bypass.sh app.apk [包名] [-s 设备序列号]
# 例：
#   ./install_bypass.sh jianpian.apk com.lianli.yxq
#
# 环境：需要 adb；Git Bash 下自动设置 MSYS_NO_PATHCONV=1。

set -u
export MSYS_NO_PATHCONV=1

APK="${1:-}"
PKG="${2:-}"
DEV=""
if [ "${3:-}" = "-s" ]; then DEV="-s ${4:-}"; fi

ADB="${S6_ADB:-adb}"
TMP_DEV="/data/local/tmp/s6_install_bypass.apk"

fail() { echo "[错误] $*" >&2; exit 1; }

[ -n "$APK" ] || fail "用法: $0 <apk路径> [包名] [-s 设备序列号]"
[ -f "$APK" ] || fail "找不到 APK：$APK"

# stat 兼容 Linux / macOS
SIZE=$(stat -c %s "$APK" 2>/dev/null || stat -f%z "$APK" 2>/dev/null)
[ -n "$SIZE" ] && [ "$SIZE" -gt 0 ] || fail "无法取得 APK 字节数"
echo "=== APK: $APK ($SIZE 字节) ==="

# 设备在线检查
# shellcheck disable=SC2086
$ADB $DEV devices | grep -qw "device" || \
  $ADB $DEV devices | grep -qw "recovery" || \
  fail "没有在线设备，先执行 adb devices 确认"

echo "=== [1/4] 推送暂存 ==="
# shellcheck disable=SC2086
$ADB $DEV push "$APK" "$TMP_DEV" || fail "push 失败"
# shellcheck disable=SC2086
DEV_SIZE=$($ADB $DEV shell "stat -c %s $TMP_DEV" 2>/dev/null | tr -d '\r')
[ "$DEV_SIZE" = "$SIZE" ] || fail "设备端字节数不符：$DEV_SIZE != $SIZE"

echo "=== [2/4] 创建安装会话 ==="
# shellcheck disable=SC2086
OUT=$($ADB $DEV shell "pm install-create -r -S $SIZE" 2>&1)
echo "$OUT"
SID=$(echo "$OUT" | grep -oE '[0-9]+' | tail -1)
[ -n "$SID" ] || fail "未取得 session id"

echo "=== [3/4] 写入并提交（session=$SID）==="
# shellcheck disable=SC2086
$ADB $DEV shell "pm install-write -S $SIZE $SID base $TMP_DEV" || \
  echo "[警告] install-write 返回非零，继续复核"
# shellcheck disable=SC2086
$ADB $DEV shell "pm install-commit $SID" || \
  echo "[警告] install-commit 返回非零（本机常见），以包状态为准"

echo "=== [4/4] 复核（不看返回码，看真实结果）==="
if [ -n "$PKG" ]; then
  # shellcheck disable=SC2086
  echo "-- pm list packages: $($ADB $DEV shell "pm list packages $PKG" | tr -d '\r')"
  # shellcheck disable=SC2086
  echo "-- pm path:          $($ADB $DEV shell "pm path $PKG" | tr -d '\r')"
  # shellcheck disable=SC2086
  echo "-- 是否被禁用:        $($ADB $DEV shell "pm list packages -d $PKG" | tr -d '\r')"
else
  echo "[提示] 未传包名，跳过精确复核；请手动执行 pm list packages -3"
fi
# shellcheck disable=SC2086
$ADB $DEV shell "logcat -d -t 400" 2>/dev/null | \
  grep -E "New package installed|Integrity check passed|Running dexopt" | tail -10 || true

# shellcheck disable=SC2086
$ADB $DEV shell "rm -f $TMP_DEV" 2>/dev/null || true
echo "=== 完成。若包未出现，改用 Magisk 模块预置通道（见 SKILL.md 流程二）==="
