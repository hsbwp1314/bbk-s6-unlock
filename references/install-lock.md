# 步步高定制安装管控与三条绕过通道

## 管控分三层

### 第一层：云控白名单（决定「能不能开 ADB」）

点「型号」6 次试图开启 USB 调试时，Settings 会 POST 厂商服务器：

```
https://os-app.eebbk.net/os-app/app/usbScreenDebug/getUsbScreenDebugStatusByMachineId
body: machineId=<序列号>
返回 {"stateCode":"0","data":"<3DES密文>"}   # desede/CBC/PKCS5Padding，固定 IV xgspring
```

解密得 `{"status":0}` 就走 `handleFailed(0)` 弹「USB 调试授权失败, code 0」，并写 `development_settings_enabled=0` / `adb_enabled=0`。**白名单在厂商服务器，本地无开关**：重复点、断网、换账号都无效。

开机后 `com.eebbk.bbkallowlisting` 还会把 `settings_global.xml` 里的 `adb_enabled` / `adb_wifi_enabled` 置 0，这才是 5555 端口「积极拒绝」的真开关；只写 `persist.adb.tcp.port=5555` 没用。

### 第二层：定制安装器 UI（决定「安装按钮在不在」）

`/system/priv-app/BPackageInstaller`（`com.eebbk.bbkpackageinstaller`）的 `PackageInstallerActivity.isAllowInstall()` 在 V4.0.0 上对普通 APK 返回 false，执行 `mAllowButton.setVisibility(8)` 隐藏安装按钮，提示「此应用无法安装，请尝试到"应用商店"下载」。

- 界面会显示调用来源（如「来自文件管理」），说明判断依据是包名／来源，**改文件名、后缀、目录都无效**。
- S5 / Android 9 时代「普通 APK 直接 return true」的老结论在 V4.0.0 已失效。
- 界面上「打开下载娱乐应用权限申请」实际只覆盖微信／QQ／百度网盘，抖音与 WorkBuddy 都不在白名单。

### 第三层：框架钩子（决定「命令行安装能不能过」）

即使绕开 UI，`pm install` / `cmd package install` / `adb install` 仍会失败：

```
Failed transaction (2147483646)          # 部分场景
exit 255，无任何输出                      # 更常见
```

logcat 证据链：

```
PackageManagerShellCommand: runinstall getRemoteUsbState
BBKCustomizedDelegate: delegate getRemoteUsbState
（随后日志中断）
```

钩子依赖 `com.eebbk.bbkallowlisting/.service.CustomizedService`；当该服务被禁用（`pm list packages -d` 可见）时，钩子拿不到状态就卡死整个安装流程。`settings put global verifier_verify_adb_installs 0` 与 `package_verifier_enable 0` **实测无效**，事后应 `settings delete` 还原。

---

## 通道 A（首选）：Magisk 模块预置为系统应用

**原理**：完全不走安装事务，把 APK 交给 PackageManager 的开机分区扫描。

```
/data/adb/modules/<id>/
├── module.prop                          # 必须有，id/name/version/versionCode/description
├── post-fs-data.sh                      # 可选：早期属性、adb_keys
├── service.sh                           # 可选：boot_completed 后的补强
├── system.prop                          # 可选：resetprop ro.adb.secure=0 等
└── system/app/<Name>/<Name>.apk         # 开机 overlay 到 /system/app/<Name>/
```

实测要点：

1. **必须有 `module.prop`**，否则 Magisk 不加载模块。
2. **只放 `/data/app/` 裸目录无效**：PMS 不注册没有 `packages.xml` 记录的裸目录。干净对照实验：同一次运行、两个 APK 的 MD5 都正确，唯一变量是投放位置，结果只有模块内那个出现在应用列表。
3. **同签名 + versionCode 递增**才能升已装应用；`/data/data/` 登录数据保留。
4. **版本错配会打不开**：换掉磁盘 APK 但 PMS 仍登记旧版本时，系统按旧记录找 oat/dex、native 库路径、签名摘要，对不上就启动失败，定制 UI 吞掉 FC 后表现为「点了没反应」。处置是让磁盘版本与 PMS 登记对齐，并清该应用的 `oat/` / `package-cache` / `dalvik-cache`（不碰 `/data/data`）。
5. **原生库（`extractNativeLibs=true`）必须预解压**：
   - 判断：`AndroidManifest.xml` 里 `extractNativeLibs=true`、APK 内 so 是 DEFLATED 压缩、未 4K 对齐。
   - 把 `lib/arm64-v8a/*.so` 全部解出，投到模块目录的 **`lib/arm64-v8a/`、`lib/arm64/`、`lib/` 三种约定**（本机缺第三种就卡 Logo）。
   - 每个 so `chmod 755` + `chcon u:object_r:system_file:s0`。
   - 反例：WorkBuddy 2.7.2 的 35 个 so 全 STORED、`extractNativeLibs=false`，可直接 mmap，不需要解压。
6. 模块是只读挂载，大型应用首次 dex2oat（57 个 dex）可能 5～15 分钟，期间「卡启动页」属正常，**别连点、别强停**。
7. 安装 Magisk Manager 本身也用这条通道（`system/priv-app/MagiskManager/MagiskManager.apk`），因为 `pm install` 同样被拦。

## 通道 B（次选）：分段安装会话

已在系统里、有 adb 时可用，绕开被钩住的 `runinstall`：

```bash
export MSYS_NO_PATHCONV=1
SIZE=$(stat -c %s app.apk)
adb push app.apk /data/local/tmp/x.apk
SID=$(adb shell pm install-create -r -S "$SIZE")     # Success: created install session [ID]
ID=$(echo "$SID" | grep -oE '[0-9]+' | tail -1)
adb shell pm install-write -S "$SIZE" "$ID" base /data/local/tmp/x.apk
adb shell pm install-commit "$ID"                    # 可能仍返回 255
```

**不要以 exit code 判断成败**。`install-commit` 失败时 PMS 可能已异步完成安装，必须用下列证据复核：

```bash
adb shell pm list packages -3 | grep <关键字>
adb shell pm path <包名>
adb shell pm list packages -e | grep <关键字>      # 确认未被禁用
adb shell logcat -d | grep -E 'New package installed|Integrity check passed|Running dexopt'
adb shell am start -n <包名>/<入口Activity>
```

本机实测日志链：`installNewPackageLI` → 重命名到 `/data/app/~~xxx/<包名>/base.apk` → `Running dexopt` 完成。

## 通道 C（兜底）：应用内自升级

抖音 41.0.0 实测可以在应用内升级完成，不触发安装白名单。但 WorkBuddy 曾因 2.8.0 与系统登记的 2.7.2 错配打不开，**不能一概而论**；系统应用优先走通道 A 整包替换。

## 安装成败验证清单

| 检查 | 命令 |
|---|---|
| 包是否注册 | `pm list packages <包名>` |
| APK 路径 | `pm path <包名>` / `dumpsys package <包名> \| grep codePath` |
| 版本是否对齐 | `dumpsys package <包名> \| grep -E 'versionName\|versionCode'` 与磁盘 APK 的 AXML 解析结果比对 |
| 是否被禁用 | `pm list packages -d \| grep <包名>` |
| 能否启动 | `am start -n <包名>/<Activity>` 返回 0、`pidof <包名>` 非空 |
| 原生库齐不齐 | `ls /system/app/<Name>/lib/arm64-v8a \| wc -l` 等三处计数一致 |

## 签名核对（升级前必做）

```python
import zipfile, hashlib
z = zipfile.ZipFile(p)
sig = [n for n in z.namelist() if n.startswith("META-INF/") and n.upper().endswith((".RSA", ".DSA", ".EC"))]
print(sig, hashlib.sha256(z.read(sig[0])).hexdigest())
```

更严格时解 PKCS#7 提 X.509 证书指纹（ serial / Subject / 指纹）。注意：不同版本 APK 的 `.RSA` 内容不同是**正常的**（PKCS#7 含内容摘要），判断是否换 key 要看证书本身，不是看 `.RSA` 哈希。

## 明确无效的做法（别再试）

- 改 APK 文件名／后缀／存放目录。
- 关闭安装包验证开关（`verifier_verify_adb_installs` / `package_verifier_enable`）。
- 把 APK 放进 `/sdcard/WhileListInstaller` 或 `.WhiteListInstaller` 后重启（那只是绿网登记 USB 复制文件的目录）。
- 禁用单个管控 APP 期待解锁（会复活，且钩子拿不到服务反而更容易卡死）。
- 用 `/data/app/` 裸目录投放。
