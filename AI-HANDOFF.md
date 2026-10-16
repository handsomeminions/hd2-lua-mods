# AI-HANDOFF.md —— 接手指南（给人，也给 AI）

> 这个文件是**给下一个接手的人或 AI 的地图**。
> 目标：你拿到这个仓库，**不需要问原作者任何问题**，就能看懂、运行、修改、再发布。
>
> **如果你是一个 AI 助手，请按下面的顺序做完第 0 节，再动任何代码。**

---

## 0. 30 秒上手（AI 必读）

```
你（AI）被要求接手本仓库。请依次执行：

1. 读本文件（AI-HANDOFF.md）—— 全部
2. 读 .workbuddy/memory/MEMORY.md —— 项目 38 条硬约定，**违反会出事**
3. 读 HANDOVER.md —— 原始交接文档（更详尽的工程细节）
4. 运行环境自检：
      python vendor/restore.py      # 还原大体积离线数据（若缺失）
      python analysis/_env.py       # 必须全部 OK
5. 跑一遍测试确认基线：
      <venv-python> analysis/test_addon.py 等（见 §7）
6. 只有在 4、5 都通过之后，才开始改代码。
7. 改完必须：跑测试（连跑 5~8 遍查时序抖动）→ 变异测试 → 重新打包 →
   从 zip 取回正文复测 → 更新 §5 的档案表 + HANDOVER.md + .workbuddy/memory/MEMORY.md
```

**最容易犯的两个错**（先记住，能省你半天）：

1. **不要以为 `*ComponentData` 表在内存里。** 内存里常驻的**只有 `*_Settings` 家族**（本构建 37 张表）。
   `WeaponDataComponentData`、`SprayWeaponComponentData`、`BombardmentComponentData` 等
   **运行时根本不加载** —— 对着它们设计的 Mod 会 100% 失败（踩过，见 §6）。
2. **不要用枚举下标（index）认记录。** 枚举顺序随游戏构建漂移，而且会**静默写错**（不是找不到）。
   必须用**跨构建稳定的指纹**：物理量（口径/速度/质量）、本地化键哈希（`name_upper`）、
   粒子/音效资源哈希、或者**纯结构关系**。

---

## 1. 这是什么项目

《绝地潜兵2（Helldivers 2）》的 **Lua 注入型内存 Mod**。

| 项目 | 说明 |
| --- | --- |
| 加载器 | **Bingus Shared Loader**（本项目在 **v19 / API 1** 上开发） |
| 原理 | loader 把 Lua 脚本注入游戏进程 → 脚本用 **FFI 直接读写游戏内存** |
| 交付形态 | Arsenal / HD2MM 可导入的 `.zip`（内含 `.patch_0` 归档 + manifest + 图标） |
| 副作用 | **不改磁盘上任何文件**；管理器禁用 + Purge + 重启游戏 = 完全还原 |
| 语言 | **Lua（LuaJIT 2.1）** —— 无 `string.pack`、无 `goto`、无 `//` 整除 |
| 测试 | 纯离线的 LuaJIT 仿真（`lupa`），**不需要启动游戏** |

**基线构建戳**（改代码前先核对，变了说明游戏更新过）：

```
executable 6AB382E4   /   game.dll 6AB3B43F
loader: Bingus Shared Loader v19, API 1
内存常驻表: 37 张，全部为 *_Settings 家族
```

> 游戏更新后偏移与枚举会漂移。**不要改常量**，要重新取明文并用全表复现校准
> （见 §8「游戏更新后怎么办」）。

---

## 2. 环境恢复

仓库里**没有**提交 285 MB 的可复现离线数据（GitHub 体积考虑）。克隆后先还原：

```bash
git clone https://github.com/handsomeminions/hd2-lua-mods.git
cd hd2-lua-mods

python vendor/restore.py      # 还原：
                              #   vendor/community/data/                  (241 MB)
                              #   analysis/ref/generated_entities.dl_bin  ( 44 MB)
python analysis/_env.py       # 自检，必须全部 OK
```

`vendor/restore.py` 是幂等的（已有就跳过），也可以 `--check` 只看状态。

### Python 环境（重要）

测试需要 **`lupa`**（提供 `luajit21`）。**系统 Python 通常没装**，必须用隔离 venv：

```bash
# 用托管 python 建 venv（这台机器上的路径；换机器请自行调整）
C:/Users/rouge/.workbuddy/binaries/python/versions/3.13.12/python.exe \
    -m venv C:/Users/rouge/.workbuddy/binaries/python/envs/default
C:/Users/rouge/.workbuddy/binaries/python/envs/default/Scripts/pip install lupa Pillow

# 之后所有测试都用这个 venv
PY=C:/Users/rouge/.workbuddy/binaries/python/envs/default/Scripts/python.exe
```

**为什么要 `luajit21` 而不是默认的 Lua 5.5**：`lupa` 的默认解释器会**放过** `//`（整除）之类
的 LuaJIT 专属语法，导致测试通过但游戏里报错。必须用 `lupa.luajit21`。

---

## 3. 领域知识速查

### 3.1 数据表是怎么找的

游戏的内存里有若干 **LDLD 表**（游戏自己的数据表格式）：

```
"LDLD" | <III u32 ver, u32 type_hash, u32 size> | <QQ u64 recdata_off, u64 count>
       | 桶数组 (16 B / 桶) | 记录区
```

- **类型哈希** = `djb2(name)`，最后**再减 5381**：

  ```python
  def dlsum(name):
      r = 5381
      for c in name:
          r = (r * 33 + ord(c)) & 0xFFFFFFFF
      return (r - 5381) & 0xFFFFFFFF
  ```

- 扫描策略：在进程内存里找 `"LDLD"` 魔数 → 校验 `size` 合理 → 用类型哈希确认是目标表。
- ⚠️ **同一张表在内存里可能有多个副本** → 必须**全部打**，并持续维护。
- ⚠️ **表描述符在文件形态里是相对偏移，在内存形态里是绝对指针** —— 两种都要试。
- ⚠️ **绝不要用「表大小 / 记录数」当准入条件** —— 一次构建更新就能让 Mod 静默失效。

### 3.2 离线数据源（三方交叉验证）

| 来源 | 路径 | 用途 |
| --- | --- | --- |
| **游戏 typelib**（权威结构） | `vendor/ref/typelib_all.json` + `typelib_all.json.enums` | 每个类型的**字段偏移 / 大小 / type_id** |
| **FileDiver 明文镜像** | `vendor/filediver/datalibrary/*.go` + `generated_*.dl_bin` | 每个组件每个字段的**名字与注释**（由 typelib 生成，是布局的权威） |
| **社区 JSON** | `vendor/community/data/settings/`、`entities/`、`enums/` | 已解成 JSON 的表内容、本地化字符串、枚举**名字** |

**关键技巧**：`typelib_all.json` 里**没有字段名**（只有哈希）。要反查字段类型，用
`dlsum(候选名)` 去比对 `member['type_id']`。例：`StatusEffectInfo` 的 `m0@0` 的 `type_id`
正好等于 `dlsum('StatusEffectType')` ⇒ 证明 `+0` 是 `StatusEffectType` 枚举。

**localization**：`vendor/community/data/translations/English.json` 把 `name_upper` 哈希翻成名字。

### 3.3 本构建常驻内存的表（类型哈希）

```
ProjectileSettings        0xBD4042C2   ← 射弹表（6 个 Mod 的战场）
ExplosionSettings         0x2AEA2592   ← 爆炸表
DamageSettings            0xE0A72CF0   ← 伤害表
StratagemSettings         0x30EB6399   ← 战备表
StatusEffectSettings      0xC63E0B22   ← 状态效果表（毒气/火/流血…）
```

**不在内存**（别对着它设计 Mod）：
`WeaponDataComponentData` `0x88E4DBB1`、`SprayWeaponComponentData` `0x8E551126`、
`BombardmentComponentData` `0xCDBC43D8`，以及一切 `*ComponentData`。

> **想知道某字段能不能改？先查它所属的表在不在上面这个名单里。**
> 名单来自实机日志：`docs/ingame-2026-10-13/*.log` 里的 `LDLD types seen:` 行 —— **那是金矿**。

### 3.4 两个核心记录的布局

**`ProjectileInfo`（射弹表记录，272 字节）**

| 偏移 | 字段 | 说明 |
| --- | --- | --- |
| `+0` | `type` | 枚举（会漂移，只作提示） |
| `+4` / `+8` | `name_upper` / `name_cased` | 本地化键哈希 / 原始字符串哈希 |
| `+24` | `calibre` (f32) | 口径 —— **稳定指纹** |
| `+28` | **`num_projectiles` (u32)** | **一次开火生成几枚射弹** ← 霰弹枪靠它一次打 9~20 颗 |
| `+32` / `+36` | `speed` / `mass` | 初速 / 质量 —— **稳定指纹** |
| `+72` / `+96` | `particle_thruster` / `particle_trail` | 推进 / 拖尾粒子哈希 —— **强指纹** |
| `+128` | `unit_path` | 模型资源哈希 |
| `+144` | `explosion_type_on_impact` | 命中爆炸类型 |
| `+152` | `explosion_delay` | 引信延时 |
| `+208` / `+212` | `audio_trail_*` | 飞行音效事件 |
| `+240` | `flags` | 标志位 |

**`DamageInfo`（伤害表记录，76 字节；DamageSettings 块起始 = `magic + 40`，stride = 76）**

| 偏移 | 字段 | 说明 |
| --- | --- | --- |
| `+0` | `type` | DamageInfoType 枚举 |
| `+4` / `+8` | `damage` / `durable_damage` (i32) | 直接伤害 / 对耐久伤害 |
| `+12` | `armor_penetration_per_angle[4]` (u32) | 护甲穿透 |
| `+28` / `+32` / `+36` | `demolition_strength` / `force_strength` / `force_impulse` | 拆迁 / 推力 / 冲量 |
| `+40` | `element_type` | 元素类型 |
| `+44` | `DamageStatusEffectInfo[4]` = `{ u32 type, f32 value }` × 4 | 挂载的状态效果及其**施加量** |

---

## 4. 目录导航

| 路径 | 是什么 |
| --- | --- |
| `src/*.lua` | **8 个 addon 的明文源码**（与包内逐字节一致） |
| `dist/*.zip` | 7 个安装包（下载即用） |
| `dist/thumbnail*.png` | Arsenal 卡片图标 |
| `docs/*.md` | 每个 Mod 的详细版面 |
| `analysis/harness.lua` | **LuaJIT 假 FFI / 假内存仿真框架** ← 最重要的基础设施 |
| `analysis/test_*.py` | 各 Mod 的功能 + 变异测试 |
| `analysis/build_package_*.py` | 打包脚本（生成 `dist/*.zip`） |
| `analysis/build_fixtures_*.py` | 从真实明文生成测试夹具 |
| `analysis/fixtures/*.bin` | 真实内存/明文的字节级夹具 |
| `analysis/_env.py` | 环境自检（路径、依赖、工具链） |
| `vendor/hd2-lua-mod/` | **HD2 Lua Mod 技能包**：归档读写 / 打包工具 + `references/` 实战案例 |
| `vendor/restore.py` | 还原大体积离线数据 |

---

## 5. 7 个 Mod 的技术档案 ★（最有用的一页）

> 全部都是「扫内存 → 认记录 → 只写自己的字段 → 回读校验」这套架构。
> 「指纹」= 用来认出目标记录的**跨构建稳定特征**（**绝不含本 Mod 会改的字段**）。

### 5.1 轨道120MM高爆弹火力网 → 飞鹰500kg　`v1.3.0`

| | |
| --- | --- |
| 源码 / 包 | `src/orbital_120mm_500kg.lua` / `dist/Orbital120mm-Eagle500kg.zip` |
| 资源名 / GUID | `mods/hd2/orbital_120mm_500kg` / `a914455b-75f8-4df8-9472-e0fc0bf64464` |
| 靶表 | `ProjectileSettings` `0xBD4042C2` |
| 目标记录 | `120mm HE CANNON ROUND`（**两条**） |
| **指纹** | **`audio_trail_event_stop == 3741852184`**（全表 350 条唯一，天然排除同名凝固汽油弹）+ 口径 84 / 初速 400 / 质量 5000 + 拖尾粒子哈希 |
| 源记录 | `500KG BOMB`：`name_upper == 1027666422` + 口径 50 / 初速 500 / 质量 500 |
| 改写字段 | `+60 damage_info_type`、`+144 explosion_type_on_impact`、`+152 explosion_delay`、`+156 explosion_type_expire`（取源记录同段字节，**运行时读出，绝不写死**） |
| 硬保证 | **逐字节 keep-guard**：除这 4 段外任何字节变了就拒绝写入 ⇒ 弹道/模型/速度/拖尾绝不被动 |
| 测试 | `analysis/test_addon.py` 25/25 |
| 实机 | ✅ 已确认 |

### 5.2 轨道380MM高爆弹火力网 → 地狱火炸弹　`v1.0.1`

| | |
| --- | --- |
| 源码 / 包 | `src/orbital_380mm_hellbomb.lua` / `dist/Orbital380mm-Hellbomb.zip` |
| 资源名 / GUID | `mods/hd2/orbital_380mm_hellbomb` / `41d2cdd0-7f8e-4b4d-b54d-c98c36d455c6` |
| 靶表 | `ProjectileSettings` `0xBD4042C2` |
| 机制 | 同上：把 380mm 火力网炮弹的**爆炸配置**换成 HELLBOMB 的（半径 17/25/45、Nuke 弹坑、专属火焰粒子/音效） |
| 测试 | `analysis/test_380mm.py` 7/7 |
| 实机 | ✅ 已确认 |

### 5.3 A/M-12 迫击哨戒炮 → 凝固汽油弹　`v1.0.1`

| | |
| --- | --- |
| 源码 / 包 | `src/mortar_sentry_napalm.lua` / `dist/MortarSentry-NapalmImpact.zip` |
| 资源名 / GUID | `mods/hd2/mortar_sentry_napalm` / `0208faf4-f89b-416e-8806-2f242d394ef2` |
| 靶表 | `ProjectileSettings` `0xBD4042C2` |
| 机制 | 命中爆炸 → 轨道凝固汽油弹单颗的效果：`FireTemplate_Large`（**落地留下燃烧火海**）+ `Scorch` 焦土弹坑 + 汽油弹专属粒子与音效。索敌/弹道/模型/直接命中伤害全保留原版 |
| 测试 | `analysis/test_mortar_napalm.py` 23/23 |
| 实机 | ⏳ 未上机 |

### 5.4 胆汁迫击炮 → 落地炸成 RL-77 空爆集束　`v1.5.0`

| | |
| --- | --- |
| 源码 / 包 | `src/bug_artillery_airburst.lua` / `dist/BileSpewer-RL77Airburst.zip` |
| 资源名 / GUID | `mods/hd2/bug_artillery_airburst` / `8cf04434-8f4e-43d5-8493-22aaace62e20` |
| 靶表 | `ProjectileSettings` `0xBD4042C2`（胆汁射弹） |
| 改写字段 | `+144 explosion_type_on_impact`、`+152 delay`、`+240 flags`（+ 音效） |
| **外形保持原版** | `+128 unit_path` / `+72` `+96` 粒子 **一个字节都不动** |
| 关键约定 | `recheck` 用 **`rebuild_owned`**：从**当前字节**出发、**只补自己的那几个字段**，绝不整条回写（否则会覆盖别的 Mod 的成果） |
| 测试 | `analysis/test_bug_artillery.py` 28/28 |
| 实机 | ⏳ 未上机 |

### 5.5 胆汁喷涌虫 · 齐射档位选择（合集包）　`v1.0.0`

| | |
| --- | --- |
| 包 / 源码 | `dist/BileSpewer-Salvo-Choice.zip` / `src/bug_artillery_{6,4}rounds.lua` |
| 合集 GUID | `01845481-055a-41a8-8d63-b26764e74933` |
| 元件 GUID | 6 团 `fe9ac944-32e4-4388-99d3-c146780aeaed`（`v2.2.0`）／4 团 `70126b6b-5fae-4936-9937-237fb7ab2c23`（`v1.0.0`） |
| 靶表 | `ProjectileSettings` `0xBD4042C2`（胆汁射弹） |
| **改写字段** | **`+28 num_projectiles`**：1 → **3**（6 团）或 **2**（4 团）。只写 4 字节 |
| **为什么是 3 或 2** | 实机确认原版齐射 = **开火 2 次**，每次 1 枚 ⇒ 3×2 = 6 团 / 2×2 = 4 团 |
| **指纹** | 口径 50 + 速度 30 + 质量 1000 + 推进粒子 `758CA9293725AFE2` + 拖尾 `29354B9DC32A52AC`。**刻意不含音频/爆炸字段**（那些会被 4. 空爆 Mod 改） |
| **互斥** | 姊妹版内置 `RIVAL_SINGLETON` 检测（`init` 与 `recheck` **两处**），命中即 `phase="dead"`，STATUS 首行 `SKIPPED - …`。合集里两个 addon 双选时后加载者自动让位 |
| 合集格式 | `manifest.json` 的 `Options[]` 每项 `Include` 指向**目录名**，每目录放自己的 `9ba626afa44a3aa3.patch_0`；入口放 ZIP **根** |
| 测试 | `analysis/test_package_bug_salvo.py`（结构+双选共存）；元件逻辑 `test_bug_6rounds.py` 27/27、`test_bug_4rounds.py` 28/28；共存 `test_bug_combo.py` / `test_bug_combo4.py` |
| 实机 | ⏳ 未上机（管理器勾选 UI 未实测） |

> **已知结果**：同一次开火的 N 枚射弹**同向**、会叠在一起。射弹表里**没有发射散布参数**，
> 所以「6 个方向」做不到 —— 能调的只有「每方向几枚」。详见 §6。

### 5.6 TX-41 灭菌器 → G-4 伤害 + 毒气施加量 ×2　`v2.0.0`

| | |
| --- | --- |
| 源码 / 包 | `src/sterilizer_gas_damage.lua` / `dist/Sterilizer-G4GasDamage.zip` |
| 资源名 / GUID | `mods/hd2/sterilizer_gas_damage` / `d369d2c7-93a1-455a-a61a-ba3c7d47e991` |
| 靶表 | **`DamageSettings` `0xE0A72CF0`**（`*_Settings` ⇒ 常驻内存） |
| 目标记录 | 灭菌器 `DamageInfoType_Spray_Chem_Gun` |
| 改写字段 | `+4 damage` / `+8 durable_damage`：1 → **3**（= G-4 毒气榴弹爆炸伤害）；`+48` / `+56`（`SE[Gas].value` / `SE[Gas_Confusion].value`）：0.5 → **1.0** |
| **指纹** | `AP=[5,5,5,0]` + `demo=5` + `force=10/5` + **前两条 SE 的 `type != 0`、后两条 SE 的 `type == 0`**（纯结构关系）。**刻意不含 `damage` 与 SE `value`** —— 那些是本 Mod 会改的字段，含进去会导致「改完认不出自己」 |
| **同名邻居（危险）** | 敌方化学无人机 `Drone_Chem_Gun` 与灭菌器 `Spray_Chem_Gun` **数值逐字段完全相同**，只能靠 **DamageInfoType 相邻 + 取较小者** 区分（本构建 28 < 29；社区枚举 12 < 13）。**候选 ≠ 恰好 2 条相邻 → 拒绝写入**（宁可不打，也绝不强化敌人） |
| 写入方式 | **只写 3 段共 16 字节**（`+4..+11`、`+48..+51`、`+56..+59`），逐段回读；中间的 `+52..+55`（`SE[1].type`）**绝不触碰** |
| cfg | `sterilizer_gas_damage.cfg`：`damage=3` / `gas=1.000`（~5 秒热重打） |
| 测试 | `analysis/test_sterilizer_gas_damage.py` 28/28（含 9 条变异） |
| 实机 | ⏳ 未上机 |

### 5.7 TX-41 灭菌器 → 开火音效替换（**实验性**）　`v1.0.0`

| | |
| --- | --- |
| 源码 / 包 | `src/sterilizer_sfx.lua` / `dist/Sterilizer-PunchierSFX.zip` |
| 资源名 / GUID | `mods/hd2/sterilizer_sfx` / `43181292-a226-45de-9610-46a2de6cadfc` |
| **靶表** | **无** —— 它走的是**裸内存值扫描**（见下） |
| 锚点 | `1773671782` = 灭菌器 `firing.audio_event_start` |
| 佐证 | 命中点 **±256 字节**内必须再出现 ≥1 个同组哈希：`599097114`(stop) / `418315309`(callout) / `1803865503`(audio_node) / `3435018303`(warmup) / `1928837757`(cooldown) / `3956223216`(vo)，以及 **u64 `0xA3D15A3BBC56DE55`（`firing.muzzle_effect`，14 个喷射武器实例里只属于灭菌器）** |
| 判据 | **孤立命中一律跳过**（宁可漏，不可错） |
| 写入 | 只写 4 字节 + 回读；稳态复查**用窗口佐证重新验证位置**，而不是靠「被自己改过的值」认自己 |
| cfg | `sterilizer_sfx.cfg`：`event=<id>`。候选：`335829265`（敌无人机，默认）／`1881104745`（FLAM-40）／`3757506625`／`2970598254`／`1773671782`（原版 A/B） |
| 测试 | `analysis/test_sterilizer_sfx.py` 16/16（含 4 条变异） |
| 实机 | ⏳ 未上机 —— **这是个赌**：如果游戏没把这段数据留在内存，就不会生效。一次上机即可判定 |

---

## 6. 已知做不到的事（别再试了，已穷尽验证）

| 需求 | 为什么做不到 |
| --- | --- |
| **改喷射类武器（灭菌器/喷火器）的「射程」** | `SprayWeaponComponent.projectile_type = ProjectileType_None` ⇒ 它们**不发射射弹**，伤害靠「粒子碰撞事件」触发。喷多远完全由**枪口 VFX 粒子资源**决定。`SprayWeaponComponent`(224B) 与 `WeaponDataComponent`(56 字段) 里**没有任何 range / length / distance 字段**；唯一带 `length` 的 `SprayCapsuleOverlap` 在 entities blob 里**0 个实例**；`BeamSettings` 里没有化学/火焰喷流条目。⇒ **射程属美术(VFX)资产** |
| **只给某个武器改毒气「持续时间」** | `duration` 只存在于**全局** `StatusEffectSettings` 表，被灭菌器/敌无人机/G-4 榴弹/轨道毒气弹/胚胎簇**共用**。想「只影响灭菌器」就**必然改不到持续时间**。改全局 = 敌我一起变强（用户明确拒绝） |
| **让「一次开火 N 枚」朝不同方向散开** | `ProjectileInfo` 里**没有发射散布参数**（唯一的 spread 是 `+192/+196` **跳弹**散布；`+256 unk_vector` 全表恒 0）。霰弹枪的散布来自**武器侧**，而武器侧是**不加载**的 `*ComponentData` ⇒ 改不到。**能调的只有「每方向几枚」，「方向数」由游戏固定** |
| **改「敌人一次齐射开火几次」** | 开火次数/连发数在**不加载**的 `WeaponDataComponentData` / `ProjectileWeaponComponentData`；AI 的「齐射/攻击模式」在能力资源（`AbilityId_*`，不在离线数据里） |
| **把武器原声「放大」** | **音量**编在 **Wwise SoundBank 音频资源**里，**任何数据字段都没有**。纯内存 Mod 不可能放大。正路 = `hd2-audio-modder` + Wwise 重新编码 `.wem`（**资源替换**，属另一条技术路线）。内存层最多只能**换一个音效事件** |
| **让客机也能结算改动后的伤害** | 游戏是**主机权威**：伤害由房主进程用房主的数据表计算。纯本机内存补丁改不到房主。唯一正路 = 房主也装，或自己开房 |

---

## 7. 常用命令

```bash
PY=C:/Users/rouge/.workbuddy/binaries/python/envs/default/Scripts/python.exe

# --- 环境 ---
python vendor/restore.py                       # 还原大体积离线数据
python vendor/restore.py --check               # 只检查
$PY analysis/_env.py                           # 自检（必须全 OK）

# --- 测试（离线，不需要游戏）---
$PY analysis/test_addon.py                     # 1. 轨道120MM        25/25
$PY analysis/test_380mm.py                     # 2. 轨道380MM         7/7
$PY analysis/test_mortar_napalm.py             # 3. 迫击炮凝固汽油弹  23/23
$PY analysis/test_bug_artillery.py             # 4. 胆汁空爆          28/28
$PY analysis/test_package_bug_salvo.py         # 5. 齐射合集包（结构+共存）
$PY analysis/test_bug_6rounds.py               #    合集内含的 6 团    27/27
$PY analysis/test_bug_4rounds.py               #    合集内含的 4 团    28/28
$PY analysis/test_sterilizer_gas_damage.py     # 6. 灭菌器伤害+毒气   28/28
$PY analysis/test_sterilizer_sfx.py            # 7. 灭菌器音效        16/16
$PY analysis/test_bug_combo.py                 #    空爆 × 多团 共存

# --- 打包 ---
$PY analysis/build_package.py                  # 1 -> dist/Orbital120mm-Eagle500kg.zip
$PY analysis/build_package_380.py              # 2
$PY analysis/build_package_mortar_napalm.py    # 3
$PY analysis/build_package_bug_airburst.py     # 4
$PY analysis/build_package_bug_salvo.py        # 5（合集包）
$PY analysis/build_package_sterilizer.py       # 6
$PY analysis/build_package_sterilizer_sfx.py   # 7
```

### 用环境变量替换源码跑测试（**发布产物端到端复测**用）

测试脚本支持从别处读源码，用来验证「**zip 里的正文**和 `src/` 逐字节一致」：

```bash
# 1. 从 zip 取出正文
$PY -c "
import zipfile,sys,os
sys.path.insert(0, os.path.expanduser('~/.workbuddy/skills/hd2-lua-mod/tools'))
import hd2_archive as A
z=zipfile.ZipFile('dist/Sterilizer-G4GasDamage.zip')
a=A.parse(z.read('Addon/'+A.ARCHIVE_NAME))
open('build/_e2e.lua','wb').write(a['entries'][0]['body'])
"
# 2. 用取出的正文跑测试
HD2_ADDON_SZ_SRC=D:/WorkBuddyWork/hd2mods/build/_e2e.lua $PY analysis/test_sterilizer_gas_damage.py
```

可用变量：`HD2_ADDON_SRC`（120mm）、`HD2_ADDON_380_SRC`、`HD2_ADDON_MS_SRC`、`HD2_ADDON_BA_SRC`、
`HD2_ADDON_B6_SRC`、`HD2_ADDON_B4_SRC`、`HD2_ADDON_SZ_SRC`、`HD2_ADDON_SFX_SRC`。

---

## 8. 硬约定（违反会出事）★★ 必读

完整 38 条在 `.workbuddy/memory/MEMORY.md`。这里列最关键的：

### 认记录 / 指纹

1. 认记录用**稳定指纹**（`name_upper` 本地化键哈希 / 64 位资源哈希 / 物理量），
   **绝不用枚举下标** —— 会随版本漂移，而且是「**静默写错**」而非「找不到」。
2. **绝不用「表大小 / 记录数」当准入条件** —— 一次构建更新就能让 Mod 静默失效。
3. **指纹绝不能含「本 Mod 会改的字段」**，否则 cfg 热调 = 自己把自己搞失忆
   （实测踩过：灭菌器 v2.0.0 一开始用「SE value == 0.5」当指纹，改完 value 后 `recheck` 认不出记录，
   于是移除副本 → 重扫 → 震荡）。**每新增一个「可改字段」，都要回头重审指纹。**
4. 同名且数值相同的「邻居记录」怎么区分：用**枚举相邻 + 取较小者**（声明顺序稳定），
   并且**要求「恰好 N 条且关系成立」，否则拒绝写入** —— 改错 = 强化敌人。

### 写入 / 复查

5. **只写自己那几个字节** + 写完**立刻回读校验**。
6. **「只改爆炸 / 只改外观」这类需求一律用「精准字段改写」，绝不整条记录克隆** ——
   克隆会把飞行参数（速度/质量/阻力/寿命/引信）一起换掉，导致**弹道偏离原版**（实测过）。
   并必须配**逐字节 keep-guard**（除要改的字段外任何字节变了就拒绝写入）。
7. **绝不「改运行时资源引用来换外观」**：把 `+128 unit_path` / 粒子哈希换成别的武器的，
   实机**模型根本不渲染**（实测：火箭模型）。要还原/保持外观就整组不动并纳入 keep-guard。
8. 多个 Mod 改在同一条记录上时，复查必须「**只为自己的字段负责**」：
   从**当前字节**出发、只补自己那几个字段，**绝不整条回写**（否则会把别的 Mod 的成果覆盖掉，
   两边每 5 秒互抢）。
9. **打完补丁后不能立刻停扫**：必须「继续把**当前这一轮**扫完再彻底停扫」
   （否则内存里第二份表可能漏打）。所有 addon 统一用这个写法。
10. 所有写入的都是 **`*_Settings`** 表；`*_ComponentData` 表内存里不加载（见 §3.3）。

### 性能 / 安全

11. 单帧 ≤ 2ms、单块 ≤ 256 KB、空手指数退避；**打完即休眠**，绝不周期性全量重扫（会掉帧）。
12. 复查只按**已记录的地址直读**，不重跑全表解析。
13. 每个 addon **只碰自己唯一命名的全局** + `update`，内部函数全 `local`（用前向声明）。
    （踩过：两个 addon 都用通用全局名 `end_pass`/`flush_log` → 后加载的覆盖先加载的 → 日志写丢）
14. `manifest.json` 的 `Name` 必须**纯 ASCII**、不含 `\ / : * ? " < > |`。
15. 交付必须给一个**一句话结论的 `STATUS.txt`**；只用管理器导入（手拷 `Addon/` 会互相覆盖）。

### 互斥 / 调参

16. **「同一条记录同一字段」的姊妹版 Mod 要内置互斥**：放 `RIVAL_SINGLETON = "_HD2_..."`，
    在 **`init` 与稳态 `recheck` 两处**检测 `rawget(_G, RIVAL)`，命中就 `phase="dead"`
    （不扫描/不写入），STATUS 首行写 `SKIPPED - …`。各自用**独立的 cfg 文件**。
17. **给不确定的数值留「运行时可调」的口子**：把待定值写进日志目录的一个小 cfg 文件，
    稳态复查时重读、变了就重打 —— 用户**不用重打包、不用重启游戏**就能现场试出正确值。
    ⚠️ 反过来也要提醒用户：**已存在的旧 cfg 会覆盖新默认值**，升级时要手改或删除。

### 测试

18. 仿真必须用 **`lupa.luajit21`**（默认 Lua 5.5 会放过 `//` 之类语法）；**必须配变异测试**。
19. **变异要直接让 `write_xxx` 函数整个变成空操作** —— 若只改写入分支，
    5 秒后的 `recheck` 会把漏掉的字段补回去，变异「未被抓住」（其实是兜底在起作用）。
20. 改完任何 addon，测试要**连跑 5~8 遍**查时序抖动；`analysis/_env.py` 自检必须全 OK。
21. **删/重构字段后必须 grep 一遍所有 `CONFIG.` 引用**
    （踩过：`recheck()` 引用未定义的 `CONFIG.REC_SIZE` → 直接报错 → 稳态复查从未生效）。
22. **合成内存夹具一定要 `assert len(b) == 期望长度`** —— 布局类夹具没有 assert 会静默错位。

### 游戏更新后怎么办

23. 偏移/枚举会漂移。**不要手改常量**：
    1. 重新取明文（`vendor/README.md` 附录写了怎么从 FileDiver / 社区重新拿）；
    2. 用 `analysis/build_fixtures_*.py` 重新生成夹具；
    3. 跑全表复现验证指纹仍然唯一；
    4. 跑测试，全绿再发布。

---

## 9. 标准工作流

### A. 新增一个 Mod

```
1. 先想清楚「改哪个量」。到 §3.3 的内存表名单里找对应的 *_Settings 表。
   —— 找不到 ⇒ 这个需求（很可能）做不到，别开始写代码。
2. 用离线数据源（§3.2）确认：
   * 目标记录怎么认（跨构建稳定指纹，且**不含你要改的字段**）
   * 要改的字段偏移（typelib 权威 + 全表复现校准）
3. cp 一个同族的现成 addon 当框架（扫描器/日志/FFI/tick/复查框架逐字保留），
   只替换：头部注释 / 名字 / CONFIG / 指纹 / 写入函数 / STATUS 文案。
4. 写 build_fixtures_*.py 生成夹具（**从真实明文切，别手搓**）。
5. 写 test_*.py：功能用例 + 变异用例 + 逐字节 keep-guard 用例。
   —— 基线：连跑 5~8 遍稳定。
6. 写 build_package_*.py（改 NAME/GUID/DISPLAY/ENTRY/ICON/OUT/DESC）。
   GUID 用 `python -c "import uuid;print(uuid.uuid4())"` 生成。
7. 图标：图像生成后**必须去水印**（右下角），用 `analysis/make_icon.py`。
8. 打包 → **从 zip 取回正文复测**（§7 的环境变量法）→ 逐字节比对 src。
9. 更新：README.md（总表）、docs/0N-*.md、HANDOVER.md、.workbuddy/memory/MEMORY.md。
```

### B. 修改一个已有 Mod

```
1. $PY analysis/_env.py  → 全 OK
2. 跑该 Mod 的测试 → 确认基线是绿的
3. 改 src/*.lua
4. 若改了「指纹」或「可改字段」⇒ 回头重审 §8 第 3 条
5. 测试（连跑 5~8 遍）+ 变异测试
6. 重新打包 → 端到端复测
7. 更新版本号（源码头部 REVISION + build 脚本里的版本）
8. 更新文档与记忆
```

---

## 10. 交付规范（用户偏好）

- **中文交流**；要「**能直接丢进 Arsenal 用**」的成品：**安装包 + 图标 + 中文说明**一起给。
- **用户会自己上机实测**，并把 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\` 的日志发回来 ——
  所以**日志要写得上机可判**（首行即结论 + 关键计数）。
- **必须主动讲清「客户端改动 / 主机权威」**：客机看不到、伤害按房主算。
- 每个 Mod 交付时必须给一个**一句话结论**（`STATUS.txt` 首行语义）。
- 多个 Mod 一起交付时，优先给**独立包**；只有当用户明确要求才做多选项合集包。

---

## 11. 未验证 / 待办

| # | 事项 | 怎么看结果 |
| --- | --- | --- |
| 1 | **7 个 Mod 中 6 个还没上机**（只有 #1、#2 实机确认过） | 进任务后看 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\<mod>_STATUS.txt` 首行 |
| 2 | **齐射合集包的「管理器勾选 UI」没实测** | 在 Arsenal 里导入后确认能看到两个可勾选项 |
| 3 | **灭菌器毒气 `+48/+56` 的实际体感属推断** | 没感觉就把 cfg 的 `gas` 调到 `2.000` / `4.000` 再试，`0.5` 即回原版 |
| 4 | **灭菌器音效是可移植性的赌注** | 首行 `OK - patch applied` ⇒ 内存路线成立；一直 `SEARCHING` + `NO verified ... found` ⇒ 此路不通（转 `hd2-audio-modder` 资源替换） |
| 5 | **胆汁齐射「6 团一方向叠成一团」是结构限制**（§6） | 不是 bug |

---

## 12. 相关文件

| 文件 | 内容 |
| --- | --- |
| `.workbuddy/memory/MEMORY.md` | **38 条硬约定 + Mod 清单 + 用户偏好**（每次开工前读） |
| `.workbuddy/memory/2026-*.md` | 逐日工作日志（append-only，记录了每个决策与踩坑的现场） |
| `HANDOVER.md` | 原始交接与迁移文档（更详尽的工程细节、命令、附录） |
| `vendor/hd2-lua-mod/SKILL.md` + `references/` | HD2 Lua Mod 技能包：归档格式、打包工具、**6 个实战案例**、踩坑清单 |
| `vendor/README.md` | 离线数据源的来源与重新获取方法 |
| `docs/ingame-2026-10-13/*.log` | 真实游戏日志样本（含 `LDLD types seen:` 全表普查） |

---

**祝顺利。改完记得回写文档 —— 下一个人（或 AI）会感谢你。**
