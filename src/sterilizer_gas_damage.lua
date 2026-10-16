-- HD2-Addon: mods/hd2/sterilizer_gas_damage
-- ============================================================================
-- TX-41 灭菌器(Sterilizer) 增强:
--   (1) 直接伤害 -> G-4 毒气榴弹(Explosion_Gas_Grenade) 级别          [v1.x]
--   (2) 喷出的毒气状态效果"施加量" -> 2 倍(可调, 只影响灭菌器)          [v2.0.0 新增]
-- TX-41 Sterilizer: G-4-level direct damage + doubled gas status buildup
--
-- 用户需求: "TX-41 灭菌器 的喷毒射程范围更改为和 B/FLAM-80 焚燃者 喷火范围一样,
--            同时伤害提升为 G-4 毒气榴弹一样"
--   => 伤害已完成; 射程**数据层无字段可改**(理由见下, 已逐项离线验证)。
-- 后续需求: "射程改不了那把毒气效果的强度/持续时间调强"
--   => 用户拍板: **仅灭菌器**(不触碰全局毒气, 敌人的毒气不受影响), 幅度 = 原版 2 倍。
--
-- ★ 为什么"射程"改不了(离线穷尽验证过的):
--   喷射类武器(TX-41 / B/FLAM-80 / FLAM-40 / Crisper)的
--     SprayWeaponComponent.projectile_type = ProjectileType_None
--   => 它们**不发射射弹**; 伤害靠"粒子碰撞事件"触发 component 里的 damage_info_type。
--   => "喷多远"完全由枪口粒子效果(muzzle_effect, 一个 VFX 资源哈希)决定:
--        SprayWeaponComponent(224B/16 字段) 与 WeaponDataComponent(56 字段) 里
--        **没有任何 range / length / distance 字段**;
--        唯一带 length 的 SprayCapsuleOverlap(8B) 在 entities blob 里 **0 个实例**;
--        BeamSettings 里也没有化学/火焰喷流条目。
--   => 而且这些 *ComponentData 表**在内存里不加载**(实机全内存 LDLD 普查 0 命中)。
--   => 结论: 射程属于美术(VFX)资产, Lua 内存补丁改不到。
--
-- ★ 为什么"毒气强度"也只能走"仅灭菌器"这条路:
--   灭菌器喷中的目标会挂两个状态效果:
--     StatusEffectType_Gas           (毒气, 带 DamageInfoType_DPS_Gas 持续伤害)
--     StatusEffectType_Gas_Confusion (致幻)
--   这两个效果的 strength / duration 定义在**全局**表 StatusEffectSettings(0xC63E0B22) 里,
--   并被**多方共用**: 灭菌器 / 敌方化学无人机 / G-4 毒气榴弹 / 轨道毒气弹 / 胚胎簇。
--   => 改它们 = 敌我双方毒气一起变强(+ 榴弹/轨道弹也一起变), 用户不接受。
--   => 因此本 addon 改为拉高**灭菌器自己那条 DamageInfo 记录**里的
--      "状态效果施加量"(DamageStatusEffectInfo.value), 严格只影响灭菌器:
--        DamageInfoType_Spray_Chem_Gun : SE[Gas].value 0.5 -> 1.0
--                                        SE[Gas_Confusion].value 0.5 -> 1.0   [v2.0.0]
--      敌方化学无人机用的是**另一条**记录 DamageInfoType_Drone_Chem_Gun, 原封不动。
--   (已知取舍: 这样**改不到"持续时间"** —— duration 只存在于全局表, 无法只对灭菌器生效。)
--
-- 本 addon 改什么(纯内存补丁; 禁用 mod + Purge 即完全还原, 不改任何磁盘文件):
--   表 DamageSettings(LDLD 类型哈希 0xE0A72CF0; 属于 *_Settings 家族, 实机普查确认**常驻内存**)
--   记录 DamageInfoType_Spray_Chem_Gun —— 由实体 blob 反查确认**只被 TX-41 灭菌器使用**
--     (敌人"化学无人机"用的 Drone_Chem_Gun 是一条**数值完全相同**的邻居记录;
--      本 addon 用"两条里 Type 较小者 = 灭菌器"来区分, 见 patch_into_table)
--
--   DamageInfo 记录(76 字节, 游戏 typelib 权威布局):
--     +0   u32 DamageInfoType            (枚举, 会随构建漂移 -> 只作提示, 不当判据)
--     +4   i32 damage          [1,1] -> [3,3]        <- 【改写项 1】
--     +8   i32 durable_damage  [1,1] -> [3,3]        <- 【改写项 1】
--     +12  u32[4] armor_penetration_per_angle = 5,5,5,0
--     +28  u32 demolition_strength = 5      +32 u32 force_strength = 10
--     +36  u32 force_impulse = 5            +40 u32 element_type
--     +44  DamageStatusEffectInfo[4]  { u32 type, f32 value }  (8B/条)
--             +44 type(Gas)                   +48 value [0.5] -> [1.0]  <- 【改写项 2】
--             +52 type(Gas_Confusion)         +56 value [0.5] -> [1.0]  <- 【改写项 2】
--             +60 / +68 type == 0 (空)
--
--   => **只写 +4..+11 (8B) 与 +48..+51 / +56..+59 (2x4B) 这三段**;
--      其余逐字节 keep-guard —— 尤其 +52..+55 的 SE[1].type 绝不碰。
--
--   目标值依据: G-4 毒气榴弹的爆炸伤害 DamageInfoType_Explosion_Gas_Grenade
--     = damage 3 / durable_damage 3 (离线产物里 8 项字段逐项比对确认)。
--   => 毒气施加量取原版 0.5 的 2 倍 = 1.0(用户指定"原版 2 倍")。
--
-- ★ 两个数值都可在游戏运行时调, 不用重新打包:
--   日志目录里的 `sterilizer_gas_damage.cfg`:
--       damage=3      # 每次命中的直接伤害(原版 1; G-4 毒气榴弹 = 3)
--       gas=1.0       # 毒气状态效果施加量(原版 0.5; 1.0 = 2 倍)
--   改完保存, ~5 秒内自动重打, 下一枪立刻生效。(旧的"单个数字"cfg 仍兼容 = damage。)
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存.
-- ============================================================================

local MOD_NAME = "mods/hd2/sterilizer_gas_damage"
local REVISION = "2.0.0"
local SINGLETON = "_HD2_STERILIZER_GAS_DAMAGE"

if rawget(_G, SINGLETON) then return end
rawset(_G, SINGLETON, true)

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------
local CONFIG = {
    TYPE_DAMAGE_SETTINGS = 0xE0A72CF0,  -- djb2("DamageSettings")

    -- DamageInfo 字段偏移(游戏 typelib 权威, 记录 76 字节)
    REC_SIZE    = 76,
    OFF_TYPE    = 0,     -- u32 DamageInfoType (枚举, 只作提示)
    OFF_DAMAGE  = 4,     -- i32 damage          <- 【改写项 1】
    OFF_DURABLE = 8,     -- i32 durable_damage  <- 【改写项 1】
    OFF_AP      = 12,    -- u32[4] armor_penetration_per_angle
    OFF_DEMO    = 28,    -- u32 demolition_strength
    OFF_FS      = 32,    -- u32 force_strength
    OFF_FI      = 36,    -- u32 force_impulse
    OFF_ELEM    = 40,    -- u32 element_type
    OFF_SE      = 44,    -- DamageStatusEffectInfo[4]  { u32 type, f32 value } (8B/条)

    -- 状态效果条目: 灭菌器挂两条(毒气 + 致幻), 后两条为空
    OFF_SE0_TYPE  = 44,  -- SE[0].type  = StatusEffectType_Gas
    OFF_SE0_VALUE = 48,  -- SE[0].value -> 【改写项 2】
    OFF_SE1_TYPE  = 52,  -- SE[1].type  = StatusEffectType_Gas_Confusion  (★绝不修改)
    OFF_SE1_VALUE = 56,  -- SE[1].value -> 【改写项 2】
    OFF_SE2_TYPE  = 60,  -- SE[2].type  == 0 (空)
    OFF_SE3_TYPE  = 68,  -- SE[3].type  == 0 (空)

    -- 身份指纹: 全部是"数值/物理量 + 结构关系", 不依赖会漂移的枚举下标。
    --   ★ 刻意**不含**任何本 addon 会改的字段(damage / durable / SE value) ——
    --     否则打完、或 cfg 热调之后就会认不出自己。
    --   预期在整个 DamageSettings 表里命中 **2 条**: 灭菌器(Spray_Chem_Gun) 与其后紧邻的
    --   敌方化学无人机(Drone_Chem_Gun), 两条其余数值完全相同, 只有 DamageInfoType 不同。
    --   (离线实测: 在 649 条真实整表上恰好命中这 2 条。)
    SIG_AP       = 5,      -- armor_penetration_per_angle = 5,5,5,0
    SIG_DEMO     = 5,
    SIG_FS       = 10,
    SIG_FI       = 5,
    SIG_DMG_LO   = 1,      -- 合法的 damage 下限(原版)
    SIG_DMG_HI   = 200,    -- 合法的 damage 上限(打过之后)

    -- 目标伤害 = G-4 毒气榴弹的爆炸伤害(默认值; 运行时会被 cfg 文件覆盖)
    DMG_DEFAULT = 3,
    DMG_MIN = 1,
    DMG_MAX = 200,

    -- 毒气状态效果"施加量"(默认值; 运行时会被 cfg 文件覆盖)
    --   原版 0.5 -> 1.0 = 2 倍(用户指定)。只作用于灭菌器那条记录。
    GAS_DEFAULT = 1.0,
    GAS_MIN = 0.0,
    GAS_MAX = 1000.0,
    GAS_EPS = 1e-4,        -- 浮点比较容差

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

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local state = {
    phase = "init",
    frames = 0,
    retired = false,
    loader_api = nil,
    loader_version = nil,

    regions = nil, enum_cursor = 0, enum_done = false,
    ri = 1, off = 0, pass = 0, bytes_scanned = 0, resume_frame = 0,
    scan_stopped = false,
    types_seen = {},
    done_blocks = {},

    target_type = nil,
    last_reject = nil,       -- 最近一次拒绝写入的原因(给 STATUS 看)
    dmg_old = nil,           -- 原版 damage
    dmg_new = nil,           -- 当前生效值
    gas_old = nil,           -- 原版毒气施加量
    gas_new = nil,           -- 当前生效值
    copies = {},             -- {rec=, idx=, blk=}

    next_recheck = 0,
}

-- 要写入的两个值(来自 cfg 文件; 没有就取默认)
local want_dmg = CONFIG.DMG_DEFAULT
local want_gas = CONFIG.GAS_DEFAULT

-- ---------------------------------------------------------------------------
-- 日志 / 状态文件
-- ---------------------------------------------------------------------------
local log_lines = {}
local last_err = nil
local status_head = "INIT - starting"

local function env_dir()
    local ok, v = pcall(os.getenv, CONFIG.LOG_DIR_ENV)
    if ok and v and v ~= "" then return v .. CONFIG.LOG_SUBDIR end
    return nil
end

-- 读 cfg。返回 (damage, gas); 某项缺失/非法 -> 该项返回 nil(用默认)。
--   支持两种写法(可混用):
--     damage=3      gas=1.0        <- 推荐
--     3                            <- 旧格式: 文件里第一个裸数字 = damage(向后兼容)
local function read_cfg()
    local dir = env_dir()
    if not dir then return nil, nil end
    local ok, f = pcall(io.open, dir .. CONFIG.CFG_NAME, "r")
    if not ok or not f then return nil, nil end
    local txt = f:read("*a") or ""
    f:close()

    local d, g = nil, nil
    for line in string.gmatch(txt, "[^\r\n]+") do
        if not string.match(line, "^%s*#") then          -- 跳过注释行
            local dv = string.match(line, "damage%s*[=:]%s*(%-?%d+)")
            if dv then d = tonumber(dv) end
            local gv = string.match(line, "gas%s*[=:]%s*(%-?[%d%.]+)")
            if gv then g = tonumber(gv) end
        end
    end
    if d == nil and g == nil then
        -- 旧格式: 整个文件里第一个整数 = damage
        local n = tonumber(string.match(txt, "(%d+)"))
        if n then d = n end
    end
    if d ~= nil and (d < CONFIG.DMG_MIN or d > CONFIG.DMG_MAX) then d = nil end
    if g ~= nil and (g < CONFIG.GAS_MIN or g > CONFIG.GAS_MAX) then g = nil end
    return d, g
end

-- 首次运行时把默认值(带注释)写出来, 让用户知道有这个开关
local function ensure_cfg()
    local dir = env_dir()
    if not dir then return end
    local ok, f = pcall(io.open, dir .. CONFIG.CFG_NAME, "r")
    if ok and f then f:close(); return end
    local ok2, w = pcall(io.open, dir .. CONFIG.CFG_NAME, "w")
    if ok2 and w then
        w:write("# TX-41 Sterilizer tunables - edit & save; re-applied within ~5s, no repack/restart\n")
        w:write("# damage : direct hit damage    (vanilla 1;   G-4 Gas Grenade = 3)\n")
        w:write("# gas    : gas status buildup   (vanilla 0.5; 1.0 = double strength)\n")
        w:write(string.format("damage=%d\n", CONFIG.DMG_DEFAULT))
        w:write(string.format("gas=%.3f\n", CONFIG.GAS_DEFAULT))
        w:close()
    end
end

local function build_status_text()
    local parts = { status_head }
    parts[#parts + 1] = string.format("mod=%s revision=%s", MOD_NAME, REVISION)
    parts[#parts + 1] = string.format("phase=%s frames=%d", state.phase, state.frames)
    parts[#parts + 1] = string.format("loader_api=%s loader_version=%s",
        tostring(state.loader_api), tostring(state.loader_version))
    if state.phase == "searching" then
        parts[#parts + 1] = string.format("scan_pass=%d region=%d/%s scanned_mb=%.1f",
            state.pass, state.ri, state.regions and #state.regions or "?",
            state.bytes_scanned / 1048576.0)
    end
    parts[#parts + 1] = string.format("target(sterilizer damage record) damage_info_type=%s", tostring(state.target_type))
    parts[#parts + 1] = string.format("damage=%s->%s (vanilla 1; G-4 Gas Grenade = 3)",
        tostring(state.dmg_old), tostring(want_dmg))
    parts[#parts + 1] = string.format("gas_buildup=%s->%s (vanilla 0.5; 1.0 = 2x strength)",
        tostring(state.gas_old), string.format("%.3f", want_gas))
    if state.last_reject and state.phase ~= "patched" then
        parts[#parts + 1] = "last_reject=" .. state.last_reject
    end
    parts[#parts + 1] = string.format("patched_records=%d", #state.copies)
    for i = 1, #state.copies do
        local c = state.copies[i]
        parts[#parts + 1] = string.format("  copy%d: rec@0x%X idx=%d", i, c.rec, c.idx)
    end
    if state.phase == "searching" then
        local ts = {}
        for th, c in pairs(state.types_seen) do ts[#ts + 1] = { th = th, c = c } end
        table.sort(ts, function(a, b) return a.c > b.c end)
        local out = {}
        for i = 1, #ts do
            if i > 8 then break end
            out[#out + 1] = string.format("0x%08X:%d", ts[i].th, ts[i].c)
        end
        if #out > 0 then parts[#parts + 1] = "ldld_types=" .. table.concat(out, " ") end
    end
    parts[#parts + 1] = "effect: TX-41 Sterilizer direct damage -> G-4 Gas Grenade level, AND its"
    parts[#parts + 1] = "        gas status buildup doubled (0.5 -> 1.0)."
    parts[#parts + 1] = "        Scope: sterilizer ONLY. The enemy chem drone uses a separate record"
    parts[#parts + 1] = "        (Drone_Chem_Gun) and stays byte-for-byte untouched."
    parts[#parts + 1] = "        AP / demolition / knockback / SE types / every other byte stay vanilla."
    parts[#parts + 1] = "range: spray distance is driven by the muzzle VFX particle and CANNOT be"
    parts[#parts + 1] = "       changed from memory (no range field exists in the data tables)."
    parts[#parts + 1] = "limit: gas DURATION lives on the shared global effect table and cannot be"
    parts[#parts + 1] = "       changed for the sterilizer alone -- only its buildup is raised here."
    parts[#parts + 1] = string.format("tune: edit %s and save:", CONFIG.CFG_NAME)
    parts[#parts + 1] = "        damage=3   gas=1.0    (re-applies within ~5s, no repack/restart)"
    parts[#parts + 1] = "note: damage is host-authoritative; host needs this mod for real damage to count"
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "sterilizer_gas_damage_STATUS.txt", "w")
        if f then f:write(build_status_text()); f:close() end
    end)
end

local function set_status(text)
    if status_head ~= text then status_head = text; flush_status() end
end

local function flush_log()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "sterilizer_gas_damage.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_STERILIZER_FLUSH = flush_log   -- 唯一名字, 不与其它 addon 的全局函数冲突

local function log(msg)
    log_lines[#log_lines + 1] = string.format("[frame %d] %s", state.frames, msg)
    if #log_lines > 2000 then table.remove(log_lines, 1) end
    flush_log()
end

local function log_err(msg)
    if last_err == msg then return end
    last_err = msg
    log("ERROR " .. msg)
end

-- ---------------------------------------------------------------------------
-- 字节工具
-- ---------------------------------------------------------------------------
local function u32_le(v)
    v = math.floor(v)
    local b1 = v % 256
    local b2 = math.floor(v / 256) % 256
    local b3 = math.floor(v / 65536) % 256
    local b4 = math.floor(v / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

local function u32_at(s, off)
    local a, b, c, d = string.byte(s, off + 1, off + 4)
    if not d then return 0 end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function u64_at(s, off)
    return u32_at(s, off) + u32_at(s, off + 4) * 4294967296
end

local function hex8_be(s, off)
    local t = {}
    for i = 8, 1, -1 do
        t[#t + 1] = string.format("%02X", string.byte(s, off + i) or 0)
    end
    return table.concat(t)
end

local function hex_to_le_bytes(hex)
    local out = {}
    local i = #hex - 1
    while i >= 1 do
        out[#out + 1] = string.char(tonumber(string.sub(hex, i, i + 1), 16))
        i = i - 2
    end
    return table.concat(out)
end

local function bits_to_f32(bits)
    local sign = 1
    if bits >= 2147483648 then sign = -1; bits = bits - 2147483648 end
    local exp = math.floor(bits / 8388608)
    local mant = bits - exp * 8388608
    if exp == 255 then
        if mant == 0 then return sign * math.huge end
        return 0 / 0
    end
    if exp == 0 then
        if mant == 0 then return sign * 0.0 end
        return sign * mant * 2 ^ -149
    end
    return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

local function f32_at(s, off) return bits_to_f32(u32_at(s, off)) end

-- 纯 Lua 打包 float32 的位(不用 ffi / string.pack —— 离线仿真环境两者都不可靠)
local function f32_bits(x)
    if x ~= x then return 0x7FC00000 end             -- NaN
    local sign = 0
    if x < 0 then sign = 0x80000000; x = -x end
    if x == 0 then return sign end
    if x == math.huge then return sign + 0x7F800000 end
    local e = math.floor(math.log(x) / math.log(2))
    while x >= 2 ^ (e + 1) do e = e + 1 end
    while x < 2 ^ e do e = e - 1 end
    local mant = math.floor((x / (2 ^ e) - 1) * 8388608 + 0.5)
    if mant >= 8388608 then mant = mant - 8388608; e = e + 1 end
    local exp = e + 127
    if exp <= 0 then return sign end                 -- 下溢 -> 0
    if exp >= 255 then return sign + 0x7F800000 end  -- 饱和
    return sign + exp * 8388608 + mant
end

local function near(v, want, tol)
    local d = v - want
    if d < 0 then d = -d end
    return d <= tol
end

local function float_codec_selftest()
    local cases = {
        { 0x3F800000, 1.0 }, { 0x3F000000, 0.5 }, { 0x42480000, 50.0 },
        { 0x41F00000, 30.0 }, { 0x447A0000, 1000.0 }, { 0x40400000, 3.0 },
        { 0x00000000, 0.0 }, { 0x3E800000, 0.25 }, { 0x40C00000, 6.0 },
    }
    for i = 1, #cases do
        if bits_to_f32(cases[i][1]) ~= cases[i][2] then return false end
        if f32_bits(cases[i][2]) ~= cases[i][1] then return false end   -- 往返
    end
    return true
end

-- ---------------------------------------------------------------------------
-- FFI
-- ---------------------------------------------------------------------------
local ffi_ok = false
local ffi = nil
local C = nil
local MBI_SIZE = 48
local MEM_COMMIT = 0x1000
local PAGE_READABLE = { [0x02]=true,[0x04]=true,[0x08]=true,[0x20]=true,[0x40]=true,[0x80]=true }
local PAGE_WRITABLE = { [0x04]=true,[0x08]=true,[0x40]=true,[0x80]=true }

local function setup_ffi()
    local ok, f = pcall(require, "ffi")
    if not ok or not f then return false end
    ffi = f
    local ok2 = pcall(ffi.cdef, [[
typedef struct {
    void* BaseAddress; void* AllocationBase;
    unsigned int AllocationProtect; unsigned int __alignment1;
    unsigned long long RegionSize;
    unsigned int State; unsigned int Protect; unsigned int Type; unsigned int __alignment2;
} MEMORY_BASIC_INFORMATION;
typedef unsigned long long SIZE_T;
int VirtualQuery(void* lpAddress, MEMORY_BASIC_INFORMATION* lpBuffer, SIZE_T dwLength);
int ReadProcessMemory(void* hProcess, void* lpBaseAddress, void* lpBuffer, SIZE_T nSize, SIZE_T* lpNumberOfBytesRead);
int WriteProcessMemory(void* hProcess, void* lpBaseAddress, void* lpBuffer, SIZE_T nSize, SIZE_T* lpNumberOfBytesWritten);
int VirtualProtect(void* lpAddress, SIZE_T dwSize, unsigned int flNewProtect, unsigned int* lpflOldProtect);
void* GetCurrentProcess(void);
]])
    if not ok2 then return false end
    C = ffi.C
    return true
end

local self_addrs = {}
local function register_self_pattern(s)
    local ok, p = pcall(function()
        return tonumber(ffi.cast("uintptr_t", ffi.cast("const char *", s)))
    end)
    if ok and p then self_addrs[#self_addrs + 1] = p end
end
local function is_self_addr(a)
    for i = 1, #self_addrs do
        local d = a - self_addrs[i]
        if d < 0 then d = -d end
        if d <= CONFIG.SELF_SKIP then return true end
    end
    return false
end

local proc_handle = nil
local read_buf = nil
local read_buf_size = 0
local function ensure_buf(n)
    if read_buf == nil or read_buf_size < n then
        read_buf = ffi.new("char[?]", n); read_buf_size = n
    end
end
local function read_mem(addr, size)
    if not ffi_ok or size <= 0 or size > 32 * 1024 * 1024 then return nil end
    ensure_buf(size)
    local nread = ffi.new("SIZE_T[1]")
    local r = C.ReadProcessMemory(proc_handle, ffi.cast("void*", addr), read_buf, size,
                                  ffi.cast("SIZE_T*", nread))
    if r == 0 then return nil end
    return ffi.string(read_buf, size)
end
local function raw_write(addr, bytes, size)
    local buf = ffi.new("char[?]", size)
    for i = 1, size do buf[i - 1] = string.byte(bytes, i) end
    local nwr = ffi.new("SIZE_T[1]")
    return C.WriteProcessMemory(proc_handle, ffi.cast("void*", addr), buf, size,
                                ffi.cast("SIZE_T*", nwr))
end
local function write_mem(addr, bytes)
    local size = #bytes
    local mbi = ffi.new("MEMORY_BASIC_INFORMATION")
    local need_unprot = false
    local old_prot = ffi.new("unsigned int[1]")
    if C.VirtualQuery(ffi.cast("void*", addr), ffi.cast("MEMORY_BASIC_INFORMATION*", mbi), MBI_SIZE) ~= 0 then
        if not PAGE_WRITABLE[tonumber(mbi.Protect)] then
            if C.VirtualProtect(ffi.cast("void*", addr), size, 0x40,
                                ffi.cast("unsigned int*", old_prot)) == 0 then return false end
            need_unprot = true
        end
    end
    local r = raw_write(addr, bytes, size)
    if need_unprot then
        C.VirtualProtect(ffi.cast("void*", addr), size, old_prot[0], ffi.cast("unsigned int*", old_prot))
    end
    return r ~= 0
end

-- ---------------------------------------------------------------------------
-- 环境闸门
-- ---------------------------------------------------------------------------
local function loader_gate()
    local l = rawget(_G, "CowboyBingusModLoader")
    local api, ver = nil, nil
    if type(l) == "table" then api = tonumber(l.api); ver = tonumber(l.version) end
    if api == nil then
        local dir = env_dir()
        if dir then
            local ok, f = pcall(io.open, dir .. "BingusSharedLoader.log", "r")
            if ok and f then
                local line = f:read("*l") or ""; f:close()
                local v, a = string.match(line, "loader%-v(%d+);%s*API%s+(%d+)")
                if v then ver = tonumber(v) end
                if a then api = tonumber(a) end
            end
        end
    end
    state.loader_api = api; state.loader_version = ver
    if api ~= nil and api < 1 then
        return false, string.format("FAILED - Bingus Shared Loader too old (API %s, v%s); need API 1",
            tostring(api), tostring(ver))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- 扫描器
-- ---------------------------------------------------------------------------
local SIG_LDLD = "LDLD"
local process_dmg_block

local function enum_regions_step()
    if state.regions == nil then state.regions = {} end
    local mbi = ffi.new("MEMORY_BASIC_INFORMATION")
    local addr = state.enum_cursor
    local budget = os.clock() + 0.004
    local n = 0
    while addr < 0x7FFFFFFFFFF000 do
        if C.VirtualQuery(ffi.cast("void*", addr), ffi.cast("MEMORY_BASIC_INFORMATION*", mbi), MBI_SIZE) == 0 then
            state.enum_done = true; break
        end
        local base = tonumber(ffi.cast("uintptr_t", mbi.BaseAddress))
        local rsize = tonumber(mbi.RegionSize)
        if rsize <= 0 then state.enum_done = true; break end
        local prot = tonumber(mbi.Protect); local mtype = tonumber(mbi.Type)
        if tonumber(mbi.State) == MEM_COMMIT and PAGE_READABLE[prot] and rsize >= CONFIG.REGION_MIN then
            state.regions[#state.regions + 1] = { base = base, size = rsize, image = (mtype == 0x1000000) }
        end
        addr = base + rsize
        n = n + 1
        if n >= 4000 or os.clock() > budget then break end
    end
    if addr >= 0x7FFFFFFFFFF000 then state.enum_done = true end
    state.enum_cursor = addr
    if state.enum_done then
        table.sort(state.regions, function(a, b)
            if a.image ~= b.image then return (not a.image) end
            return a.size > b.size
        end)
        log(string.format("region enum done: %d regions", #state.regions))
    end
    return state.enum_done
end

local function scan_one_chunk(region_base, off, len)
    local data = read_mem(region_base + off, len)
    if not data then return end
    state.bytes_scanned = state.bytes_scanned + len
    local init = 1
    while true do
        local p = string.find(data, SIG_LDLD, init, true)
        if not p then break end
        if p + 15 <= #data then
            local ver = u32_at(data, p + 3)
            local th = u32_at(data, p + 7)
            local size = u32_at(data, p + 11)
            if ver == 1 and size >= 64 and size <= 64 * 1024 * 1024 then
                local addr = region_base + off + p - 1
                if not is_self_addr(addr) then
                    state.types_seen[th] = (state.types_seen[th] or 0) + 1
                    if th == CONFIG.TYPE_DAMAGE_SETTINGS then
                        local ok, err = pcall(process_dmg_block, { addr = addr, type = th, size = size })
                        if not ok then log_err("damage block error: " .. tostring(err)) end
                    end
                end
            end
        end
        init = p + 1
    end
end

local function scan_pump(budget)
    if state.scan_stopped then return end
    if not state.enum_done then enum_regions_step(); return end
    if #state.regions == 0 then enum_regions_step(); return end
    if state.frames < state.resume_frame then return end
    local deadline = os.clock() + budget
    while os.clock() < deadline do
        if state.ri > #state.regions then
            state.ri = 1
            state.pass = state.pass + 1
            log(string.format("pass %d done: scanned %.1f MB, target=%s copies=%d",
                state.pass, state.bytes_scanned / 1048576.0,
                tostring(state.target_type), #state.copies))
            local ts = {}
            for th, c in pairs(state.types_seen) do ts[#ts + 1] = string.format("0x%08X x%d", th, c) end
            if #ts > 0 then log("LDLD types seen: " .. table.concat(ts, ", ")) end
            flush_status()
            if state.phase == "patched" then
                state.scan_stopped = true
                log("scan stopped: patch applied and a full pass completed")
                return
            end
            local wait = 2 ^ math.min(state.pass, 6)
            state.resume_frame = state.frames + wait * 60
            log(string.format("next pass in %ds", wait))
            if os.clock() > deadline then break end
        end
        local region = state.regions[state.ri]
        if state.off >= region.size then
            state.ri = state.ri + 1; state.off = 0
        else
            local len = CONFIG.CHUNK + CONFIG.OVERLAP
            if state.off + len > region.size then len = region.size - state.off end
            scan_one_chunk(region.base, state.off, len)
            state.off = state.off + CONFIG.CHUNK
        end
    end
end

-- ---------------------------------------------------------------------------
-- 表解析(settings 表: +24 {u64 相对偏移 或 绝对指针, u64 条数})
-- ---------------------------------------------------------------------------
local function read_table(blk)
    local desc = read_mem(blk.addr + 24, 16)
    if not desc then return nil end
    local a = u64_at(desc, 0)
    local count = u64_at(desc, 8)
    if count < 1 or count > 200000 then return nil end
    local stride = (blk.size - 16) / count
    if stride ~= math.floor(stride) or stride < 8 or stride > 16384 then return nil end
    stride = math.floor(stride)
    if a >= 8 and a + count * stride <= blk.size then
        return { recbase = blk.addr + 24 + a, count = count, stride = stride, tag = "file" }
    end
    if a > 4096 and a ~= blk.addr then
        return { recbase = a, count = count, stride = stride, tag = "mem" }
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 记录指纹 / 改写
-- ---------------------------------------------------------------------------
-- 灭菌器伤害记录的身份指纹(数值/物理量 + 结构关系)。
--   ★ 刻意**不含**任何本 addon 会改的字段(damage / durable / SE value):
--     这样打完补丁、或 cfg 热调之后仍然认得出自己 -> 幂等 + 可反复重打。
--   ★ 也不认具体枚举值(会随构建漂移), 只判"前两条 SE 存在 / 后两条为空"这一结构。
local function is_target_record(r)
    if u32_at(r, CONFIG.OFF_AP)      ~= CONFIG.SIG_AP then return false end
    if u32_at(r, CONFIG.OFF_AP + 4)  ~= CONFIG.SIG_AP then return false end
    if u32_at(r, CONFIG.OFF_AP + 8)  ~= CONFIG.SIG_AP then return false end
    if u32_at(r, CONFIG.OFF_AP + 12) ~= 0 then return false end
    if u32_at(r, CONFIG.OFF_DEMO) ~= CONFIG.SIG_DEMO then return false end
    if u32_at(r, CONFIG.OFF_FS)   ~= CONFIG.SIG_FS then return false end
    if u32_at(r, CONFIG.OFF_FI)   ~= CONFIG.SIG_FI then return false end
    -- 前两条状态效果必须存在(枚举值随构建漂移 -> 只判非零)
    if u32_at(r, CONFIG.OFF_SE0_TYPE) == 0 then return false end
    if u32_at(r, CONFIG.OFF_SE1_TYPE) == 0 then return false end
    -- 后两条状态效果必须为空(类型 0)
    if u32_at(r, CONFIG.OFF_SE2_TYPE) ~= 0 then return false end
    if u32_at(r, CONFIG.OFF_SE3_TYPE) ~= 0 then return false end
    -- damage 必须落在合法区间(原版 1 .. 打过之后的 200)。刻意不要求 == 1, 以支持幂等。
    local d = u32_at(r, CONFIG.OFF_DAMAGE)
    if d < CONFIG.SIG_DMG_LO or d > CONFIG.SIG_DMG_HI then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- 打补丁
-- ---------------------------------------------------------------------------
local function register_copy(rec_addr, idx)
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

-- 把两条状态效果的"施加量"同时写成 want_gas —— **只写 +48..+51 与 +56..+59 这 2x4 个字节**.
--   ★ 两次独立 4 字节写入: 中间的 +52..+55(SE[1].type) 绝不触碰(keep-guard)。
local function write_gas(rec_addr, g)
    local want = f32_bits(g)
    local bytes = u32_le(want)
    if not write_mem(rec_addr + CONFIG.OFF_SE0_VALUE, bytes) then
        log_err(string.format("gas write failed @0x%X (+%d)", rec_addr, CONFIG.OFF_SE0_VALUE))
        return false
    end
    if not write_mem(rec_addr + CONFIG.OFF_SE1_VALUE, bytes) then
        log_err(string.format("gas write failed @0x%X (+%d)", rec_addr, CONFIG.OFF_SE1_VALUE))
        return false
    end
    local b0 = read_mem(rec_addr + CONFIG.OFF_SE0_VALUE, 4)
    local b1 = read_mem(rec_addr + CONFIG.OFF_SE1_VALUE, 4)
    if b0 == nil or b1 == nil or u32_at(b0, 0) ~= want or u32_at(b1, 0) ~= want then
        log_err(string.format("gas read-back mismatch @0x%X", rec_addr))
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
            hits[#hits + 1] = { idx = k, ty = u32_at(r, CONFIG.OFF_TYPE),
                                se0 = u32_at(r, CONFIG.OFF_SE0_TYPE),
                                se1 = u32_at(r, CONFIG.OFF_SE1_TYPE) }
        end
    end
    -- ★ 必须**恰好 2 条**、DamageInfoType 相邻、且两条挂的状态效果类型完全相同。
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
    if h1.se0 ~= h2.se0 or h1.se1 ~= h2.se1 then
        state.last_reject = string.format("SE types %d/%d vs %d/%d differ", h1.se0, h1.se1, h2.se0, h2.se1)
        log_err(string.format("two candidates but their status-effect types differ (%d/%d vs %d/%d); refusing",
            h1.se0, h1.se1, h2.se0, h2.se1))
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
    local cur_g = f32_at(cur, CONFIG.OFF_SE0_VALUE)

    -- 只写"还没到位"的那一段; 每段都是 4/8 字节的精准改写(keep-guard)
    local did_write = false
    local dmg_ok = (u32_at(cur, CONFIG.OFF_DAMAGE) == want_dmg)
                 and (u32_at(cur, CONFIG.OFF_DURABLE) == want_dmg)
    if not dmg_ok then
        if not write_damage(tgt_addr, want_dmg) then return false end
        did_write = true
    end
    local gas_ok = near(cur_g, want_gas, CONFIG.GAS_EPS)
               and near(f32_at(cur, CONFIG.OFF_SE1_VALUE), want_gas, CONFIG.GAS_EPS)
    if not gas_ok then
        if not write_gas(tgt_addr, want_gas) then return false end
        did_write = true
    end

    register_copy(tgt_addr, chosen.idx)
    state.last_reject = nil
    if state.target_type == nil then
        state.target_type = u32_at(cur, CONFIG.OFF_TYPE)
        state.dmg_old = cur_d
        state.gas_old = cur_g
    end
    state.dmg_new = want_dmg
    state.gas_new = want_gas
    log(string.format("%s sterilizer @0x%X (idx %d, damage_info_type %s, %d candidates): damage %d -> %d, gas %.3f -> %.3f",
        did_write and "PATCHED" or "ALREADY", tgt_addr, chosen.idx,
        tostring(u32_at(cur, CONFIG.OFF_TYPE)), #hits, cur_d, want_dmg, cur_g, want_gas))
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
            "OK - patch applied (revision %s): TX-41 Sterilizer damage %s -> %s, gas buildup %s -> %.3f",
            REVISION, tostring(state.dmg_old), tostring(want_dmg), tostring(state.gas_old), want_gas))
    end
end

-- ---------------------------------------------------------------------------
-- 稳态: 按地址直读复查 + 重读 cfg(改了数值就立刻重打, 不用重开游戏)
-- ---------------------------------------------------------------------------
local function recheck()
    local cd, cg = read_cfg()
    if cd and cd ~= want_dmg then
        log(string.format("cfg changed: damage %d -> %d", want_dmg, cd))
        want_dmg = cd
    end
    if cg and cg ~= want_gas then
        log(string.format("cfg changed: gas %.3f -> %.3f", want_gas, cg))
        want_gas = cg
    end

    local changed = false
    local i = 1
    while i <= #state.copies do
        local c = state.copies[i]
        local cur = read_mem(c.rec, CONFIG.REC_SIZE)
        if cur == nil or not is_target_record(cur) then
            table.remove(state.copies, i); changed = true
        else
            local need_d = (u32_at(cur, CONFIG.OFF_DAMAGE) ~= want_dmg)
                        or (u32_at(cur, CONFIG.OFF_DURABLE) ~= want_dmg)
            local need_g = (not near(f32_at(cur, CONFIG.OFF_SE0_VALUE), want_gas, CONFIG.GAS_EPS))
                        or (not near(f32_at(cur, CONFIG.OFF_SE1_VALUE), want_gas, CONFIG.GAS_EPS))
            if need_d or need_g then
                log(string.format("copy @0x%X drift (damage=%d/%d, gas=%.3f/%.3f); re-applying",
                    c.rec, u32_at(cur, CONFIG.OFF_DAMAGE), want_dmg,
                    f32_at(cur, CONFIG.OFF_SE0_VALUE), want_gas))
                local ok = true
                if need_d then ok = write_damage(c.rec, want_dmg) end
                if ok and need_g then ok = write_gas(c.rec, want_gas) end
                if ok then
                    i = i + 1; changed = true
                else
                    table.remove(state.copies, i); changed = true
                end
            else
                i = i + 1
            end
        end
    end

    if #state.copies == 0 then
        log("all patched records gone (map/table reloaded); restarting search")
        state.done_blocks = {}
        state.enum_done = false
        state.enum_cursor = 0
        state.regions = nil
        state.ri = 1; state.off = 0; state.resume_frame = 0
        state.scan_stopped = false
        state.phase = "searching"
        set_status("SEARCHING - patched copies lost; rescanning")
        return
    end
    if changed then
        state.dmg_new = want_dmg
        state.gas_new = want_gas
        flush_status()
    end
end

-- ---------------------------------------------------------------------------
-- 主循环(单向收敛: init -> searching -> patched -> 休眠)
-- ---------------------------------------------------------------------------
local function tick()
    state.frames = state.frames + 1
    if state.phase == "init" then
        if not ffi_ok then
            ffi_ok = setup_ffi()
            if not ffi_ok then set_status("FAILED - FFI unavailable; cannot run"); state.phase = "dead"; return end
            proc_handle = C.GetCurrentProcess()
            register_self_pattern(SIG_LDLD)
        end
        if not float_codec_selftest() then
            set_status("FAILED - float codec self-test failed; refusing to run")
            state.phase = "dead"; return
        end
        local ok, msg = loader_gate()
        if not ok then set_status(msg); state.phase = "dead"; return end
        ensure_cfg()
        local cd, cg = read_cfg()
        if cd then want_dmg = cd end
        if cg then want_gas = cg end
        state.phase = "searching"
        log("addon started revision " .. REVISION .. "; loader API "
            .. tostring(state.loader_api) .. " v" .. tostring(state.loader_version)
            .. "; target damage=" .. tostring(want_dmg)
            .. " gas=" .. string.format("%.3f", want_gas))
        set_status("SEARCHING - starting scan (v" .. REVISION .. ")")
        return
    end
    if state.phase == "dead" then return end

    if state.phase == "searching" then
        if state.frames < CONFIG.START_DELAY then return end
        if state.frames % CONFIG.SCAN_EVERY ~= 0 then return end
        local ok, err = pcall(scan_pump, CONFIG.BUDGET_SEARCH)
        if not ok then log_err("scan error: " .. tostring(err)) end
        return
    end

    if state.phase == "patched" then
        if state.frames % CONFIG.STEADY_CADENCE ~= 0 then return end
        if not state.scan_stopped then
            local ok, err = pcall(scan_pump, CONFIG.BUDGET_SEARCH)
            if not ok then log_err("post-patch scan error: " .. tostring(err)) end
        end
        if state.frames >= state.next_recheck then
            state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
            local ok, err = pcall(recheck)
            if not ok then log_err("recheck error: " .. tostring(err)) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 挂 update 钩子(安全退钩: 只在自身仍是顶层 wrapper 时才还原)
-- ---------------------------------------------------------------------------
local original_update = update
if type(original_update) ~= "function" then original_update = function() end end
local my_update
my_update = function(...)
    if not state.retired then
        local ok, err = pcall(tick)
        if not ok then log_err("tick error: " .. tostring(err)) end
    end
    return original_update(...)
end
update = my_update
state.retire_hook = function()
    state.retired = true
    if update == my_update then update = original_update end
end

set_status("INIT - starting (loader gate pending)")
flush_log()
