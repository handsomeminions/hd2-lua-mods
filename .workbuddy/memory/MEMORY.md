# 项目长期记忆 · HD2 Lua 注入型 Mod

> 工作区：`D:\WorkBuddyWork\hd2mods`（换机器后路径可能不同，用 `analysis/_env.py` 自检）
> **接手第一件事：读 `HANDOVER.md`（交接与迁移指南）**，再读 `.workbuddy/memory/<日期>.md` 的工作日志。
> 方法论与踩坑大全：`vendor/hd2-lua-mod/SKILL.md` + 其 `references/`（含 6 个实战案例）。

## 这是什么
《绝地潜兵2》的 **Lua 注入型内存 mod**：Bingus Shared Loader 把 Lua 塞进游戏进程，
用 FFI 读写游戏内存。**不改磁盘文件**，管理器禁用 + Purge 即完全还原。
后端数据全部离线：`vendor/filediver/`（明文镜像 + `.go` 字段名）、`vendor/ref/`（typelib 偏移）、
`vendor/community/data/`（社区解好的 JSON + 本地化表）。

## 已交付的 7 个 mod + 1 个 Arsenal 合集包（都在 `src/` + `dist/`）
| mod | 资源名 | GUID | 版本 | 测试 | 实机 |
|---|---|---|---|---|---|
| 轨道120MM高爆弹火力网 → 飞鹰500kg(仅爆炸) | `mods/hd2/orbital_120mm_500kg` | `a914455b-75f8-4df8-9472-e0fc0bf64464` | 1.3.0 | 25/25 | ✅ 1.2.1 确认 / 1.3.0 待测 |
| 轨道380MM高爆弹火力网 → 地狱火炸弹 | `mods/hd2/orbital_380mm_hellbomb` | `41d2cdd0-7f8e-4b4d-b54d-c98c36d455c6` | 1.0.1 | 7/7 | ✅ 已确认 |
| 胆汁喷涌虫胆汁迫击炮 → 落地炸成空爆集束 | `mods/hd2/bug_artillery_airburst` | `8cf04434-8f4e-43d5-8493-22aaace62e20` | **1.5.0** | 28/28 | ⏳ 未上机 |
| A/M-12 迫击哨戒炮 → 凝固汽油弹效果 | `mods/hd2/mortar_sentry_napalm` | `0208faf4-f89b-416e-8806-2f242d394ef2` | 1.0.1 | 23/23 | ⏳ 未上机 |
| 胆汁喷涌虫 **一次齐射 6 团**（每发 3 枚；cfg 可调） | `mods/hd2/bug_artillery_6rounds` | `fe9ac944-32e4-4388-99d3-c146780aeaed` | **2.2.0** | 27/27 | ✅ 实机确认：原版齐射 = 开火 **2 次**；3 枚/发 ⇒ 6 团 |
| 胆汁喷涌虫 **一次齐射 4 团**（每发 2 枚；#5 的姊妹版，**与 #5 互斥**） | `mods/hd2/bug_artillery_4rounds` | `70126b6b-5fae-4936-9937-237fb7ab2c23` | **1.0.0** | 28/28 + combo4 | ⏳ 未上机 |
| **Arsenal 合集包**：#5+#6 两个可勾选项 | 复用 #5/#6 资源名 | `01845481-055a-41a8-8d63-b26764e74933`（合集本身） | 1.0.0 | `test_package_bug_salvo.py` | ⏳ 未上机（管理器勾选 UI 未实测） |
| **TX-41 灭菌器** → G-4 伤害（1→3）+ 毒气施加量 ×2（0.5→1.0，**仅灭菌器**） | `mods/hd2/sterilizer_gas_damage` | `d369d2c7-93a1-455a-a61a-ba3c7d47e991` | **2.0.0** | 28/28 | ⏳ 未上机（**射程 & 持续时间都做不到**，见 #25/#28） |
| **TX-41 灭菌器** 开火音效 → 换事件（默认敌方化学无人机喷毒）**实验性** | `mods/hd2/sterilizer_sfx` | `43181292-a226-45de-9610-46a2de6cadfc` | 1.0.0 | 16/16 | ⏳ 未上机（**原声放大做不到**；见 #35） |

> **v1.0.0 的 6 发方案已被实机否决**：它改的 `WeaponDataComponentData` 表**不在内存**。
> 现有的一切都改 `*_Settings` 表（见硬约定 #17）。

基线环境：Bingus Shared Loader **v19 / API 1**；游戏构建戳 `executable 6AB382E4` / `game.dll 6AB3B43F`。
**游戏更新后偏移/枚举会漂移** → 别改常量，重新取明文 + 用全表复现校准。

## 项目硬约定（违反会出事）
1. 认记录用**稳定指纹**（`name_upper` 本地化键哈希 / 64 位资源哈希 / 物理量），
   **绝不用枚举下标**（会随版本漂移，且是"静默写错"而非"找不到"）。
2. **绝不用"表大小/记录数"当准入条件** —— 一次构建更新就能让 mod 静默失效。
3. 表描述符：**文件形态是相对偏移，内存形态是绝对指针**，两种都要试。
4. 同一张表在内存里可能有**多份** → 全部打 + 持续维护。
5. 单帧 ≤2ms、单块 ≤256KB、空手指数退避；**打完即休眠**，绝不周期性全量重扫（会掉帧）。
6. 复查只按**已记录的地址直读**，不重跑全表解析。
7. 每个 addon **只碰自己唯一命名的全局** + `update`，内部函数全 `local`（用前向声明）。
8. 仿真必须用 `lupa.luajit21`（默认 Lua 5.5 会放过 `//` 之类语法）；**必须配变异测试**。
9. `manifest.json` 的 `Name` 必须**纯 ASCII**、不含 `\ / : * ? " < > |`。
10. 交付必须给用户一个**一句话结论的 `STATUS.txt`**；只用管理器导入（手拷 `Addon/` 会互相覆盖）。
11. **"只改爆炸/只改外观"这类需求，一律用"精准字段改写"，绝不用整条记录克隆** ——
   克隆会把飞行参数（速度/质量/阻力/寿命/引信）一起换掉，导致**弹道偏离原版**（实测过）。
   并且必须配 **逐字节 keep-guard**（除要改的字段外，任何字节变了就拒绝写入）。
12. **绝不"改运行时资源引用来换外观"**：把 `+128 projectile_unit_path` / 粒子哈希换成别的武器的，
   实机**模型根本不渲染**（模型丢失，实测：火箭模型）。要还原/保持外观就整组不动、并纳入 keep-guard。
13. **打完补丁后不能立刻停扫**：必须"继续把**当前这一轮**扫完再彻底停扫"
   （否则内存里第二份表可能漏打 → 测试时序抖动）。四个 addon 统一用这个写法。
14. 改完任何 addon，跑测试要**连跑 5~8 遍**查时序抖动；`analysis/_env.py` 自检必须全 OK。
15. **实体组件表（`*ComponentData`）的布局**（仅在**离线明文**里用）：`+24 ComponentIndexData[N]`
    （16B/条：u64 实体哈希 + u32 记录号 + u32 0）+ 记录区。**N / 记录数 / stride 一律自标定**：
    索引区按"pad==0 且记录号<上限"扫出 N 与最大记录号；`stride=(size−N×16)/k`，
    k 取 `maxRec+1..maxRec+4` 里"能整除且 stride∈[64,16384]"的唯一解（`WeaponDataComponentData`
    本构建 = N 730 / 366 条 / stride 1232）。**记录按实体哈希选**（不是下标）。
    ⚠ 但要改**运行时**的东西请看 #17 —— 这些表**不在内存**。
16. **多选项 mod 包**（用户 2026-10-14 明确**不要**，仅留作知识）：`manifest.json` 的 `Options[]`
    每项 `Include` 指向**目录名**，每个目录放自己的 `9ba626afa44a3aa3.patch_0`（管理器按勾选部署 +
    自动重编号）。入口必须放 ZIP 根。**用户偏好：宁要两个独立 ZIP，也不要一个多选项包。**
17. ★★ **实机内存里常驻的只有 `*_Settings` 表，`*_ComponentData` 表根本不加载。**
    证据：6rounds v1.0.0 的实机日志 —— 4 轮全内存 LDLD 普查（13.7 GB）只见到
    `ProjectileSettings`/`ExplosionSettings`/`StratagemSettings`/`DamageSettings`/… ，
    **0 个 `*ComponentData`** → `targets_found=0/4`。
    ⇒ **要改运行时行为, 只能打 `*_Settings` 表**（射弹表 `0xBD4042C2`、爆炸表 `0x2AEA2592`、
    战备表……）。`vendor/ref/typelib_all.json` 可把扫到的类型哈希反查成表名。
    ⇒ 推论：以后别再对着 "某个敌人的某个组件字段" 设计 mod，先在 `*_Settings` 里找等价的量。
18. ★ **"一次开火生成几枚射弹" = 射弹表 `ProjectileInfo +28 u32 num_projectiles`**。
    霰弹枪就是靠它一次打出 9~20 颗（它们的弹匣是 `Uniform`，不是 `Pattern`）。
    **总发数 = 每次开火枚数 × 开火次数**。胆汁迫击炮**实机确认原版齐射 = 开火 2 次**
    （v2.1.0 设 2 时实测 `2×2 = 4` 团）、每次 1 枚 ⇒ 每发枚数设 **3** 得 3×2 = **6 团**。
    ⚠ 同一次开火的多枚**同向**、会叠在一起（这就是"2 个方向、每方向 3 枚"）；
    本 mod **改不到开火次数**（表不加载），所以"方向数"固定 = 2，能调的只有"每方向几枚"。
19. ★★ **射弹表里没有"发射散布"参数** ⇒ 用 `num_projectiles` 做不出"多枚朝不同方向"。
    `ProjectileInfo` 唯一的 spread 是 `+192/+196 ricochet_spread_*`（跳弹散布；胆汁 12/45
    比霰弹枪 2/12 **还大** ⇒ 显然不是发射散布）；`+256 unk_vector` 全表恒 0；
    `+216 unk_float2` 胆汁与霰弹枪同为 -1.0。霰弹枪的散布来自**武器侧参数**，
    而 `*ComponentData` 不加载（见 #17）⇒ 改不到。**要"分散"只能"少发多次"**。
20. ★ **多个 mod 改在同一条记录上时, 复查必须"只为自己的字段负责"**：
    从**当前字节**出发、只补自己那几个字段（或只写自己那 4 个字节），**绝不整条回写** ——
    否则会把别的 mod 的成果覆盖掉, 两边每 5 秒互抢（实测踩过：6rounds × airburst）。
    推论：**识别指纹也不能包含"别的 mod 会改的字段"**（否则同装时认不出自己的目标；
    airburst 会改 `+208/+212/+144/+152/+240`, 所以 6rounds 的指纹只能靠 `name/口径/速度/质量/粒子哈希`）。
21. **给不确定的数值留"运行时可调"的口子**：把待定值写进日志目录的一个小 cfg 文件（纯数字），
    稳态复查时重读、变了就重打 —— 用户**不用重打包、不用重启游戏**就能现场试出正确值。
    （参考 `bug_artillery_6rounds.lua` 的 `read_cfg/ensure_cfg`）
    ⚠ 反过来也要提醒用户：**已存在的旧 cfg 会覆盖新默认值**，升级时要手改或删除。
22. ★ **"同一条记录同一字段"的姊妹版 mod 要内置互斥**：6 团版(`bug_artillery_6rounds`) 与
    4 团版(`bug_artillery_4rounds`) 改的是**同一条射弹记录的同一个 `+28`**，同时启用会每 5 秒互抢。
    做法：姊妹版里放 `RIVAL_SINGLETON = "_HD2_...."`，在 **`init` 与稳态 `recheck` 两处**检测
    `rawget(_G, RIVAL)`，命中就 `phase="dead"`（不扫描/不写入），STATUS 首行写 `SKIPPED - …`。
    ⇒ 管理器里"二选一启用"即可，不会互相破坏。（各自用**独立的 cfg 文件**，否则调参会串联。）
23. ★ **"敌人一次齐射开火几次"改不了**（也决定了能不能做"N 个方向"）：
    开火次数 / 连发数 / 武器散布都在**不加载**的 `*ComponentData`
    （`WeaponDataComponentData`、`ProjectileWeaponComponentData`）；AI"齐射 / 攻击模式"在能力资源
    （`AbilityId_*`，不在离线数据里）。typelib 里虽有 `AttackPatternSettings`/`AttackPatternComponentData`，
    但 FileDiver 与社区数据**都没有导出** ⇒ 不是可改的数据表。
    ⇒ **方向数由游戏固定，可调的只有"每方向几枚"**。
    **判定法（30 秒，别猜）**：cfg 设 `1`，进任务数一次齐射吐几团 —— 2 团 ⇒ 开火 2 次；3 团 ⇒ 开火 3 次。
    （本次 3→2→3 走了个来回，就是因为没先做这个判定。）

24. ★ **Arsenal / HD2MM 多选项 manifest（V1）**：`Options[]` 每项 = 一个**可自由勾选**的部分，
    字段 `Name` / `Description` / `Image`（选项自己的图）/ `Include`（**勾选该项时要加入的目录名**）。
    每个 Include 目录里各放一份 `9ba626afa44a3aa3.patch_0`（+ 空 `.stream`/`.gpu_resources`），
    入口文件放 ZIP **根**。`SubOptions` 才是"单选变体"。
    规范来源：HD2 Modding Wiki `dev/misc/manifest.html`；范例见 `analysis/build_package_bug_salvo.py`。
    ⚠ 合集里的选项若与"独立包"**同资源名** ⇒ 两者**不能同时装**（会部署两份定义同一资源的补丁）。
    另：合集里两个 addon 若互斥（见 #22），选一个即可，双选由让位逻辑兜底。
25. ★★ **喷射类武器（灭菌器/喷火器）的"射程"是数据层改不到的**：
    `SprayWeaponComponent.projectile_type = ProjectileType_None` ⇒ 它们**不发射射弹**，
    伤害靠"粒子碰撞事件"触发 component 里的 `damage_info_type`；"喷多远"由**枪口粒子效果
    (muzzle_effect，一个 VFX 资源哈希)** 决定。离线穷尽验证：
      * `SprayWeaponComponent`(224B/16 字段) 与 `WeaponDataComponent`(56 字段) **没有 range/length/distance**；
      * 唯一带 `length` 的 `SprayCapsuleOverlap`(8B) 在 entities blob 里 **0 个实例**（无人使用）；
      * `BeamSettings`(有 Length) 里没有化学/火焰喷流条目；
      * 这些全是 `*ComponentData` 表 ⇒ 内存里**不加载**（见 #17）。
    ⇒ 结论：射程属美术(VFX)资产。**要改就只能改伤害/毒气效果来补偿**。
    （喷射武器的伤害数值在 `DamageSettings`（`0xE0A72CF0`，常驻），可改。）
26. ★ **同名数值完全相同的"邻居记录"怎么区分**：灭菌器 `DamageInfoType_Spray_Chem_Gun` 与
    敌方化学无人机 `Drone_Chem_Gun` 的 DamageInfo 记录**数值逐字段相同**，只能靠
    "**DamageInfoType 枚举相邻且取较小者**"（声明顺序稳定：社区 12<13 / 本构建 28<29）。
    ⇒ 这类场景**必须要求"恰好 N 条且关系成立"**，否则**拒绝写入** —— 改错 = 强化敌人。
    `DamageInfo` 记录 76B：`+0 type(u32) +4 damage(i32) +8 durable_damage(i32) +12 AP[4]`
    `+28 demo +32 force_strength +36 force_impulse +40 element_type +44 SE[4]{u32 type,f32 value}`。
27. ★ **离线测试的 python 不带 lupa 就用不了**：托管 python 本体没有 lupa，必须装在
    隔离 venv：`<managed-python> -m venv ~/.workbuddy/binaries/python/envs/default`
    → `<venv>/Scripts/pip install lupa Pillow`，之后**所有测试都用 venv 的 python**跑。
28. ★★ **"只影响某个武器" vs "全局 `*_Settings`"**：状态效果的 `strength`/`duration` 在**全局表**
    `StatusEffectSettings`（类型哈希 **`0xC63E0B22`**）里，被多方共用
    （灭菌器 / 敌方化学无人机 / G-4 毒气榴弹 / 轨道毒气弹 / 胚胎簇）。
    * 要"**只影响某武器**" ⇒ 只能改**它自己那条 `DamageInfo` 记录**里的
      `DamageStatusEffectInfo.value`（施加量）：灭菌器 = `SE[Gas].value @+48` / `SE[Gas_Confusion].value @+56`，原版都 0.5。
    * **持续时间(duration) 没有 per-weapon 入口** ⇒ 想"只改这个武器"就**必然改不到持续时间**。
    * 改全局表 = 敌我一起变强（灭菌器场景用户明确**拒绝**）。
      ⇒ 接这类需求先问清"接受全局副作用吗"，再动手。
29. ★ **`StatusEffectInfo` 布局（152B；typelib 权威 + 类型哈希交叉验证）**：
    `+0 type(StatusEffectType 枚举)` / `+8 debug_name(u64)` / `+16 shader_variable_preset(枚举)` /
    `+24 shading_environment(u64)` / `+32 fade_time(f32)` / **`+36 strength(f32)`** / **`+40 duration(f32)`** /
    `+44 damage_info_type(DamageInfoType 枚举)` / `+52..+59 script_event` / `@100 4×1bit 布尔` /
    `@104 与 @136 各一个 16B 数组`。
    典型值：`Gas 0.25/6s`、`Gas_Confusion 0.25/5s`、`Gas_MK2 50/1s`、`Fire 5/3s`、`Bleed 5/9999`。
    验证法：`dlsum`(减 5381 的 djb2) 反查 member 的 `type_id` —— 本次因此确认
    `m0=StatusEffectType` / `m2=StatusEffectShaderVariablePreset` / `m7=DamageInfoType`。
    ⚠️ 社区 `enums/StatusEffectType.json` 与 `status_effect_settings.json` 的**顺序互相矛盾**
    ⇒ **绝不用序位推枚举名**（老规矩 #1）。
    ⚠️ `parse_typelib.py` 跑出来 `strsize=0` ⇒ **dl_typelib 里没有成员名/枚举名**，只有哈希。
30. ★★ **指纹绝不能含"本 mod 会改的字段"，否则 cfg 热调 = 自己把自己搞失忆**：
    sterilizer v2.0.0 一开始沿用"SE value==0.5"作指纹，改完 value 后 `recheck` 认不出记录
    → 移除副本 → 重扫 → 震荡（cfg 热调等于失效）。新指纹只认
    `AP/demo/force` + **前两条 SE 的 type 非零 + 后两条 SE 为空**（纯结构关系）。
    ⇒ **每新增一个"可改字段"，都要回头重审指纹。** 单测 T17（热调 cfg 后仍认得出自己）守这个。
31. ★ **`recheck` 的兜底会让"半吊子变异"测不出来**：若变异只改 `patch_into_table` 的写入分支，
    5 秒后的 `recheck` 会把漏掉的字段补回去 → 变异"未被抓住"（其实是兜底在起作用）。
    ⇒ 变异要直接让 `write_xxx` 函数**整个变成空操作**，两条路径一起失效才测得准。
32. ★ **LuaJIT 写 float 要纯 Lua 打包**：没有 `string.pack`，离线 harness 的 `ffi` 也是假的 ⇒
    自写 `f32_bits()`（带往返 self-test）。**写非整数字段必须逐段 4 字节写**，
    因为目标值之间常夹着"不能碰"的字段（如 `+52..+55` 的 SE[1].type，两次独立写、中间不碰）。
33. **删/重构字段后必须 grep 一遍所有 `CONFIG.` 引用**：v1.0.0 的 `recheck()` 引用了**未定义**的
    `CONFIG.REC_SIZE` → `read_mem(addr, nil)` 直接报错 → **稳态复查从未生效（cfg 热调一直没用）**。
34. **多参数 cfg 的写法**（v2.0.0 起）：逐行解析、跳过 `#` 注释行，`key=value`
    （`damage%s*[=:]%s*(%-?%d+)` / `gas%s*[=:]%s*(%-?[%d%.]+)`），无 key 时退回"第一个裸整数 = damage"
    以兼容旧版；每项独立做范围校验，非法即退回默认。**旧 cfg 长期存在会覆盖新默认值**（老坑 #21）。
35. ★★ **音效是"资源"，不是"数据"** —— 想改音效先看清能改到哪一步：
    * **音量**编在 **Wwise SoundBank 音频资源**（`content/audio/...`）里，**任何数据字段都没有**。
      ⇒ **纯内存 mod 不可能"把原声放大"**；HD2 社区正路 = `hd2-audio-modder`(RaidingForPants)
      + **Wwise 2023**（要注册账号）重新编码 `.wem`，属**资源替换**，本项目不产出那种包。
    * 数据层能做的**只有"换一个 Wwise 事件"**（event 哈希）。武器的开火音效在
      `SprayWeaponComponent -> SprayWeaponStateInfo[3]`（warmup/firing/cooldown）的
      `audio_event_start/**+44**` / `audio_event_stop/**+48**`（56B 结构：
      `shake(32) + muzzle_effect(u64) + callout(4) + a0(4) + a1(4) + wind(4)`）。
      **但这些字段属于 `*ComponentData` ⇒ 内存普查 0 命中 ⇒ 数据层也改不到。**
      （灭菌器实测：`firing.a0=1773671782`、`firing.muzzle_effect=0xA3D15A3BBC56DE55`、
      `audio_node=1803865503`；候选替代事件：FLAM-40=`1881104745`、手枪型=`3757506625`、
      Crisper/Ripley=`2970598254`、敌无人机=`335829265`。）
36. ★★ **"裸内存值 + 佐证窗口"扫描法**（`sterilizer_sfx` 首创，试验性）：
    LDLD 普查只能发现**表**，发现不了**运行时实例的裸数据**。所以当目标字段所属的表不加载时，
    还可以**在整个进程内存里搜那个值本身**，用"同一结构内多个独立哈希共现"当签名：
    * 锚点 = 目标 u32（4 字节 LE），在 256KB 块里 `string.find(pat, init, true)`；
    * **佐证** = 同一结构内其它 u32/u64 哈希，命中点 **±WIN** 字节内必须 ≥`MIN_CORROB` 个；
      u64 用 `u32_le(lo) .. u32_le(hi)` 拼（**Lua 的 double 存不下 >2^53 的整数，绝不能直接写 u64 字面量**）；
    * **孤立命中一律跳过**（宁可漏，不可错）；`OVERLAP > 2*WIN` 保证跨块窗口不漏；
    * 只写目标字段那几个字节 + 回读；稳态复查**用窗口佐证重新验证位置**，而不是靠"被自己改过的值"认自己；
    * `register_self_pattern()` 要把**锚点和佐证的模式串**都登记，否则会扫到 Lua 堆里的自己；
    * 成败都要在 STATUS 里写清楚（`hits` / `lone_hits_skipped` / `rewrites`）—— 这三者能区分
      "值根本不在内存" / "值在但佐证不齐" / "游戏频繁重置"，是排障的关键信息。
37. ★ **`docs/ingame-*/` 里的实机日志是金矿**：`LDLD types seen` 那一行列出了**内存里全部常驻表**
    （本构建 = 37 张，全是 `*Settings` 家族）。**想知道"某个字段能不能改"，先去那里查它所属的表在不在。**
    另：`HARNESS.patched_records()` 只认 `patched_records=`；自己改 STATUS 关键字时要同步改测试的解析。
38. **合成内存夹具时一定要 assert 长度**：写 `SprayWeaponStateInfo` 时漏了一个字段（少 8 字节）→
    整个组件 200≠224 → 靠 `assert len(b)==224` 立刻发现。布局类夹具没有 assert 会静默错位。

39. ★ **仓库 `* -text`（`.gitattributes` + `core.autocrlf false`）**：本仓库的测试里有
    "从 zip 取回正文与 src **逐字节比对**"的用例 ⇒ **CRLF 转换会破坏它**。
    WorkBuddy 自带 PortableGit 默认 `core.autocrlf=true`，克隆/提交前必须显式关掉。
40. ★ **WorkBuddy 的 GitHub 连接器只有读权限**：`get_me`/`search_repositories` 可用，但
    `create_repository` 报 **403 `Resource not accessible by integration`**；`push_files` 只能推
    **文本**（UTF-8 直传，不能 base64）⇒ **二进制（zip/png/gz）推不了**。
    ⇒ **建仓 + 推送一律走 git CLI**。本机无 `gh`，但自带 **GCM 2.9.0**
    （`/d/WorkBuddy/resources/vendor/PortableGit/mingw64/bin/git-credential-manager.exe`，
    `credential.helper=manager` 已配，只是默认无缓存账号 ⇒ 需 `git-credential-manager github login`）。
41. ★ **发布仓库的版面结构（用户 2026-10-16 定）**：**大版面 = 根 `README.md`**（总览 + 分类总表 +
    快速开始 + 联机说明 + 目录结构）；**每个 Mod 一个独立版面 = `docs/0N-*.md`**
    （由 `dist/README-*.md` 加统一导航头生成）。目的有三：别人**下载即用**、**AI 无缝接手**、
    人能看懂。配套必须提交 `AI-HANDOFF.md`（接手指南）+ `.workbuddy/memory/MEMORY.md`（硬约定）。
42. **仓库体积控制法**：把**可复现的大体积数据**排除、只提交**压缩替补 + `restore.py`**
    （本仓库 340 MB → 提交 53 MB）。排除项必须写进 `.gitignore` 的注释里说明怎么还原。
    **未对外发布的中间产物也用 `.gitignore` 排除**（而不是删文件），源码与打包脚本保留即可重建。
43. **对外只发"集成后的成品"**：用户 2026-10-16 明确 —— 胆汁 4 团 / 6 团**不再单独发布**，
    只发 Arsenal 合集包 `BileSpewer-Salvo-Choice.zip`（一个包两个可勾选项）。
    ⇒ 交付数量口径 = **7 个 Mod**（源码 addon 仍是 8 个）。

## 发布仓库

* **<https://github.com/handsomeminions/hd2-lua-mods>**（账号 `handsomeminions` / `3141930265@qq.com`）
* git 身份只在本仓库 `git config` 里设，**不动全局**。
* 推送前自检清单：`git ls-files` 里不该出现 `vendor/community/data`、
  `analysis/ref/generated_entities.dl_bin`、未发布的独立 zip；`dist/*.zip` 应恰好 **7 个**。
* 推送后要更新：`README.md`（总表）、`docs/0N-*.md`、`AI-HANDOFF.md`（§5 档案表）、
  `HANDOVER.md`、`.workbuddy/memory/MEMORY.md`。

## 用户偏好
- 中文交流；要"能直接丢进 Arsenal 用"的成品：安装包 + 图标 + 中文说明一起给。
- 会自己上机实测并把 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\` 的日志发回来 —— 排障效率高。
- 图标由图像生成后**必须去水印**（右下角），用 `analysis/make_icon.py`。
- 强调"客户端改动 / 主机权威"必须主动讲清楚（客机看不到、伤害按房主算）。
