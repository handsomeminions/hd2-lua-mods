<div align="center">

# HD2 Lua Mods

**《绝地潜兵2》Lua 注入型内存 Mod 合集 —— 下载即用 · 不改游戏文件 · 源码与测试全公开**

[![Loader](https://img.shields.io/badge/Bingus%20Shared%20Loader-v15%2B%20(API%201)-blue)](#1-前置要求)
[![Mods](https://img.shields.io/badge/mods-7-brightgreen)](#-全部-mod-一览7-个)
[![Tests](https://img.shields.io/badge/offline%20tests-127%20passing-success)](#-离线测试)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

</div>

---

## 📖 这是什么

一组基于 **Bingus Shared Loader** 的 **Lua 注入型** Mod。它们把 Lua 脚本塞进游戏进程，
用 FFI **直接读写游戏运行时内存**里的数据表，从而改变战备、敌人、武器的行为。

**关键特性 —— 对你没有风险的部分：**

| | |
|---|---|
| 🔒 **不改任何磁盘文件** | 游戏本体、`.patch_0`、资源包一个字节都不动 |
| ♻️ **完全可还原** | 在管理器里禁用 + Purge，重启游戏即回到原版 |
| 🧪 **离线测试齐全** | 每个 Mod 都有 LuaJIT 仿真测试（功能 + 变异），共 **127/127 通过** |
| 📚 **离线可复现** | 数据来源、字段偏移、识别指纹全部留档，换台机器也能接着改 |
| 🤖 **AI 友好** | [`AI-HANDOFF.md`](AI-HANDOFF.md) 给接力的人 / AI 一张完整的地图 |
| ⚠️ **官方不支持** | HD2 有 nProtect GameGuard，这类内存补丁属灰色地带，**建议单人 / 自己开房使用，风险自担** |

> **这不是资源替换 Mod。** 那些改模型/贴图/音效的 Mod 走的是 `hd2-audio-modder` 之类的
> 资源打包工具；本仓库走的是**运行时内存**这条路，两者可以共存。

---

## 🎁 全部 Mod 一览（7 个）

> **7 个 Mod 全部已在真实游戏中上机验证通过（✅）。** 点名字进入该 Mod 的**详细版面**。

### 🚀 战备（Stratagem）

| # | Mod | 效果 | 版本 | 测试 | 实机 |
| :-: | --- | --- | :-: | :-: | :-: |
| 1 | **[轨道120MM高爆弹火力网 → 飞鹰500kg](docs/01-orbital-120mm-eagle-500kg.md)** | 每发炮弹的**落地爆炸**变成飞鹰500kg炸弹（音效/伤害/范围/特效全对齐）。**打击方式与弹道保持原版 120mm** | `1.3.0` | 25/25 | ✅ |
| 2 | **[轨道380MM高爆弹火力网 → 地狱火炸弹](docs/02-orbital-380mm-hellbomb.md)** | 每次打击炸出**核弹级地狱火炸弹**：半径 17/25/45，核弹坑，专属火焰粒子与音效 | `1.0.1` | 7/7 | ✅ |

### ⚙️ 哨戒炮（Sentry）

| # | Mod | 效果 | 版本 | 测试 | 实机 |
| :-: | --- | --- | :-: | :-: | :-: |
| 3 | **[A/M-12 迫击哨戒炮 → 凝固汽油弹](docs/05-mortar-sentry-napalm.md)** | 炮弹飞行照旧，**落地炸成轨道凝固汽油弹**：落地留下燃烧火海、焦土弹坑。索敌/弹道/模型全保持原版 | `1.0.1` | 23/23 | ✅ |

### 🐛 胆汁喷涌虫（Bile Spewer —— 终结族群）

| # | Mod | 效果 | 版本 | 测试 | 实机 |
| :-: | --- | --- | :-: | :-: | :-: |
| 4 | **[胆汁迫击炮 → 落地炸成 RL-77 空爆集束](docs/03-bile-spewer-rl77-airburst.md)** | 外形与飞行**保持原版绿色胆汁团块**，落地炸成空爆集束。一发 = 一次空爆 | `1.5.0` | 28/28 | ✅ |
| 5 | **[齐射档位选择 · 合集包（4 团 / 6 团）](docs/04-bile-spewer-salvo-choice-pack.md)** | **一个包 = 两个可勾选项**。在 Arsenal / HD2MM 里勾「4 Mortars」或「6 Mortars」，想用哪档用哪档 | `1.0.0` | 结构+共存 | ✅ |

> **#5 已整合 4 团 / 6 团两档**，不再单独发布独立包 —— 一个合集包搞定，不用同时装两个。

### 🔫 武器（Weapon）

| # | Mod | 效果 | 版本 | 测试 | 实机 |
| :-: | --- | --- | :-: | :-: | :-: |
| 6 | **[TX-41 灭菌器 → G-4 伤害 + 毒气 ×2](docs/06-sterilizer-g4-gas-damage.md)** | 每次命中**直接伤害 1→3**（= G-4 毒气榴弹），**毒气施加量翻倍**。**只影响灭菌器**，敌人毒气不动 | `2.0.0` | 28/28 | ✅ |
| 7 | **[TX-41 灭菌器 → 开火音效替换](docs/07-sterilizer-punchier-sfx.md)** | 把"软绵绵"的喷气声换成更明显的喷射音效（默认 = 敌方化学无人机的喷毒声，可在 cfg 里换其它） | `1.0.0` | 16/16 | ✅ |

**#6 与 #7 互相独立，可以同时装。**

---

## 🚀 快速开始

### 1. 前置要求

| 项目 | 要求 |
| --- | --- |
| **Bingus Shared Loader** | **v15 或更高**（本项目在 **v19 / API 1** 上开发与验证）。必须开启 addon 支持 |
| **Mod 管理器** | [Arsenal](https://github.com/darnias/Arsenal) 或 HD2MM（Helldivers 2 Mod Manager） |
| **游戏** | Steam 版《绝地潜兵2》 |
| 系统 | Windows（x64） |

> `API 1` 是 loader 自身的 Lua API 等级（在 `BingusSharedLoader.log` 首行可见），**不需要额外安装什么**。

### 2. 下载

**方式 A —— 直接下 ZIP（推荐，下载即用）**

到本页 `dist/` 目录点开你要的包，或直接从以下链接下载：

| Mod | 安装包 |
| --- | --- |
| 1. 轨道120MM → 飞鹰500kg | [`dist/Orbital120mm-Eagle500kg.zip`](dist/Orbital120mm-Eagle500kg.zip) |
| 2. 轨道380MM → 地狱火炸弹 | [`dist/Orbital380mm-Hellbomb.zip`](dist/Orbital380mm-Hellbomb.zip) |
| 3. 迫击哨戒炮 → 凝固汽油弹 | [`dist/MortarSentry-NapalmImpact.zip`](dist/MortarSentry-NapalmImpact.zip) |
| 4. 胆汁迫击炮 → 空爆集束 | [`dist/BileSpewer-RL77Airburst.zip`](dist/BileSpewer-RL77Airburst.zip) |
| 5. 胆汁喷涌虫 · 齐射档位合集（4 / 6 团） | [`dist/BileSpewer-Salvo-Choice.zip`](dist/BileSpewer-Salvo-Choice.zip) |
| 6. 灭菌器 → G-4 伤害 + 毒气 ×2 | [`dist/Sterilizer-G4GasDamage.zip`](dist/Sterilizer-G4GasDamage.zip) |
| 7. 灭菌器 → 开火音效替换 | [`dist/Sterilizer-PunchierSFX.zip`](dist/Sterilizer-PunchierSFX.zip) |

**方式 B —— 克隆整个仓库**（想改代码 / 让 AI 接着做，用这个）

```bash
git clone https://github.com/handsomeminions/hd2-lua-mods.git
cd hd2-lua-mods
python vendor/restore.py     # 还原大体积离线数据（约 285 MB），只需一次
python analysis/_env.py      # 自检，全部 OK 才算就绪
```

### 3. 导入与启用

1. 用 **Arsenal / HD2MM** 导入上面对应的 `.zip`（**只走管理器导入**，不要手动拷 `Addon/` 目录，
   那样多个 Mod 会互相覆盖）。
2. 启用 Mod，与 loader 一起 **Deploy**。
3. 进游戏生效。启动约 2 秒后开始扫描内存；补丁通常在**任务内**才完整打上（飞船上是 `SEARCHING` 属正常）。

### 4. 看状态与日志

每个 Mod 都会在下面这个目录写状态文件与详细日志：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\
    <mod名>_STATUS.txt      # 人可读状态，**首行即结论**
    <mod名>.log             # 详细日志，逐行即时落盘
```

- `OK - patch applied ...` —— ✅ 补丁已生效
- `SEARCHING - ...` —— ⏳ 还没找到目标表（多在飞船；进任务后自动继续）
- `FAILED - ...` —— ❌ 环境不满足（如 loader 版本过旧、FFI 不可用、判据没过）

**遇到问题请把 `<mod名>_STATUS.txt` 和 `<mod名>.log` 一起发到 Issues。**

---

## 🌐 联机说明（很重要，请务必读）

这些 Mod 是**纯客户端内存补丁**，但《绝地潜兵2》是 **主机权威（host-authoritative）**：
伤害/血量/军械生成由**房主的进程**用**房主自己的数据表**结算并同步。

| 你的身份 | 屏幕上看到 | 实际结算 |
| --- | --- | --- |
| **房主 / 单人 / 自己开房** | 改动后的效果 | ✅ **改动后（真正生效）** |
| **客机（进别人的房）** | 大概率看到改动后的表现 | ❌ **按房主的原版数据结算** |

- 想让改动**真正生效**，请**自己开房当房主**，或让**房主也装同一个 Mod**。
- 网络包篡改去伪造伤害属于**联机作弊**，会被 GameGuard 打击 —— 本仓库不做也不建议。
- ⚠️ HD2 启用了 **nProtect GameGuard**。这类进程内内存补丁属官方不支持的灰色地带，
  **强烈建议单人 / 自己开房使用，风险自担。**

---

## 📂 仓库结构

```
.
├── README.md              ← 你正在看的这页（总览大版面）
├── AI-HANDOFF.md          ← ★ 给接力的人/AI 的完整接手指南
├── HANDOVER.md            ← 原始交接与迁移文档（更详尽的技术细节）
├── LICENSE
│
├── docs/                  ← ★ 每个 Mod 一个独立版面（7 个）
│   ├── 01-orbital-120mm-eagle-500kg.md
│   ├── 02-orbital-380mm-hellbomb.md
│   ├── 03-bile-spewer-rl77-airburst.md
│   ├── 04-bile-spewer-salvo-choice-pack.md
│   ├── 05-mortar-sentry-napalm.md
│   ├── 06-sterilizer-g4-gas-damage.md
│   ├── 07-sterilizer-punchier-sfx.md
│   └── ingame-2026-10-13/         真实游戏日志样本
│
├── dist/                  ← 安装包（下载即用）+ 图标
│   ├── *.zip                      7 个安装包（下载即用）
│   ├── thumbnail*.png             各 Mod 的 Arsenal 卡片图标
│   └── README-*.md                （与 docs/ 对应的原始说明，保持包内一致）
│
├── src/                   ← ★ 8 个 addon 源码（7 个 Mod；胆汁齐射合集包内含 4 团 / 6 团两份）
│
├── analysis/              ← 离线测试、打包脚本、仿真 harness、夹具
│   ├── harness.lua               LuaJIT 假 FFI / 假内存 仿真框架
│   ├── test_*.py                 各 Mod 的功能 + 变异测试
│   ├── build_package_*.py        打包脚本（生成 dist/*.zip）
│   ├── build_fixtures_*.py       从真实明文生成测试夹具
│   ├── _env.py                   环境自检
│   └── ref/ fixtures/            引用数据与测试夹具
│
└── vendor/                ← 离线数据源与工具链（详见 vendor/README.md）
    ├── hd2-lua-mod/              HD2 Lua Mod 技能包（归档读写/打包工具 + 实战案例）
    ├── ref/                      typelib 反编译产物（字段偏移权威）
    ├── filediver/                FileDiver 明文镜像（每字段名字与注释）
    ├── community/                社区解好的 JSON（settings/entities/enums）
    └── restore.py                还原大体积数据的脚本
```

---

## 🧪 离线测试

所有 Mod 都有可复现的离线仿真测试，**不需要启动游戏**：

```bash
# 需要一个装了 lupa 的 Python（lupa 提供 luajit21）—— 搭法见 AI-HANDOFF.md §2
PY=<装了 lupa 的 python>          # Windows 例：<venv>/Scripts/python.exe

$PY analysis/test_addon.py                     # 1. 轨道120MM -> 25/25
$PY analysis/test_380mm.py                     # 2. 轨道380MM -> 7/7
$PY analysis/test_mortar_napalm.py             # 3. 迫击炮 + 凝固汽油弹 -> 23/23
$PY analysis/test_bug_artillery.py             # 4. 胆汁空爆 -> 28/28
$PY analysis/test_package_bug_salvo.py         # 5. 齐射合集包（结构与共存）
$PY analysis/test_bug_6rounds.py               # 5. 合集包内含的 6 团源码逻辑 -> 27/27
$PY analysis/test_bug_4rounds.py               # 5. 合集包内含的 4 团源码逻辑 -> 28/28
$PY analysis/test_sterilizer_gas_damage.py     # 6. 灭菌器伤害 + 毒气 -> 28/28
$PY analysis/test_sterilizer_sfx.py            # 7. 灭菌器音效 -> 16/16
$PY analysis/test_bug_combo.py                 # 空爆 × 多团 共存（两种加载顺序各 2700 帧）
```

**测试方法论要点**（也是这个仓库最值得看的部分）：

- **假 FFI + 假内存** 的完整仿真环境，可以注入任意内存布局、模拟写入失败、模拟多份表共存
- **变异测试**：故意把源码改坏（写错指纹、漏写回读校验、改成整条记录克隆……），
  断言测试**必须**抓到 —— 保证测试本身有牙齿
- **逐字节 keep-guard**：除目标字段外任何一个字节变了就**拒绝写入**
- 每个 Mod 发布前**从 zip 取回正文再复测**，确保交付物与源码逐字节一致

---

## 🤖 让 AI / 其他人接着改

这个仓库是**为接力而整理**的 —— 换台机器、换个人、换个 AI 都能无缝上手。

**给人看**：[`HANDOVER.md`](HANDOVER.md) —— 原始交接文档，含全部工程细节与踩坑记录。

**给 AI 看**：把下面这句话连同仓库一起丢给它即可 ——

> 读 `AI-HANDOFF.md`，再读 `HANDOVER.md`，按里面的约定干活。

[`AI-HANDOFF.md`](AI-HANDOFF.md) 是这个仓库**最重要的一份文档**，**自包含**地包含：

- **30 秒上手** + 第一步检查清单（先自检、先跑基线测试，再动代码）
- **环境恢复**：`python vendor/restore.py` + `python analysis/_env.py`；LuaJIT venv 的搭法
- **领域速查**：LDLD 表格式、类型哈希算法、**内存里常驻的表名单**、
  `ProjectileInfo` / `DamageInfo` 的完整字段布局
- **7 个 Mod 的技术档案表**：靶表、字段偏移、识别指纹、互斥关系 ← 改代码前必看
- **硬约定 30 条**（违反会出事），例如：
  - 内存里常驻的**只有 `*_Settings` 表**，`*_ComponentData` 表**运行时根本不加载** ← 最容易踩的坑
  - 认记录必须用**跨构建稳定的指纹**（物理量 / 本地化键哈希），**绝不用枚举下标**
  - 多个 Mod 改同一条记录时，复查必须**只为自己的字段负责**，绝不整条回写
  - 待定数值一律留**运行时 cfg 热调**的口子，用户不用重打包、不用重启游戏
- **已知做不到的事**（射程 / 持续时间 / 发射散布 / 音效音量 / 客机结算）—— 避免重复踩坑
- **标准工作流**（新增 Mod / 修改 Mod）+ **交付规范**

---

## 📜 免责声明

- 本项目**不包含**任何游戏代码、模型、贴图、音频或二进制资产。所有交付物都是运行时内存补丁。
- 仅供**学习、研究与单人娱乐**使用。使用本项目的 Mod 可能违反游戏的用户协议，
  **请自行评估风险，作者不对任何账号处罚或数据损失负责。**
- 请**不要**在公开匹配（尤其是官方活动、排行榜）中使用，也不要用它破坏他人的游戏体验。

<div align="center">

**如果你从这些 Mod 里学到东西，或者它们让游戏更好玩了 —— 给个 ⭐ 吧。**

</div>
