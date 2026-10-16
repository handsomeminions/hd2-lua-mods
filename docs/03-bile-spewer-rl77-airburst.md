> **[胆汁喷涌虫 · 胆汁迫击炮 → 落地炸成 RL-77 空爆集束](03-bile-spewer-rl77-airburst.md)**　v1.5.0　·　**实机** ✅ 已上机验证通过
>
> [← 返回总览](../README.md) · [全部 Mod 一览](../README.md#-全部-mod-一览7-个)
>
> **安装包** [`dist/BileSpewer-RL77Airburst.zip`](../dist/BileSpewer-RL77Airburst.zip)　·　**源码** [`src/bug_artillery_airburst.lua`](../src/bug_artillery_airburst.lua)
>
> **离线测试** `analysis/test_bug_artillery.py`（28/28）　·　**Manifest GUID** `8cf04434-8f4e-43d5-8493-22aaace62e20`

---

# 胆汁喷涌虫 · 胆汁迫击炮 → 落地炸成 RL-77 空爆集束

> 把《绝地潜兵2》终结族 **胆汁喷涌虫（Bile Spewer）** 的「胆汁迫击炮」改造成：
> **外形与飞行都保持原版绿色胆汁迫击炮，落地炸成 RL-77 空爆集束。**
> **一发胆汁迫击炮 = 一次空爆**，不多不少。
> （齐射总共几发由游戏决定；若装了「多发齐射」mod，则每一发都各炸一次空爆。）

---

## 一、改了什么（v1.4.0 定型；v1.5.0 只改复查方式）

| # | 项目 | 处理 | 实现 |
| --- | --- | --- | --- |
| 1 | **外形（模型 + 飞行粒子）** | **保持原版胆汁迫击炮**（那个绿色团块） | `+128` 模型 / `+72` `+88` `+96` 粒子 **一个字节都不动** |
| 2 | **攻击方式 / 飞行速度 / 轨迹** | **与原版逐字节一致** | 速度/质量/阻力/重力/寿命/爆炸角度/近炸距离/引信/解保距离 **全部不动** |
| 3 | **落地炸开** | 用 RL-77 空爆火箭的爆炸方式 | `+144 explosion_type_on_impact` ← 空爆集束爆炸（半径 3/5/7，抛出 **25 枚子弹药**） |
| 4 | **子弹药物理** | 与原版 RL-77 一致（碰撞 + 随机散射 + 无规律飞溅） | `+152 explosion_delay`（0 → 0.2）与 `+240 flags`（0xB5 → 0x94）← 火箭 |

具体表现：

- 胆汁喷涌虫在 **Extreme（7）及以上难度** 仍然把腹部举向天空、以**原来的迫击炮弹道与速度**抛射（齐射多发的数量由游戏决定）
  —— 弹道、速度、射程、下落曲线**和原版完全一样**；
- 飞在空中的那发**看起来就是原来的绿色胆汁团块**；
- **落地（命中）那一刻**炸开的是**空爆集束**：主爆炸半径 3/5/7，并抛出 **25 枚子弹药** ——
  它们带**原版空爆火箭的物理**：随机散射角、会跳弹、无规律飞溅后各自再爆；
- 火焰、粒子、弹坑、音效、伤害全部是 RL-77 那一套。

> **不是"近炸"**：近炸保持为 0，所以它**一定飞完全程、落地才炸**。

### 为什么 v1.4.0 要把外形回退？

v1.1.0~v1.3.0 试过把弹体换成 **RL-77 火箭**（`+128` 模型 + `+72/+88/+96` 粒子），想做出"完整火箭"外形。
**实机结果是火箭模型不渲染（模型丢失）**，而原来的绿色团块又被换掉了 ⇒ **弹体看不见**。
所以 v1.4.0 按要求**回退**：拿回**原版胆汁迫击炮的外形**（绿色团块），其余照旧。

> 补充一个小知识：胆汁迫击炮原版 `projectile_unit_path == 0`，**它本来就没有实体模型**；
> 你在游戏里看到的"绿色团块"其实是 **粒子特效**（`+72` 推进粒子 / `+96` 拖尾粒子）。
> 所以"回退模型"实际是把 `+128` 与 `+72/+88/+96` **整组**保持原版。

### 关于"飞行音效"（可选开关）

v1.4.0 默认沿用你 v1.3.0 的设置：**飞行音效仍换成火箭的**（`SWAP_FLIGHT_FX = true`）。
想连音效也回退成原版胆汁，把源码里这一行改成 `false` 重新打包即可：

```lua
local CONFIG = {
    ...
    SWAP_FLIGHT_FX = true,   -- false = 连飞行音效也保持原版胆汁迫击炮
```

> 说一声我可以直接给你一个 `SWAP_FLIGHT_FX = false` 的版本。

---

## 二、安装

1. 用 **HD2 Arsenal / HD2 Mod Manager** 导入 `BileSpewer-RL77Airburst.zip`（拖进去即可）。
2. 确保 **Bingus Shared Loader v15+**（API 1）已安装并启用。
3. **两个都要勾选，一起 Deploy**。本 mod 单独不生效 —— loader 负责把 Lua 注入游戏。
4. 进任务（最好**自己开房当房主**），找胆汁喷涌虫，等它进入 7+ 难度的迫击炮形态。

> **想还原**：在管理器里禁用本 mod 并 **Purge**，重新 Deploy。游戏文件从未被改动，改动只在内存里。

---

## 三、怎么确认生效

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\
    bug_artillery_airburst_STATUS.txt   ← 给用户看：第一行就是结论
    bug_artillery_airburst.log          ← 给开发者看：详细过程
```

**STATUS 首行**：`OK - patch applied (revision 1.5.0): ...`（生效）／`SEARCHING - ...`（还没找到射弹表）／`FAILED - ...`。

生效时同一文件还会明确写出：

```
target(bug artillery) type=344 | source(RL-77 airburst) type=312
impact_explosion=6->325 (airburst cluster)                       ← 落地爆炸换成了空爆集束
submuni_physics_swapped delay 0.00->0.20 flags 0xB5->0x94        ← 25 枚子弹药按火箭物理抛射
model_kept_vanilla_bile=true (unit=0x0000000000000000) particles_kept_vanilla thruster=0x758CA9293725AFE2 trail=0x29354B9DC32A52AC (green blob kept)
flight(trajectory/speed/arc)_preserved=true  shape(model/particles)_preserved=true  flight_audio_swapped=true
patched_records=N
```

日志里成功时会看到：

```
PATCHED bug artillery @0x... (idx 29, type 344): shape kept vanilla bile
(unit 0x0000000000000000 / thr 0x758CA9293725AFE2 / trail 0x29354B9DC32A52AC),
impact explosion 6->325 (airburst cluster), submuni delay 0.00->0.20 flags 0xB5->0x94
(25 bomblets w/ rocket scatter), flight preserved [src idx 101]
```

---

## 四、联机说明（重要）

本 mod 是**纯客户端内存补丁**，不修改任何网络数据。

- 你是**房主 / 单人**：真正生效。别人也看得到。
- 你是**客机（别人开房）**：实际伤害由**房主**用它自己的数据结算 —— 你这边可能看到空爆，
  但敌人实际掉血仍按房主的原版数据走，其他玩家也看不到你的改动。
  **想真打出效果：自己开房当房主，或让房主也装这个 mod。**

另照例提醒：HD2 有 **nProtect GameGuard**，这类「进程内改内存」的 mod 属官方不支持的灰色地带，
风险自担；同类内存 mod 的通行建议是**单人 / 自己开房**使用。

---

## 五、原理（简述）

1. 扫描进程内存，定位常驻的 **`ProjectileSettings`（射弹表）**（`LDLD` 块，类型哈希 `0xBD4042C2`）。
2. 在表里用**跨构建稳定**的指纹定位两条记录（**不写死任何枚举下标** —— 枚举会随版本漂移）：
   - **目标**：胆汁迫击炮 `ProjectileType_Bug_Artillery`
     指纹 = 无名（`name_upper==0`）+ 口径 50 + 初速 30 + 质量 1000
     + **推进粒子资源哈希 `758CA9293725AFE2`** + 拖尾粒子资源哈希 `AC522AC39D4B3529` + 尾迹音频 `3340293219`
   - **源**：RL-77 空爆火箭 `ProjectileType_Grenade_85mm_AirburstCluster`（Flak 近炸模式）
     指纹 = 口径 85 + 质量 3300 + 初速 250 + 寿命 1.5 s + 近炸 2 m
     + 拖尾粒子资源哈希 `C8FD1E326BA587BF` + 尾迹音频 `1680798988`
3. **只改写目标记录的这 3 组字段**（不是整条克隆）：
   - `+144` `explosion_type_on_impact`（4 字节）← 源（空爆集束爆炸）—— **总是**
   - `+152` `explosion_delay`（4 字节）← 源（0.2，子弹药抛出时机）—— **总是**
   - `+240` `flags` 首字节（1 字节）← 源（`0x94`；bit0 `inherit_velocity` / bit5 `explosions_inherit_velocity`）—— **总是**
   - `+208 / +212`（飞行音效）—— **仅当 `SWAP_FLIGHT_FX`**（默认 true）

**"外形 + 弹道必须与原版一致"的硬保证**：写入前会核对这些字段在新内容里与原文**逐字节相同** ——
`speed`(+32)、`mass`(+36)、`drag`(+40)、`gravity_multiplier`(+44)、`life_time`(+52)、
**`particle_thruster`(+72)、`thruster_length`(+88)、`particle_trail`(+96)、`projectile_unit_path`(+128)**、
`explosion_threshold_angle`(+136)、`explosion_proximity`(+148)、`explosion_type_expire`(+156)、`arming_distance`(+160)。
**任一不同就拒绝写入并记错误**。写完后还会再确认"爆炸与子弹药开关确实取自源"，以及读回校验与写入内容一致。

**关键数值**（离线三方交叉核对：游戏 typelib + FileDiver 明文镜像 + 社区 JSON，并与 wiki 逐项吻合；
本 mod 用到的每个偏移都做过**全表复现**验证，命中率 ~100%）：

| 项目 | 值 |
| --- | --- |
| `ProjectileInfo` 大小 | 272 字节 |
| 关键字段偏移 | `+24 calibre`、`+32 speed`、`+36 mass`、`+40 drag`、`+44 gravity`、`+52 life_time`、`+72 particle_thruster(u64)`、`+88 thruster_length`、`+96 particle_trail(u64)`、`+128 projectile_unit_path(u64)`、`+136 explosion_threshold_angle`、`+144 explosion_type_on_impact`、`+148 explosion_proximity`、`+152 explosion_delay`、`+156 explosion_type_expire`、`+160 arming_distance`、`+208/+212 audio_trail_start/stop`、`+240 flags` |
| 目标（胆汁迫击炮）本构建 type | `344`（原爆炸 `ExplosionType_Bug_Artillery`，半径 1/8/14） |
| 源（RL-77 Flak）本构建 type | `312`（爆炸 `ExplosionType_AirburstCluster`，半径 3/5/7，25 枚子弹药） |
| RL-77 官方数值（wiki） | 质量 3.3 kg / 初速 250 m/s / 阻力 30% / 重力 100% / 寿命 1.5 s / 近炸 2 m / 内径 3 外径 5 震波 7 / **25 枚子弹药** |

> **子弹药为什么不用我们改？** 子弹药"用哪条记录、怎么飞"由**爆炸记录**决定：
> `ExplosionType_AirburstCluster` 里写着 `num_shrapnel_projectiles = 25` 与
> `shrapnel_projectile_type = ProjectileType_AirburstCluster_Bomb`，而那条记录自带全部飞溅物理
> （速度 25 / 寿命 0.8 s ±70% **随机** / 跳弹 / 散射角 垂直3° 水平15°），会自动生效。
> 真正需要跟着火箭走的是上面那两个**生成开关**（`+152` / `+240`）。

> RL-77 有 **Flak（近炸）** 与 **Cluster（定时）** 两种弹药。本 mod 从 **Flak 变体**取"落地爆炸"，
> 用寿命 1.5 s / 近炸 2 m 两个判据把它与 Cluster 变体区分开；但**不采用它的飞行参数**。

---

## 六、性能与生命周期

- **搜索期**：每帧最多 2 ms CPU、单次读取 256 KB、每 2 帧推进一步；数据段优先、代码段垫底。
- **找到即停**：打完补丁并**跑完当前这一轮完整扫描**（覆盖内存里所有副本）后**彻底停止扫描**，
  不再做任何周期性全量重扫 —— 没有掉帧风暴。
- **复查**：稳态每 5 秒**按已记录的地址直读**（不到 1 微秒），被地图重载冲掉会自动重打；
  只有在所有副本都消失时才重新扫描。

---

## 七、目录结构（本 mod 相关）

```
src/bug_artillery_airburst.lua             addon 源码（REVISION 1.5.0）
analysis/test_bug_artillery.py             离线仿真测试（功能 16 + 变异 11）
analysis/harness.lua                       离线仿真环境（假 FFI / 假内存）
analysis/fixtures/ba_*.bin                 夹具（当前构建真实记录字节）
analysis/build_package_bug_airburst.py     打包脚本
dist/BileSpewer-RL77Airburst.zip           安装包
dist/thumbnail_bug_airburst.png            图标
```

**离线测试结果**：功能 **17/17**、变异 **11/11** = **28/28 全通过**；**发布正文**端到端复测同样 28/28。
另有一项**共存专项**：`analysis/test_bug_combo.py` —— 与「多发齐射」mod 同装时，
两边改在同一条射弹记录上的字段互不覆盖、多个复查周期不互抢。

重点用例：

- **T1** 真实整表：整条记录必须**恰好等于**"只改爆炸 + 子弹药开关（+音效）"的期望字节；
- **T2** ★核心回退断言：**模型 `+128` 与粒子 `+72/+88/+96` 必须与原版逐字节相同**
  （且 `+128` 仍为 `0`），同时速度仍 30、寿命仍 0、近炸仍 0；
- **T15** `SWAP_FLIGHT_FX=false`：连飞行音效也保持原版，外形/弹道照旧不变；
- **T16** STATUS/日志必须把"改了什么 / 外形与弹道保持不变"写清楚。

变异测试（故意改坏每一处保护，都必须被测试抓住）：目标拖尾指纹写错 / 目标推进粒子指纹写错 /
源拖尾指纹写错 / 字节序搞反 / **★ 又去改模型（回退被破坏）** / **★ 又去改飞行粒子** /
不改爆炸 / 漏掉子弹药 flags / 整条克隆且去掉自检 / 去掉寿命-近炸判据（误选 Cluster）/
去掉回读校验（写入失败被漏过）。

---

## 八、常见问题

| 现象 | 处理 |
| --- | --- |
| 进游戏没看到效果 | ① 确认 `STATUS.txt` 首行是 `OK - patch applied`；② 确认你是**房主**；③ 胆汁喷涌虫的迫击炮**只在 7+ 难度**出现（低难度它只用胆汁喷吐和近战） |
| 弹体看不见 / 模型丢失 | v1.4.0 已回退成**原版绿色胆汁迫击炮外观**（`+128` 与 `+72/+88/+96` 不动）。若仍异常请把 `STATUS.txt` 发我核对 `shape(model/particles)_preserved=true` |
| 弹道/速度变了？ | 不应该。请把 `STATUS.txt` 里的 `flight(trajectory/speed/arc)_preserved=` 发我；mod 内置了逐字节自检，任何会改变弹道或外形的写法都会被拒绝写入 |
| 想让飞行音效也变回原版胆汁 | 见上面"可选开关"，或直接找我要 `SWAP_FLIGHT_FX = false` 的版本 |
| STATUS 一直 `SEARCHING` | 射弹表多在任务内加载；进任务后会自动继续。仍不行请看日志的 `LDLD types seen` 是否含 `0xBD4042C2` |
| STATUS 显示 `FAILED ... too old` | 把 Bingus Shared Loader 升级到 v15 及以上（API 1） |
| 同时装了 120mm / 380mm / 迫击炮那几个 mod | 不冲突：各用独立的状态/日志文件与独立命名的全局函数。**但必须都用管理器导入** |
| 想改回原版 | 管理器里禁用 + Purge + 重新 Deploy |

> ⚠️ **手动拷贝 `Addon/` 会互相覆盖**：多个 addon 的 ZIP 里都带 `Addon/9ba626afa44a3aa3.patch_N`，
> 管理器部署时会自动重排编号。**请始终用管理器导入**，不要把 `Addon/` 手拷进 `data/`，
> 否则会出现「装了好几个只有一个生效」。
