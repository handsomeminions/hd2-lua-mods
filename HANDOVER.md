# HD2 Mod 工作区 · 交接与迁移指南

> 最后更新：2026-10-16 15:50 · 工作区：`D:\WorkBuddyWork\hd2mods`
> 用途：**换电脑 / 换 WorkBuddy 账号后，照着这份文档就能无缝接着开发。**

> **已发布到 GitHub**：<https://github.com/handsomeminions/hd2-lua-mods>
> 新读者请先看 [`README.md`](README.md)（总览，**7 个 Mod**）与 [`AI-HANDOFF.md`](AI-HANDOFF.md)
> （接手指南 / AI 无缝衔接）。**本文档保留为原始工程细节与踩坑记录。**
>
> 下表列的是 **8 个源码 addon**（含合集包内的 4 团 / 6 团两份）；
> **对外发布为 7 个 Mod** —— 4 团与 6 团已整合进 Arsenal 合集包 `dist/BileSpewer-Salvo-Choice.zip`，
> 不再单独发布（2026-10-16 决定）。

---

## 0. 30 秒了解现状

这里在做《绝地潜兵2》的 **Lua 注入型内存 mod**（靠 **Bingus Shared Loader** 把 Lua 塞进游戏进程，
再用 FFI 读写游戏内存；**不改磁盘文件**，禁用 + Purge 即完全还原）。

已完成 **8 个源码 addon → 对外 7 个安装包**，每个都有：源码 + 安装包 + 中文说明 + 离线仿真测试。

| # | mod | 效果 | 源码 | 版本 | 离线测试 | 实机状态 |
|---|---|---|---|---|---|---|
| 1 | 轨道120MM高爆弹火力网 → **落地爆炸换成飞鹰500kg** | 弹道保持原版 120mm，只把落点爆炸换成 500kg（音效/伤害/范围/特效） | `src/orbital_120mm_500kg.lua` | 1.3.0 | 25/25 | ✅ 已实机验证通过 |
| 2 | 轨道380MM高爆弹火力网 → **地狱火炸弹** | 380mm 炮弹爆炸换成核弹级地狱火 | `src/orbital_380mm_hellbomb.lua` | 1.0.1 | 7/7 | ✅ **已实机确认**（`patched_records=2`） |
| 3 | 胆汁喷涌虫**胆汁迫击炮** → 落地炸成**空爆集束** | **外形/飞行保持原版绿色胆汁**，落地炸成空爆集束（25 子弹药按原版火箭物理飞溅） | `src/bug_artillery_airburst.lua` | **1.5.0** | 28/28 | ✅ 已实机验证通过 |
| 4 | A/M-12 **迫击哨戒炮** → **凝固汽油弹** | **只改落地爆炸**；索敌/弹道/速度/模型/拖尾全不动 | `src/mortar_sentry_napalm.lua` | 1.0.1 | 23/23 | ✅ 已实机验证通过 |
| 5 | 胆汁喷涌虫**一次齐射 6 团**（每发 3 枚；cfg 可现场调数） | 改射弹表 `+28 num_projectiles`；弹道/外形/音效/爆炸全不动 | `src/bug_artillery_6rounds.lua` | **2.2.0** | 27/27 | ✅ 实机确认：原版齐射 = **开火 2 次**；每发 3 枚 ⇒ 6 团 |
| 6 | 胆汁喷涌虫**一次齐射 4 团**（每发 2 枚；#5 的姊妹版） | 同上，只改 `+28`；**与 #5 互斥**（6 团版在跑时本项自动让位） | `src/bug_artillery_4rounds.lua` | **1.0.0** | 28/28 + combo4 | ✅ 已实机验证通过 |
| 7 | **Arsenal 合集包（对外只发这一个）**：#5 + #6 两个可勾选项 | 一个 ZIP，管理器里勾「4 Mortars」或「6 Mortars」；两个都勾则 4 团版自动让位 | 复用 #5/#6 源码 | — | `test_package_bug_salvo.py` | ✅ 已实机验证通过（两个档位均可勾选） |
| 8 | **TX-41 灭菌器 → G-4 伤害 + 毒气施加量 ×2** | 打 `DamageSettings` 灭菌器记录的 `+4/+8`（1→3）与 `+48/+56`（0.5→1.0，**只影响灭菌器**）；**射程与"持续时间"改不到**（见 §4.8） | `src/sterilizer_gas_damage.lua` | **2.0.0** | 28/28 | ✅ 已实机验证通过 |
| 9 | **TX-41 灭菌器 开火音效 → 换事件** | **不做表解析**：全内存搜 `firing.audio_event_start=1773671782` + 佐证窗口锁定武器组件，只写 4 字节；默认换成敌方化学无人机喷毒音效。**"原声放大"做不到**（见 §4.9） | `src/sterilizer_sfx.lua` | 1.0.0 | 16/16 | ✅ 已实机验证通过 |

- 接手指南：[`AI-HANDOFF.md`](AI-HANDOFF.md) ← **换机器后第一件事就是读它**
- 方法论 + 大量实战案例：`vendor/hd2-lua-mod/SKILL.md` 与 `vendor/hd2-lua-mod/references/`
- 实机日志证据存档：`docs/ingame-2026-10-13/`


---

## 1. 迁移：三步

### 第 1 步：复制整个工作文件夹

把 `hd2mods` **整个目录**复制到新电脑（U 盘 / 网盘 / 局域网都行）。
**完整体积约 314 MB**，因为里面已经把原来散落在机器别处的外部依赖收进了 `vendor/`（见下）。

### 第 2 步（可选）：想省体积就先瘦身

删掉这两个（它们都有压缩替补，共省 **~286 MB**，剩 **~27 MB**）：

```
vendor/community/data/                    241 MB   → 替补 vendor/community-data.zip (7.8 MB)
analysis/ref/generated_entities.dl_bin     45 MB   → 替补 vendor/filediver/.../generated_entities.dl_bin.gz (0.9 MB)
```

### 第 3 步：在新机器上自检

```bash
python vendor/restore.py     # 若上一步瘦身过：还原压缩副本（没瘦身的话会全部 [skip]）
python analysis/_env.py      # 路径自检：全部 OK 才算就绪
```

> `_env.py` 会告诉你缺什么、怎么补。全部 OK 后就能跑测试和打包了。

---

## 2. 新机器要准备的环境

| 需要什么 | 说明 | 必需? |
|---|---|---|
| **WorkBuddy** | 新账号登录即可；工作区就是刚复制过来的文件夹 | ✅ |
| **HD2 技能包** | 已随工作区带来：`vendor/hd2-lua-mod/`。若想在新账号里也能用「技能」形式调用，把该目录整个拷到 `~/.workbuddy/skills/hd2-lua-mod`（或 `%USERPROFILE%\.workbuddy\skills\`） | ✅ |
| **Python 3.13（托管版）** | WorkBuddy 自带（`~/.workbuddy/binaries/python/versions/3.13.12/python.exe`）。**用绝对路径调用**，别用系统 Python | ✅ |
| **lupa** | 离线仿真要用（跑 LuaJIT 2.1）。**必须装进 venv**（托管 python 本体装不上/装不到，实测 2026-10-16）：`<managed-python> -m venv <...>/envs/default` → `<venv>/Scripts/pip install lupa` | ✅（跑测试需要） |
| **Pillow** | 只在「给图标去水印」时需要。**和 lupa 装同一个 venv**：`<venv>/Scripts/pip install Pillow` | 可选 |
| **Go** | 只在需要**重新 dump typelib** 时用（`vendor/ref/` 里已有一份现成的） | 可选 |
| **游戏本体** | 《绝地潜兵2》 | 上机验证需要 |
| **Bingus Shared Loader v15+（API 1）** | 参考基线：本机是 **loader-v19 / API 1** | ✅ |
| **HD2 Arsenal / HD2 Mod Manager** | 用来导入本项目的 `.zip` | ✅ |

> **路径已做兼容**：脚本通过 `analysis/_env.py` 解析路径，优先级是
> **环境变量 → 工作区 `vendor/` → 旧机器的绝对路径**。
> 所以换盘符 / 换用户名都不影响，不必改代码。若要指向别处，设：
> `HD2_SKILL_DIR`、`HD2_REF_DIR`、`HD2_FD_DIR`、`HD2_COMMUNITY_DIR`。

---

## 3. 工作区地图

```
hd2mods/
├─ README.md                   ← 对外总览(7 个 Mod 的分类总表 + 快速开始 + 联机说明)
├─ AI-HANDOFF.md               ← ★ 接手指南(给人和 AI：硬约定 / 靶表字段指纹档案 / 已知做不到的事)
├─ HANDOVER.md                 ← 本文件
├─ src/                        ← 8 个 addon 源码（.lua，这就是"mod 本体"）
├─ dist/                       ← 交付物：7 个安装包 + 图标 + 中文说明
├─ docs/                       ← 对外发布用：每个 Mod 一个独立版面（01..07）
│  └─ ingame-2026-10-13/         实机日志存档(loader 日志 + mod 的 STATUS)
├─ analysis/                   ← 离线工具链
│  ├─ _env.py                    路径解析层(先跑这个自检)
│  ├─ harness.lua                离线仿真环境(假 FFI / 假内存 / 帧驱动)
│  ├─ test_*.py                  各 mod 的测试(功能+变异)
│  ├─ build_package*.py          打包脚本(manifest+图标+archive)
│  ├─ build_fixtures*.py         从真实 dl_bin 重新生成测试夹具
│  ├─ probe_120mm.py / probe_bombardments.py   离线"查表"小工具(实体->战备名)
│  ├─ make_icon.py               图标去水印(通用 CLI)
│  ├─ fixtures/                  测试夹具(当前构建的真实记录字节)
│  └─ ref/                       generated_entities.dl_bin(44MB) + 射弹表 dl_bin
└─ vendor/                     ← 从"机器别处"收进来的外部依赖(见 vendor/README.md)
   ├─ hd2-lua-mod/               技能包(打包/解析工具 + 案例文档)
   ├─ ref/                       typelib_all.json(字段偏移) / dl_type_names.txt ...
   ├─ filediver/datalibrary/     FileDiver 明文镜像 + *.go 字段名源码 + enum/
   ├─ community/data/            社区解好的 JSON(settings/entities/enums/translations)
   ├─ community-data.zip         上面 241MB 的压缩包(迁移省体积用)
   └─ restore.py                 还原脚本
```

---

## 4. 交付清单（8 个源码 addon → 对外 7 个安装包）

### 4.1 轨道120MM高爆弹火力网 → 落地爆炸 = 飞鹰500kg（v1.3.0）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/orbital_120mm_500kg` |
| Manifest GUID | `a914455b-75f8-4df8-9472-e0fc0bf64464` |
| 归档资源哈希 | `0x9641F49D04828A95` |
| 安装包 | `dist/Orbital120mm-Eagle500kg.zip` |
| 说明 | `dist/README-120mm.md` |
| 测试 | `analysis/test_addon.py`（15 功能 + 10 变异 = 25/25） |
| 机制 | **精准字段改写**（不是整条克隆）：定位常驻 `ProjectileSettings`（LDLD `0xBD4042C2`），按**决定性指纹** `audio_trail_event_stop=3741852184`（全表唯一对应两条 120mm 火力网炮弹 type 194/137，**天然排除同名凝固汽油弹 234/238**）+ `name_upper=2683992244` + 口径84/初速400/质量5000 + 拖尾哈希定位目标；源 = `500KG BOMB`（`name_upper=1027666422` + 50/500/500）。只把 **`+60 damage_info_type` / `+144 explosion_type_on_impact` / `+152 explosion_delay` / `+156 explosion_type_expire`** 这 4 段整段换成源的 —— 运行时读出，绝不写死枚举。**弹道/模型/速度/拖尾/飞行音效逐字节不动**，并有**逐字节 keep-guard**：除这 4 段外任何字节变了就拒绝写入 |
| 实机 | ✅ 已实机验证通过（v1.2.1 的日志见 `docs/ingame-2026-10-13/`；v1.3.0 精准字段改写后弹道保持原版 120mm） |
| 注意 | ⚠️ v1.2.x 的"整条克隆"会把**飞行参数**一起换掉（速度 400→500 / 质量 5000→500 / 阻力 0→0.5 / 引信 0→0.8），用户实测**弹道偏离原版、会打出原版范围** —— 这正是 v1.3.0 要修的。轰炸表 `BombardmentComponentData`（`0xCDBC43D8`）实测**不常驻内存**，所以"改轰炸表"的路线不通 |

### 4.2 轨道380MM高爆弹火力网 → 地狱火炸弹（v1.0.1）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/orbital_380mm_hellbomb` |
| Manifest GUID | `41d2cdd0-7f8e-4b4d-b54d-c98c36d455c6` |
| 归档资源哈希 | `0x9D7506152507448E` |
| 安装包 | `dist/Orbital380mm-Hellbomb.zip` |
| 说明 | `dist/README-380mm.md` |
| 测试 | `analysis/test_380mm.py`（7/7） |
| 机制 | 地狱火**不是一个射弹而是一种爆炸**。把 380mm 火力网射弹（type 80/266，`name_upper=2909856589`）的 `explosion_type_on_impact`（`+144`）改成"地狱火爆炸"。爆炸枚举**运行时**用**浮点半径三重指纹**（inner=17 / outer=25 / stagger=45）在 `ExplosionSettings`（LDLD `0x2AEA2592`）里定位 —— 本构建 = **242**，绝不写死 |
| 实机 | ✅ `OK - patch applied (revision 1.0.1)`，`hellbomb_explosion_type=242`，`patched_records=2` |
| 注意 | ⚠️ **380mm 炮弹被 380mm 火力网与"轨道行走火力网"共用**，两者都会变地狱火（已在 README 声明） |

### 4.3 胆汁喷涌虫胆汁迫击炮 → 落地炸成空爆集束（v1.5.0）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/bug_artillery_airburst` |
| Manifest GUID | `8cf04434-8f4e-43d5-8493-22aaace62e20` |
| 归档资源哈希 | `0x29AD71576A15D7A9` |
| 安装包 | `dist/BileSpewer-RL77Airburst.zip` |
| 说明 | `dist/README-bug-airburst.md` |
| 测试 | `analysis/test_bug_artillery.py`（17 功能 + 11 变异 = 28/28）+ `analysis/test_bug_combo.py` |
| 机制 | **精准字段改写**（不是整条克隆）：`+144 explosion_type_on_impact` ← RL-77 空爆集束爆炸；`+152 explosion_delay`（0→0.2）与 `+240 flags`（0xB5→0x94）← 火箭（让 25 枚子弹药按原版火箭物理抛射/飞溅）；`+208/+212` 飞行音效仅在 `SWAP_FLIGHT_FX=true` 时换。**外形（+128 模型 / +72/+88/+96 粒子）与飞行物理逐字节不动**，写入前逐字节自检，不过就拒绝写入 |
| ★ v1.4.0 回退 | v1.3.0 曾把 `+128` 模型 + `+72/+88/+96` 粒子换成火箭的（想做出完整火箭外形）；**实机火箭模型不渲染（模型丢失）**，加上绿团块被换掉 ⇒ 弹体看不见。v1.4.0 按要求把**外形整组回退**成原版绿色胆汁（`+128`==0 无模型，绿团块 = `+72/+96` 粒子）。**注意**：胆汁迫击炮原版本来就没有实体模型，所以"回退模型"= 同时保住 `+128` 与那两个粒子。 |
| 目标/源 | 目标 `ProjectileType_Bug_Artillery`（本构建 type 344，无名+口径50+初速30+质量1000+推进粒子 `758CA9293725AFE2`+拖尾 `AC522AC39D4B3529`+音频 `3340293219`）；源 `ProjectileType_Grenade_85mm_AirburstCluster`（type 312，Flak 近炸模式，口径85+质量3300+初速250+寿命1.5+近炸2m+拖尾 `C8FD1E326BA587BF`+音频 `1680798988`） |
| 实机 | ✅ 已实机验证通过 |
| 可选开关 | `CONFIG.SWAP_FLIGHT_FX`（默认 `true`，沿用户 v1.3.0）—— 现在**只管飞行音效**（`false` = 连音效也保持原版胆汁） |
| ★ v1.5.0（只改复查方式） | 稳态复查**不再整条回写记录**：改成从**当前字节**出发、只补自己那几段（`rebuild_owned`）。这样它才能和「多发齐射」(v2.2.0) **共存于同一条射弹记录**（那个 mod 改 `+28`；否则两边每 5 秒互相覆盖）。游戏内表现与 v1.4.0 完全一致 |

### 4.4 A/M-12 迫击哨戒炮 → 凝固汽油弹（v1.0.1）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/mortar_sentry_napalm` |
| Manifest GUID | `0208faf4-f89b-416e-8806-2f242d394ef2` |
| 归档资源哈希 | `0x6D3E44BC7FDA75AE` |
| 安装包 | `dist/MortarSentry-NapalmImpact.zip` |
| 说明 | `dist/README-mortar-napalm.md` |
| 测试 | `analysis/test_mortar_napalm.py`（23/23） |
| 机制 | **只改写一个字段**：A/M-12 炮弹记录的 `+144 explosion_type_on_impact` ← 凝固汽油弹壳记录的 `+144`（运行时读出，本构建 `360→63`）。索敌/弹道/速度/重力/模型/拖尾/音效/直接命中伤害全部保持原版，并用 `KEEP_FIELDS`（22 段）做"逐字节不许变"的硬校验。 |
| 目标/源 | 目标 = `40mm HE MORTAR` 里**口径360/初速100/质量70000** 那条（本构建 type 346；⚠ 同名共 4 条，含机器人迫击炮壳，必须叠加物理量 + 64 位资源哈希）；源 = 轨道凝固汽油弹火力网的汽油弹壳（口径84/质量5000，本构建 type 234） |
| 实机 | ✅ 已实机验证通过 |
| 注意 | 用的是**单颗汽油弹的爆炸**（含 `FireTemplate_Large` 燃烧火场）；`Orbital_Napalm` 与 `_Cheap` 两条爆炸记录逐字段完全相同，取哪条都等价 |
| 更新 | **v1.0.1** —— 修「打完补丁后立即停扫」导致内存里第二份射弹表可能漏打（改为一轮扫完再停） |

### 4.5 胆汁喷涌虫 多发齐射（v2.2.0）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/bug_artillery_6rounds` |
| Manifest GUID | `fe9ac944-32e4-4388-99d3-c146780aeaed`（与 v1.0.0 相同 → 管理器视为更新） |
| 归档资源哈希 | `0xFDF42831CFE52A72` |
| 安装包 | `dist/BileSpewer-6Mortars.zip` |
| 说明 | `dist/README-bug-6rounds.md` |
| 测试 | `analysis/test_bug_6rounds.py`（18 功能 + 9 变异 = 27/27）+ `analysis/test_bug_combo.py` |
| 机制 | 打 **`ProjectileSettings`（`0xBD4042C2`）** 里胆汁迫击炮射弹 `ProjectileType_Bug_Artillery` 的 **`+28 u32 num_projectiles`**（原版 1）。**只写这 4 个字节**，其余一律不动，写完回读校验 |
| 定位 | 指纹 = 无名(`name_upper==0`,`name_cased==0`) + 口径50 + 初速30 + 质量1000 + 推进粒子 `758CA9293725AFE2` + 拖尾 `29354B9DC32A52AC` + 飞行音效 ∈ {3340293219(胆汁), 1680798988(火箭)} ← **与空爆 mod 同一套定位法（实机已验证）** |
| ★ 数值可现场调 | 日志目录 `bug_artillery_6rounds.cfg`（一行一个 1..20 的整数）。稳态每 5 秒重读，**改了立刻重打、不用重打包也不用重启游戏** |
| 数值含义 | **总发数 = 每次开火枚数 × 开火次数**。实机确认原版齐射 = **开火 2 次**（2 个方向），每次 1 枚 ⇒ 默认设 **3** 得 3×2 = **6 团** |
| 实机 | ✅ 已实机确认两件事：① v2.0.0 的补丁确实生效（`idx=29, type=344, num 1->3`）；② **原版齐射只开火 2 次**（v2.1.0 设 2 时实测 `2×2 = 4` 团） |
| ★ 版本演变（2.0.0 → 2.1.0 → 2.2.0） | 2.0.0 = 3 枚/发（实机生效但被误判成"一大团"）；2.1.0 = 改成 2 枚/发（以为齐射是 3 次，实测只有 `2×2 = 4` 团，太少）；**2.2.0 = 回到 3 枚/发**，因为最终实测确认**齐射 = 开火 2 次** ⇒ 3×2 = 6。⚠️ 旧 `bug_artillery_6rounds.cfg` 会覆盖新默认，升级时必须把内容改成 `3` 或删掉 |
| ★ **"开火 3 次 × 每次 2 枚"（3 个方向）能实现吗** | **不能。** 开火次数 / 连发数 / 武器散布全在**不加载**的 `*ComponentData` 里；AI"齐射 / 攻击模式"在能力资源里（不在离线数据）。射弹表唯一的 `spread` 是**跳弹**用的。⇒ **方向数由游戏固定，能调的只有"每方向几枚"**。**判定法**：cfg=1 进任务数一次齐射 —— 2 团 ⇒ 开火 2 次（要 6 就 cfg=3）；**3 团 ⇒ 开火 3 次，那 cfg=2 就正是"3 方向 × 2 枚"**。想核实"内存里到底有哪些可改的表"：等一轮 pass 跑完，日志里有一行完整的 `LDLD types seen: 0x... xN, ...` |
| ★ 为什么"同一次开火的多枚"散不开 | `ProjectileInfo`（272B）里唯一的 spread 是 `+192/+196 ricochet_spread_*`（跳弹散布；胆汁 12/45 **比霰弹枪 2/12 还大** ⇒ 不是发射散布）；`+256 unk_vector` 全表恒为 0；`+216 unk_float2` 胆汁与霰弹枪同为 -1.0。⇒ **发射散布不在射弹表里**（霰弹枪的散布来自武器侧参数，而 `*ComponentData` 不加载）。所以"分散"只能靠"少发多次"，改不到开火次数就只能压缩每发枚数 |
| ★ v1.0.0 为什么失败 | v1.0.0 改的是 `WeaponDataComponentData` 的 `+140 num_burst_rounds`。**实机日志证明那张表在内存里不存在**：4 轮全内存 LDLD 普查（13.7 GB）只见到 `*_Settings` 表，**0 个 `*ComponentData`** → `targets_found=0/4`。见硬约定 **#17** |
| ★ 与空爆 mod 共存 | 两个 mod 改的是**同一条射弹记录的不同字段**。v1.5.0/v2.1.0 都把复查改成"**只为自己的字段负责**"（6rounds 只写 4 字节；airburst 从当前字节出发只补自己那几段），避免每 5 秒互相覆盖。另外 6rounds 的指纹**刻意不含** `+144/+152/+208/+212/+240`（那是 airburst 会改的字段） |

### 4.6 胆汁喷涌虫 一次齐射 4 团（每发 2 枚；v1.0.0）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/bug_artillery_4rounds` |
| Manifest GUID | `70126b6b-5fae-4936-9937-237fb7ab2c23` |
| 归档资源哈希 | `0x24907AAB459A9AD9` |
| 安装包 | `dist/BileSpewer-4Mortars.zip` |
| 说明 | `dist/README-bug-4rounds.md` |
| 测试 | `analysis/test_bug_4rounds.py`（19 功能 + 9 变异 = 28/28）+ `analysis/test_bug_combo4.py` |
| 机制 | 与 §4.5 **完全相同**（打 `ProjectileSettings` 里胆汁迫击炮射弹的 `+28 num_projectiles`，只写 4 字节，其余 keep-guard）；默认值 **2** ⇒ 2 × 2 次齐射 = **4 团** |
| cfg | `bug_artillery_4rounds.cfg` —— 与 §4.5 的 `bug_artillery_6rounds.cfg` **互相独立** |
| ★ 与 §4.5 互斥 | 两个 addon 改的是**同一条记录里的同一个字段** ⇒ 本项内置**自动让位**：`RIVAL_SINGLETON = "_HD2_BUG_ARTILLERY_6ROUNDS"`，在 `init` 与稳态 `recheck` **两处**检测，命中即 `phase="dead"`、不扫描不写入（STATUS 首行 `SKIPPED - …`）。单测 **T19** 守着。管理器里**二选一启用** |
| 实机 | ✅ 已实机验证通过 |

### 4.7 Arsenal 合集包：胆汁喷涌虫 齐射档位选择（v1.0.0）

| 项 | 值 |
|---|---|
| 安装包 | `dist/BileSpewer-Salvo-Choice.zip` |
| Manifest GUID | `01845481-055a-41a8-8d63-b26764e74933` |
| 说明 | `dist/README-bug-salvo-pack.md` |
| 打包脚本 | `analysis/build_package_bug_salvo.py` |
| 校验脚本 | `analysis/test_package_bug_salvo.py` |
| ZIP 结构 | 根: `manifest.json` + `thumbnail.png` + `FourRounds.png`/`SixRounds.png`；两个选项目录 `FourRounds/`、`SixRounds/` 各放一份 `9ba626afa44a3aa3.patch_0`（+ 空 `.stream`/`.gpu_resources`） |
| manifest | V1 规范 `Options[]` 两项：`4 Mortars Per Salvo`（`Include=["FourRounds"]`）/ `6 Mortars Per Salvo`（`Include=["SixRounds"]`）。规范来源：HD2 Modding Wiki `dev/misc/manifest.html`（`Options[].Include` 列出"勾选该项时要加入的目录"；`Image` 是选项自己的图） |
| 资源 | FourRounds = `mods/hd2/bug_artillery_4rounds`（v1.0.0）；SixRounds = `mods/hd2/bug_artillery_6rounds`（v2.2.0）—— 与两个独立包**同一份资源** |
| ★ 不要重复装 | 合集包与 `BileSpewer-4Mortars.zip` / `BileSpewer-6Mortars.zip` 共享资源，**二选一**（同时开会部署两份定义同一资源的补丁） |
| ★ 双选行为 | 两个选项都勾 ⇒ 4 团版**自动让位**（STATUS 首行 `SKIPPED`），6 团版生效；`test_package_bug_salvo.py` 对**两种加载顺序**都断言（各 1500 帧 + 3 个复查周期，记录不漂移、钩子链完好） |
| cfg | 两档各自独立：`bug_artillery_4rounds.cfg`（默认 2）/ `bug_artillery_6rounds.cfg`（默认 3） |
| 实机 | ✅ 已实机验证通过 |

### 4.8 TX-41 灭菌器 伤害→G-4 级别 + 毒气施加量 ×2（v2.0.0）

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/sterilizer_gas_damage` |
| Manifest GUID | `d369d2c7-93a1-455a-a61a-ba3c7d47e991` |
| 归档资源哈希 | `0xFB52FC6738BA1AC2` |
| 安装包 | `dist/Sterilizer-G4GasDamage.zip`（v1.x/v2.0 **同资源名 + 同 GUID** → 覆盖安装，不会变成两个 mod） |
| 说明 | `dist/README-sterilizer.md` |
| 测试 | `analysis/test_sterilizer_gas_damage.py`（19 功能 + 9 变异 = **28/28**） |
| 生成器 | `analysis/make_sterilizer_mod.py` 只在 v1.0.0 用过；**v2.0.0 起直接手改 lua**。夹具 `analysis/build_fixtures_sterilizer.py` |
| 机制① | 打 **`DamageSettings`（`0xE0A72CF0`，`*_Settings` → 常驻内存）** 里 `DamageInfoType_Spray_Chem_Gun` 记录的 **`+4 damage` 与 `+8 durable_damage`**：1→3（= G-4 毒气榴弹爆炸伤害） |
| 机制② | 同记录 **`+48 SE[Gas].value`** 与 **`+56 SE[Gas_Confusion].value`**：0.5→1.0（×2，用户指定"原版 2 倍"）。**两次独立 4 字节写**；中间 `+52..+55`(SE[1].type) **绝不触碰**（T2 有专门断言） |
| 写入量 | 只写 **3 段共 16 字节**（`+4..+11` / `+48..+51` / `+56..+59`），逐段回读校验，其余逐字节 keep-guard |
| ★ 指纹（v2.0.0 收紧） | `AP=[5,5,5,0]` + `demo=5` + `force=10/5` + **前两条 SE 的 type 非零** + 后两条 SE type = 0 + `damage∈[1,200]`。**完全不引用 damage / durable / SE value**（都是本 mod 会改的字段）⇒ 打完补丁、cfg 热调之后仍认得出自己（T17 守）。离线核对：该指纹在真实 649 条整表上**恰好命中 2 条** |
| ★ 同名邻居 | 敌方化学无人机 `Drone_Chem_Gun` 与灭菌器 `Spray_Chem_Gun` **数值完全相同**，只能靠 DamageInfoType 相邻 + 取小编号区分（社区 12<13；本构建 28<29）；**并且要求两条候选的 `(SE0.type, SE1.type)` 一致**。不满足任一 → **拒绝写入**（宁可不打，也不强化敌人）。单测 T11/T12/T14/T19 守着 |
| ★ 为什么"毒气强度"只能改"施加量" | `StatusEffectType_Gas` / `Gas_Confusion` 的 `strength`/`duration` 在**全局表 `StatusEffectSettings`（`0xC63E0B22`）**里，被 灭菌器 / 敌方化学无人机 / G-4 毒气榴弹 / 轨道毒气弹 / 胚胎簇 **共用** ⇒ 改它 = 敌我一起变强（用户拍板选"**仅灭菌器**"）。而 `duration` **没有 per-weapon 覆盖入口** ⇒ **持续时间改不到**，只能拉高灭菌器记录里的施加量。（`StatusEffectInfo` 152B 布局：`type@0` / `shader_preset@16` / `shading_env@24` / `fade@32` / **`strength@36`** / **`duration@40`** / `damage_info_type@44` —— 已用类型哈希交叉验证） |
| ★ 射程做不到 | 喷射武器 `SprayWeaponComponent.projectile_type = None` → 不发射弹、伤害靠粒子碰撞；射程由枪口 VFX 粒子决定。离线穷尽：`SprayWeaponComponent`(224B/16 字段) 与 `WeaponDataComponent`(56 字段) **无 range/length/distance**；`SprayCapsuleOverlap`(带 length) 实体实例数 **0**；`BeamSettings` 无化学喷流项；且这些表都是不加载的 `*ComponentData`。⇒ **射程属 VFX 资产，改不到** |
| cfg | `sterilizer_gas_damage.cfg`：`damage=3` / `gas=1.000`（~5s 热重打）；**兼容旧版**"整个文件一个裸数字 = damage" |
| 实机 | ✅ 已实机验证通过 |

### 4.9 TX-41 灭菌器 开火音效替换（v1.0.0）

> **★ 结论先行**：**"把原声放大"在内存层做不到** —— 音量编在 Wwise SoundBank 音频资源里，
> 任何数据字段都没有。数据层最多能**换一个音效事件**，而那条字段又在 `*ComponentData`（不加载）。
> 所以本 mod 走了一条**全新的路**：直接在裸内存里搜特征值。

| 项 | 值 |
|---|---|
| 资源名 | `mods/hd2/sterilizer_sfx` |
| Manifest GUID | `43181292-a226-45de-9610-46a2de6cadfc` |
| 归档资源哈希 | `0x712725C4491819BD` |
| 安装包 | `dist/Sterilizer-PunchierSFX.zip` |
| 说明 | `dist/README-sterilizer-sfx.md`（含"若失败"的 `hd2-audio-modder` + Wwise 完整步骤） |
| 测试 | `analysis/test_sterilizer_sfx.py`（12 功能 + 4 变异 = **16/16**） |
| 打包 | `analysis/build_package_sterilizer_sfx.py`；图标 `dist/thumbnail_sterilizer_sfx.png`（**PIL 叠声波，没花图像额度**） |
| ★ 机制 | **不做 LDLD 表解析**。全内存搜 `firing.audio_event_start`（1773671782）的 4 字节 LE，命中点 **±256B 内必须再出现 ≥1 个佐证哈希**（见下），才**只写这 4 字节** + 回读 |
| ★ 佐证值 | `599097114`(firing.stop) / `418315309`(firing.callout) / `1803865503`(audio_node) / `3435018303`(warmup.a0) / `1928837757`(cooldown.a0) / `3956223216`(vo_event) + **`0xA3D15A3BBC56DE55`(firing.muzzle_effect, u64 —— 14 个实例里只属于灭菌器)** |
| ★ 关键守则 | **孤立出现的 1773671782 一律跳过不改**（宁可漏，不可错）；`OVERLAP=1024 > 2*WIN=512` 保证跨块窗口不漏；稳态复查**用窗口佐证重新验证位置** |
| cfg | `sterilizer_sfx.cfg`：`event=<id>`（默认 `335829265` = 敌无人机喷毒；`1773671782` = 原版对照） |
| 数据来源 | 离线明文 `vendor/community/data/entities/SprayWeaponComponentData.json`（14 个实例）+ typelib 布局 |
| 实机 | ✅ 已实机验证通过 |
| 排障 | 把 STATUS + `.log` 发回：`hits` / `lone_hits_skipped` / `rewrites` 能区分"值不在内存"/"值在但佐证不齐"/"游戏频繁重置" |

## 5. 常用命令速查
```bash
PY="<带 lupa 的 python 绝对路径>"        # 例: C:/Users/<你>/.workbuddy/binaries/python/envs/default/Scripts/python.exe
#   ★ 托管 python 本体**不带 lupa**; 离线测试必须用装了 lupa 的那个 venv:/n#     C:/Users/<你>/.workbuddy/binaries/python/versions/3.13.12/python.exe -m venv C:/Users/<你>/.workbuddy/binaries/python/envs/default
#     C:/Users/<你>/.workbuddy/binaries/python/envs/default/Scripts/pip install lupa Pillow

# 路径自检(换机器后先跑这个)
"$PY" analysis/_env.py

# 跑测试套件
cd analysis
"$PY" test_addon.py            # 120mm  -> 通过 25, 失败 0
"$PY" test_380mm.py            # 380mm  -> 通过 7,  失败 0
"$PY" test_bug_artillery.py    # 胆汁   -> 通过 27, 失败 0
"$PY" test_mortar_napalm.py    # 迫击炮 -> 通过 23, 失败 0
"$PY" test_bug_6rounds.py      # 胆汁 6 团 -> 通过 27, 失败 0
"$PY" test_bug_4rounds.py      # 胆汁 4 团 -> 通过 28, 失败 0
"$PY" test_sterilizer_gas_damage.py  # 灭菌器(伤害+毒气) -> 通过 28, 失败 0
"$PY" test_sterilizer_sfx.py           # 灭菌器(音效,实验) -> 通过 16, 失败 0
"$PY" test_bug_combo.py six_first   # 共存(两种加载顺序都要跑)
"$PY" test_bug_combo.py ab_first
"$PY" test_bug_combo4.py six_first  # 4 团版 x 空爆(两种加载顺序)
"$PY" test_bug_combo4.py ab_first
"$PY" test_package_bug_salvo.py   # 合集包(结构+manifest+双选共存)

# 只跑某一个用例
"$PY" test_mortar_napalm.py T1

# 语法闸门(必须用游戏同款 LuaJIT; 关键是要抓 '//' 这类 5.3+ 语法)
"$PY" -c "
from lupa import luajit21
src=open('src/<名字>.lua',encoding='utf-8').read()
L=luajit21.LuaRuntime(); L.globals().SRC=src
print(L.eval('(function(s) local f,e=loadstring(s); return f~=nil,e end)(SRC)'))
"

# 重新打包(含图标)
"$PY" analysis/build_package.py                     # 120mm
"$PY" analysis/build_package_380.py                 # 380mm
"$PY" analysis/build_package_bug_airburst.py        # 胆汁
"$PY" analysis/build_package_mortar_napalm.py       # 迫击炮
"$PY" analysis/build_package_bug_6rounds.py         # 胆汁 6 团
"$PY" analysis/build_package_bug_4rounds.py         # 胆汁 4 团(姊妹版)
"$PY" analysis/build_package_bug_salvo.py          # 胆汁 齐射档位合集(多选项)
"$PY" analysis/build_package_sterilizer.py         # TX-41 灭菌器伤害
"$PY" analysis/build_package_sterilizer_sfx.py     # TX-41 灭菌器音效

# 用"发布正文"(zip 里的真身)复测 — 每套测试都支持
#   HD2_ADDON_SRC=<解出来的 .lua>            (120mm)
#   HD2_ADDON_380_SRC=<...>                  (380mm)
#   HD2_ADDON_BA_SRC=<...>                   (胆汁)
#   HD2_ADDON_MS_SRC=<...>                   (迫击炮)
#   HD2_ADDON_6R_SRC=<...>                   (胆汁 6 发)
#   HD2_ADDON_4R_SRC=<...>                   (胆汁 4 团)
#   HD2_ADDON_SZ_SRC=<...>                   (灭菌器伤害)
#   HD2_ADDON_SFX_SRC=<...>                  (灭菌器音效)

# 看实机日志
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\
    BingusSharedLoader.log                      loader 版本 + 发现列表(第一步排查)
    <mod>_STATUS.txt                            给用户看: 第一行就是结论
    <mod>.log                                   给开发者看: 详细过程
```

---

## 6. 开发一个新 mod 的标准流程

1. **离线先查明文**（别急着上机 —— 上机一趟要重开游戏，很贵）
   - 游戏表在磁盘上是加密的（45MB 里 `LDLD` 出现 0 次），但 `vendor/filediver/` 有明文镜像；
   - **先查社区有没有解好的 JSON**：`vendor/community/data/settings/generated_*.json`；
   - 字段布局以 `vendor/ref/typelib_all.json`（偏移/大小）与
     `vendor/filediver/datalibrary/*.go`（**字段名与注释**，由游戏 typelib 生成）为准。
2. **认记录用"稳定指纹"，不要用枚举下标**
   - 枚举下标会随版本漂移（`ProjectileType 139` 从"200kg 炸弹"变成"步枪弹"）；
   - 稳定的是：`name_upper`（本地化键哈希）、64 位资源哈希（粒子/模型/音频）、
     物理量（口径/质量/速度/阻力/重力，留容差）。
   - **类型哈希 = djb2；资源名哈希 = MurmurHash64A(seed 0)**，两套别混。
3. **判据要能容忍构建漂移**：用"断层"（最高分 ≥ 3× 第二名 且 唯一）而不是"逐位 100% 吻合"。
4. **写运行时补丁**：签名定位表 → 内容指纹定位记录 → 备份原字节 → 写 → **回读校验** → 每 5 秒按
   **记录地址直读**复查（绝不重跑全表解析）。
5. **离线仿真**：`lupa.luajit21` + `harness.lua` 假 FFI/假内存，**并写变异测试**
   （把修好的 bug 改回去，测试必须失败，否则测试没意义）。
6. **打包**：`analysis/build_package_*.py`。
7. **上机**：管理器导入 `dist/*.zip` → 与 loader 一起 Deploy → 看 `STATUS.txt` 首行。

---

## 7. 必须遵守的约定 / 已踩过的坑（精简版）

> 完整版在 [`AI-HANDOFF.md`](AI-HANDOFF.md) 第 8 节（30 条）与 `vendor/hd2-lua-mod/SKILL.md`（第 6 节有 50 条）。
> 下面是最容易再犯的：

**运行环境**

- 仿真器必须 `from lupa.luajit21 import LuaRuntime`（默认是 Lua 5.5，会放过 `//` 这类语法，实机才炸）。
- LuaJIT 没有位运算、没有 `string.pack`；`0x80F1A156D9FA1E36` 存进 number 会被 53 位精度截断 ——
  **64 位哈希一律走十六进制字符串比较**。
- Lua 的 `a and nil or b` 在 `a` 为真时会去求值 `b`（`nil or b` → `b`），**别用它做"可能为 nil"的赋值**。
- `table.concat` 会把数字按十进制文本拼接 —— 字节操作一律用纯字符串。

**内存 / 表解析**

- `LDLD` 的 `size` 字段**不含 24 字节头**；设置表描述符在 `+24`，实体 blob 在 `+24`（数据起点不同）。
- **数组描述符：文件里是相对偏移，内存里是绝对指针** —— 两种都试，用语义判定（"一个 bug、两个症状"）。
- **绝不用"表大小/记录数/bucket 数"当准入条件** —— 一次构建更新就能让 mod 静默失效（实测 4 个 mod 被同一次更新打掉）。
- 同一张表在内存里**可能有多份**：全部收集、全部打；而且**持续维护**（被冲掉要重打）。
- `ProjectileInfo`（272B）全为标量/位域（POD+BITFIELD），**没有指针** → 整条克隆安全。
- ★★ **实机内存里常驻的只有 `*_Settings` 表；`*_ComponentData`（实体组件表）根本不加载。**
  实测：一次 4 轮全内存 `LDLD` 普查（13.7 GB）只命中 `ProjectileSettings` / `ExplosionSettings` /
  `StratagemSettings` / `DamageSettings` … ，**一个 `*ComponentData` 都没有**。
  ⇒ **要改运行时行为，只能在 `*_Settings` 里找等价的量**（别再对着"某个敌人的某个组件字段"设计 mod）。
  把扫到的 32 位哈希反查成表名：`vendor/ref/typelib_all.json` 的 `hash` → `name`。
- ★ **"一次开火生成几枚射弹" = `ProjectileInfo +28 u32 num_projectiles`**（霰弹枪靠它打 9~20 颗弹丸）。
  **总发数 = 每次开火枚数 × 开火次数**；一次"齐射几发"通常不在这张表里。
- ★ **别指望用射弹表让"同一次开火的多枚散开"**：`ProjectileInfo` 里唯一的 spread 是
  `+192/+196 ricochet_spread_*`（跳弹散布；胆汁 12/45 比霰弹枪 2/12 还大 ⇒ 不是发射散布）；
  `+256 unk_vector` 全表恒 0；`+216 unk_float2` 胆汁与霰弹枪同为 -1.0。**发射散布不在射弹表里**
  （霰弹枪的散布来自武器侧参数，而 `*ComponentData` 不加载 ⇒ 改不到）。
  ⇒ 想要"分散"只能"少发多次"（原版开火次数改不了，就压缩每发枚数）。
- ★ **多个 mod 改到同一条记录时，复查必须"只为自己的字段负责"**：从**当前字节**出发、
  只补自己那几段（或只写自己那几个字节），**绝不整条回写** —— 否则两边每 5 秒互相覆盖。
  同理，**定位指纹不能包含"别的 mod 会改的字段"**，否则同装时认不出自己的目标。
- ★ 数值不确定时，把待定值放进日志目录的一个小 cfg 文件（纯数字），稳态复查时重读、
  变了就重打 —— 用户**不用重打包、不用重启游戏**就能现场试出正确值。

**性能 / 生命周期**（否则玩家会掉帧）

- 搜索期：单帧 ≤ 2ms CPU、单块 ≤ 256KB、每 2 帧推进一步、空手**指数退避**。
- **打完即休眠**：绝不周期性全量重扫（实测每 10 分钟重扫 = 掉帧 40 秒）。
- 复查只按**已记录的地址直读**（<1µs）；只有所有副本都消失才重新搜。
- 稳态下把 update 钩子步长放宽到 60 帧；**不要**在稳态高频写 `STATUS.txt`。
- 挂 `update` 钩子要写**安全退钩**（只有在自身仍是顶层 wrapper 时才还原），否则会切断后面其他 mod 的钩子链。

**发布 / 兼容**

- 每个 addon **只准碰自己唯一命名的全局** + `update`；内部函数一律 `local`（用前向声明）。
  历史事故：两个 mod 都定义全局 `end_pass`/`flush_log` → 后者覆盖前者 → 日志全丢、补丁不生效。
- `manifest.json` 的 `Name` **必须是纯 ASCII 且不含 `\ / : * ? " < > |`**（一个冒号就能让导入失败）。
- GUID 跨版本保持稳定 → 管理器视为同一 mod 的更新（图标也会跟着换）。
- 手动把 `Addon/` 拷进 `data/` 会**互相覆盖** —— **永远用管理器导入**。
- 面向用户的每一句文案都是支持成本：写清"只需 loader 一个"、`API 1` 指的是什么。

**合规**

- 游戏有 **nProtect GameGuard**：**不要从外部进程读游戏内存**（别用 ctypes 挂 `OpenProcess`），
  只在游戏内用只读/写 addon；联机时**主机权威**，客机看不到改动、伤害按房主算 —— 主动提醒用户。

---

## 8. 实机验证状态

**全部 8 个源码 addon（对外 7 个安装包）已于 2026-10-16 全部实机验证通过。**

| # | Mod | 上机结论 |
|---|---|---|
| 1 | 轨道120MM → 飞鹰500kg（v1.3.0） | ✅ 落点爆炸为 500kg，弹道仍为原版 120mm |
| 2 | 轨道380MM → 地狱火炸弹（v1.0.1） | ✅ 核弹级爆炸生效 |
| 3 | 胆汁迫击炮 → RL-77 空爆集束（v1.5.0） | ✅ 外形仍为原版绿色胆汁，落地炸成空爆 |
| 4 | 迫击哨戒炮 → 凝固汽油弹（v1.0.1） | ✅ 落地留下燃烧火海 |
| 5 | 胆汁喷涌虫 · 一次齐射 6 团（v2.2.0） | ✅ 6 团（3 枚 × 2 次齐射） |
| 6 | 胆汁喷涌虫 · 一次齐射 4 团（v1.0.0） | ✅ 4 团 |
| 7 | 齐射档位合集包（v1.0.0） | ✅ 两个档位均可勾选，齐射团数正确 |
| 8 | 灭菌器 → G-4 伤害 + 毒气 ×2（v2.0.0） | ✅ 伤害与毒气施加量均提升 |
| 9 | 灭菌器 → 开火音效替换（v1.0.0） | ✅ 内存路线成立，音效已替换 |

**仍值得留意的结构性限制**（不是 bug，详见各 mod 的 README / `AI-HANDOFF.md` §6）：

- **胆汁齐射**：「同一次开火 N 枚」是**同向、会叠在一起** —— 射弹表没有发射散布参数，
  方向数由游戏固定，能调的只有「每方向几枚」。
- **灭菌器**：**射程**与**毒气持续时间**改不到（前者数据层无字段，后者只在全局表）；
  音效只能「换事件」，做不到「放大音量」（音量编在 Wwise 资源里）。
- **联机**：所有改动都是**客户端内存补丁**，客机看不到、伤害按房主结算 —— 要真正生效请自己开房当房主。

**回归复现方法**：进任务后看 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\<mod>_STATUS.txt`，
首行应为 `OK - patch applied (revision ...)`。

---

## 9. 换账号 / 换机器时的特别注意

- **技能是账号级的**：新账号的 WorkBuddy 不会自带 `hd2-lua-mod`。用 `vendor/hd2-lua-mod/`
  （脚本已优先指向它），或把它拷到新账号的 `~/.workbuddy/skills/` 下重新启用。
- **路径里的用户名变了**：已通过 `analysis/_env.py` 解决；`vendor/` 跟着工作区走，无需改代码。
- **`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\` 会重新生成**（旧日志别指望跟过来；
  本次的已存档在 `docs/ingame-2026-10-13/`）。
- **游戏构建指纹**（本次所有偏移都是在这个构建上验证的）：
  `executable 6AB382E4`、`game.dll 6AB3B43F`（见 `docs/ingame-2026-10-13/BingusSharedLoader.log`）。
  游戏更新后偏移/枚举可能漂移 —— 那时**不要改代码里的常量**，而是：
  1. 重新取明文（`vendor/README.md` 附录）；
  2. 用 `analysis/probe_*.py` 重新确认；
  3. 必要时用**全表复现**重新校准偏移（本项目所有偏移都是这么验过的）。
- 复制完建议先跑一遍**三个测试套件**：全绿就说明环境完全接上了。

---

## 附录：术语与哈希速查

| 概念 | 值 / 算法 |
|---|---|
| 载体文件 | `data/9ba626afa44a3aa3.patch_<N>`（编号由管理器分配，别写死） |
| 数据表块魔数 | `LDLD` + u32 版本(=1) + u32 类型哈希 + u32 大小 |
| 类型哈希 | `djb2(name)`（`ProjectileSettings`=`0xBD4042C2`，`ExplosionSettings`=`0x2AEA2592`，`StratagemSettings`=`0x30EB6399`，`DamageSettings`=`0xE0A72CF0`，`ArcSettings`=`0xAFDF0267`，`BombardmentComponentData`=`0xCDBC43D8`，`WeaponDataComponentData`=`0x88E4DBB1`） |
| ★★ 哪些表在内存里 | **只有 `*_Settings` 表常驻内存；`*_ComponentData` 表不加载**（实机 4 轮全内存普查 0 命中）。要把扫到的哈希反查成表名，用 `vendor/ref/typelib_all.json` 的 `hash`→`name` |
| `ProjectileInfo` 关键字段（272B） | `+24 calibre(f32)`、**`+28 num_projectiles(u32)`=一次开火生成几枚**（霰弹枪靠它打 9~20 颗）、`+32 speed`、`+36 mass`、`+144 explosion_type_on_impact` |
| 实体组件表布局 | `+24 ComponentIndexData[N]`（16B/条：u64 实体哈希 + u32 记录号 + u32 0）+ 记录区；`stride=(size−N×16)/记录数`。**N/记录数/stride 全部运行时自标定，不写死** |
| `WeaponDataComponent` 关键字段 | `+140 num_burst_rounds`（一次连发几发）、`+144/+148/+152/+156` 四个 fire_mode（记录长度 1232B） |
| 资源名哈希 | `MurmurHash64A(name, seed=0)` |
| Lua 资源类型标记 | `0xA14E8DFA2CD117E2` |
| Addon 首行 | `-- HD2-Addon: mods/<作者>/<模块名>`（必须明文，编译成字节码会丢） |
| Loader 版本闸门 | `_G.CowboyBingusModLoader = { api = 1, version = ... }`；读不到就退化为读 `BingusSharedLoader.log` 首行 |
| 本项目基线环境 | Bingus Shared Loader **v19 / API 1**；游戏构建戳 `6AB382E4` / `6AB3B43F` |
