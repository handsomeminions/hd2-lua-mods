-- HD2-Addon: mods/hd2/mortar_sentry_napalm
-- ============================================================================
-- A/M-12 迫击哨戒炮(Mortar Sentry) 的炮弹 -> 落地爆炸改成 轨道凝固汽油弹
-- A/M-12 Mortar Sentry shell -> Orbital Napalm Barrage single-bomb impact effect
--
-- 效果(用户的明确要求):
--   * 【只改爆炸】迫击哨戒炮每一发炮弹**落地炸开**时, 用"轨道凝固汽油弹火力网"里
--     单颗凝固汽油弹的打击效果(爆炸粒子/火焰/弹坑/音效/伤害 全部换成那一套;
--     含 FireTemplate_Large —— 落地留下一片燃烧的凝固汽油)。
--   * 【其余全部保持原版迫击炮】索敌/瞄准、飞行轨迹、飞行速度、重力、引信、
--     弹体模型、拖尾粒子、飞行音效、直接命中伤害 —— 一个字节都不动。
--
-- 原理(纯内存补丁; 禁用 mod + Purge 即完全还原, 不改任何磁盘文件):
--   1. 扫描内存, 定位常驻的 ProjectileSettings(射弹表, LDLD 类型哈希 0xBD4042C2);
--   2. 在表里按"跨构建稳定"的指纹(本地化键哈希 + 物理量 + 64位资源哈希)定位两条记录:
--        - 目标: A/M-12 迫击炮炮弹 (name_upper=900451699 "40mm HE MORTAR"
--                + 口径360 + 初速100 + 质量70000 + 拖尾粒子哈希 + 尾迹音频)
--                ⚠ 仅凭 name_upper 会命中 4 条(含机器人迫击炮壳), 必须带物理量才唯一
--        - 源:   轨道凝固汽油弹火力网 的凝固汽油弹壳
--                (口径84 + 质量5000 + 拖尾粒子哈希 + 尾迹音频)
--   3. **只改写一个字段**: 目标记录的 +144 `explosion_type_on_impact`
--      <- 源记录的 +144 (运行时读出来, 绝不写死枚举值).
--
--   **"其余一律不动"的硬保证**: 写入前用 KEEP_FIELDS 逐段核对"这些字段在新内容里
--   与原文逐字节相同", 任一不同就拒绝写入并记错误 —— 覆盖 身份/口径/初速/质量/阻力/重力/
--   寿命/伤害类型/推进粒子/拖尾粒子/弹体模型/爆炸角度/近炸/延迟/引信/解保距离/
--   贴花/落点音效 等 22 段。写完后还再确认"爆炸字段确实取自源", 并做读回校验。
--
-- 关键数值(离线三方交叉核对: 游戏 typelib + FileDiver 明文镜像 + 社区 JSON;
--          字段偏移都做过全表复现验证, 命中率 ~100%):
--   ProjectileInfo 大小 272 字节; 字段偏移:
--     +0 type  +4 name_upper  +8 name_cased  +12 short_name  +16 hud_icon(u64)
--     +24 calibre  +32 speed  +36 mass  +40 drag  +44 gravity  +52 life_time
--     +60 damage_info_type  +72 particle_thruster(u64)  +88 thruster_length
--     +96 particle_trail(u64)  +128 projectile_unit_path(u64)
--     +136 explosion_threshold_angle  +144 explosion_type_on_impact  +148 explosion_proximity
--     +152 explosion_delay  +156 explosion_type_expire  +160 arming_distance
--     +164 decal_size  +168 surface_impact_type  +208/+212 audio_trail_start/stop
--   目标(A/M-12 炮弹, 本构建 type=346): 原用 ExplosionType_Grenade_Mortar_40mm_HE (半径 3/9/13)
--   源  (凝固汽油弹壳, 本构建 type=234): 用 ExplosionType_Orbital_Napalm (半径 3.3/10/11, FireTemplate_Large)
--
--   ※ "轨道凝固汽油弹火力网"同时用 Orbital_Napalm 与 Orbital_Napalm_Cheap 两种弹药,
--     但这两条爆炸记录在表里**逐字段完全相同**(只有 type 与 surface_impact_type 不同),
--     观感与伤害一致, 故取哪一条都等价; 本 addon 直接取"汽油弹壳自己那一颗"。
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存.
-- ============================================================================

local MOD_NAME = "mods/hd2/mortar_sentry_napalm"
local REVISION = "1.0.1"
local SINGLETON = "_HD2_MORTAR_SENTRY_NAPALM"

if rawget(_G, SINGLETON) then return end
rawset(_G, SINGLETON, true)

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------
local CONFIG = {
    TYPE_PROJECTILE = 0xBD4042C2,   -- djb2("ProjectileSettings")

    -- ProjectileInfo 字段偏移
    OFF_TYPE        = 0,
    OFF_NAME_UPPER  = 4,
    OFF_NAME_CASED  = 8,
    OFF_CAL         = 24,
    OFF_SPEED       = 32,
    OFF_MASS        = 36,
    OFF_DRAG        = 40,
    OFF_GRAV        = 44,
    OFF_LIFE        = 52,
    OFF_DMG         = 60,
    OFF_TRAIL       = 96,
    OFF_UNIT        = 128,
    OFF_EXPL_IMPACT = 144,
    OFF_EXPL_PROX   = 148,
    OFF_EXPL_EXPIRE = 156,
    OFF_AUDIO_START = 208,

    -- 目标: A/M-12 迫击哨戒炮炮弹
    TGT_NAME_UPPER = 900451699,          -- "40mm HE MORTAR" (注意: 同名 4 条, 必须配合物理量)
    TGT_TRAIL_HEX  = "7E7C55538A04ACFD", -- 0x7E7C55538A04ACFD = 9114253563177250045 (u64 拖尾粒子资源哈希)
    TGT_AUDIO      = 3053896360,         -- 0xB606C2A8 尾迹音频资源哈希
    TGT_CAL        = 360.0,
    TGT_SPEED      = 100.0,
    TGT_MASS       = 70000.0,

    -- 源: 轨道凝固汽油弹火力网的凝固汽油弹壳
    SRC_TRAIL_HEX  = "68358A1CC55AFDDB", -- 0x68358A1CC55AFDDB = 7509059809884962267
    SRC_AUDIO      = 808888556,          -- 0x3036A8EC
    SRC_CAL        = 84.0,
    SRC_MASS       = 5000.0,

    REC_SIZE = 272,

    -- 扫描参数(温和: 小步长 + 硬时间预算 + 空手退避; 打完即休眠)
    START_DELAY    = 120,
    CHUNK          = 262144,        -- 256 KB
    OVERLAP        = 64,
    BUDGET_SEARCH  = 0.002,         -- 每帧最多 2ms CPU
    SCAN_EVERY     = 2,             -- 搜索期每 2 帧推进一步
    STEADY_CADENCE = 60,            -- 稳态每 60 帧(约1秒)唤醒一次
    RECHECK_EVERY  = 300,           -- 每 5 秒按地址直读复查
    SELF_SKIP      = 65536,
    REGION_MIN     = 4096,

    LOG_DIR_ENV = "LOCALAPPDATA",
    LOG_SUBDIR  = "/CowboyBingus/Helldivers2/Logs/",
}

-- 要改写的字段(本 mod 只有一个)
local PATCH_FIELDS = {
    { off = 144, len = 4, name = "explosion_type_on_impact" },
}

-- "其余一律不动"的硬保证: 写入前核对这几段在新内容里与原文**逐字节相同**.
-- 覆盖: 身份(类型/名称/图标) + 弹道(口径/初速/质量/阻力/重力/寿命/爆炸角度/近炸/延迟/引信/解保)
--       + 飞行观感(推进粒子/拖尾粒子/弹体模型/贴花) + 直接命中伤害 + 落点音效
local KEEP_FIELDS = {
    { 0, 4 },   { 4, 4 },   { 8, 4 },   { 12, 4 },  { 16, 8 },   -- 身份
    { 24, 4 },  { 28, 4 },  { 32, 4 },  { 36, 4 },  { 40, 4 },  -- 口径/弹数/初速/质量/阻力
    { 44, 4 },  { 48, 4 },  { 52, 4 },  { 56, 4 },  { 60, 4 },  -- 重力/仿真步/寿命/寿命抖动/伤害类型
    { 64, 4 },  { 68, 4 },  { 72, 8 },  { 80, 8 },  { 88, 4 },  -- 穿透/推进粒子/低弹药粒子/推进长度
    { 92, 4 },  { 96, 8 },  { 104, 8 }, { 112, 8 }, { 120, 8 }, -- 消散/拖尾/解体/命中提示
    { 128, 8 }, { 136, 4 },                                     -- 弹体模型/爆炸角度
    { 148, 4 }, { 152, 4 }, { 156, 4 }, { 160, 4 }, { 164, 4 }, { 168, 4 }, -- 爆炸其余参数(不含144)
    { 208, 4 }, { 212, 4 },                                     -- 飞行音效起/止
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
    source_type = nil,
    source_desc = nil,
    expl_old = nil,
    expl_new = nil,
    copies = {},

    next_recheck = 0,
}

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
    parts[#parts + 1] = string.format("target(mortar sentry shell) type=%s | source(napalm shell) type=%s",
        tostring(state.target_type), tostring(state.source_type))
    if state.source_desc then parts[#parts + 1] = "source_src=" .. state.source_desc end
    if state.expl_new then
        parts[#parts + 1] = string.format("impact_explosion=%s->%s (Orbital Napalm)",
            tostring(state.expl_old), tostring(state.expl_new))
        parts[#parts + 1] = "flight(targeting/arc/speed)_preserved=true  visuals_preserved=true"
    end
    parts[#parts + 1] = string.format("patched_records=%d", #state.copies)
    for i = 1, #state.copies do
        local c = state.copies[i]
        parts[#parts + 1] = string.format("  copy%d: rec@0x%X idx=%d", i, c.rec, c.idx)
    end
    parts[#parts + 1] = "effect: A/M-12 Mortar Sentry shells now burst with the Orbital Napalm bomb effect on impact"
    parts[#parts + 1] = "note: targeting/flight/speed/model/trail all stay vanilla; damage is host-authoritative"
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "mortar_sentry_napalm_STATUS.txt", "w")
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
        local f = io.open(dir .. "mortar_sentry_napalm.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_MORTAR_NAPALM_FLUSH = flush_log   -- 唯一名字, 不与其它 addon 冲突

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

-- 8 字节 -> 大端十六进制串(不经过 Lua number, 避免 53 位精度截断)
local function hex8_be(s, off)
    local t = {}
    for i = 8, 1, -1 do
        t[#t + 1] = string.format("%02X", string.byte(s, off + i) or 0)
    end
    return table.concat(t)
end

-- "82E4BA7BDCBB1B9F" -> 8 字节小端串(不经过 Lua number)
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

local function f32_bytes(v)
    if v ~= v then return "\0\0\192\127" end
    local sign = 0
    if v < 0 then sign = 2147483648; v = -v end
    if v == 0 then return u32_le(sign) end
    local exp = 127
    while v >= 2 do v = v / 2; exp = exp + 1 end
    while v < 1 do v = v * 2; exp = exp - 1 end
    local mant = math.floor((v - 1) * 8388608 + 0.5)
    if mant >= 8388608 then mant = 0; exp = exp + 1 end
    return u32_le(sign + exp * 8388608 + mant)
end

local function float_codec_selftest()
    local cases = {
        { 0x3F800000, 1.0 }, { 0x3F000000, 0.5 }, { 0x41D80000, 27.0 },
        { 0x42A80000, 84.0 }, { 0x43B40000, 360.0 }, { 0x42C80000, 100.0 },
        { 0x4788B800, 70000.0 }, { 0x459C4000, 5000.0 },
    }
    for i = 1, #cases do
        if bits_to_f32(cases[i][1]) ~= cases[i][2] then return false end
    end
    if f32_bytes(360.0) ~= u32_le(0x43B40000) then return false end
    if f32_bytes(0.25) ~= u32_le(0x3E800000) then return false end
    return true
end

local function near(v, want, tol)
    local d = v - want
    if d < 0 then d = -d end
    return d <= tol
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
local process_proj_block

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
                    if th == CONFIG.TYPE_PROJECTILE then
                        local ok, err = pcall(process_proj_block, { addr = addr, type = th, size = size })
                        if not ok then log_err("proj block error: " .. tostring(err)) end
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
            log(string.format("pass %d done: scanned %.1f MB, target=%s source=%s copies=%d",
                state.pass, state.bytes_scanned / 1048576.0,
                tostring(state.target_type), tostring(state.source_type), #state.copies))
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
-- 表解析
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
-- 记录指纹
-- ---------------------------------------------------------------------------
local tgt_trail, src_trail

local function is_target_record(r)
    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.TGT_NAME_UPPER
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0)
       and string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) == tgt_trail
       and u32_at(r, CONFIG.OFF_AUDIO_START) == CONFIG.TGT_AUDIO
end

local function is_source_record(r)
    return string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) == src_trail
       and u32_at(r, CONFIG.OFF_AUDIO_START) == CONFIG.SRC_AUDIO
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.SRC_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.SRC_MASS, 1.0)
end

-- ---------------------------------------------------------------------------
-- 打补丁: 只把目标记录的 +144 换成源的 +144
-- ---------------------------------------------------------------------------
local function build_patched(cur, src)
    local out = cur
    for i = 1, #PATCH_FIELDS do
        local f = PATCH_FIELDS[i]
        out = string.sub(out, 1, f.off)
           .. string.sub(src, f.off + 1, f.off + f.len)
           .. string.sub(out, f.off + f.len + 1)
    end
    return out
end

-- 硬保证: KEEP_FIELDS 里每一段都必须与原文**逐字节相同**
local function keep_guard_ok(cur, new)
    for i = 1, #KEEP_FIELDS do
        local g = KEEP_FIELDS[i]
        if string.sub(cur, g[1] + 1, g[1] + g[2]) ~= string.sub(new, g[1] + 1, g[1] + g[2]) then
            return false
        end
    end
    return true
end

-- 确认"该改的确实改了"
local function patch_applied_ok(new, src)
    return string.sub(new, CONFIG.OFF_EXPL_IMPACT + 1, CONFIG.OFF_EXPL_IMPACT + 4)
        == string.sub(src, CONFIG.OFF_EXPL_IMPACT + 1, CONFIG.OFF_EXPL_IMPACT + 4)
end

local function patch_into_table(blk, t, data)
    if t.stride ~= CONFIG.REC_SIZE then
        log_err(string.format("unexpected stride %d at 0x%X (want %d)", t.stride, blk.addr, CONFIG.REC_SIZE))
        return false
    end
    local tgt_idx, src_idx = nil, nil
    for k = 0, t.count - 1 do
        local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
        if is_target_record(r) then tgt_idx = k; break end
    end
    if tgt_idx == nil then return false end
    for k = 0, t.count - 1 do
        if k ~= tgt_idx then
            local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
            if is_source_record(r) then src_idx = k; break end
        end
    end
    if src_idx == nil then
        log_err(string.format("target found (idx %d) but napalm shell source missing in table@0x%X",
            tgt_idx, blk.addr))
        return false
    end

    local tgt_addr = t.recbase + tgt_idx * t.stride
    local src_rec = string.sub(data, src_idx * t.stride + 1, (src_idx + 1) * t.stride)
    local cur = read_mem(tgt_addr, t.stride)
    if not cur then
        log_err(string.format("cannot read target record @0x%X", tgt_addr))
        return false
    end
    local new = build_patched(cur, src_rec)
    if not keep_guard_ok(cur, new) then
        log_err(string.format("keep-guard failed @0x%X: a preserved field would change; refusing", tgt_addr))
        return false
    end
    if not patch_applied_ok(new, src_rec) then
        log_err(string.format("field patch incomplete @0x%X: explosion not taken from source; refusing", tgt_addr))
        return false
    end
    if state.target_type == nil then
        state.target_type = u32_at(cur, CONFIG.OFF_TYPE)
        state.source_type = u32_at(src_rec, CONFIG.OFF_TYPE)
        state.expl_old = u32_at(cur, CONFIG.OFF_EXPL_IMPACT)
        state.expl_new = u32_at(new, CONFIG.OFF_EXPL_IMPACT)
        state.source_desc = string.format(
            "cal=%.0f spd=%.0f mass=%.0f trail=%s audio=%d (idx %d)",
            f32_at(src_rec, CONFIG.OFF_CAL), f32_at(src_rec, CONFIG.OFF_SPEED),
            f32_at(src_rec, CONFIG.OFF_MASS),
            hex8_be(src_rec, CONFIG.OFF_TRAIL), u32_at(src_rec, CONFIG.OFF_AUDIO_START), src_idx)
    end
    local is_already = (cur == new)
    if not is_already then
        if not write_mem(tgt_addr, new) then
            log_err(string.format("write failed @0x%X", tgt_addr))
            return false
        end
        local back = read_mem(tgt_addr, t.stride)
        if back ~= new then
            log_err(string.format("read-back mismatch @0x%X", tgt_addr))
            return false
        end
    end
    local seen = false
    for i = 1, #state.copies do if state.copies[i].rec == tgt_addr then seen = true end end
    if not seen then
        state.copies[#state.copies + 1] = { rec = tgt_addr, want = new, idx = tgt_idx, blk = blk.addr }
    end
    log(string.format("%s mortar sentry shell @0x%X (idx %d, type %s): impact explosion %s->%s (Orbital Napalm); targeting/flight/visuals untouched [src idx %d]",
        is_already and "ALREADY" or "PATCHED", tgt_addr, tgt_idx, tostring(state.target_type),
        tostring(state.expl_old), tostring(state.expl_new), src_idx))
    state.done_blocks[blk.addr] = true
    return true
end

function process_proj_block(h)
    if state.done_blocks[h.addr] then return end
    local t = read_table(h)
    if not t then return end
    local data = read_mem(t.recbase, t.count * t.stride)
    if not data then return end
    local ok = patch_into_table(h, t, data)
    if ok and state.phase ~= "patched" then
        state.phase = "patched"
        state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
        set_status("OK - patch applied (revision " .. REVISION
            .. "): Mortar Sentry shells now burst with the Orbital Napalm effect on impact")
    end
end

-- ---------------------------------------------------------------------------
-- 稳态: 按已记录的地址直读复查
-- ---------------------------------------------------------------------------
local function recheck()
    local changed = false
    local i = 1
    while i <= #state.copies do
        local c = state.copies[i]
        local cur = read_mem(c.rec, #c.want)
        if cur == nil then
            table.remove(state.copies, i); changed = true
        elseif cur ~= c.want then
            log(string.format("copy @0x%X lost its patch; re-applying", c.rec))
            if write_mem(c.rec, c.want) then
                local back = read_mem(c.rec, #c.want)
                if back ~= c.want then table.remove(state.copies, i); changed = true
                else i = i + 1 end
            else
                table.remove(state.copies, i); changed = true
            end
        else
            i = i + 1
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
    elseif changed then
        flush_status()
    end
end

-- ---------------------------------------------------------------------------
-- 主循环(单向收敛)
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
        tgt_trail = hex_to_le_bytes(CONFIG.TGT_TRAIL_HEX)
        src_trail = hex_to_le_bytes(CONFIG.SRC_TRAIL_HEX)
        local ok, msg = loader_gate()
        if not ok then set_status(msg); state.phase = "dead"; return end
        state.phase = "searching"
        log("addon started revision " .. REVISION .. "; loader API "
            .. tostring(state.loader_api) .. " v" .. tostring(state.loader_version))
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
        -- 打完补丁后, 仍把"当前这一轮"扫完 —— 保证内存里所有副本都被打到;
        -- 一轮结束后由 scan_pump 置 scan_stopped, 从此彻底停扫(不掉帧).
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
-- 挂 update 钩子(安全退钩)
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
