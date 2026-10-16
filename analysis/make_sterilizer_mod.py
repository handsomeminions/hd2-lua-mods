# -*- coding: utf-8 -*-
"""从 bug_artillery_6rounds.lua 的成熟框架生成 sterilizer_gas_damage.lua。

★ 已过时(v1.0.0 时代的一次性生成器)。**v2.0.0 起 src/sterilizer_gas_damage.lua 是手改的**
  (新增了毒气施加量 +48/+56、指纹收紧、双参数 cfg、f32_bits 等)。
  再跑本脚本会用旧的 6rounds 框架**覆盖**掉 v2.0.0 的全部改动。
  确需重新生成, 请显式设置 HD2_ALLOW_STERILIZER_REGEN=1。

只替换: 头部注释 / 名字 / CONFIG / 指纹 / 补丁写入 / STATUS 文案。
扫描器、日志、FFI、tick、复查框架**逐字保留**。
"""
import io, os, sys

if os.environ.get("HD2_ALLOW_STERILIZER_REGEN") != "1":
    sys.exit("REFUSING: this generator would overwrite the hand-maintained "
             "src/sterilizer_gas_damage.lua (now v2.0.0). "
             "Set HD2_ALLOW_STERILIZER_REGEN=1 if you really mean it.")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "src", "bug_artillery_6rounds.lua")
DST = os.path.join(ROOT, "src", "sterilizer_gas_damage.lua")

s = io.open(SRC, encoding="utf-8").read()
miss = []


def rep(old, new, cnt=1):
    global s
    if s.count(old) < cnt:
        miss.append(old[:80])
        return
    s = s.replace(old, new, cnt)


# ---------------------------------------------------------------------------
# 1. 头部注释
# ---------------------------------------------------------------------------
HEAD = '''-- HD2-Addon: mods/hd2/sterilizer_gas_damage
-- ============================================================================
-- TX-41 灭菌器(Sterilizer) 伤害 -> G-4 毒气榴弹(Explosion_Gas_Grenade) 级别
-- TX-41 Sterilizer: raise the damage to G-4 Gas Grenade level
--
-- 用户需求: "TX-41 灭菌器 的喷毒射程范围更改为和 B/FLAM-80 焚燃者 喷火范围一样,
--            同时伤害提升为 G-4 毒气榴弹一样"
--   => 本 addon 做**后半**: 伤害对齐 G-4 毒气榴弹。
--   => 前半(射程)**数据层无字段可改** —— 理由见下, 已逐项离线验证。
--
-- ★ 为什么"射程"改不了(离线穷尽验证过的):
--   喷射类武器(TX-41 灭菌器 / B/FLAM-80 焚燃者 / FLAM-40 / Crisper)的
--     SprayWeaponComponent.projectile_type = ProjectileType_None
--   => 它们**不发射射弹**; 伤害靠"粒子碰撞事件"触发 component 里的 damage_info_type。
--   => "喷多远"完全由枪口粒子效果(muzzle_effect, 一个 VFX 资源哈希)决定:
--        SprayWeaponComponent(224 字节, 16 个字段) 和 WeaponDataComponent(56 个字段) 里
--        **没有任何 range / length / distance 字段**;
--        唯一带 length 的 SprayCapsuleOverlap(8 字节) 在 entities blob 里
--        **0 个实例**(没有任何实体使用它)。
--   => 而且这些 *ComponentData 表**在内存里不加载**(实机全内存 LDLD 普查 0 命中)。
--   => 结论: 射程属于美术(VFX)资产, Lua 内存补丁改不到。
--
-- 本 addon 改什么(纯内存补丁; 禁用 mod + Purge 即完全还原, 不改任何磁盘文件):
--   表 DamageSettings(LDLD 类型哈希 0xE0A72CF0; 属于 *_Settings 家族, 实机普查确认**常驻内存**)
--   记录 DamageInfoType_Spray_Chem_Gun —— 由实体 blob 反查确认**只被 TX-41 灭菌器使用**
--     (敌人"化学无人机"用的 Drone_Chem_Gun 是一条**数值完全相同**的邻居记录;
--      本 addon 用"两条里 Type 较小者 = 灭菌器"来区分, 见 patch_into_table)
--
--   DamageInfo 记录(76 字节, 游戏 typelib 权威布局):
--     +0   u32 DamageInfoType            (枚举, 会随构建漂移 -> 只作提示, 不当判据)
--     +4   i32 damage          [1,1] -> [3,3]   <- 【改写项】
--     +8   i32 durable_damage  [1,1] -> [3,3]   <- 【改写项】
--     +12  u32[4] armor_penetration_per_angle = 5,5,5,0
--     +28  u32 demolition_strength = 5      +32 u32 force_strength = 10
--     +36  u32 force_impulse = 5            +40 u32 element_type
--     +44  DamageStatusEffectInfo[4] (type u32 + value f32)
--
--   目标值依据: G-4 毒气榴弹的爆炸伤害 DamageInfoType_Explosion_Gas_Grenade
--     = damage 3 / durable_damage 3 (离线产物里 8 项字段逐项比对确认)
--   => 所以把灭菌器的 1 -> 3。**只写 +4..+11 这 8 个字节**, 其余逐字节 keep-guard
--      (护甲穿透/拆迁/推力/毒气状态值 全部保持原版, 不改)。
--
-- ★ 数值可在游戏运行时调, 不用重新打包:
--   日志目录里的 `sterilizer_gas_damage.cfg` 就一个整数(1..200), 例如改成 5 就是每次命中 5。
--   改完保存, ~5 秒内自动重打, 下一枪立刻生效。
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存.
-- ============================================================================

'''

i = s.index("local MOD_NAME")
s = HEAD + s[i:]

# ---------------------------------------------------------------------------
# 2. 名字 / 版本 / 单例
# ---------------------------------------------------------------------------
rep('local MOD_NAME = "mods/hd2/bug_artillery_6rounds"',
    'local MOD_NAME = "mods/hd2/sterilizer_gas_damage"')
rep('local REVISION = "2.2.0"', 'local REVISION = "1.0.0"')
rep('local SINGLETON = "_HD2_BUG_ARTILLERY_6ROUNDS"',
    'local SINGLETON = "_HD2_STERILIZER_GAS_DAMAGE"')

# ---------------------------------------------------------------------------
# 3. CONFIG
# ---------------------------------------------------------------------------
a = s.index("local CONFIG = {")
b = s.index("\n}\n", a) + len("\n}\n")
NEW_CFG = '''local CONFIG = {
    TYPE_DAMAGE_SETTINGS = 0xE0A72CF0,  -- djb2("DamageSettings")

    -- DamageInfo 字段偏移(游戏 typelib 权威, 记录 76 字节)
    OFF_TYPE    = 0,     -- u32 DamageInfoType (枚举, 只作提示)
    OFF_DAMAGE  = 4,     -- i32 damage          <- 改写项
    OFF_DURABLE = 8,     -- i32 durable_damage  <- 改写项
    OFF_AP      = 12,    -- u32[4] armor_penetration_per_angle
    OFF_DEMO    = 28,    -- u32 demolition_strength
    OFF_FS      = 32,    -- u32 force_strength
    OFF_FI      = 36,    -- u32 force_impulse
    OFF_ELEM    = 40,    -- u32 element_type
    OFF_SE      = 44,    -- DamageStatusEffectInfo[4] { u32 type, f32 value }

    -- 身份指纹: 全部是"数值/物理量", 不依赖会漂移的枚举下标。
    --   ★ 刻意**不含** damage / durable —— 那是本 addon 要改的字段(否则打完认不出自己)。
    --   预期在整个 DamageSettings 表里命中 **2 条**: 灭菌器(Spray_Chem_Gun) 与其后紧邻的
    --   敌方化学无人机(Drone_Chem_Gun), 两条数值完全相同, 只有 DamageInfoType 不同。
    SIG_AP       = 5,      -- armor_penetration_per_angle = 5,5,5,0
    SIG_DEMO     = 5,
    SIG_FS       = 10,
    SIG_FI       = 5,
    SIG_SE_VALUE = 0.5,    -- 两条毒气状态效果的 value 都是 0.5
    SIG_DMG_LO   = 1,      -- 合法的 damage 下限(原版)
    SIG_DMG_HI   = 200,    -- 合法的 damage 上限(打过之后)

    -- 目标伤害 = G-4 毒气榴弹的爆炸伤害(默认值; 运行时会被 cfg 文件覆盖)
    DMG_DEFAULT = 3,
    DMG_MIN = 1,
    DMG_MAX = 200,

    -- 扫描参数(温和: 小步长 + 硬时间预算 + 空手退避; 打完即休眠)
    START_DELAY    = 120,
    CHUNK          = 262144,            -- 256 KB
    OVERLAP        = 64,
    BUDGET_SEARCH  = 0.002,             -- 每帧最多 2ms CPU
    SCAN_EVERY     = 2,                 -- 搜索期每 2 帧推进一步
    STEADY_CADENCE = 60,                -- 稳态每 60 帧(约1秒)唤醒一次
    RECHECK_EVERY  = 300,               -- 每 5 秒按地址直读复查 + 重读 cfg
    SELF_SKIP      = 65536,
    REGION_MIN     = 4096,

    CFG_NAME    = "sterilizer_gas_damage.cfg",
    LOG_DIR_ENV = "LOCALAPPDATA",
    LOG_SUBDIR  = "/CowboyBingus/Helldivers2/Logs/",
}
'''
s = s[:a] + NEW_CFG + s[b:]

# ---------------------------------------------------------------------------
# 4. state 字段名
# ---------------------------------------------------------------------------
rep("""    target_type = nil,
    proj_old = nil,          -- 原版 num_projectiles
    proj_new = nil,          -- 当前生效值
    copies = {},             -- {rec=, want=, idx=, blk=}""",
    """    target_type = nil,
    last_reject = nil,       -- 最近一次拒绝写入的原因(给 STATUS 看)
    dmg_old = nil,           -- 原版 damage
    dmg_new = nil,           -- 当前生效值
    copies = {},             -- {rec=, idx=, blk=}""")

rep("""-- 要写入的"每次开火枚数"(来自 cfg 文件; 没有就取默认)
local want_proj = CONFIG.PROJ_PER_SHOT_DEFAULT""",
    """-- 要写入的"伤害值"(来自 cfg 文件; 没有就取默认)
local want_dmg = CONFIG.DMG_DEFAULT""")

# ---------------------------------------------------------------------------
# 5. cfg 读取
# ---------------------------------------------------------------------------
rep("""    local n = tonumber(string.match(txt, "(%d+)"))
    if n and n >= CONFIG.PROJ_MIN and n <= CONFIG.PROJ_MAX then return n end
    return nil
end""",
    """    local n = tonumber(string.match(txt, "(%d+)"))
    if n and n >= CONFIG.DMG_MIN and n <= CONFIG.DMG_MAX then return n end
    return nil
end""")

rep("""        w:write(tostring(CONFIG.PROJ_PER_SHOT_DEFAULT) .. "\\n")""",
    """        w:write(tostring(CONFIG.DMG_DEFAULT) .. "\\n")""")

# ---------------------------------------------------------------------------
# 6. STATUS 文本
# ---------------------------------------------------------------------------
rep('''    parts[#parts + 1] = string.format("target(bug artillery projectile) type=%s", tostring(state.target_type))
    parts[#parts + 1] = string.format("projectiles_per_shot=%s->%s (vanilla 1 per shot)",
        tostring(state.proj_old), tostring(want_proj))''',
    '''    parts[#parts + 1] = string.format("target(sterilizer damage record) damage_info_type=%s", tostring(state.target_type))
    parts[#parts + 1] = string.format("damage=%s->%s (vanilla 1; G-4 Gas Grenade = 3)",
        tostring(state.dmg_old), tostring(want_dmg))''')

rep('''    parts[#parts + 1] = "effect: Bile Spewer fires N bile mortars per shot; vanilla lobs ONE per shot."
    parts[#parts + 1] = "        vanilla salvo = 2 shots (2 directions); 3/shot => 6 mortars in 2 directions."
    parts[#parts + 1] = "        Targeting / flight / arc / shape / sound / impact explosion are UNCHANGED."
    parts[#parts + 1] = string.format("tune: edit %s (one number, 1-20) and save;", CONFIG.CFG_NAME)
    parts[#parts + 1] = "      it re-applies within ~5s, no repack/restart. expected salvo = value x 2."
    parts[#parts + 1] = "      not 6?  4 -> put 3 ;  2 -> put 3 ;  9 -> put 2."
    parts[#parts + 1] = "note: damage is host-authoritative; host needs this mod for real damage to count"''',
    '''    parts[#parts + 1] = "effect: TX-41 Sterilizer direct damage raised to G-4 Gas Grenade level"
    parts[#parts + 1] = "        (only the damage value changes; AP / demolition / knockback /"
    parts[#parts + 1] = "         gas status values stay vanilla, byte-for-byte)"
    parts[#parts + 1] = "range: spray distance is driven by the muzzle VFX particle and CANNOT be"
    parts[#parts + 1] = "       changed from memory (no range field exists in the data tables)."
    parts[#parts + 1] = string.format("tune: edit %s (one number, 1-200) and save;", CONFIG.CFG_NAME)
    parts[#parts + 1] = "      it re-applies within ~5s, no repack/restart. 3 = G-4 level."
    parts[#parts + 1] = "note: damage is host-authoritative; host needs this mod for real damage to count"''')

# ---------------------------------------------------------------------------
# 7. 文件名 + 全局 flush 名
# ---------------------------------------------------------------------------
rep('''    parts[#parts + 1] = string.format("patched_records=%d", #state.copies)''',
    '''    if state.last_reject and state.phase ~= "patched" then
        parts[#parts + 1] = "last_reject=" .. state.last_reject
    end
    parts[#parts + 1] = string.format("patched_records=%d", #state.copies)''')

rep('bug_artillery_6rounds_STATUS.txt', 'sterilizer_gas_damage_STATUS.txt')
rep('bug_artillery_6rounds.log', 'sterilizer_gas_damage.log')
rep('_HD2_BUG6R_FLUSH', '_HD2_STERILIZER_FLUSH')

# ---------------------------------------------------------------------------
# 8. 指纹函数
# ---------------------------------------------------------------------------
a = s.index("local tgt_trail, tgt_thr")
b = s.index("-- ---------------------------------------------------------------------------\n-- 打补丁")
NEW_FP = '''-- 灭菌器伤害记录的身份指纹(全部是数值/物理量; 不含 damage, 支持幂等)
local function is_target_record(r)
    if u32_at(r, CONFIG.OFF_AP)      ~= CONFIG.SIG_AP then return false end
    if u32_at(r, CONFIG.OFF_AP + 4)  ~= CONFIG.SIG_AP then return false end
    if u32_at(r, CONFIG.OFF_AP + 8)  ~= CONFIG.SIG_AP then return false end
    if u32_at(r, CONFIG.OFF_AP + 12) ~= 0 then return false end
    if u32_at(r, CONFIG.OFF_DEMO) ~= CONFIG.SIG_DEMO then return false end
    if u32_at(r, CONFIG.OFF_FS)   ~= CONFIG.SIG_FS then return false end
    if u32_at(r, CONFIG.OFF_FI)   ~= CONFIG.SIG_FI then return false end
    -- 两条毒气状态效果的值都是 0.5(不同下标, 但值必须都等于 0.5)
    if not near(f32_at(r, CONFIG.OFF_SE + 4),  CONFIG.SIG_SE_VALUE, 1e-6) then return false end
    if not near(f32_at(r, CONFIG.OFF_SE + 12), CONFIG.SIG_SE_VALUE, 1e-6) then return false end
    -- 后两条状态效果必须为空(类型 0)
    if u32_at(r, CONFIG.OFF_SE + 16) ~= 0 then return false end
    if u32_at(r, CONFIG.OFF_SE + 24) ~= 0 then return false end
    -- damage 必须落在合法区间(原版 1 .. 打过之后的 200)。刻意不要求 == 1, 以支持幂等。
    local d = u32_at(r, CONFIG.OFF_DAMAGE)
    if d < CONFIG.SIG_DMG_LO or d > CONFIG.SIG_DMG_HI then return false end
    return true
end

'''
s = s[:a] + NEW_FP + s[b:]

# ---------------------------------------------------------------------------
# 9. 打补丁
# ---------------------------------------------------------------------------
a = s.index("local function register_copy(rec_addr, idx)")
b = s.index("-- ---------------------------------------------------------------------------\n-- 稳态: 按地址直读复查")
NEW_PATCH = '''local function register_copy(rec_addr, idx)
    for i = 1, #state.copies do
        if state.copies[i].rec == rec_addr then return false end
    end
    state.copies[#state.copies + 1] = { rec = rec_addr, idx = idx }
    return true
end

-- 把一条记录的 damage(+4) 和 durable_damage(+8) 同时写成 want_dmg —— **只写这 8 个字节**.
local function write_damage(rec_addr, n)
    local bytes = u32_le(n) .. u32_le(n)
    if not write_mem(rec_addr + CONFIG.OFF_DAMAGE, bytes) then
        log_err(string.format("write failed @0x%X (+%d)", rec_addr, CONFIG.OFF_DAMAGE))
        return false
    end
    local back = read_mem(rec_addr + CONFIG.OFF_DAMAGE, 8)
    if back == nil or u32_at(back, 0) ~= n or u32_at(back, 4) ~= n then
        log_err(string.format("read-back mismatch @0x%X", rec_addr))
        return false
    end
    return true
end

local function patch_into_table(blk, t, data)
    -- 收集所有"身份指纹命中"的记录(期望 2 条: 灭菌器 + 敌方化学无人机)
    local hits = {}
    for k = 0, t.count - 1 do
        local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
        if is_target_record(r) then
            hits[#hits + 1] = { idx = k, ty = u32_at(r, CONFIG.OFF_TYPE) }
        end
    end
    -- ★ 必须**恰好 2 条**且 DamageInfoType 相邻。
    --   Spray_Chem_Gun(玩家灭菌器) 与 Drone_Chem_Gun(敌方化学无人机) 数值完全相同,
    --   只能靠"枚举声明顺序"(Type 较小者 = 灭菌器)区分。
    --   少于 2 条 => 无法确认哪条是灭菌器 => **宁可不写**, 绝不冒险改到敌方那条(那会反过来强化敌人)。
    if #hits ~= 2 then
        state.last_reject = string.format("candidates=%d (need exactly 2)", #hits)
        log_err(string.format("%d candidate record(s) match the fingerprint; expected exactly 2 (sterilizer + enemy chem drone); refusing", #hits))
        return false
    end
    local h1, h2 = hits[1], hits[2]
    local ty_diff = h1.ty - h2.ty
    if ty_diff < 0 then ty_diff = -ty_diff end
    if ty_diff ~= 1 then
        state.last_reject = string.format("types %d/%d not adjacent", h1.ty, h2.ty)
        log_err(string.format("two candidates but DamageInfoType %d and %d are not adjacent; refusing", h1.ty, h2.ty))
        return false
    end
    -- 枚举声明顺序稳定: Spray_Chem_Gun 先声明(社区枚举 12<13; 本构建 28<29) => 取小者
    local chosen = (h2.ty < h1.ty) and h2 or h1

    local tgt_addr = t.recbase + chosen.idx * t.stride
    local cur = read_mem(tgt_addr, t.stride)
    if not cur then
        log_err(string.format("cannot read target record @0x%X", tgt_addr))
        return false
    end
    if not is_target_record(cur) then
        log_err(string.format("record @0x%X no longer matches the sterilizer fingerprint; refusing", tgt_addr))
        return false
    end
    local cur_d = u32_at(cur, CONFIG.OFF_DAMAGE)
    if cur_d < CONFIG.SIG_DMG_LO or cur_d > CONFIG.SIG_DMG_HI then
        log_err(string.format("damage=%d out of range @0x%X; refusing", cur_d, tgt_addr))
        return false
    end

    local already = (cur_d == want_dmg)
    if not already then
        if not write_damage(tgt_addr, want_dmg) then return false end
    end

    register_copy(tgt_addr, chosen.idx)
    state.last_reject = nil
    if state.target_type == nil then
        state.target_type = u32_at(cur, CONFIG.OFF_TYPE)
        state.dmg_old = cur_d
        state.dmg_new = want_dmg
    end
    log(string.format("%s sterilizer damage @0x%X (idx %d, damage_info_type %s, %d candidate(s)): damage %d -> %d",
        already and "ALREADY" or "PATCHED", tgt_addr, chosen.idx, tostring(u32_at(cur, CONFIG.OFF_TYPE)),
        #hits, cur_d, want_dmg))
    state.done_blocks[blk.addr] = true
    return true
end

function process_dmg_block(h)
    if state.done_blocks[h.addr] then return end
    local t = read_table(h)
    if not t then return end
    local data = read_mem(t.recbase, t.count * t.stride)
    if not data then return end
    local ok = patch_into_table(h, t, data)
    if ok and state.phase ~= "patched" then
        state.phase = "patched"
        state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
        set_status(string.format(
            "OK - patch applied (revision %s): TX-41 Sterilizer damage %s -> %s (G-4 Gas Grenade level)",
            REVISION, tostring(state.dmg_old), tostring(want_dmg)))
    end
end

'''
s = s[:a] + NEW_PATCH + s[b:]

# 扫描器里的引用
rep("                if th == CONFIG.TYPE_PROJECTILE then\n"
    "                        local ok, err = pcall(process_proj_block, { addr = addr, type = th, size = size })\n"
    "                        if not ok then log_err(\"proj block error: \" .. tostring(err)) end",
    "                if th == CONFIG.TYPE_DAMAGE_SETTINGS then\n"
    "                        local ok, err = pcall(process_dmg_block, { addr = addr, type = th, size = size })\n"
    "                        if not ok then log_err(\"damage block error: \" .. tostring(err)) end")

rep("local SIG_LDLD = \"LDLD\"\nlocal process_proj_block",
    "local SIG_LDLD = \"LDLD\"\nlocal process_dmg_block")

# ---------------------------------------------------------------------------
# 10. 复查
# ---------------------------------------------------------------------------
rep('''    local cfg = read_cfg()
    if cfg and cfg ~= want_proj then
        log(string.format("cfg changed: per-shot %d -> %d", want_proj, cfg))
        want_proj = cfg
    end''',
    '''    local cfg = read_cfg()
    if cfg and cfg ~= want_dmg then
        log(string.format("cfg changed: damage %d -> %d", want_dmg, cfg))
        want_dmg = cfg
    end''')

rep('''        if cur == nil or not is_target_record(cur) then
            table.remove(state.copies, i); changed = true
        else
            local cur_n = u32_at(cur, CONFIG.OFF_NUM_PROJ)
            if cur_n ~= want_proj then
                log(string.format("copy @0x%X num_projectiles=%d, want %d; applying", c.rec, cur_n, want_proj))
                if write_num_proj(c.rec, cur, want_proj) then
                    i = i + 1; changed = true
                else
                    table.remove(state.copies, i); changed = true
                end
            else
                i = i + 1
            end
        end''',
    '''        if cur == nil or not is_target_record(cur) then
            table.remove(state.copies, i); changed = true
        else
            local cur_d = u32_at(cur, CONFIG.OFF_DAMAGE)
            if cur_d ~= want_dmg then
                log(string.format("copy @0x%X damage=%d, want %d; applying", c.rec, cur_d, want_dmg))
                if write_damage(c.rec, want_dmg) then
                    i = i + 1; changed = true
                else
                    table.remove(state.copies, i); changed = true
                end
            else
                i = i + 1
            end
        end''')

rep('''    if changed then
        state.proj_new = want_proj
        flush_status()
    end''',
    '''    if changed then
        state.dmg_new = want_dmg
        flush_status()
    end''')

# ---------------------------------------------------------------------------
# 11. tick / init
# ---------------------------------------------------------------------------
rep("""        tgt_trail = hex_to_le_bytes(CONFIG.TGT_TRAIL_HEX)
        tgt_thr   = hex_to_le_bytes(CONFIG.TGT_THR_HEX)
        local ok, msg = loader_gate()""",
    """        local ok, msg = loader_gate()""")

rep("""        local cfg = read_cfg()
        if cfg then want_proj = cfg end
        state.phase = "searching"
        log("addon started revision " .. REVISION .. "; loader API "
            .. tostring(state.loader_api) .. " v" .. tostring(state.loader_version)
            .. "; per-shot=" .. tostring(want_proj))""",
    """        local cfg = read_cfg()
        if cfg then want_dmg = cfg end
        state.phase = "searching"
        log("addon started revision " .. REVISION .. "; loader API "
            .. tostring(state.loader_api) .. " v" .. tostring(state.loader_version)
            .. "; target damage=" .. tostring(want_dmg))""")

# 遗留引用
rep("""            local cur_n = u32_at(cur, CONFIG.OFF_NUM_PROJ)""",
    """            local cur_n = u32_at(cur, CONFIG.OFF_DAMAGE)""", 0)

io.open(DST, "w", encoding="utf-8", newline="\n").write(s)
print("miss:", miss)
print("wrote", DST, len(s), "bytes")

# 残留检查
leftovers = []
for bad in ["bug_artillery_6rounds", "PROJ_PER_SHOT", "OFF_NUM_PROJ", "process_proj_block",
            "want_proj", "proj_old", "proj_new", "TGT_TRAIL", "TGT_THR", "TGT_AUDIO",
            "TYPE_PROJECTILE", "REC_SIZE = 272", "num_projectiles", "bug artillery", "Bile Spewer"]:
    if bad in s:
        leftovers.append(bad)
print("leftovers:", leftovers)
