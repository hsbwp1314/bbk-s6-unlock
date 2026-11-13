#!/system/bin/sh
# BBK S6 网络 ADB 保活（v5）
#
# 部署位置： /data/adb/service.d/96-s6-netadb.sh
# 权限：     chown root:root; chmod 0755
# 需 root 环境：先在 recovery 下推送，或用 Magisk 模块投放。
#
# 修复 v3 的关键 bug：旧脚本只查 IPv4 /proc/net/tcp，而 adbd 监听
# IPv6 [::]:5555，导致每约 20 秒误判「端口未监听」并 ctl.restart adbd，
# 把连接踢掉、整机卡顿。v5 同时检查 tcp / tcp6，且只在端口确实
# 没监听时才重启 adbd。

PORT_HEX="15B3"   # 5555

listen_5555() {
  if grep -q "$PORT_HEX" /proc/net/tcp 2>/dev/null; then
    grep -q " 00000000:$PORT_HEX " /proc/net/tcp 2>/dev/null && return 0
    grep -q "0100007F:$PORT_HEX " /proc/net/tcp 2>/dev/null && return 0
  fi
  if grep -q "$PORT_HEX" /proc/net/tcp6 2>/dev/null; then
    grep -q "00000000000000000000000000000000:$PORT_HEX " /proc/net/tcp6 2>/dev/null && return 0
  fi
  return 1
}

setprop persist.adb.tcp.port 5555

# 等开机完成，最多 120 秒
for i in $(seq 1 60); do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
done

settings put global adb_enabled 1 2>/dev/null
settings put global adb_wifi_enabled 1 2>/dev/null
setprop service.adb.tcp.port 5555

if ! listen_5555; then
  setprop ctl.restart adbd
  for i in $(seq 1 10); do
    sleep 1
    listen_5555 && break
  done
fi

(
  while true; do
    # 白名单服务可能在开机后把总开关置回 0，需幂等顶回
    settings put global adb_enabled 1 2>/dev/null
    settings put global adb_wifi_enabled 1 2>/dev/null
    setprop service.adb.tcp.port 5555
    if ! listen_5555; then
      setprop ctl.start adbd 2>/dev/null
      sleep 2
      listen_5555 || setprop ctl.restart adbd
      sleep 8
    fi
    sleep 30
  done
) &

exit 0
