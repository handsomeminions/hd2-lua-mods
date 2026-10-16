> **[TX-41 灭菌器 → G-4 伤害 + 毒气施加量 ×2](08-sterilizer-g4-gas-damage.md)**　v2.0.0
>
> [← 返回总览](../README.md) · [全部 Mod 一览](../README.md#-全部-mod-一览)
>
> **安装包** [`dist/Sterilizer-G4GasDamage.zip`](../dist/Sterilizer-G4GasDamage.zip)　·　**源码** [`src/sterilizer_gas_damage.lua`](../src/sterilizer_gas_damage.lua)　·　**离线测试** `analysis/test_sterilizer_gas_damage.py`（28/28）
>
> **Manifest GUID** `d369d2c7-93a1-455a-a61a-ba3c7d47e991`

---

# TX-41 灭菌器 · 伤害升到 G-4 级别 + 毒气施加量 ×2

> **一句话**：TX-41 灭菌器每次命中 **直接伤害 1 → 3**（= G-4 毒气榴弹爆炸的伤害值），并且**喷出的毒气状态效果「施加量」翻倍**（0.5 → 1.0）。
> **只影响灭菌器** —— 敌人化学无人机的毒气一点没动，全局毒气表也没动。
> **射程改不了** —— 见第四节，不是没做，是数据层没有这个字段。

- 安装包：`dist/Sterilizer-G4GasDamage.zip`
- 源码：`src/sterilizer_gas_damage.lua`（**v2.0.0**）
- 离线测试：`analysis/test_sterilizer_gas_damage.py`（**28/28**，含 9 条变异测试）

> v2.0.0 与 v1.x **共用同一资源名与 GUID**：直接导入覆盖即可，管理器里不会变成两个 mod。

---

## 一、改了什么

| | 原版 | 本 mod |
|---|---|---|
| 每次命中**直接伤害** | **1** | **3** |
| 耐久伤害（durable） | 1 | 3 |
| 毒气状态效果**施加量**（`Gas`） | 0.5 | **1.0**（×2） |
| 致幻状态效果**施加量**（`Gas_Confusion`） | 0.5 | **1.0**（×2） |
| 其它一切 | — | **逐字节不变** |

**为什么伤害是 3**：G-4 毒气榴弹的爆炸伤害记录（`DamageInfoType_Explosion_Gas_Grenade`）就是 `damage = 3 / durable = 3`，离线把两条记录的全部 8 个字段逐项比对确认过。

**没动的东西**（这是本 mod 的重点）：
护甲穿透（5/5/5/0）、拆迁强度、推力/冲量、**状态效果的类型编号（SE 枚举）**、喷毒粒子外观、音效、弹道 —— 全部保持原版。
**敌人那条记录（`Drone_Chem_Gun`）逐字节未动**。**全局毒气表（`StatusEffectSettings`）也没有被修改**。

### 技术细节（给好奇的人）

| 项 | 值 |
|---|---|
| 表 | `DamageSettings`（LDLD 类型哈希 `0xE0A72CF0`，属于 `*_Settings` 家族 → **实机确认常驻内存**） |
| 记录 | `DamageInfoType_Spray_Chem_Gun`（**只被 TX-41 灭菌器使用**，由实体 blob 反查确认） |
| 字段① | `+4 damage(i32)`、`+8 durable_damage(i32)` |
| 字段② | `+48 SE[Gas].value(f32)`、`+56 SE[Gas_Confusion].value(f32)` |
| 写入 | **只写 3 段共 16 字节**（`+4..+11` / `+48..+51` / `+56..+59`），每段写完回读校验；其余逐字节 keep-guard |

⚠️ **一段被刻意保护的空隙**：`+52..+55` 是 `SE[1].type`（`Gas_Confusion` 的类型编号）。两次值写入是**分开的 4 字节操作**，中间这段**绝不触碰** —— 测试里专门有一条断言守着它。

⚠️ 有一个**同名邻居**：敌人"化学无人机"用的 `DamageInfoType_Drone_Chem_Gun`，数值和灭菌器**一模一样**。本 mod 用"两条候选的 `DamageInfoType` 必须**相邻**、且两条挂的状态效果类型**完全相同**、取较小编号 = 灭菌器"来区分（枚举声明顺序稳定：12<13 / 28<29）。
**只要候选不是恰好 2 条、或类型关系对不上，mod 直接拒绝写入**（宁可不动，也绝不冒险去强化敌人）。

### 关于"毒气施加量"的体感

那个 `0.5 → 1.0` 是**每次命中时施加的毒气状态量**。按字段语义，翻倍后目标**更快 / 更容易**进入毒气（掉血）与致幻状态。
这一条**属于推断**（字段语义 + 原版数值对比），**具体体感请上机实测确认** —— 如果你觉得没变化、或者方向不对，把 `gas` 调更高（如 `2.0` / `4.0`）或调回 `0.5` 试试，**改 cfg 即可，不用重打包**。

## 二、为什么"持续时间"改不了（只能改施加量）

灭菌器喷中的目标会挂两个状态效果：

- `StatusEffectType_Gas` —— 毒气，带持续掉血（`DamageInfoType_DPS_Gas`）
- `StatusEffectType_Gas_Confusion` —— 致幻

这两个效果的 **`strength` / `duration`（强度 / 持续时间）定义在一张全局表** `StatusEffectSettings`（类型哈希 `0xC63E0B22`）里，而这张表是**多方共用**的：

| 谁在用 | 说明 |
|---|---|
| TX-41 灭菌器 | 玩家（想要的对象） |
| **敌方化学无人机** | 敌人 ✗ |
| G-4 毒气榴弹 / 轨道毒气弹 / 胚胎簇 | 爆炸类 |

⇒ 改这条全局记录 = **敌我双方的毒气一起变强**（榴弹和轨道弹也跟着变），你选择的是**不要**这种副作用。

所以本 mod 改为拉高**灭菌器自己那条 `DamageInfo` 记录**里的"施加量"——**严格只影响灭菌器**。
**代价**：这样**改不到"持续时间"**，因为 duration 只存在于全局表，没有"只对灭菌器生效"的写入口。这是数据结构的硬限制，不是实现取舍。

## 三、⚠️ 为什么"射程"改不了（重要）

喷射类武器（TX-41 灭菌器 / B/FLAM-80 焚燃者 / FLAM-40 / Crisper）在数据层**根本没有射程字段**：

1. 它们的 `SprayWeaponComponent.projectile_type = None`
   → **不发射射弹**，伤害靠"粒子碰撞事件"触发。
2. 所以"喷多远"完全由**枪口粒子效果（muzzle_effect，一个 VFX 资源哈希）**决定。
3. 离线逐项翻过：
   - `SprayWeaponComponent`（224 字节，16 个字段）和 `WeaponDataComponent`（56 个字段）里**没有任何 range / length / distance 字段**；
   - 唯一带 `length` 的是 `SprayCapsuleOverlap`（8 字节），但它在整个实体数据里**0 个实例**（没有任何东西用它）；
   - `BeamSettings`（有 Length）里没有化学/火焰喷流条目。
4. 而且这些组件都是 `*ComponentData` 表 —— 实机全内存普查证明它们**在内存里不加载**。

⇒ **射程属于美术（VFX）资产，Lua 内存补丁改不到。**

## 四、怎么用

1. 打开 Arsenal / HD2MM → 把 `Sterilizer-G4GasDamage.zip` **拖进去 / 导入** → 部署（Deploy）。
2. 完事。没有选项要勾。

### 两个数值都可现场调（不用重打包、不用重启游戏）

装好后会自动生成：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\sterilizer_gas_damage.cfg
```

内容是：

```
# damage : direct hit damage    (vanilla 1;   G-4 Gas Grenade = 3)
# gas    : gas status buildup   (vanilla 0.5; 1.0 = double strength)
damage=3
gas=1.000
```

| 想做的事 | 怎么改 |
|---|---|
| 伤害更高 | `damage=5`（上限 200；填 `1` = 回原版） |
| 毒气更猛 | `gas=2.000`（`0.5` = 回原版） |
| 只想改伤害 | 删掉 `gas=` 那一行也可以（会退回默认 1.0） |

改完保存 → **5 秒内自动重打**，下一枪立刻生效。超范围/非法内容会自动退回默认值。
（兼容旧版：整个文件只写一个裸数字 `5`，会被当成 `damage`。）

## 五、上机怎么确认

进任务后看：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\sterilizer_gas_damage_STATUS.txt
  首行应为 OK - patch applied (revision 2.0.0): TX-41 Sterilizer damage 1 -> 3, gas buildup 0.5 -> 1.000
  damage=1->3 (vanilla 1; G-4 Gas Grenade = 3)
  gas_buildup=0.5->1.000 (vanilla 0.5; 1.0 = 2x strength)
  patched_records=1
  copy1: rec@0x...
```

然后拿灭菌器喷敌人，感受伤害 + 中毒速度的变化。

> 如果首行一直是 `SEARCHING`，看同目录的 `.log`：
> - 有 `PATCHED sterilizer @0x... (idx N, damage_info_type 28, 2 candidates): damage 1 -> 3, gas 0.500 -> 1.000` → 已生效；
> - 有 `expected exactly 2 ... refusing` 或 `status-effect types differ ... refusing` → 判据没通过（把 `.log` 发我）；
> - 什么都没有 → 表还没扫到，多等几秒。

## 六、联机提醒

**客户端改动、主机权威** —— 客机看不到、伤害按房主算。要真正生效，**房主也要装**。

## 七、验证情况

- `analysis/test_sterilizer_gas_damage.py`：**功能 19 + 变异 9 = 28/28**，连跑 8 遍稳定
- 用包内"发布正文"复测同样 **28/28**；包内正文与 `src/sterilizer_gas_damage.lua` **逐字节一致**
- 夹具 = **当前构建的真实明文镜像**（`DamageSettings` 整表 649 条 × 76 字节）
- 指纹离线核对：新指纹在真实 649 条整表上**恰好命中 2 条**（灭菌器 + 敌方无人机），且**不引用任何本 mod 会改的字段** → 打完补丁 / 改 cfg 之后仍认得出自己

**变异测试守着的关键行为**：
身份指纹失效 / 只写 damage 不写 durable / 取错候选记录（会改到敌方无人机）/ 去掉候选数约束 / 去掉回读校验 / 干脆不写伤害 / 干脆不写毒气 / 毒气写错偏移 / 毒气写成原版值 —— 每一条都确认会被测试抓住。

## 八、包内文件

```
manifest.json                    Arsenal / HD2MM 配置
thumbnail.png                    图标
Addon/9ba626afa44a3aa3.patch_0   -> mods/hd2/sterilizer_gas_damage
（含空的 .stream / .gpu_resources 伴生文件）
```
