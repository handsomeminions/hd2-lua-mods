# 胆汁喷涌虫「齐射档位选择」合集包

> **一句话**：一个包 = 两个可勾选项，在 Arsenal / HD2MM 里想要 4 团就勾「4 Mortars」，想要 6 团就勾「6 Mortars」，勾哪个用哪个。

- 安装包：`dist/BileSpewer-Salvo-Choice.zip`
- 源码：`dist` 不含，见 `src/bug_artillery_4rounds.lua`（v1.0.0）与 `src/bug_artillery_6rounds.lua`（v2.2.0）
- 离线校验：`analysis/test_package_bug_salvo.py`

---

## 一、它是什么

胆汁喷涌虫（和胆汁医护虫）的**胆汁迫击炮齐射**，原来一次齐射会吐几团。本包把「一次开火生成几枚」放大，从而改变**一次齐射的总团数**，并且给你**两档**可自由选择：

| 选项名（管理器里显示） | 效果 | 总团数 | 每发枚数 |
|---|---|---|---|
| **4 Mortars Per Salvo** | 2 枚/次 × 2 次齐射 | **4 团** | 2 |
| **6 Mortars Per Salvo** | 3 枚/次 × 2 次齐射 | **6 团** | 3 |

> 说明：原版一次齐射 = **开火 2 次**（2 个方向），每次 1 枚 = 2 团。所以「每发几枚」× 2 就是总数。
> 「方向数」由游戏固定（改不到），能调的只有「每个方向几枚」；同一次开火的多枚是**同向**的。

**除了团数，其它一律原版**：索敌、攻击方式、飞行弧线/速度、绿色胆汁团块外形、音效、落地爆炸——逐字节不变。

## 二、怎么用（Arsenal / HD2MM）

1. 打开管理器 → 把 `BileSpewer-Salvo-Choice.zip` **拖进去 / 导入**。
2. 列表里会出现**一个** mod：「Bile Spewer - Salvo Choice (4 or 6 Mortars)」。
3. 展开它的**选项**，里面有两个开关 —— **勾你要的那个**，取消另一个。
4. 部署（Deploy）。

> 首次导入时，管理器按它自己的设置可能默认把**两个选项都勾上**，也可能只勾第一个。**进去手动确认一下**只留你想要的那一档。

### 两个都勾会怎样？
不会出错。**4 团版会自动让位给 6 团版**（它的 STATUS 首行会写 `SKIPPED - …6rounds is also loaded`），最终生效的是 **6 团**。
但为了干净，**还是建议只勾一个**。

## 三、和「空爆火箭」mod 的联动

和以前一样，本包的任意一档都能和 `BileSpewer-RL77Airburst.zip` 同时用：

| 勾选状态 | 结果 |
|---|---|
| 只勾「4 Mortars」 | 4 枚 **空爆火箭弹**（每枚落地炸成空爆集束） |
| 只勾「6 Mortars」 | 6 枚 **空爆火箭弹** |
| 两个 salvo 选项都勾 | 6 枚空爆火箭弹（4 团版已让位） |

## 四、⚠️ 不要和独立包重复安装

本合集里的两个 addon 与单独安装的 **`BileSpewer-4Mortars.zip`** / **`BileSpewer-6Mortars.zip`** 是**同一份资源**。
如果你已经装了那两个独立包，**请二选一**：
- 想要「一个包里切换档位」→ 用本合集包，把两个独立包**禁用/删除**；
- 想要「两个独立条目各自管理」→ 保留独立包，不用本合集。

同时启用「合集包」+「同资源的独立包」会让管理器部署两个定义同一资源的补丁，**可能冲突**。

## 五、cfg（一般不用动）

两个 addon 各自会生成一个运行时可调的配置文件（**默认值就是你要的值**）：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\bug_artillery_4rounds.cfg   -> 2
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\bug_artillery_6rounds.cfg   -> 3
```

改完保存，**5 秒内自动生效，不用重开游戏、不用重打包**。
- 4 团版把 `2` 改成 `3` 就变成 6 团（效果等同选另一档）。
- 6 团版把 `3` 改成 `2` 就变成 4 团。
- ⚠️ 如果你之前调过 cfg 想回到默认，**改成上面对应的数字或直接删掉文件**即可。

## 六、上机怎么确认

进任务后看（两档的 STATUS 文件名不同）：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\bug_artillery_6rounds_STATUS.txt
  首行应为 OK - patch applied (revision 2.2.0): ... spawns 3 bile mortars per shot ... expected salvo = 6 (2 directions)
  projectiles_per_shot=1->3

%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\bug_artillery_4rounds_STATUS.txt
  首行应为 OK - patch applied (revision 1.0.0): ... spawns 2 bile mortars per shot ... expected salvo = 4 (2 directions)
  （若你两个都勾了，这里会是 SKIPPED - …6rounds is also loaded，属正常）
```

然后数一次齐射的总团数：**4 或 6，与你勾的那档一致** 即成功。

> 胆汁喷涌虫的**迫击炮形态只在 Extreme(7)+ 难度**出现；低难度它只用胆汁喷吐和近战。

## 七、联机提醒

**客户端改动、主机权威** —— 客机看不到、伤害按房主算。要真正生效，**房主也要装**。

## 八、验证情况

- 包结构 + manifest（V1 规范：`Options[].Include` / `Image` / `IconPath`）：通过
- 两个选项的发布正文与 `src/*.lua` **逐字节一致**：通过
- **双选共存**（两种加载顺序各跑 1500 帧 + 3 个复查周期）：4 团版让位、6 团版生效、无互抢、钩子链完好：通过
- 回归：4 团 28/28、6 团 27/27、空爆 28/28、迫击炮 23/23、120mm 25/25、380mm 7/7

## 九、包内文件

```
manifest.json                     Arsenal / HD2MM 配置（含两个 Options）
thumbnail.png                     合集图标
FourRounds.png / SixRounds.png    两个选项各自的小图标
FourRounds/9ba626afa44a3aa3.patch_0     -> mods/hd2/bug_artillery_4rounds
SixRounds/9ba626afa44a3aa3.patch_0      -> mods/hd2/bug_artillery_6rounds
（各含空的 .stream / .gpu_resources 伴生文件）
```
