#!/usr/bin/env bash
# BBK S6 改造后的一键验收采集（只读 + 一张截图）。
#
# 用法： ./verify.sh [输出目录] [-s 设备序列号]
# 默认用 -d 指定唯一 USB 设备；网络 adb 用 -s <IP>:5555。
# 不修改设备任何文件（只按 HOME、截屏、读属性）。

set -u
export MSYS_NO_PATHCONV=1

OUT="${1:-./s6_verify}"
DEV="-d"
if [ "${2:-}" = "-s" ]; then DEV="-s ${3:-}"; fi
ADB="${S6_ADB:-adb}"

mkdir -p "$OUT" || exit 1
# shellcheck disable=SC2086
run() { timeout 25 $ADB $DEV shell "$1" 2>&1 | tr -d '\r'; }

echo "=== 设备 ===" | tee "$OUT/report.txt"
# shellcheck disable=SC2086
timeout 20 $ADB $DEV devices -l 2>&1 | tee -a "$OUT/report.txt"

echo "" | tee -a "$OUT/report.txt"
echo "=== 应用与版本 ===" | tee -a "$OUT/report.txt"
for P in com.tencent.workbuddy.app com.ss.android.ugc.aweme com.topjohnwu.magisk; do
  echo "-- $P" | tee -a "$OUT/report.txt"
  # shellcheck disable=SC2086
  timeout 25 $ADB $DEV shell "dumpsys package $P | grep -E 'versionName|codePath|^    Package'" 2>&1 | \
    tr -d '\r' | head -5 | tee -a "$OUT/report.txt"
done

echo "" | tee -a "$OUT/report.txt"
echo "=== 桌面 ===" | tee -a "$OUT/report.txt"
run "input keyevent 3" >/dev/null
sleep 2
# shellcheck disable=SC2086
timeout 30 $ADB $DEV exec-out screencap -p > "$OUT/home.png" 2>/dev/null
echo "截图: $OUT/home.png ($(wc -c < "$OUT/home.png") 字节)" | tee -a "$OUT/report.txt"

echo "" | tee -a "$OUT/report.txt"
echo "=== 网络与 ADB 属性 ===" | tee -a "$OUT/report.txt"
run "ip addr show wlan0 | grep 'inet '" | tee -a "$OUT/report.txt"
for K in persist.adb.tcp.port ro.adb.secure sys.usb.config; do
  echo "-- $K = $(run "getprop $K")" | tee -a "$OUT/report.txt"
done

echo "" | tee -a "$OUT/report.txt"
echo "=== ADB 稳定性（6 次）===" | tee -a "$OUT/report.txt"
OK=0
for i in 1 2 3 4 5 6; do
  R=$(run "getprop sys.boot_completed")
  echo "  #$i -> $R" | tee -a "$OUT/report.txt"
  [ "$R" = "1" ] && OK=$((OK+1))
  sleep 2
done
echo "稳定: $OK/6" | tee -a "$OUT/report.txt"

echo "" | tee -a "$OUT/report.txt"
echo "=== 人工核对项 ===" | tee -a "$OUT/report.txt"
echo "  1. 打开 home.png，确认无学科大卡片、无空白占位框" | tee -a "$OUT/report.txt"
echo "  2. 页面指示器点数是否符合预期（空屏应被自动回收）" | tee -a "$OUT/report.txt"
echo "  3. versionName 是否与磁盘 APK 一致（防版本错配）" | tee -a "$OUT/report.txt"
echo "报告: $OUT/report.txt"
