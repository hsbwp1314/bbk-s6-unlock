# 学习桌面 launcher.db 结构与实践手册

## 为什么之前一直找不到

BBK 学习桌面 `com.bbk.studyos.launcher` 使用 **device-encrypted（DE）存储**。常规 Android 排查会查 `/data/data/<包名>/databases/`，在这台机器上那里只有 cache，容易得出「桌面布局是硬编码、删不掉」的错误结论。

真实路径：

```
/data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
/data/user_de/0/com.bbk.studyos.launcher/databases/app_icons.db
```

`/data/user_de/0/` 与 `/data/data/` 的差异是关键，排查任何「桌面图标删不掉」的问题先确认这两条路径。

## 库结构

四张按学段分的表，字段名一致：

| 表 | 学段 |
|---|---|
| `PreschoolFavorites` | 学前 |
| `JuniorFavorites` | 初中 |
| `SeniorFavorites` | 高中（本机当前激活） |
| `OnlineClassFavorites` | 网课 |

常用字段（用 `PRAGMA table_info(<表名>)` 现场确认，不同固件版本可能增减）：

| 字段 | 含义 |
|---|---|
| `_id` | 主键，删除时按它精确定位 |
| `title` | 显示名；widget 记录通常为 `NULL` |
| `intent` | 应用快捷方式的启动 Intent；widget 为 `NULL` |
| `container` | `-100` = 桌面；`-101` = hotseat；正数 = 文件夹 id |
| `screen` | 屏幕序号（可不连续，launcher 按非空屏数量显示页面点） |
| `cellX` / `cellY` | 网格坐标 |
| `spanX` / `spanY` | 占格；全屏学科卡片常见 `6x4`，学习卡片常见 `2x4` / `2x2` |
| `itemType` | `0` = 应用快捷方式、`2` = 文件夹、`4` = **appwidget** |
| `appWidgetId` / `appWidgetProvider` | widget 的 id 与 provider 组件名 |
| `iconPackage` / `iconResource` | 图标来源 |
| `icon` | 图标 BLOB |
| `restored` / `options` | widget 恢复标志与选项 |
| `tabName` / `tabScreen` | 分组标签 |

**判据**：`itemType=4` 且 `spanX*spanY` 很大（≥8）的记录，就是霸占整屏的学科卡片。`appWidgetProvider` 形如 `<包名>/<类名>`，用包名判断该应用是否已被卸载。

## 本次实测样本（高中表）

| id | screen | 位置 | 尺寸 | provider 包 | 状态 |
|---|---|---|---|---|---|
| 若干 | 1～5 | (0,0) | 6×4 | `com.eebbk.aimathlearning`、`synstudy`、`vtraining`、`synchinese`、`syncenglish`、`tutoringonline` | 已卸载 → 残留空壳 |
| 91 | 0 | (0,0) | 2×4 | `com.eebbk.askhomework/...HomeworkToolMidWidgetH130V21` | 包仍在，但用户不需要 → 删除 |
| 112/113/114（初中表） | 0 | — | 2×2 | `schoolassignment`、`widget.billboard`、`askhomework` | 同上 |

- 第一轮删 11 条（高中 6 + 初中 5），保留 4 个仍指向已安装应用的「正常」widget → 桌面 10 屏 → 3 屏。
- 用户反馈仍有「智慧工具／错题本」一屏 → 第二轮把四张表里**全部剩余 `itemType=4`** 删掉（4 条）→ 3 屏 → 2 屏。
- **经验**：不要武断认为「provider 包还在就该保留」。用户目标是把学习机当普通平板用，学习类 widget 一律可删；判断依据是用户意图，不是包是否存在。

## 标准操作流程

### 1. 进 recovery 并拉取（读操作）

```bash
export MSYS_NO_PATHCONV=1
adb -d reboot recovery
# 轮询 adb devices -l 出现 "<SERIAL>  recovery"
adb -d shell id                      # 必须 uid=0(root)
adb -d pull /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db "C:/<工作目录>/launcher.db"
```

### 2. 记录原始元数据（推回前必做）

```bash
adb -d shell "ls -lZ /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db; \
              ls -n  /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db; \
              ls -la /data/user_de/0/com.bbk.studyos.launcher/databases/"
```

本机实测：

```
-rw-rw---- 1 u0_a85 u0_a85 u:object_r:app_data_file:s0:c512,c768  launcher.db
uid/gid = 10085:10085，mode = 0660
launcher.db-journal = 0 字节（rollback journal 模式，无活跃 WAL）
```

### 3. 备份 + 精准删除（电脑端）

```bash
cp launcher.db launcher.db.BACKUP
python3 scripts/clean_launcher_widgets.py launcher.db --list        # 先只看不删
python3 scripts/clean_launcher_widgets.py launcher.db               # 删指向已卸载包的 widget
python3 scripts/clean_launcher_widgets.py launcher.db --all-widgets # 清空全部学习卡片
```

脚本会逐条打印 `id / screen / provider`、执行删除、跑 `PRAGMA integrity_check`、输出各表剩余数量。

若需手工 SQL：

```sql
SELECT _id, screen, appWidgetProvider FROM SeniorFavorites WHERE itemType=4;
DELETE FROM SeniorFavorites WHERE _id = ?;
PRAGMA integrity_check;
```

### 4. 推回并**原样恢复元数据**

```bash
adb -d push "C:/<工作目录>/launcher.db" /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
adb -d shell '
  chown 10085:10085 /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
  chmod 0660 /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
  chcon u:object_r:app_data_file:s0:c512,c768 /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db
  ls -lZ /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db'
```

**`chcon` 里的 `c512,c768` 是 CE 分类，不能省**。漏掉属主、权限或 SELinux 上下文中的任何一项，launcher 都打不开库，表现为桌面空白或反复崩溃。

### 5. 重启验证

```bash
timeout 15 adb -d reboot
# 等 sys.boot_completed=1
adb -d shell "input keyevent 3"                 # HOME
adb -d exec-out screencap -p > "C:/<工作目录>/home.png"
```

检查：页面指示器点数是否减少（空屏会被 launcher 自动回收）、有无学科大卡片、有无空白占位框。**正常系统下 shell 读这个 db 报 `Permission denied` 反而说明属主／权限恢复正确**，只有 launcher 自己能读写。

## 常见误判

| 现象 | 真实原因 |
|---|---|
| `/data/data/.../databases/` 只有 cache | 数据在 DE 存储 `/data/user_de/0/` |
| `dumpsys shortcut` 查不到图标 | 那是 appwidget 记录，不是 shortcut |
| 长按图标无反应 | widget 的 provider 包已卸载，空壳 |
| 删了记录但桌面没变 | 没恢复元数据、或改的不是当前激活学段的表 |
| 重启后卡片又出现 | 需检查是否有开机脚本／launcher 默认布局在重建；本机实测不会重建 |
| 想连桌面 db 都打不开 | 正常系统 shell 无权限，必须进 recovery |

## 可逆性

`launcher.db.BACKUP` 保留在电脑端。还原只需把备份 push 回原路径，再执行同一组 `chown / chmod / chcon`，重启即可完整恢复原桌面。
