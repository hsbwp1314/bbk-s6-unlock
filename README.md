# 步步高 S6 学习机改造与学习插件屏蔽（WorkBuddy Skill）

一个可安装到 **WorkBuddy** 的技能包，也是一份完整的实战复盘。它把一台被云控白名单、定制安装器、学习桌面三层锁死的步步高 S6（Android 11 / Study OS V4.0.0）改造成普通平板：清掉桌面学科大卡片、装上第三方应用、让 ADB 稳定不再卡顿。

所有结论来自 **2026-11-08 ～ 2026-11-13 的实机操作**，包含走死的路线与最终跑通的那一条，不是理论推演。

## 解决什么问题

| 现象 | 本技能给出的答案 |
|---|---|
| 桌面物理／化学等学科图标长按无反应、删不掉 | 不是快捷方式，是 `/data/user_de/0/.../launcher.db` 里的失效 appwidget 记录 |
| 第三方 APK 提示「请到应用商店下载」、`exit 255` 无输出 | 框架级安装钩子；用 Magisk 模块预置或分段安装会话绕开 |
| ADB 每 20 秒掉线、平板卡顿 | 保活脚本只查 IPv4，而 adbd 监听 IPv6，误判后反复重启 adbd |
| 想 root 改系统文件但 `su` 被拒 | 不需要常驻 root，进 recovery 天然 `uid=0` |
| 冻结学习 APP 后黑屏点不动 | 误冻 `com.bbk.studyos.launcher`，附恢复方法与红线清单 |

## 目录结构

```
bbk-s6-unlock/
├── SKILL.md                         # 技能主文档：决策树、六条流程、五条铁律
├── README.md                        # 本文件
├── references/
│   ├── full-timeline.md             # ★ 全过程详细时间线（11-08 → 11-13）
│   ├── environment.md               # 设备指纹、USB PID、驱动、命令与路径速查
│   ├── install-lock.md              # 三层安装管控原理 + 三条绕过通道
│   ├── launcher-db.md               # 桌面数据库结构、字段、SQL、元数据恢复
│   └── pitfalls.md                  # 20 个踩坑，按根因/修复/验证三段式
└── scripts/
    ├── clean_launcher_widgets.py    # 精准删除残留 widget（电脑端 Python 3）
    ├── install_bypass.sh            # 分段安装会话绕过安装钩子
    ├── adb_keepalive_v5.sh          # IPv6 感知的 ADB 保活脚本（设备端）
    └── verify.sh                    # 一键验收：版本、桌面截图、ADB 稳定性
```

## 安装到 WorkBuddy

### 方式一：上传技能包（推荐）

1. 取得 `bbk-s6-unlock.zip`（zip 内第一层为 `bbk-s6-unlock/` 目录，含全部文件）。用官方脚本自行生成：
   ```bash
   python3 <skill-creator目录>/scripts/package_skill.py <本仓库目录> ./dist
   ```
2. 在 WorkBuddy 左侧边栏点 **专家·技能·连接器** → 选 **技能** 页签。
3. 点 **添加技能** → **上传技能**，拖入或选择 zip 文件。导入后系统自动完成配置。
4. 在 **已安装** 列表确认技能出现且开关为启用状态。

### 方式二：从 GitHub 克隆后放到本地技能目录

仓库地址：<https://github.com/hsbwp1314/bbk-s6-unlock>。本仓库**根目录就是技能目录**，克隆后复制并改名为 `bbk-s6-unlock` 即可：

```bash
git clone https://github.com/hsbwp1314/bbk-s6-unlock.git
cp -r bbk-s6-unlock ~/.workbuddy/skills/bbk-s6-unlock
```

Windows（Git Bash）同样用 `~/.workbuddy/skills/`；也可直接把目录拖到
`C:\Users\<用户名>\.workbuddy\skills\bbk-s6-unlock\`。重启 WorkBuddy 生效。

项目级（团队共享）则放 `<项目>/.workbuddy/skills/bbk-s6-unlock/`。

> 目录名必须与 `SKILL.md` 里的 `name: bbk-s6-unlock` 一致。frontmatter 含
> `agent_created: true`，保证技能管理工具后续可以修改或卸载它。

## 卸载／替换旧技能

- 通过界面上传的技能： **专家·技能·连接器 → 技能 → 已安装** → 找到目标 → 点「...」→ **卸载**。也可用 **批量管理** 勾选多个后统一卸载。
- 「关闭」只是暂停调用，文件与配置都还在；**卸载**才会彻底删除技能及开关记录。
- 若是手工放进 `~/.workbuddy/skills/` 的本地文件夹（没有市场元数据），界面「已安装」里可能看不到，直接删除该目录即可；删除前建议先备份到别处。
- 替换流程：先卸载旧技能 → 再上传新 zip，避免同名技能互相干扰。

## 快速使用

安装后直接用自然语言描述需求即可，例如：

- 「桌面还有几个学科大图标删不掉，帮我清掉」
- 「给学习机装这个 APK，一直提示去应用商店」
- 「ADB 老掉线还卡顿，帮我查一下」
- 「把学习机上装的应用升到最新版」

技能会自动判断目标并路由到对应流程；执行前务必阅读 `SKILL.md` 的「五条铁律」。

## 重要红线

- **绝不冻结或卸载 `com.bbk.studyos.launcher`**（学习桌面／启动器），否则开机后黑屏、点哪都没反应。同类禁区见 `SKILL.md` 流程五。
- 改 `/data` 下的数据库，推回后必须原样恢复 **属主 + 权限 + SELinux 上下文**（`launcher.db` 是 `10085:10085` / `0660` / `app_data_file:s0:c512,c768`）。
- 改动前先在电脑端留备份；升级系统应用前先比对 SHA256 与签名证书，哈希相同就不要覆盖、不要重启。
- 本技能涉及 recovery、Magisk 模块、系统数据库修改，**操作前请自行评估数据丢失与保修风险**。所有写入类脚本都遵循「先只读体检 → 备份 → 改动 → 校验」，失败即停止。

## 适用与验证环境

| 项 | 值 |
|---|---|
| 设备 | 步步高 S6 / P20H130 / 6+128G |
| 平台 | 高通 sm6150（骁龙 730G）、Android 11 |
| 系统版本 | Study OS V4.0.0_250905 |
| recovery | TWRP 3.7.0_11 |
| Magisk | 28.1 |
| 电脑 | Windows 11 + Android platform-tools (adb/fastboot) + Python 3 |

其他品牌学习机或不同固件版本可作思路参考，但**路径、包名、SELinux 分类、USB PID 必须现场重新探测**，不要照抄。

## 免责声明

本项目是个人实机经验整理，仅供学习与研究。修改系统文件、刷写 recovery、绕过厂商管控可能违反设备保修条款或厂商服务协议，并存在数据丢失风险。使用者需自行确认行为合法性并承担后果。作者不对设备损坏、数据丢失或任何间接损失负责。

## 许可证

MIT，见 `LICENSE`。文档与脚本可自由使用、修改与分发；请保留来源说明。
