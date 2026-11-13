# 踩坑清单与反直觉结论

按「根本原因 / 修复方案 / 验证方式」组织。这些坑大多会让「看起来成功了但其实是假的」，优先级高于常规操作手册。

## 一、误报成功类（最危险）

### 1. `fh_loader` 预建空文件制造假阳性

- **根本原因**：回读分区时 `fh_loader` 会先创建目标文件，设备没回数据时文件仍存在且进程可能返回 0；本机 `firehose.elf` 对 LUN 数据区回全零或挂起，只有 LUN 头部 6 扇区（GPT）有真实数据。
- **修复方案**：任何「读取成功」都要校验**内容**：GPT 头偏移 510 应有 `55aa`、boot 起始应有 `ANDROID!` 魔数、对不同地址的块做全文件 SHA256 比对（全零块哈希相同即为假）。`read_gpt()` 必须严判 `rc==0 且 size>=24576 且 nparts>0`。
- **验证方式**：三地址对照实验（扇区 0 / 1000 / boot 起始）；本机结果是 0 真成功、1000 与高地址全零假成功、boot 起始超时，据此判定 EDL 导出 boot 走不通并止损。

### 2. 脚本不判 rc，把「掉线后什么都没写」报成「全部完成」

- **根本原因**：`sh()` 只取 stdout 不检查返回码；ADB 掉线后所有命令都返回 `device not found`，脚本仍逐条打印「已追加」「修复完成」。
- **修复方案**：封装统一 `sh()` 返回 `(rc, out)`；每步前 `require_online()` 守卫；掉线抛异常立即停止写入；用 ResultBook 按**真实结果**汇总，绝不无条件打印成功。
- **验证方式**：干跑（无确认变量时「设备未改动」且非 0 退出）、离线 mock 覆盖掉线分支、实机看回读内容而不看日志措辞。

### 3. trace 日志在收尾才落盘

- **根本原因**：`__main__` 结束才一次性写 trace 文件，脚本运行中途读到的必然是上一次的旧内容。曾据此误判「本次脚本没跑」，实际上它已完整执行并主动重启。
- **修复方案**：交叉验证进程存活、其它实时日志、设备状态；关键步骤实时 flush。
- **验证方式**：以设备端真实状态（PMS 登记、文件字节数、开机时间）为准。

### 4. 「布置完成 ✔」但目标文件 MISSING

- **根本原因**：脚本只校验了 A 路径的推送，没校验 B 路径（模块内 `/system/app/`）是否落盘，而真正生效的恰恰是 B。
- **修复方案**：每个目标路径独立 `stat` 字节数 + `md5sum` 双校验，失败重试、全败不重启。
- **验证方式**：重启后 `pm list packages` + 桌面／应用列表实拍，不接受脚本自报成功。

## 二、开机脚本类

### 5. `service.sh` 里 `|| exit 0` 之后的追加永远不执行

- **根本原因**：原脚本第 2 行是 `[ "$(getprop sys.boot_completed)" = "1" ] || exit 0`，往文件末尾 append 的代码被提前 return 挡住。
- **修复方案**：**整体重写**开机脚本，而不是追加；重写时逐个检查红线包（`guard.is_never_touch()`），别只按前缀粗判。
- **验证方式**：部署后 `cat` 回读，grep 确认关键行存在且位于 `exit` 之前。

### 6. v3 保活脚本 IPv4/IPv6 误判导致掉线＋卡顿

- **根本原因**：只在 `/proc/net/tcp` 找 `00000000:15B3`（5555），但 adbd 监听 IPv6 `[::]:5555`，于是每约 20 秒误判「没监听」→ `ctl.restart adbd` 把连接踢掉。脚本以 root 在 `service.d` 运行，普通 adb 杀不掉。
- **修复方案**：换 v5 —— 同时查 `/proc/net/tcp` 与 `/proc/net/tcp6`，仅在端口确实没监听时才 `ctl.start` / `ctl.restart adbd`，循环间隔 30 秒；旧脚本先 `mv` 成 `.disabled`。
- **验证方式**：连续 6 次 `getprop sys.boot_completed` 全部返回 1；用户主观卡顿消失。

### 7. TWRP 下改 XML 用 `sed -i` / `adb push` 会丢属性

- **根本原因**：`sed -i` 换 inode、push 覆盖会丢属主／权限／SELinux 上下文，`settings_global.xml` 属 `1000:1000 600 u:object_r:system_data_file:s0`。
- **修复方案**：设备端 `sed` 生成 tmp → `cat tmp > 原文件` **原地截断写**（保留 inode 与全部元数据），失败从 `.bak` 回滚。
- **验证方式**：`ls -lZ` 前后一致 + `grep` 确认目标值已改。

### 8. 白名单服务开机重置 ADB 开关

- **根本原因**：`com.eebbk.bbkallowlisting` 开机把 `adb_enabled` / `adb_wifi_enabled` 写回 0，并给 XML 打上 `package="com.eebbk.bbkallowlisting"`。
- **修复方案**：Magisk 开机脚本幂等 `settings put global adb_enabled 1`，配合 XML 原地改写摘掉 package 归属。
- **验证方式**：重启后 `adb connect <IP>:5555` 是否从「10061 积极拒绝」变为 connected。

## 三、ADB / 连接类

### 9. `adb pull` 目录会打挂 TWRP 的 adbd

- **根本原因**：连续读 `/data/anr`、`dropbox` 等目录时 adbd 崩溃，之后的命令全是 `device not found`。
- **修复方案**：诊断**后置**到所有写入完成之后，且默认跳过（需显式开关才跑）；诊断改用容错的 `adb shell cat/grep` 文本读取。单文件大 `adb push`（258 MB）反而稳定。
- **验证方式**：修复先做、诊断最后做，确保重启命令能发出去。

### 10. Windows Git Bash 路径与 adb.exe 的路径转换

- **根本原因**：`adb.exe` 是 Windows 程序；`adb push` 的源路径若写成 `/c/...` 会被 MSYS 转换失败；`adb pull` 的目标路径同理。
- **修复方案**：`export MSYS_NO_PATHCONV=1`，本地路径统一用 `C:/...`，设备端路径保持 `/data/...`。
- **验证方式**：看 push/pull 是否报「1 file pulled/pushed」。

### 11. 幽灵端口与 COM 口漂移

- **根本原因**：反复插拔后 Windows 残留 `CM_PROB_PHANTOM` 条目，并把同一物理口重分配成 COM3/5/6。
- **修复方案**：只认 `Status -eq OK` 且 `Problem -eq CM_PROB_NONE`；每轮重新枚举在线端口并跟随新 COM 号；「所有在线端口都消失」才判会话结束。
- **验证方式**：PnP 的 `IsPresent` / `Status` / `Problem` 三项对齐。

### 12. Sahara HELLO 是一次性数据

- **根本原因**：9008 的 HELLO 只在上电瞬间发一次；握手前任何 PowerShell/PnP 查询、或用 `CreateFileW` 打开串口，都会把这次 HELLO 冲掉或错过，导致 watchdog 超时重启。
- **修复方案**：「检测到端口 → 静默 1 秒 → **立刻**发引导」，**失败之后**才诊断换口／换参数。曾因在握手前插了一次 `Get-PnpDevice` 造成整条链路回归。
- **验证方式**：离线 mock 断言「首轮握手前 PnP 调用次数 = 0」。

## 四、安装与版本类

### 13. 版本错配导致「点了没反应」

- **根本原因**：磁盘 APK 换成新版，但 PMS 里仍登记旧版，系统按旧记录找 oat/dex、native 路径、签名摘要，对不上就启动失败；定制 UI 吞掉 FC 对话框。
- **修复方案**：让磁盘版本与 PMS 登记**对齐**（不是简单降级），清该应用 oat／package-cache／dalvik-cache 强制重解析，不碰 `/data/data`。
- **验证方式**：`dumpsys package` 的 versionName/codePath 与 APK 的 AXML 解析结果一致；应用能登录。

### 14. `extractNativeLibs=true` 的应用卡在 Logo

- **根本原因**：模块 `/system/app/` 是只读挂载，压缩的 so 无处解压；且必须覆盖 `lib/arm64-v8a/`、`lib/arm64/`、`lib/` **三种** ABI 目录约定，本机缺第三种就一直卡。
- **修复方案**：电脑端 `tarfile` 解出全部 so 打**一个整包**单次 push，设备端解包到三处，`chmod 755` + `chcon u:object_r:system_file:s0`，文件数 + 整包 MD5 双校验。
- **验证方式**：三处 so 计数一致；`dumpsys package` 的 `nativeLibraryDir` / `primaryCpuAbi` 正确；应用能播放。

### 15. 卡启动页被误判成崩溃／风控

- **根本原因**：ANR 与 tombstone 里全是微信、和平精英、system_server 等进程，**没有任何目标应用包名**，说明不是崩溃也不是风控。
- **修复方案**：先抓持久化崩溃记录做排除法，再回到「原生库目录」这个静态事实；不要在抓日志上无限折腾 ADB（管控会关掉）。
- **验证方式**：补 `lib/arm64/` 268 个 so 后应用恢复播放，由结果反证根因。

### 16. 首次 dex2oat 造成的临时卡顿

- **根本原因**：57 个 dex 首次编译 + 应用内升级占用，期间画面卡顿／卡启动页属正常。
- **修复方案**：让升级跑完，别连点、别强停、别急着重启或换旧版。
- **验证方式**：本机升级完成后账号登录顺畅，先前给的「重启 / Plan B 换旧版」两项建议均作废。

## 五、系统改动类

### 17. 冻结启动器导致「屏死」（最严重事故）

- **根本原因**：可逆精简把 `com.bbk.studyos.launcher` 归进低风险组一并冻结，开机后没有桌面接管主屏，壁纸在、点哪都没反应、三大键失灵。
- **修复方案**：进 TWRP，把 `service.sh` 里 9 条 `pm disable-user` 逐条改成 `pm enable`，推回、重启；此后在保护清单加 `CRITICAL_PROTECTED` 层（launcher／桌面／系统 UI／设置）。
- **验证方式**：开机回桌面、触摸与三大键恢复响应。

### 18. 离线改 `magisk.db` 开常驻 root 走不通

- **根本原因**：Magisk 28 在无 Manager 时不建 su 二进制；离线写 `adb_root=1` / `superuser=2` / `policies(2000,…)` 后，`strings /system/bin/magisk` 里**根本没有 `adb_root` 键名**，加上 BBK 定制 sepolicy 拦截，`su -c id` 仍 `Permission denied`、`adb root` 仍报 `adbd cannot run as root in production builds`。中途 `pkill -9 magiskd` 还一度把 su 弄成 `not found`。
- **修复方案**：**放弃常驻 root**。所有任务改用 recovery 的天然 uid 0 完成，完全不依赖 `su`。要真正开通需 patch boot／改 sepolicy，风险远大于收益。
- **验证方式**：三项实际交付（删图标、装 APP、ADB 稳定）全部完成且设备正常开机，证明不需要常驻 root。

### 19. TWRP 里 `df -k /data | tail -1` 不是用户存储

- **根本原因**：TWRP toybox 输出 `rootfs … /` 行，读到的是 ramdisk 容量（约 2689 MB），不是 userdata（本机可用 44 GB）。曾据此误判「空间不足，四个大文件放不下」，还衍生出「/data 是 tmpfs」的错误假说，两者后来都被撤回。
- **修复方案**：写前用 `/proc/mounts` 判断挂载源含 `/dev/block` 或 `dm-`，并确认 `/data/system/packages.xml` > 1 KB；挂不上就零写入停止，提示 TWRP【挂载】勾选 Data / 输锁屏密码。
- **验证方式**：`df -h` 原始输出 + `mount` + packages.xml 可见性三项一起看。

### 20. 恢复出厂／降级不是万能还原

- **根本原因**：被 `pm uninstall --user 0` 卸载的是固化固件应用，APK 仍在 `/system`；但被写过的 recovery 分区、misc 标志、Magisk 模块不会因为恢复出厂自动撤销。
- **修复方案**：所有改动留电脑端备份（数据库 `.BACKUP`、原厂 boot 镜像、模块脚本 `.bak`），还原按「推回 + 恢复元数据 + 重启」执行。
- **验证方式**：还原后逐项截图／命令复核，不靠「应该恢复了吧」。

## 六、Windows 批处理与中文

- `.bat` 含中文提示必须 **GBK + CRLF 无 BOM**；UTF-8 写入会被 cmd 按 936 代码页误读致 `for` 块解析错乱。
- `ECHO` 行里的裸 `->` 会被 cmd 当重定向，生成垃圾文件并截断提示文字，改用全角 `→` 或转义。
- Python 3.6+ 在真实 Windows 控制台输出中文需 `WriteConsoleW`（Unicode），把 stdout 设成 GBK 会变成菱形方块；输出被重定向时才回退 GBK 字节流。
- 本机可能没有系统 Python，可用 WorkBuddy 自带的 `vendor/python/python.exe`；Windows 应用执行别名的 `python.exe` 是商店存根，要用 `-c "import sys"` 自检挡掉。
- 9008 脚本因 `devcon.exe` manifest 要求提升，必须**右键以管理员身份运行**；非管理员下 `pnputil /add-driver` 返回「拒绝访问」而不是签名错误，别误判。
