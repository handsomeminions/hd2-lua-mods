# 轨道380MM高爆弹火力网 → 地狱火炸弹

把 **轨道380MM高爆弹火力网（Orbital 380MM HE Barrage）** 的每一次打击，
爆炸都换成 **地狱火炸弹（HELLBOMB）** 的效果。

- 核弹级爆炸：半径 **17 / 25 / 45**（对照原版 380mm 爆炸约 3.3 / 10 / 11），
  弹坑为 **Nuke（核弹坑）**，专属火焰粒子与音效，同级伤害。
- 纯**客户端内存补丁**，不改动任何游戏文件。禁用并 Purge 后完全还原。

---

## 前置要求

| 项目 | 要求 |
| --- | --- |
| Bingus Shared Loader | **v15 及以上**（`API 1`）。需启用 addon 支持 |
| 安装器 | Arsenal 或 HD2MM |
| 游戏 | Steam 版《绝地潜兵2》 |

---

## 安装

1. 确保 **Bingus Shared Loader** 已安装并启用（通常放列表最底部）。
2. 用 Arsenal / HD2MM 导入 `Orbital380mm-Hellbomb.zip`，启用，与 loader 一同 Deploy。
3. 进游戏打一发 **轨道380MM高爆弹火力网**，每次落弹应变成地狱火级别的爆炸。

---

## ⚠️ 重要：影响范围

游戏里 **"380mm HE CANNON ROUND"（380mm 炮弹）被 380mm 火力网与"轨道行走火力网"共用**，
两者用的是同一种炮弹定义。本 mod 改的是这枚炮弹的爆炸，**因此行走火力网也会一起变成地狱火**。
（未发布/未使用的其它 380mm 实体若也引用同款炮弹，同样会被带上。）

> 说明：轰炸表 `BombardmentComponentData` 在多数情况下**不常驻内存**，无法只针对"380mm 火力网"那一条记录做精准改写，
> 所以只能从"常驻的射弹表"入手 —— 代价就是共享同款炮弹的战备会一起变。

---

## 状态与日志

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\
    orbital_380mm_hellbomb_STATUS.txt   # 首行即结论
    orbital_380mm_hellbomb.log          # 详细日志(每行即时落盘)
```

STATUS 首行含义：

- `OK - patch applied ...` —— 补丁已生效
- `SEARCHING - ...` —— 尚未找到目标表；日志里 `LDLD types seen:` 会列出实际扫到的数据表类型
- `FAILED - ...` —— 环境不满足（loader 过旧 / FFI 不可用 / 浮点编解码自检失败）

关注字段：`hellbomb_explosion_type=`（运行时解析出的地狱火爆炸枚举值，**不写死**）、`patched_records=`（应=2）。

---

## 工作原理（简述）

1. 扫描内存，定位常驻的 `ExplosionSettings`（爆炸表）与 `ProjectileSettings`（射弹表）。
2. **运行时解析地狱火爆炸**的 `ExplosionType`：在爆炸表里用**音频事件哈希 + 粒子哈希 + 核弹级半径(17/25/45)**
   三重指纹定位记录并读其 `+0 类型`（当前构建 = **242**）。枚举下标随版本漂移，所以**绝不写死**。
   （爆炸表记录的 stride=152、记录从 payload+16 起；表尾含变长数组，不能按 `size/count` 推 stride。）
3. 把"380mm HE CANNON ROUND"（`type 80 / 266`，即 380mm 火力网所用）射弹记录的
   `explosion_type_on_impact`（+144）改写为地狱火爆炸。

所有写入**先回读验证**；幂等，被冲掉后自动重打。只改 4 字节 ×2。

---

## 卸载 / 还原

在 Arsenal / HD2MM 中**禁用并 Purge**本 mod，再重新 Deploy —— 内存补丁随进程重启消失，游戏回到原版。
本 mod 不修改磁盘上的任何游戏文件。

---

## 联机说明

与"120mm→500kg"那个 mod 相同：本 mod 只改**你本机内存**，而 HD2 是**主机权威**。
- 你是**房主/单人** → 地狱火真正生效（敌人按地狱火结算）。
- 你是**客机** → 实际结算按房主的原版 380mm，其他玩家看不到你的改动。
- 想真正生效请**自己开房当房主**。⚠️ nProtect GameGuard 在场，此类内存补丁属灰色地带，风险自担。

---

## 已验证

离线仿真（LuaJIT 2.1 + 假 FFI/假内存）：**功能 2 + 变异 4 = 6/6 通过**（含"关闭解析""写错指纹半径"
"写错名称哈希""只打一种射弹"四个变异都会被检出），发布正文端到端复测同样 6/6。

---

## 更新记录

- **v1.0.1** —— 修复"实机没生效"。根因：爆炸表块尾带**变长数组**（ShakeAssets），
  导致 `(size-16) % count ≠ 0`，被旧代码的"几何合法性"判据拒绝 → 永远解析不出地狱火。
  现已改为按**真实记录布局**（stride=152、记录自 payload+16 起）扫描，并用
  **音频事件哈希 + 粒子哈希**做指纹（跨构建稳定），半径(17/25/45)作交叉校验。
  另修：两个 addon 曾都用通用全局名 `end_pass/flush_log`，**互相覆盖导致日志丢失**；
  现已改为各自唯一命名（`_HD2_380MM_FLUSH` / `_HD2_120MM_FLUSH`）。
  STATUS 新增 `ldld_types=`（已扫到的数据表类型直方图），便于远端排查。
- **v1.0.0** —— 首版：改 380mm 射弹的 `explosion_type_on_impact`。

---

## 目录结构（本 mod 相关）

```
dist/
  Orbital380mm-Hellbomb.zip   # 安装包(导入这个)
  thumbnail_380.png           # 图标
  README-380mm.md             # 本文件
src/
  orbital_380mm_hellbomb.lua  # addon 源码
```
