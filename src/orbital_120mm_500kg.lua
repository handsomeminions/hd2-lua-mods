-- HD2-Addon: mods/hd2/orbital_120mm_500kg
-- ============================================================================
-- 轨道120MM高爆弹火力网 -> 落地爆炸换成 飞鹰500kg炸弹 的爆炸
-- Orbital 120MM HE Barrage -> impact explosion becomes the Eagle 500kg blast
--
-- 效果(用户的明确要求, v1.3.0):
--   * 【只改爆炸】120MM 火力网每一发炮弹**落地炸开**时, 用飞鹰500kg炸弹的爆炸:
--     爆炸粒子/火焰/弹坑/音效/伤害/范围 全部换成 500kg 那一套(半径 10/25/35, 专属大爆炸);
--   * 【弹道保持原版120mm】索敌/发射、飞行轨迹、飞行速度(400)、重力、阻力、寿命、
--     爆炸角度/近炸/引信、弹体模型、拖尾粒子、飞行音效 —— 一个字节都不动。
--
-- ★ v1.3.0 修正的历史问题:
--   v1.2.x 用"整条记录克隆"把 120mm 炮弹整体换成 500kg 炸弹, 连带把**飞行参数**
--   (速度 400->500 / 质量 5000->500 / 阻力 0->0.5 / 引信延时 0->0.8)也换了,
--   导致打击弹道/落点与原版 120mm 不一致(用户实测: 会打出原版范围)。
--   本版改为"精准字段改写": 只替换**爆炸配置**字段, 飞行/攻击/观感一律保留原版。
--
-- 原理(纯内存补丁; 禁用 mod + Purge 即完全还原, 不改任何磁盘文件):
--   1. 扫描内存, 定位常驻的 ProjectileSettings(射弹表, LDLD 类型哈希 0xBD4042C2);
--   2. 在表里按"跨构建稳定"的指纹定位记录:
--        - 目标: 120MM 火力网炮弹 (两条) ——
--                name_upper = 2683992244("120mm HE CANNON ROUND")
--              + audio_trail_event_stop = 3741852184
--                ※ 这是**决定性指纹**: 全表 350 条里只有这两条枪用这个尾迹终止音效;
--                  同名的"凝固汽油弹火力网"炮弹用 4159288355, 因此天然区分开,
--                  **不需要写死任何枚举下标**。
--              + 物理量(口径84/初速400/质量5000)与拖尾粒子哈希作附加保险。
--        - 源: 飞鹰500kg炸弹 —— name_upper = 1027666422("500KG BOMB")
--              + 口径50/初速500/质量500。
--   3. 只把目标记录的这 4 段**爆炸配置字段**整段替换为源记录的同段字节
--      (运行时读出, 绝不写死枚举值):
--        +60  damage_info_type          (直接命中伤害类型)
--        +144 explosion_type_on_impact  (命中爆炸 = 500kg 的主爆炸)
--        +152 explosion_delay           (引信延时)
--        +156 explosion_type_expire     (主爆炸 = 500kg 的招牌大爆炸, 半径 10/25/35)
--
--   **"其余一律不动"的硬保证**: 写入前逐**字节**核对"除上面 4 段以外, 新内容与原文
--   完全相同", 任一不同就拒绝写入并记错误 —— 从机制上保证弹道/模型/速度/拖尾
--   绝不被改。写完后再确认"这 4 段确实取自源", 并做回读校验。
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
--   本构建实测(350 条记录):
--     目标 120mm HE 火力网炮弹: type 194 -> imp=213 / type 137 -> imp=176,
--        两者 dmg=262, delay=0, expire=0, 速度400/质量5000 (半径 3.3/10/11)
--     源   飞鹰500kg:            type 239, dmg=251, imp=193(小起爆), delay=0.8, expire=277
--        其中 277 = 500kg 招牌大爆炸(半径 10/25/35, 专属粒子/音效/弹坑/伤害)
--   => 打完后, 120mm 炮弹拥有与 500kg 炸弹**逐字节相同**的爆炸配置,
--      因此落地爆炸表现与飞鹰500kg完全一致(含那 0.8s 引信: 小起爆 -> 主爆).
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存, 不动磁盘文件.
-- ============================================================================

local MOD_NAME = "mods/hd2/orbital_120mm_500kg"
local REVISION = "1.3.0"
local SINGLETON = "_HD2_ORBITAL_120MM_500KG"

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
    OFF_THR_ANGLE   = 136,
    OFF_EXPL_IMPACT = 144,
    OFF_EXPL_PROX   = 148,
    OFF_EXPL_DELAY  = 152,
    OFF_EXPL_EXPIRE = 156,
    OFF_ARMING      = 160,
    OFF_AUDIO_START = 208,
    OFF_AUDIO_STOP  = 212,

    -- 目标: 轨道120MM高爆弹火力网的炮弹 (两条)
    TGT_NAME_UPPER = 2683992244,          -- "120mm HE CANNON ROUND"
    TGT_AUDIO_STOP = 3741852184,          -- 决定性指纹(全表唯一对应这两条; 凝固汽油弹=4159288355)
    TGT_CAL        = 84.0,
    TGT_SPEED      = 400.0,
    TGT_MASS       = 5000.0,
    TGT_TRAIL_HEX  = "68358A1CC55AFDDB",  -- u64 拖尾粒子哈希(HE 与凝固汽油弹共用, 仅作附加保险)

    -- 源: 飞鹰500kg炸弹
    SRC_NAME_UPPER = 1027666422,          -- "500KG BOMB"
    SRC_CAL        = 50.0,
    SRC_SPEED      = 500.0,
    SRC_MASS       = 500.0,

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

-- 要改写的字段(本 mod 只有这 4 段 = "爆炸配置")
local SWAP_FIELDS = {
    { off = 60,  len = 4, name = "damage_info_type" },
    { off = 144, len = 4, name = "explosion_type_on_impact" },
    { off = 152, len = 4, name = "explosion_delay" },
    { off = 156, len = 4, name = "explosion_type_expire" },
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

    target_types = nil,      -- 已命中的目标类型(日志用)
    source_type = nil,
    source_desc = nil,
    copies = {},             -- {rec=, want=, idx=, type=, blk=}

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
    parts[#parts + 1] = string.format("target(120mm HE barrage shell) type=%s | source(500kg bomb) type=%s",
        tostring(state.target_types), tostring(state.source_type))
    if state.source_desc then parts[#parts + 1] = "source_src=" .. state.source_desc end
    parts[#parts + 1] = string.format("patched_records=%d", #state.copies)
    for i = 1, #state.copies do
        local c = state.copies[i]
        parts[#parts + 1] = string.format(
            "  copy%d: rec@0x%X idx=%d type=%s | impact_explosion=%s->%s expire=%s->%s delay=%.2f->%.2f",
            i, c.rec, c.idx, tostring(c.type),
            tostring(c.old_imp), tostring(c.new_imp),
            tostring(c.old_exp), tostring(c.new_exp),
            c.old_delay or 0, c.new_delay or 0)
    end
    if #state.copies > 0 then
        local c = state.copies[1]
        parts[#parts + 1] = string.format("impact_explosion=%s->%s (Eagle 500kg)",
            tostring(c.old_imp), tostring(c.new_imp))
        parts[#parts + 1] = string.format("main_explosion=%s->%s (Eagle 500kg big blast)",
            tostring(c.old_exp), tostring(c.new_exp))
        parts[#parts + 1] = string.format("fuse_delay=%.2f->%.2f", c.old_delay or 0, c.new_delay or 0)
        parts[#parts + 1] = "flight(trajectory/arc/speed/range)_preserved=true  visuals(model/trail/sound)_preserved=true"
    end
    parts[#parts + 1] = "effect: 120mm HE Barrage shells keep vanilla 120mm flight and now burst with the Eagle 500kg explosion"
    parts[#parts + 1] = "note: trajectory/attack/model/flight-sound all stay vanilla; damage is host-authoritative"
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "orbital_120mm_500kg_STATUS.txt", "w")
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
        local f = io.open(dir .. "orbital_120mm_500kg.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_120MM_FLUSH = flush_log   -- 唯一名字, 不与其它 addon 冲突

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

-- "68358A1CC55AFDDB" -> 8 字节小端串(不经过 Lua number)
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
        { 0x42A80000, 84.0 }, { 0x43B40000, 360.0 }, { 0x43C80000, 400.0 },
        { 0x4788B800, 70000.0 }, { 0x459C4000, 5000.0 }, { 0x3F800000, 1.0 },
    }
    for i = 1, #cases do
        if bits_to_f32(cases[i][1]) ~= cases[i][2] then return false end
    end
    if f32_bytes(400.0) ~= u32_le(0x43C80000) then return false end
    if f32_bytes(0.8) ~= u32_le(0x3F4CCCCD) then return false end
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
            log(string.format("pass %d done: scanned %.1f MB, targets=%s source=%s copies=%d",
                state.pass, state.bytes_scanned / 1048576.0,
                tostring(state.target_types), tostring(state.source_type), #state.copies))
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
local tgt_trail

local function is_target_record(r)
    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.TGT_NAME_UPPER
       and u32_at(r, CONFIG.OFF_AUDIO_STOP) == CONFIG.TGT_AUDIO_STOP
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0)
       and string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) == tgt_trail
end

local function is_source_record(r)
    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.SRC_NAME_UPPER
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.SRC_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.SRC_SPEED, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.SRC_MASS, 1.0)
end

-- ---------------------------------------------------------------------------
-- 打补丁: 只把目标的 4 段"爆炸配置"换成源的
-- ---------------------------------------------------------------------------
local function is_swapped_off(o)   -- o: 0-based 字节下标
    for i = 1, #SWAP_FIELDS do
        local f = SWAP_FIELDS[i]
        if o >= f.off and o < f.off + f.len then return true end
    end
    return false
end

local function build_swapped(cur, src)
    local out = cur
    for i = 1, #SWAP_FIELDS do
        local f = SWAP_FIELDS[i]
        out = string.sub(out, 1, f.off)
           .. string.sub(src, f.off + 1, f.off + f.len)
           .. string.sub(out, f.off + f.len + 1)
    end
    return out
end

-- 硬保证: 除内 SWAP_FIELDS 覆盖的字节外, 新内容必须与原文**逐字节相同**
local function keep_guard_ok(cur, new)
    if #cur ~= #new then return false end
    for o = 0, #cur - 1 do
        if not is_swapped_off(o) then
            if string.byte(cur, o + 1) ~= string.byte(new, o + 1) then return false end
        end
    end
    return true
end

-- 确认"该改的确实改了"(这几段必须取自源)
local function applied_ok(new, src)
    for i = 1, #SWAP_FIELDS do
        local f = SWAP_FIELDS[i]
        if string.sub(new, f.off + 1, f.off + f.len) ~= string.sub(src, f.off + 1, f.off + f.len) then
            return false
        end
    end
    return true
end

local function patch_into_table(blk, t, data)
    if t.stride ~= CONFIG.REC_SIZE then
        log_err(string.format("unexpected stride %d at 0x%X (want %d)", t.stride, blk.addr, CONFIG.REC_SIZE))
        return false
    end

    -- 找源(500kg)
    local src_idx = nil
    for k = 0, t.count - 1 do
        local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
        if is_source_record(r) then src_idx = k; break end
    end

    -- 找全部目标(120mm HE 火力网炮弹, 通常两条)
    local tgt_idxs = {}
    for k = 0, t.count - 1 do
        local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
        if is_target_record(r) then tgt_idxs[#tgt_idxs + 1] = k end
    end
    if #tgt_idxs == 0 then return false end
    if src_idx == nil then
        log_err(string.format("target(s) found (%d) but 500kg bomb source missing in table@0x%X",
            #tgt_idxs, blk.addr))
        return false
    end

    local src_rec = string.sub(data, src_idx * t.stride + 1, (src_idx + 1) * t.stride)
    if state.source_type == nil then
        state.source_type = u32_at(src_rec, CONFIG.OFF_TYPE)
        state.source_desc = string.format(
            "mass=%.0f cal=%.0f speed=%.0f (idx %d)",
            f32_at(src_rec, CONFIG.OFF_MASS), f32_at(src_rec, CONFIG.OFF_CAL),
            f32_at(src_rec, CONFIG.OFF_SPEED), src_idx)
    end

    local any = false
    for ti = 1, #tgt_idxs do
        local tgt_idx = tgt_idxs[ti]
        local tgt_addr = t.recbase + tgt_idx * t.stride
        local cur = read_mem(tgt_addr, t.stride)
        if not cur then
            log_err(string.format("cannot read target record @0x%X", tgt_addr))
        else
            local new = build_swapped(cur, src_rec)
            if not keep_guard_ok(cur, new) then
                log_err(string.format(
                    "keep-guard failed @0x%X: a flight/visual field would change; refusing (bad offsets?)",
                    tgt_addr))
            elseif not applied_ok(new, src_rec) then
                log_err(string.format(
                    "explosion patch incomplete @0x%X: not taken from source; refusing", tgt_addr))
            else
                local is_already = (cur == new)
                local wrote = true
                if not is_already then
                    if not write_mem(tgt_addr, new) then
                        log_err(string.format("write failed @0x%X", tgt_addr))
                        wrote = false
                    else
                        local back = read_mem(tgt_addr, t.stride)
                        if back ~= new then
                            log_err(string.format("read-back mismatch @0x%X", tgt_addr))
                            wrote = false
                        end
                    end
                end
                if wrote then
                    local seen = false
                    for i = 1, #state.copies do
                        if state.copies[i].rec == tgt_addr then seen = true end
                    end
                    if not seen then
                        local ttype = u32_at(cur, CONFIG.OFF_TYPE)
                        state.copies[#state.copies + 1] = {
                            rec = tgt_addr, want = new, idx = tgt_idx, type = ttype, blk = blk.addr,
                            old_imp = u32_at(cur, CONFIG.OFF_EXPL_IMPACT),
                            new_imp = u32_at(new, CONFIG.OFF_EXPL_IMPACT),
                            old_exp = u32_at(cur, CONFIG.OFF_EXPL_EXPIRE),
                            new_exp = u32_at(new, CONFIG.OFF_EXPL_EXPIRE),
                            old_delay = f32_at(cur, CONFIG.OFF_EXPL_DELAY),
                            new_delay = f32_at(new, CONFIG.OFF_EXPL_DELAY),
                        }
                        state.target_types = (state.target_types and (state.target_types .. ",") or "")
                            .. tostring(ttype)
                    end
                    log(string.format(
                        "%s 120mm HE barrage shell @0x%X (idx %d, type %s): impact expl %s->%s, main expl %s->%s, fuse %s->%s (Eagle 500kg); flight/model/speed untouched [src idx %d]",
                        is_already and "ALREADY" or "PATCHED", tgt_addr, tgt_idx, tostring(u32_at(cur, CONFIG.OFF_TYPE)),
                        tostring(u32_at(cur, CONFIG.OFF_EXPL_IMPACT)), tostring(u32_at(new, CONFIG.OFF_EXPL_IMPACT)),
                        tostring(u32_at(cur, CONFIG.OFF_EXPL_EXPIRE)), tostring(u32_at(new, CONFIG.OFF_EXPL_EXPIRE)),
                        tostring(f32_at(cur, CONFIG.OFF_EXPL_DELAY)), tostring(f32_at(new, CONFIG.OFF_EXPL_DELAY)),
                        src_idx))
                    any = true
                end
            end
        end
    end
    if any then state.done_blocks[blk.addr] = true end
    return any
end

function process_proj_block(h)
    if state.done_blocks[h.addr] then return end
    local t = read_table(h)
    if not t then return end
    local data = read_mem(t.recbase, t.count * t.stride)
    if not data then return end
    local ok = patch_into_table(h, t, data)
    if ok then
        if state.phase ~= "patched" then
            state.phase = "patched"
            state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
            set_status("OK - patch applied (revision " .. REVISION
                .. "): 120mm HE Barrage keeps vanilla flight, now bursts with the Eagle 500kg explosion")
        else
            flush_status()   -- 后续新增的副本也要立刻反映到 STATUS
        end
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
        log("all patched records gone (table reloaded); restarting search")
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
        -- 打完补丁后, 仍把"当前这一轮"扫完, 保证内存里所有副本都被打到; 一轮结束后彻底停扫.
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
