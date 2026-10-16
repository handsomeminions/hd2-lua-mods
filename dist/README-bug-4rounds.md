# 胆汁喷涌虫 · 一次齐射 4 团（每发 2 枚版）

> 安装包：`dist/BileSpewer-4Mortars.zip`
> 源码：`src/bug_artillery_4rounds.lua`（**v1.0.0**）
> 离线测试：`analysis/test_bug_4rounds.py`（功能 19 + 变异 9 = **28/28**）
> 共存测试：`analysis/test_bug_combo4.py`

---

## 一句话

把胆汁迫击炮"**每次开火生成几枚**"从 1 改成 **2**：一次齐射 = **2 枚 × 2 次 = 4 团**（2 个方向，每方向 2 枚）。

> 这是 `BileSpewer-6Mortars.zip`（每发 3 枚 = 6 团）的**低配姊妹版**，逻辑一字不差，只是默认值不同。

---

## ⚠️ 和"6 团版"是**二选一**的关系

| 包 | 每次开火 | 一次齐射 | 资源名 | GUID |
|---|---|---|---|---|
| `BileSpewer-6Mortars.zip` | 3 枚 | **6 团** | `mods/hd2/bug_artillery_6rounds` | `fe9ac944-…` |
| **本包** `BileSpewer-4Mortars.zip` | 2 枚 | **4 团** | `mods/hd2/bug_artillery_4rounds` | `70126b6b-…` |

两者在管理器里是**两个独立条目**（可以都装着），但**它们改的是同一条射弹记录里的同一个字段**，
所以**同时启用会每 5 秒互抢**。为此本版内置了**自动让位**：

* 只要检测到"6 团版"已加载，**本包立刻停手**（不扫描、不写入），并在
  `bug_artillery_4rounds_STATUS.txt` 首行写 `SKIPPED - …`；
* 管理器里**禁用其中一个**即恢复正常（禁用 = 那个 addon 不加载）。

⇒ 推荐用法：**用管理器的开关切换**，想要 6 团就启用 6 团版、想要 4 团就启用本版，别同时开。

---

## 改的是什么

| 表 | 记录 | 字段 | 原版 → 改后 |
|---|---|---|---|
| `ProjectileSettings` | 胆汁迫击炮射弹 `ProjectileType_Bug_Artillery`（本构建 type=344） | **`+28 num_projectiles`** | **1 → 2** |

* `num_projectiles` = "一次开火生成几枚射弹"。**霰弹枪就是靠它一次打出 9~20 颗弹丸**
  （它们的弹匣是 Uniform，不是 Pattern），实机已验证本套方案生效。
* 记录按**稳定指纹**定位（无名 + 口径50 + 初速30 + 质量1000 + 推进粒子/拖尾粒子哈希），
  与空爆 mod 用的是同一套、已在实机跑通的定位法。
* **只写 4 个字节**（`+28..+31`），其余一个字节都不动（弹道 / 外形 / 音效 / 落地爆炸全部保持原版）。
* 稳态每 5 秒按地址直读复查（先验身份指纹，再只补 `+28`），被冲掉就重打。

---

## ★ 数值可现场调（不用重打包）

`bug_artillery_4rounds.cfg`（在日志目录里）**只有一行、一个数字 = 每次开火几枚**：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\bug_artillery_4rounds.cfg
```

* 改完**保存**即可：mod 会在 **~5 秒内**自动重打，**下一轮齐射立刻见效**（不用重启游戏）；
* **总发数 = 每次开火枚数 × 开火次数(2)**。

| 你看到的齐射总数 | 说明 | 把 cfg 改成 |
|---|---|---|
| **4 团** | 成功 | 不用改（默认就是 `2`） |
| 2 团 | cfg 成了 1 | `2` |
| 6 团 | cfg 成了 3 | `2` |
| 8 团 | cfg 成了 4 | `2` |

> 注意：本版的 cfg 文件与 6 团版的 **`bug_artillery_6rounds.cfg` 是两个独立文件**，互不影响。

---

## 与"空爆火箭弹"mod 的联动

| 4 团版 | 空爆 | 结果 |
|:---:|:---:|---|
| ✅ | ⬜ | **4 枚原版胆汁迫击炮**（2 个方向 × 各 2 枚） |
| ⬜ | ✅ | 2 枚空爆火箭弹（原版齐射次数） |
| ✅ | ✅ | **4 枚空爆火箭弹** |

> 两个都装时，两边复查都只回写自己负责的字段（空爆 v1.5.0 / 本 mod v1.0.0），不会互相覆盖。
> 离线专项测试：`analysis/test_bug_combo4.py`。

---

## 安装

1. 关闭游戏。
2. 用 **Arsenal / HD2 Mod Manager** 导入 `BileSpewer-4Mortars.zip`，启用后 **Deploy**
   （**别同时启用 6 团版**；要联动空爆就再启用 `BileSpewer-RL77Airburst.zip`）。
3. 保留 **Bingus Shared Loader v15+（API 1）**——唯一前置。

> ⚠️ **不要手动把 `Addon/` 拷进游戏 `data/`** —— 会互相覆盖。**永远用管理器导入。**

---

## 怎么确认生效 / 怎么排查

进任务后（**自己开房当房主**，伤害才真正结算）看：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\bug_artillery_4rounds_STATUS.txt
```

第一行应为：

```
OK - patch applied (revision 1.0.0): Bile Spewer now spawns 2 bile mortars per shot (vanilla 1); expected salvo = 4 (2 directions)
```

* `projectiles_per_shot=1->2` / `patched_records=1` = 打上了。
* 若是 `SKIPPED - …` = **6 团版也在跑**，本包已让位（去管理器里只留一个）。
* 若还是 `SEARCHING`：多半是还没进任务。把整个 `Logs` 目录发我即可。
* 详细过程在同目录 `bug_artillery_4rounds.log`。

**注意：**

* 客户端内存修改，**主机权威**：客机看不到、伤害按房主算。**房主也要装**。
* 胆汁喷涌虫的迫击炮形态主要出现在**高难度**。
* 禁用 + **Purge** 即完全还原，不改任何磁盘文件。

---

## 技术细节（给维护者）

* 源码 = `src/bug_artillery_6rounds.lua` 的姊妹版（同逻辑，仅默认值/命名/让位逻辑不同）。
* 定位：扫 LDLD（`LDLD`+ver=1+类型哈希 `0xBD4042C2`），表描述符在 `+24`（文件形态是相对偏移、
  内存形态是绝对指针，两种都试），记录 stride 272、本构建 350 条、目标 `idx=29`。
* **互斥**：`RIVAL_SINGLETON = "_HD2_BUG_ARTILLERY_6ROUNDS"`，在 `init` 与稳态 `recheck` 两处检测；
  检测到即 `phase = "dead"`。单测 T19 守着这条。
* 指纹刻意**不包含** `+144/+152/+208/+212/+240`（空爆 mod 会改的字段）。
* 只新增自己唯一命名的全局 `_HD2_BUG_ARTILLERY_4ROUNDS` + `_HD2_BUG4R_FLUSH`
  （`RIVAL_SINGLETON` / `rival_present` 都是 local），`update` 带安全退钩。
