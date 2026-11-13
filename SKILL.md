---
name: bbk-s6-unlock
description: 用于把步步高（BBK）S6／Study OS 学习平板改造成普通安卓平板：清除学习桌面残留的学科大卡片、卸载或屏蔽学习组件、绕过定制安装管控安装第三方应用、打通并稳定 ADB、在 recovery 下以 root 直接修改系统文件。当需要处理「桌面学科图标删不掉／长按无反应」「第三方 APK 装不上、提示去应用商店」「adb 频繁掉线或平板卡顿」「需要 root 改 launcher.db／magisk.db」「给学习机装抖音、WorkBuddy 等应用」「学习机精简／可逆冻结」等场景时，应使用本技能。覆盖 Android 11、Study OS V4.0.0、高通 sm6150、9008 EDL、fastboot、TWRP、Magisk 28.1 全链路的实测结论与红线。
display_name: 步步高 S6 学习机改造与学习插件屏蔽
display_name_en: BBK S6 StudyOS Debloat and Unlock
version: 1.0.0
agent_created: true
---

# 步步高 S6 学习机改造与学习插件屏蔽

## 技能定位

把一台被厂商云控、定制安装器、学习桌面三层锁死的步步高 S6（Android 11 / Study OS V4.0.0_250905 / 骁龙 730G / sm6150）改造成可正常使用的普通平板。所有结论均来自 2026-11-08 至 2026-11-13 的实机操作，不是理论推演。

处理任何请求前，先确认目标属于哪一类，再跳到对应流程：

| 目标 | 直接流程 |
|---|---|
| 清除桌面学科大卡片／学习插件图标 | 流程三：改 `launcher.db` |
| 装不上第三方 APK | 流程二：Magisk 模块预置 或 分段安装会话 |
| ADB 掉线、平板卡顿 | 流程四：修保活脚本 |
| 需要 root 改系统文件 | 流程一：进 recovery 拿 root |
| 卸载／冻结学习 APP | 流程五：可逆精简（严守红线） |
| 只是升级已装应用 | 流程六：版本核对与整包替换 |

完整时间线见 `references/full-timeline.md`；设备指纹、驱动与命令速查见 `references/environment.md`；安装管控原理见 `references/install-lock.md`；桌面数据库字段与操作手册见 `references/launcher-db.md`；全部踩坑与反直觉结论见 `references/pitfalls.md`。

## 先读：五条铁律

1. **绝不冻结或卸载 `com.bbk.studyos.launcher`（学习桌面／系统启动器）。** 一旦冻结，开机后壁纸在、点哪都没反应、三大键失灵。曾因此造成「屏死」事故，只能进 recovery 逐条 `pm enable` 恢复。同类禁区见流程五红线表。
2. **普通 `adb install`／`pm install` 在这台机器上不可信。** 定制 `PackageInstallerActivity` 隐藏安装按钮，`BBKCustomizedDelegate` 钩子会让 `runinstall` 静默退出（`exit 255` 无输出，或 `Failed transaction (2147483646)`）。不要用「命令返回码」判断安装成败，一律用 `pm list packages`／`pm path`／logcat 复核。
3. **不需要正常系统里的常驻 `su`。** Magisk 28.1 的 `adb root` 通道在这套定制 sepolicy 下开不通；但进 TWRP／recovery 后 USB adb 天然就是 `uid=0(root)`，直接改文件即可。所有需要 root 的任务都在 recovery 完成，别浪费时间折腾 `su`／刷 patched boot。
4. **改任何 `/data` 下的数据库，推回后必须原样恢复属主、权限、SELinux 上下文。** `launcher.db` 是 `10085:10085` / `0660` / `u:object_r:app_data_file:s0:c512,c768`（带 CE 分类），漏掉任何一项桌面都会打不开库。
5. **改动前先备份，且备份留在电脑端。** 数据库用 `cp` 留 `.BACKUP`，启动脚本留 `.bak`，设备侧关键文件留 `.bakNN`。任何「一次放多个大文件」的批量写操作都要先做字节数＋MD5 双校验。

## 流程一：拿 root（recovery 通道）

1. 确认电脑端已装 Google 官方 USB 驱动（`android_winusb.inf`，含 recovery 接口 `VID_18D1&PID_D001`）。安装命令：`pnputil /add-driver android_winusb.inf /install`。
2. 正常系统下执行 `adb reboot recovery`，等待约 10～20 秒，用 `adb devices -l` 轮询；出现 `ff5c60fc  recovery  product:twrp_sm6150` 即成功。驱动装好后**无需物理重插 USB**。
3. 用 `adb -d shell id` 验证返回 `uid=0(root) gid=0(root)`。
4. 需要回正常系统：`timeout 15 adb -d reboot`，再轮询 `getprop sys.boot_completed` 为 `1`。
5. 若 recovery 连不上：优先「USB 线从平板这头拔下、等 3 秒、插回」唤醒 adbd；其次在 TWRP 点【重启】→【Recovery】；再其次走 fastboot（关机后**只按音量下**插线，发 `fastboot reboot recovery`，零写入）。

进入 9008 EDL 只在「首次刷入 TWRP」时才需要，日常操作完全不必再碰。EDL 的一次性 Sahara HELLO、COM 口漂移、firehose 只读 GPT 等坑见 `references/pitfalls.md`。

## 流程二：安装第三方应用

按可靠性排序，优先用第一条：

- **首选：Magisk 模块预置为系统应用。** 把 APK 放到 `/data/adb/modules/<id>/system/app/<Name>/<Name>.apk`，确保同目录有 `module.prop`，开机由 Magisk overlay 到 `/system/app/`，PackageManager 开机扫描时自动注册。这条通道绕开所有安装 UI 与钩子。
  - 必须**同签名**、versionCode 递增才能升已装应用；`/data/data/` 登录数据会保留。
  - 若 APK 的 `extractNativeLibs=true`（大型应用常见），必须把 `lib/<abi>/*.so` 一并解压到模块目录，覆盖 `lib/arm64-v8a/`、`lib/arm64/`、`lib/` 三种约定，并 `chmod 755` + `chcon u:object_r:system_file:s0`。缺任何一种 ABI 目录会卡在启动页。
  - 只放 `/data/app/` 裸目录**无效**：这台机器的 PMS 不注册没有 `packages.xml` 记录的裸目录。
- **次选：分段安装会话**（已装系统可试，见 `scripts/install_bypass.sh`）。`pm install-create -r -S <字节数>` → `pm install-write -S <字节数> <ID> base <暂存APK>` → `pm install-commit <ID>`。`install-commit` 仍可能返回 255，但 PMS 已异步完成安装，用 `pm list packages -3` 与 logcat 的 `New package installed` 验证。
- **不要**依赖 `settings put global verifier_verify_adb_installs 0` 之类的验证开关，实测无效。

官网 WorkBuddy 安卓最新版直链：`https://download.codebuddy.cn/web/workbuddy/workbuddy-latest.apk`（CDN 对 HEAD 返回 502，GET／Range 正常）。升级流程见流程六。

## 流程三：清除桌面学科大卡片（本技能的核心成果）

**根因**：那些「物理／化学／智慧工具／错题本」不是快捷方式，也不是 `/data/data/` 里的数据。BBK 学习桌面 `com.bbk.studyos.launcher` 把布局放在 **DE 存储**：

```
/data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
```

库里按学段分四张表：`PreschoolFavorites`、`JuniorFavorites`、`SeniorFavorites`、`OnlineClassFavorites`。霸占整屏的是 `itemType=4` 的 **appwidget 记录**（6×4 或 2×4），`appWidgetProvider` 指向已卸载的学练机包，所以长按无反应、也删不掉。

操作步骤：

1. 进 recovery（流程一），`adb -d pull /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db <本地路径>`。
2. 在电脑端备份：`cp launcher.db launcher.db.BACKUP`。
3. 用 `scripts/clean_launcher_widgets.py` 精准删除。默认只删 `appWidgetProvider` 指向**已卸载包**的记录；确需清空全部学习卡片时加 `--all-widgets`。脚本会打印每一条待删记录的 `id / screen / provider`，并做 `PRAGMA integrity_check`。
4. `adb -d push` 推回原路径，随后**立刻**执行：
   ```
   chown 10085:10085 /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
   chmod 0660 /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
   chcon u:object_r:app_data_file:s0:c512,c768 /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
   ```
   用 `ls -lZ` 复核。
5. 检查同目录有无 `-wal`／`-shm`；本机是 0 字节 rollback journal，直接覆盖主库安全。若有活跃 WAL，先确认 launcher 未运行（recovery 下必然未运行）再删除 WAL。
6. 重启，按 HOME 截图验证：页面指示器点数应减少，空屏被 launcher 自动回收；确认无学科卡片、无空白占位框。

判据：本机最终从 10 屏 → 3 屏 → 2 屏，共删除 11 + 4 条 widget 记录，保留普通应用图标与两个正常小部件。

## 流程四：稳定 ADB、消除卡顿

- 保活脚本位置：`/data/adb/service.d/96-s6-netadb.sh`（需 root，用流程一部署）。
- **已证实的抖动根因**：旧脚本只在 IPv4 `/proc/net/tcp` 里找 `00000000:15B3`（5555），而 adbd 实际监听 IPv6 `[::]:5555`，于是每约 20 秒误判「端口没监听」→ `ctl.restart adbd` → 把连接踢掉，表现为掉线＋整机卡顿。
- 修复：用 `scripts/adb_keepalive_v5.sh`，同时查 `/proc/net/tcp` 与 `/proc/net/tcp6`，**仅在端口确实没监听时**才 `ctl.start`／`ctl.restart adbd`，循环间隔 30 秒。
- 旧的抖动脚本先 `mv` 成 `.disabled`，不要直接覆盖，避免两份同时跑。
- 系统层补强：`ro.adb.secure=0`、`persist.sys.usb.config=mtp,adb`、`persist.adb.tcp.port=5555`、`settings put global adb_enabled 1`（白名单服务开机可能重置，需开机脚本幂等顶回）。
- 注意 IP 会随 DHCP 变化，用 `adb shell ip addr show wlan0` 现场探测，不要硬编码。

## 流程五：卸载／冻结学习应用（可逆精简）

- 对当前用户卸载：`pm uninstall -k --user 0 <包名>`；冻结：`pm disable-user --user 0 <包名>`；恢复：`pm enable <包名>`。这些命令**无需 root**，shell 即可执行。
- **红线（绝对不动）**：
  - `com.bbk.studyos.launcher`（桌面／启动器）
  - `com.android.settings`、`com.android.packageinstaller`、`com.android.permissioncontroller`、系统 UI
  - `com.vivo.ai.ime.bbk`（输入法）、相机、蓝牙等基础服务
  - 用户自装的微信／QQ／抖音／B站／WPS 等
- 分批执行：第 1 批低风险组 → 观察一天 → 第 2 批管控组；开机脚本要**整体重写**而不是追加（见 `references/pitfalls.md`）。
- 一旦误冻启动器导致黑屏：进 recovery，把 `service.sh` 里的 `pm disable-user` 逐条改成 `pm enable`，推回、重启。

## 流程六：升级已装应用（先核对，别盲升）

1. 读当前版本：`dumpsys package <包名> | grep -E 'versionName|versionCode|codePath'`。
2. 下载官网最新 APK，与设备内 APK（`adb pull /system/app/<Name>/<Name>.apk`）比对 SHA256 和签名证书哈希。
3. **若哈希一致，直接告诉用户已是最新版，不要覆盖、不要重启**——覆盖同字节文件毫无意义，还可能破坏系统应用状态。
4. 有新版本才走：recovery → 覆盖模块内 APK（校验签名一致、versionCode 递增）→ 重启 → 再读 `versionName` 确认。
5. 应用内「检查更新」对某些应用可用（抖音实测可自升级），但 WorkBuddy 曾因 2.8.0 与系统登记的 2.7.2 版本错配而打不开，**优先整包替换**。

## 收尾验证清单

- `pm list packages` 确认目标包存在；`pm path <包名>` 看安装路径。
- `dumpsys package` 核对 versionName／codePath 与磁盘 APK 一致（防版本错配）。
- 按 HOME 截图，确认桌面无学科卡片、无空白占位、页面点数符合预期。
- 连续 5～6 次 `adb -d shell getprop sys.boot_completed` 全部返回 `1`，确认 ADB 稳定。
- 记录新的 IP、备份文件位置、改动清单，写入工作日志。

## 脚本用法

| 脚本 | 用途 | 运行位置 |
|---|---|---|
| `scripts/clean_launcher_widgets.py` | 精准删除失效 widget、备份、完整性校验 | 电脑端 Python 3 |
| `scripts/install_bypass.sh` | 分段安装会话绕过安装钩子 | 电脑端 Bash，需 adb |
| `scripts/adb_keepalive_v5.sh` | 稳定网络 ADB 的开机保活脚本 | 推到设备 `/data/adb/service.d/` |
| `scripts/verify.sh` | 一键采集版本／桌面／ADB 状态 | 电脑端 Bash |

所有脚本都遵循「先只读体检、再备份、再改动、再校验」；任何一步失败即停止，不无限重试。
