# 设备环境与命令速查

> 本文件里的序列号、IP、电脑路径均为**示例占位符**，实机必须现场探测。不要硬编码。

## 设备指纹

| 项 | 值 |
|---|---|
| 型号 | P20H130 / 步步高 S6（6+128G） |
| 芯片 | 高通骁龙 730G / sm6150 / UFS |
| 系统 | Android 11，Study OS V4.0.0_250905 |
| Bootloader | 已解锁（`ro.boot.flash.locked=0`、`verifiedbootstate=orange`） |
| 正常开机 USB | `VID_18D1&PID_4EE1`（MTP，序列号形如 `<SERIAL_SYSTEM>`） |
| recovery USB | `VID_18D1&PID_D001`（ADB 接口，序列号形如 `FF5C60FC`，`adb devices` 显示 `recovery`） |
| fastboot USB | `VID_18D1&PID_D00D`（接口类 `Class_FF&SubClass_42&Prot_03`） |
| 9008 EDL USB | `VID_05C6&PID_9008`（`Qualcomm HS-USB QDLoader 9008 (COMx)`）；另有 `PID_900E` 诊断口 |
| recovery 实现 | TWRP 3.7.0_11（中文定制版），由 9008 写入 recovery 分区得来 |
| Magisk | 28.1，`magiskd` 在跑，`/system/bin/su -> magisk` |

## 三种按键组合（不能混）

| 组合 | 进入 | 用途 |
|---|---|---|
| 关机后**只按音量下**插线 | fastboot | 零写入发 `fastboot reboot recovery` |
| 关机后**同时按音量上+音量下**插线 | 9008 EDL | 首次刷 TWRP、写 misc |
| 什么都不按，正常开机 | 原厂系统 | 日常使用；`adb reboot recovery` 可回 TWRP |

- 按键只在**插线通电瞬间**起作用，看到「检测到端口」即可松手；长按反而触发重启进系统。
- 9008 是一次性易失状态，几十秒无工具连接会自动重启回系统。
- 双音量键进 EDL 后若又回桌面，多半是松手晚了或误触电源键。

## 电脑端驱动

```
pnputil /add-driver android_winusb.inf /install     # Google 官方 USB 驱动（含 D001）
pnputil /enum-drivers | findstr /i oem              # 复核是否入驱动库
```

- 驱动装在**电脑上**，不动平板。
- Google 官方 INF 不含 `PID_D00D`（fastboot）与 `Class_FF&SubClass_42&Prot_03`；fastboot 需 Zadig 装 WinUSB 并补标准 Android 接口 GUID `{F72FE0D4-CBCB-407d-8814-9ED673D0DD6B}`。
- recovery 的 `D001` 是标准 ADB 接口，官方驱动直接可用；驱动装好后 `adb reboot recovery` 会自动重枚举，**无需物理重插 USB**。
- 判断真实在线：PowerShell `Get-PnpDevice` 的 `Status -eq OK` / `Problem -eq CM_PROB_NONE` / `IsPresent = True`。带 `CM_PROB_PHANTOM` 的是幽灵残留条目，不能算连接成功。

## 连接与探测命令

```bash
# 电脑端统一加这个，防止 Git Bash 把 /data/... 当成 Windows 路径
export MSYS_NO_PATHCONV=1

adb devices -l                                  # 看状态：device / recovery / offline / unauthorized
adb -d shell id                                 # -d 指定唯一 USB 设备，最稳
adb connect <平板IP>:5555                       # 网络 adb（IP 会变）
adb -d shell "ip addr show wlan0 | grep 'inet '" # 现场探测 IP
adb -d shell getprop sys.boot_completed         # 开机完成标志
adb -d reboot recovery                          # 进 recovery
timeout 15 adb -d reboot                        # 回正常系统（recovery 下 reboot 可能阻塞，加超时）
```

**adb.exe 是 Windows 程序**：`adb push` 的源路径、`adb pull` 的目标路径必须用 `C:/...` 这种 Windows 风格；纯 `/c/...` 会被 MSYS 转换导致失败。设备端路径保持 `/data/...` 不变。

**跨进程连接易丢**：把「连接 → 检查 → 操作」放进同一条命令或同一个脚本，别依赖上一条命令建立的连接。每条 adb 调用加 `timeout`，防止设备不可达时长时间阻塞。

## 关键路径

| 用途 | 路径 |
|---|---|
| 学习桌面布局库 | `/data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db` |
| 桌面图标缓存 | `/data/user_de/0/com.bbk.studyos.launcher/databases/app_icons.db` |
| Magisk 模块根 | `/data/adb/modules/<id>/` |
| 模块内系统应用 | `/data/adb/modules/<id>/system/app/<Name>/<Name>.apk` |
| 开机脚本（post-fs 阶段） | `/data/adb/post-fs-data.d/`、`/data/adb/modules/<id>/post-fs-data.sh` |
| 开机脚本（boot 完成） | `/data/adb/service.d/`、`/data/adb/modules/<id>/service.sh` |
| Magisk 配置库 | `/data/adb/magisk.db`（表 `settings(key,value)`、`policies(uid,policy,until,logging,notification)`） |
| ADB 公钥 | `/data/misc/adb/adb_keys`（AOSP 标准属主 `system:shell` 1000:2000、权限 640、目录 02750） |
| 系统设置 | `/data/system/users/0/settings_global.xml`（`adb_enabled` / `adb_wifi_enabled`） |
| 原厂 boot 备份 | 建议放 `/sdcard/s6_boot_orig.img` 并另存电脑端 |

## 包名速查

| 包名 | 角色 | 处理 |
|---|---|---|
| `com.bbk.studyos.launcher` | 学习桌面／启动器 | **绝对不动** |
| `com.eebbk.bbkallowlisting` | 云控白名单、关 ADB 总开关 | 冻结需谨慎，会复活 |
| `com.eebbk.bbkpackageinstaller` | 定制安装器（隐藏安装按钮） | 不删，绕开即可 |
| `com.eebbk.greensecuritymidware` | 绿网安全中间件 | 管控组 |
| `com.eebbk.parentsupport` | 家长管控 | 管控组 |
| `com.eebbk.vision` | 学练机（学科图标来源） | 可卸载，卸载后图标变残留 |
| `com.eebbk.ovumserver` | 智慧小布 | 可卸载 |
| `com.eebbk.askhomework` | 作业／智慧工具 widget | 包在，widget 记录可删 |
| `com.eebbk.schoolassignment` / `com.eebbk.widget.billboard` | 学习挂件 | 同上 |
| `com.tencent.workbuddy.app` | WorkBuddy | 用户自装，系统应用 |
| `com.ss.android.ugc.aweme` | 抖音 | 用户自装，系统应用 |
| `com.topjohnwu.magisk` | Magisk Manager | 用模块装，绕开安装锁 |

## 官方下载地址（2026-11 核实）

- WorkBuddy 安卓版：`https://download.codebuddy.cn/web/workbuddy/workbuddy-latest.apk`（最新正式版 2.7.2 / versionCode 931 / 316112620 字节；CDN 对 HEAD 返回 502，GET／Range 正常）。
- 版本元数据（应用宝）：`https://sj.qq.com/appdetail/<包名>` 页面正则提 `md_5` / `apk_size` / `version_name`；CDN 直连需 `curl --noproxy '*' -L --max-redirs 5`，否则无限 302 或 EdgeOne 反爬 JS。
