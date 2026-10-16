> **[A/M-12 迫击哨戒炮 → 轨道凝固汽油弹效果](07-mortar-sentry-napalm.md)**　v1.0.1
>
> [← 返回总览](../README.md) · [全部 Mod 一览](../README.md#-全部-mod-一览)
>
> **安装包** [`dist/MortarSentry-NapalmImpact.zip`](../dist/MortarSentry-NapalmImpact.zip)　·　**源码** [`src/mortar_sentry_napalm.lua`](../src/mortar_sentry_napalm.lua)　·　**离线测试** `analysis/test_mortar_napalm.py`（23/23）
>
> **Manifest GUID** `0208faf4-f89b-416e-8806-2f242d394ef2`

---

# A/M-12 迫击哨戒炮 · 落地爆炸 → 轨道凝固汽油弹效果

> 把《绝地潜兵2》**A/M-12 迫击哨戒炮（Mortar Sentry）** 的炮弹改成：
> **飞行一切照旧，落地炸开时是"轨道凝固汽油弹火力网"里单颗凝固汽油弹的打击效果。**

---

## 一、改了什么

| # | 项目 | 处理 |
| --- | --- | --- |
| 1 | **落地（命中）爆炸** | 换成 **轨道凝固汽油弹火力网单颗汽油弹** 的爆炸效果：汽油弹专属爆炸粒子、`FireTemplate_Large`（**落地留下一片燃烧的凝固汽油火海**）、`Scorch` 焦土弹坑、专属爆炸音效与伤害类型；爆炸半径 3.3 / 10 / 11 m |
| 2 | **其余全部保持原版迫击炮** | **索敌与瞄准、飞行轨迹、飞行速度、重力、引信、弹体模型、拖尾粒子、飞行音效、直接命中伤害、爆炸角度、近炸/延迟/解保距离 —— 一个字节都不动** |

也就是说：哨戒炮还是原来那个哨戒炮，炮弹还是照原来的弹道飞、原来的速度落，
**只有"炸开"那一下变成了凝固汽油弹**。

> 原版迫击炮爆炸半径是 3 / 9 / 13 m，汽油弹是 3.3 / 10 / 11 m —— 体量接近；
> 主要变化是**外观、火焰、音效与伤害类型**，以及多出来的**持续燃烧火场**。

---

## 二、安装

1. 用 **HD2 Arsenal / HD2 Mod Manager** 导入 `MortarSentry-NapalmImpact.zip`。
2. 确保 **Bingus Shared Loader v15+**（API 1）已安装并启用。
3. **两个都要勾选，一起 Deploy**。本 mod 单独不生效 —— loader 负责把 Lua 注入游戏。
4. 进任务（最好**自己开房当房主**），叫一发 **迫击哨戒炮**，等它开火。

> **想还原**：管理器里禁用本 mod 并 **Purge**，重新 Deploy。游戏文件从未被改动。

---

## 三、怎么确认生效

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\
    mortar_sentry_napalm_STATUS.txt   ← 给用户看：第一行就是结论
    mortar_sentry_napalm.log          ← 给开发者看：详细过程
```

**STATUS 首行**：

```
OK - patch applied (revision 1.0.0): Mortar Sentry shells now burst with the Orbital Napalm effect on impact
```

同一份文件里还会写清楚：

```
target(mortar sentry shell) type=346 | source(napalm shell) type=234
impact_explosion=360->63 (Orbital Napalm)
flight(targeting/arc/speed)_preserved=true  visuals_preserved=true
patched_records=1
```

日志里成功时：

```
PATCHED mortar sentry shell @0x... (idx 90, type 346): impact explosion 360->63 (Orbital Napalm);
targeting/flight/visuals untouched [src idx 140]
```

- `SEARCHING - ...` → 还没找到射弹表（多在飞船早期；进任务后会自动继续）
- `FAILED - ... too old` → loader 版本太旧，升到 v15+（API 1）

---

## 四、联机说明（重要）

本 mod 是**纯客户端内存补丁**，不修改任何网络数据。

- 你是**房主 / 单人**：真正生效。
- 你是**客机（别人开房）**：实际伤害由**房主**用自己的数据结算 —— 你这边可能看到汽油弹炸开，
  但敌人实际掉血仍按房主的原版数据走，其他玩家也看不到你的改动。
  **想真打出效果：自己开房当房主，或让房主也装这个 mod。**

另照例提醒：HD2 有 **nProtect GameGuard**，这类「进程内改内存」的 mod 属官方不支持的灰色地带，
风险自担；同类内存 mod 的通行建议是**单人 / 自己开房**使用。

---

## 五、原理（简述）

1. 扫描进程内存，定位常驻的 **`ProjectileSettings`（射弹表）**（`LDLD` 块，类型哈希 `0xBD4042C2`）。
2. 按**跨构建稳定**的指纹定位两条记录（**不写死任何枚举下标**）：

   | | 记录 | 指纹 |
   | --- | --- | --- |
   | **目标** | A/M-12 迫击哨戒炮炮弹（本构建 type **346**） | `name_upper=900451699`（"40mm HE MORTAR"）+ 口径 360 + 初速 100 + 质量 70000 + 拖尾粒子哈希 `7E7C55538A04ACFD` + 尾迹音频 `3053896360` |
   | **源** | 轨道凝固汽油弹火力网的汽油弹壳（本构建 type **234**） | 口径 84 + 质量 5000 + 拖尾粒子哈希 `68358A1CC55AFDDB` + 尾迹音频 `808888556` |

   > ⚠️ **只按名字认记录会翻车**：`"40mm HE MORTAR"` 这个名字在表里有 **4 条**（含机器人迫击炮壳 cal 40 / mass 750）。
   > 必须叠加物理量与 64 位资源哈希才唯一。测试里专门有一条用例守着这一点。

3. **只改写一个字段**：目标记录的 `+144 explosion_type_on_impact` ← 源记录的 `+144`
   （**运行时读出来的**，所以跟随版本，绝不写死 `63`）。
4. **"其余一律不动"的硬保证**：写入前用 `KEEP_FIELDS` 逐段核对 22 段（身份 / 口径 / 初速 / 质量 /
   阻力 / 重力 / 寿命 / 伤害类型 / 推进粒子 / 拖尾粒子 / 弹体模型 / 爆炸角度 / 近炸 / 延迟 / 引信 /
   解保距离 / 贴花 / 落点音效 …）在新内容里与原文**逐字节相同**；任一不同就**拒绝写入**并记错误。
   写完后再确认"爆炸字段确实取自源"，并做读回校验。

**字段偏移**（`ProjectileInfo` = 272 字节；每个偏移都做过**全表复现**验证，命中率 ~100%）：

```
+0 type  +4 name_upper  +8 name_cased  +12 short_name  +16 hud_icon(u64)
+24 calibre  +32 speed  +36 mass  +40 drag  +44 gravity  +52 life_time  +60 damage_info_type
+72 particle_thruster(u64)  +88 thruster_length  +96 particle_trail(u64)  +128 projectile_unit_path(u64)
+136 explosion_threshold_angle  +144 explosion_type_on_impact  +148 explosion_proximity
+152 explosion_delay  +156 explosion_type_expire  +160 arming_distance
+164 decal_size  +168 surface_impact_type  +208/+212 audio_trail_start/stop
```

> 说明：轨道凝固汽油弹火力网同时使用 `Orbital_Napalm` 与 `Orbital_Napalm_Cheap` 两种弹药，
> 但这两条爆炸记录在表里**逐字段完全相同**（只有 `type` 与 `surface_impact_type` 不同），
> 观感与伤害一致，取哪条都等价；本 mod 直接取"汽油弹壳自己那一颗"。

---

## 六、性能与生命周期

- **搜索期**：每帧最多 2 ms CPU、单次读取 256 KB、每 2 帧推进一步；数据段优先、代码段垫底兜底。
- **找到即停**：打完补丁并**跑完当前这一轮完整扫描**（覆盖内存里所有副本）后**彻底停止扫描**，
  不做任何周期性全量重扫 —— 没有掉帧风暴。
- **复查**：稳态每 5 秒按**已记录的地址直读**（不到 1 微秒），被地图重载冲掉会自动重打；
  只有所有副本都消失时才重新搜索。

---

## 七、目录结构（本 mod 相关）

```
src/mortar_sentry_napalm.lua                  addon 源码（REVISION 1.0.0）
analysis/test_mortar_napalm.py                离线仿真测试（功能 15 + 变异 8）
analysis/harness.lua                          离线仿真环境（假 FFI / 假内存）
analysis/fixtures/ms_*.bin                    夹具（当前构建真实记录字节）
analysis/build_package_mortar_napalm.py       打包脚本
dist/MortarSentry-NapalmImpact.zip            安装包
dist/thumbnail_mortar_napalm.png              图标
```

**离线测试结果**：功能 **15/15**、变异 **8/8** = **23/23 全通过**；**发布正文**端到端复测同样 23/23。

重点用例：

- **T2**：除 `+144` 外整条记录**逐字节不变**（逐字段点名核对速度/重力/阻力/模型/拖尾/音效…）；
- **T3**：同名 4 条同时在表里时，**只打对的那条**，干扰项一个字节都不动；
- **M4**：故意改成"只按名字认记录" → 测试必须抓到它打错了目标；
- **M5/M7**：故意改成"整条克隆"或"偏移写错" → 被 `keep-guard` 拦下、拒绝写入；
- **M8**：去掉回读校验 → 写入静默失败会被漏过（所以必须有）。

---

## 八、常见问题

| 现象 | 处理 |
| --- | --- |
| 进游戏没看到效果 | ① 确认 `STATUS.txt` 首行是 `OK - patch applied`；② 确认你是**房主**；③ 迫击哨戒炮要**叫下来并让它开火**（它只打它视野内的敌人） |
| 想要的是"汽油弹整片火海"而不是单颗爆炸 | 本 mod 用的是**单颗汽油弹的爆炸**（含 `FireTemplate_Large` 燃烧火场）。若你其实想要"火力网级别的连续覆盖"，那是另一套实现，告诉我 |
| 想连飞行尾迹也换掉 | 不需要改代码即可判断 —— 本 mod 严格按你的要求**只动爆炸**；如需改飞行观感请说明 |
| STATUS 一直 `SEARCHING` | 组件表多在任务内加载；进任务后会自动继续。仍不行看日志的 `LDLD types seen` 是否含 `0xBD4042C2` |
| 同时装了其它 HD2 mod | 不冲突：每个 addon 各用独立的状态/日志文件与独立命名的全局函数。**但必须都用管理器导入** |
| 想改回原版 | 管理器里禁用 + Purge + 重新 Deploy |

> ⚠️ **手动拷贝 `Addon/` 会互相覆盖**：多个 addon 的 ZIP 里都带 `Addon/9ba626afa44a3aa3.patch_N`，
> 管理器部署时会自动重排编号。**请始终用管理器导入**。
