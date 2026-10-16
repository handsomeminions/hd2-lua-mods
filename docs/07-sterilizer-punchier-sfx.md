> **[TX-41 灭菌器 → 开火音效替换（实验性）](09-sterilizer-punchier-sfx.md)**　v1.0.0
>
> [← 返回总览](../README.md) · [全部 Mod 一览](../README.md#-全部-mod-一览)
>
> **安装包** [`dist/Sterilizer-PunchierSFX.zip`](../dist/Sterilizer-PunchierSFX.zip)　·　**源码** [`src/sterilizer_sfx.lua`](../src/sterilizer_sfx.lua)　·　**离线测试** `analysis/test_sterilizer_sfx.py`（16/16）
>
> **Manifest GUID** `43181292-a226-45de-9610-46a2de6cadfc`

---

# TX-41 灭菌器 · 开火音效替换（实验性）

> **一句话**：把灭菌器开火时那个"软绵绵"的喷气声，**换成另一个更明显的喷射音效**（默认 = 敌方化学无人机的喷毒声）。
> ⚠️ **先说清楚：把"原声放大"这件事做不到** —— 原因见第二节，不是偷懒。
> ⚠️ **本 mod 是实验性的**：它能不能生效，取决于游戏有没有把那段数据留在内存里。**一次上机就能知道**。

- 安装包：`dist/Sterilizer-PunchierSFX.zip`
- 源码：`src/sterilizer_sfx.lua`（v1.0.0）
- 离线测试：`analysis/test_sterilizer_sfx.py`（**16/16**，含 4 条变异测试）

---

## 一、这个 mod 到底做了什么

灭菌器的开火音效由武器组件里的三个状态音效决定（warmup / firing / cooldown）：

| 状态 | 原版音效事件 |
|---|---|
| warmup（预热） | `3435018303` |
| **firing（喷射）** | **`1773671782`** ← 就是你觉得"软绵绵"的那个 |
| cooldown（冷却） | `1928837757` |

本 mod 在**整个游戏进程内存**里搜索这组音效的"签名"，找到后**只改写 firing 那 4 个字节**，换成你指定的音效事件。

**默认换成** `335829265`（敌方化学无人机的喷毒音效 —— 同样是化学喷射，调性最接近）。

### 怎么保证不误伤别的音效

一个孤独的 `1773671782` **不会**被改。只有当它**周围 ±256 字节内还出现至少一个"同组音效"**时才认账，佐证包括：

```
599097114   firing.audio_event_stop
418315309   firing.callout_event_start
1803865503  SprayWeaponComponent.audio_node
3435018303  warmup.audio_event_start
1928837757  cooldown.audio_event_start
3956223216  SprayWeaponComponent.last_drop_owner_vo_event
0xA3D15A3BBC56DE55  firing.muzzle_effect（64 位，全表只属于灭菌器）
```

这 7 个里只要命中 1 个就认账；**多个独立的 32/64 位哈希共现**，随机撞车概率可以忽略。
一次只写 **4 个字节**，写完立刻回读校验，绝不整块回写。

## 二、⚠️ 为什么"把原声放大"做不到（重要）

链条如下，每一步都有证据：

1. 开火音效的选择（`audio_event_start`）存在 **`SprayWeaponComponentData`** 表里。
2. 而**实机全内存普查**（你上次跑出来的日志 `docs/ingame-2026-10-13/`）显示：内存里常驻的 37 张表**全是 `*Settings` 家族**
   （`StatusEffectSettings`、`DamageSettings`、`ProjectileSettings`、`ExplosionSettings`…），
   **没有任何 `*ComponentData`** —— `SprayWeaponComponentData`（哈希 `0x8E551126`）**一次都没出现**。
3. 更关键的是：**"音量"本身不在任何数据字段里**，它编在 **Wwise SoundBank 音频资源**（`content/audio/...`）内部。

⇒ 所以内存补丁**最多只能"换一个音效事件"，不可能"把原声调大"**。
HD2 社区做音效 mod 的正路是**资源替换**（`hd2-audio-modder` + Wwise 重新编码 `.wem`），那是另一条工具链，本 mod 不产出那种包。

**至于本 mod 为什么还可能有效**：普查只能发现"数据表"，发现不了"运行时实例的裸数据"。
武器在手里时，它的组件实例很可能带着这些 event 值躺在内存里 —— 本 mod 就是在赌这一点。
**赌不中就什么都不会发生**（STATUS 会明说）。

## 三、怎么用

1. 打开 Arsenal / HD2MM → 导入 `Sterilizer-PunchierSFX.zip` → 部署（Deploy）。
2. 进任务，**手上拿着灭菌器**（武器实例要先存在），开火听声音。

### 换哪个音效？改 cfg 现场试，不用重打包

装好后自动生成：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\sterilizer_sfx.cfg
```

```
event=335829265
```

可选的候选事件（改数字 → 保存 → **5 秒内自动重打**，下一枪立刻生效）：

| 事件值 | 是什么 |
|---|---|
| **`335829265`** | **敌方化学无人机的喷毒声（默认）** |
| `1881104745` | FLAM-40 喷火器（最响亮的"喷火"声） |
| `3757506625` | 手枪型喷火器（短促） |
| `2970598254` | Crisper / Ripley 小型喷火器 |
| `1773671782` | 原版灭菌器（**= 不改**，用来 A/B 对照） |

> 建议先记一下原版手感 → 装 mod 听一次 → 把 cfg 填 `1773671782` 再听一次，确认差异确实来自本 mod。

## 四、上机怎么确认（关键）

进任务后看：

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\sterilizer_sfx_STATUS.txt
```

**情况 A —— 找到了（有望生效）：**

```
首行: OK - patch applied (revision 1.0.0): sterilizer firing SFX 1773671782 -> 335829265
hits=N  lone_hits_skipped=M  rewrites=K
first_hit=0x....
patched_copies=1
  copy1: @0x.... corrob=3
```

`corrob=` 越大说明佐证越多（越可信）。这时开火听声音是否变成化学无人机的喷射声。

**情况 B —— 没找到（本路线失败）：**

```
首行: SEARCHING - starting scan (v1.0.0)
result: NO verified sterilizer weapon component found in memory yet.
```

说明游戏**没有**把这段数据留在内存 ⇒ 内存路线走不通。
**请把 `sterilizer_sfx_STATUS.txt` 和 `sterilizer_sfx.log` 发回来** —— 里面的 `hits` / `lone_hits_skipped` 能告诉我到底是没有这个值、还是值出现了但没有佐证（后者说明布局不完整，还有别的办法可试）。

> `rewrites` 一直往上涨 = 游戏每帧/每次开火都把值重置回去 ⇒ 也能听出效果会一闪一闪，请一并告诉我。

## 五、如果内存路线失败，还有这条路（真正的"放大音量"）

用社区工具做**音频资源替换**，这是能真正"把声音调大"的唯一办法：

1. 下载 **`hd2-audio-modder`**（RaidingForPants，GitHub releases）。
2. 前置：装 **Python 3.10+** 和 **Wwise 2023**（audiokinetic.com 免费账号，需要注册）。
3. 首次启动让它指向游戏目录：`...\SteamLibrary\steamapps\common\Helldivers 2\data\game`。
4. 在顶部搜索栏里搜 `sterilizer` / `chem` 找到对应 archive，双击载入。
5. 展开条目，找到灭菌器的**喷射（fire/loop）**音频，`Shift+左键`全选 → 右键 **Dump As .wav** 导出。
6. 用 Audacity / ffmpeg 把导出的 wav 放大（+6 dB 左右就非常明显，别削波）。
7. 回到工具，右键目标音频 → **Import Audio**，选放大后的文件（多个文件时文件名要以音频 ID 开头）。
8. `File → Create a Patch` 生成新的 `.patch_0`，再用 Arsenal 装。

> 这条路的效果**最准**（就是原声变大），代价是需要 Wwise 和本机游戏文件。
> 需要我帮你把这套流程再细化（比如查 archive 名、算 ID）随时说。

## 六、联机提醒

音效是**纯客户端本地**的 —— 你自己听得见就行，**与主机无关**，队友不会听到你的改动。

## 七、验证情况

- `analysis/test_sterilizer_sfx.py`：**功能 12 + 变异 4 = 16/16**，连跑 8 遍稳定
- 端到端：从发布包取回正文，与 `src/sterilizer_sfx.lua` **逐字节一致**，复测 16/16
- 夹具在测试里**按 typelib 权威布局合成**（`SprayWeaponStateInfo` 56B / `SprayWeaponComponent` 224B），值取自离线明文 `entities/SprayWeaponComponentData.json`

**变异测试守着的关键行为**：
去掉佐证判据（孤立值会被误改）/ 写错事件值 / 去掉回读校验 / 写到错误偏移 —— 每一条都确认会被测试抓住。
其中 **T3（孤立出现的 `1773671782` 必须原封不动）** 是最重要的一条。

## 八、包内文件

```
manifest.json                    Arsenal / HD2MM 配置
thumbnail.png                    图标（灭菌器原图 + 声波标识）
Addon/9ba626afa44a3aa3.patch_0   -> mods/hd2/sterilizer_sfx
（含空的 .stream / .gpu_resources 伴生文件）
```
