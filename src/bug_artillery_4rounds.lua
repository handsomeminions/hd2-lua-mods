-- HD2-Addon: mods/hd2/bug_artillery_4rounds
-- ============================================================================
-- 胆汁喷涌虫(Bile Spewer / Nursing Spewer) 一次齐射 -> 每方向 2 枚 (= 4 团)
-- Bile Spewer artillery: 2 bile mortars per shot (= 4 per salvo)
--
-- ★ 本 mod 是 `mods/hd2/bug_artillery_6rounds`(每发 3 枚 = 6 团) 的**低配姊妹版**:
--   逻辑一字不差, 只把默认"每次开火枚数"改成 2 => 2 × 2 次齐射 = **4 团**。
--   ★★ **两个 mod 只能启用一个**(它们在管理器里是两个独立条目)。若两个都被加载,
--      本 addon 会检测到 6 发版并**自动让位**(不扫描、不写入), 避免两边每 5 秒互抢同一条记录。
--
-- 原理(纯内存补丁; 禁用 mod + Purge 即完全还原, 不改任何磁盘文件):
--   1. 扫内存定位常驻的 ProjectileSettings(LDLD 类型哈希 0xBD4042C2);
--   2. 在表里按"跨构建稳定"的指纹定位**胆汁迫击炮射弹** ProjectileType_Bug_Artillery:
--        无名(name_upper==0, name_cased==0) + 口径50 + 初速30 + 质量1000
--        + 推进粒子哈希 758CA9293725AFE2 + 拖尾粒子哈希 29354B9DC32A52AC
--        + 尾迹音频 3340293219
--      (与空爆 mod 完全相同的定位法 —— 那个定位法已在实机跑通)
--   3. **只改写一个字段**:
--        +28 u32 num_projectiles   (ProjectileInfo 里"一次开火生成几枚射弹")
--        霰弹枪就是靠这个字段一次打出 9~20 颗弹丸(它们的弹匣是 Uniform, 不是 Pattern),
--        所以它对普通射弹同样生效。
--      本构建原版 = 1; 本 mod 设 **2**。
--   4. 其余字节一律逐字节 keep-guard。
--
-- 为什么是"每开火 N 枚"而不是"改齐射次数":
--   实机观察(两次): 原版一次齐射吐 **2 团**; 原版 num_projectiles = 1。
--   ⇒ 说明敌人一次齐射会**开火 2 次**, 每次 1 枚, 每次独立瞄准 => 得到 2 个方向。
--   ⇒ 把"每次开火枚数"设成 2 就得到 2 × 2 = **4 团**(2 个方向, 每个方向 2 枚)。
--
--   ★ 注意: 同一次开火里的多枚是**同向**的(引擎对 num_projectiles 的多枚不做方向分散,
--     霰弹枪的散布来自武器侧参数, 射弹表里没有该参数 —— 已逐字段核对过)。
--     本 mod **改不到开火次数**(那张表不加载), 所以"分散方向数"固定 = 2;
--     能调的只有"每方向几枚"。
--
-- ★ 数值可在**游戏运行时**改, 不用重新打包:
--   日志目录里有个 `bug_artillery_4rounds.cfg`, 里面就一个数字 = 每次开火几枚。
--   改完保存, mod 会在 ~5 秒内自动重打, 下一轮齐射立刻见效。
--   (想要 6 团就把这个数字改成 3; 想回到原版 2 团就改成 1。)
--
-- 关键偏移(游戏 typelib 权威 ProjectileInfo, size=272):
--   +0 type(u32)   +4 name_upper  +8 name_cased  +12 short_name  +16 hud_icon(u64)
--   +24 calibre(f32)   +28 num_projectiles(u32)  <- 【本 mod 唯一改写项】
--   +32 speed  +36 mass  +40 drag  +44 gravity  +48 simulation_steps  +52/+56 float
--   +60 damage_info_type  +72 particle_thruster(u64)  +96 particle_trail(u64)
--   +144 explosion_type_on_impact  +148 proximity  +152 delay  +156 expire
--   +208/+212 audio_trail_start/stop  +240 flags
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存.
-- ============================================================================

local MOD_NAME = "mods/hd2/bug_artillery_4rounds"
local REVISION = "1.0.0"
local SINGLETON = "_HD2_BUG_ARTILLERY_4ROUNDS"

if rawget(_G, SINGLETON) then return end
rawset(_G, SINGLETON, true)

-- ★ 与"6 发版"(mods/hd2/bug_artillery_6rounds, 每发 3 枚)互斥:
--   两个 addon 改的是**同一条射弹记录里的同一个字段**(+28), 同时启用会每 5 秒互抢。
--   所以只要检测到 6 发版在跑, 本 addon 就让位(不扫描、不写入)。
local RIVAL_SINGLETON = "_HD2_BUG_ARTILLERY_6ROUNDS"
local function rival_present()
    return rawget(_G, RIVAL_SINGLETON) ~= nil
end

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------
local CONFIG = {
    TYPE_PROJECTILE = 0xBD4042C2,       -- djb2("ProjectileSettings")

    -- ProjectileInfo 字段偏移
    OFF_TYPE          = 0,
    OFF_NAME_UPPER    = 4,
    OFF_NAME_CASED    = 8,
    OFF_CAL           = 24,
    OFF_NUM_PROJ      = 28,             -- u32 num_projectiles  <- 唯一改写项
    OFF_SPEED         = 32,
    OFF_MASS          = 36,
    OFF_THRUSTER      = 72,
    OFF_TRAIL         = 96,
    OFF_AUDIO_START   = 208,

    -- 目标(胆汁迫击炮射弹)指纹 —— 与空爆 mod 使用的定位法一致(实机已验证)
    TGT_TRAIL_HEX = "29354B9DC32A52AC",
    TGT_THR_HEX   = "758CA9293725AFE2",
    TGT_AUDIO     = 3340293219,
    -- ★ 飞行音效可能已被"空爆 mod"换成火箭的(+208/+212) —— 两种都算命中,
    --   否则两个 mod 同装时本 addon 会认不出自己的目标(实测踩过)。
    SRC_AUDIO     = 1680798988,
    TGT_CAL       = 50.0,
    TGT_SPEED     = 30.0,
    TGT_MASS      = 1000.0,

    -- 每次开火生成几枚(默认值; 运行时会被 cfg 文件覆盖)
    --   原版 = 1; 原版一次齐射 = 开火 2 次(实机确认) => 设 2 得到 2 × 2 = 4 团。
    --   ★ 同一次开火的 2 枚是同向的(射弹表里没有"发射散布"参数); 本 mod 改不到开火次数,
    --     所以"方向数"固定 2, 能调的只有"每方向几枚"。
    PROJ_PER_SHOT_DEFAULT = 2,
    PROJ_MIN = 1,
    PROJ_MAX = 20,

    REC_SIZE = 272,

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

    CFG_NAME    = "bug_artillery_4rounds.cfg",
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
    proj_old = nil,          -- 原版 num_projectiles
    proj_new = nil,          -- 当前生效值
    copies = {},             -- {rec=, want=, idx=, blk=}

    next_recheck = 0,
}

-- 要写入的"每次开火枚数"(来自 cfg 文件; 没有就取默认)
local want_proj = CONFIG.PROJ_PER_SHOT_DEFAULT

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

-- 读 cfg(只认第一个 1..20 的整数); 文件不存在/内容非法 -> 返回 nil
local function read_cfg()
    local dir = env_dir()
    if not dir then return nil end
    local ok, f = pcall(io.open, dir .. CONFIG.CFG_NAME, "r")
    if not ok or not f then return nil end
    local txt = f:read("*a") or ""
    f:close()
    local n = tonumber(string.match(txt, "(%d+)"))
    if n and n >= CONFIG.PROJ_MIN and n <= CONFIG.PROJ_MAX then return n end
    return nil
end

-- 首次运行时把默认值写出来, 让用户知道有这个开关
local function ensure_cfg()
    local dir = env_dir()
    if not dir then return end
    local ok, f = pcall(io.open, dir .. CONFIG.CFG_NAME, "r")
    if ok and f then f:close(); return end
    local ok2, w = pcall(io.open, dir .. CONFIG.CFG_NAME, "w")
    if ok2 and w then
        w:write(tostring(CONFIG.PROJ_PER_SHOT_DEFAULT) .. "\n")
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
    parts[#parts + 1] = string.format("target(bug artillery projectile) type=%s", tostring(state.target_type))
    parts[#parts + 1] = string.format("projectiles_per_shot=%s->%s (vanilla 1 per shot)",
        tostring(state.proj_old), tostring(want_proj))
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
    parts[#parts + 1] = "effect: Bile Spewer fires N bile mortars per shot; vanilla lobs ONE per shot."
    parts[#parts + 1] = "        vanilla salvo = 2 shots (2 directions); 2/shot => 4 mortars in 2 directions."
    parts[#parts + 1] = "        Targeting / flight / arc / shape / sound / impact explosion are UNCHANGED."
    parts[#parts + 1] = string.format("tune: edit %s (one number, 1-20) and save;", CONFIG.CFG_NAME)
    parts[#parts + 1] = "      it re-applies within ~5s, no repack/restart. expected salvo = value x 2."
    parts[#parts + 1] = "      not 4?  2 -> put 2 (gives 4) ;  3 -> put 3 (gives 6) ;  4 -> put 4 (gives 8)."
    parts[#parts + 1] = "note: damage is host-authoritative; host needs this mod for real damage to count"
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "bug_artillery_4rounds_STATUS.txt", "w")
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
        local f = io.open(dir .. "bug_artillery_4rounds.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_BUG4R_FLUSH = flush_log   -- 唯一名字, 不与其它 addon 的全局函数冲突

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

local function near(v, want, tol)
    local d = v - want
    if d < 0 then d = -d end
    return d <= tol
end

local function float_codec_selftest()
    local cases = {
        { 0x3F800000, 1.0 }, { 0x3F000000, 0.5 }, { 0x42480000, 50.0 },
        { 0x41F00000, 30.0 }, { 0x447A0000, 1000.0 },
    }
    for i = 1, #cases do
        if bits_to_f32(cases[i][1]) ~= cases[i][2] then return false end
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
local tgt_trail, tgt_thr

-- 胆汁迫击炮射弹的身份指纹(与空爆 mod 一致, 已在实机跑通)
local function is_target_record(r)
    if u32_at(r, CONFIG.OFF_NAME_UPPER) ~= 0 then return false end
    if u32_at(r, CONFIG.OFF_NAME_CASED) ~= 0 then return false end
    if not near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5) then return false end
    if not near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5) then return false end
    if not near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0) then return false end
    if string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) ~= tgt_trail then return false end
    if string.sub(r, CONFIG.OFF_THRUSTER + 1, CONFIG.OFF_THRUSTER + 8) ~= tgt_thr then return false end
    local au = u32_at(r, CONFIG.OFF_AUDIO_START)
    if au ~= CONFIG.TGT_AUDIO and au ~= CONFIG.SRC_AUDIO then return false end
    return true
end

-- 只把 +28 换成 want值(其余逐字节不动)
-- ★ 与空爆 mod 共存的关键: 我们**只写 4 个字节**(+28..+31), 绝不整条回写 ——
--   否则空爆 mod 改在同一记录上的 +144/+152/+240/+208/+212 会被我们覆盖掉。

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

-- 把某条记录 +28 写成 want值(只写 4 字节), 成功返回 true
local function write_num_proj(rec_addr, cur, n)
    if not write_mem(rec_addr + CONFIG.OFF_NUM_PROJ, u32_le(n)) then
        log_err(string.format("write failed @0x%X (+%d)", rec_addr, CONFIG.OFF_NUM_PROJ))
        return false
    end
    local back = read_mem(rec_addr, CONFIG.REC_SIZE)
    if back == nil or u32_at(back, CONFIG.OFF_NUM_PROJ) ~= n then
        log_err(string.format("read-back mismatch @0x%X", rec_addr))
        return false
    end
    return true
end

local function patch_into_table(blk, t, data)
    if t.stride ~= CONFIG.REC_SIZE then
        log_err(string.format("unexpected stride %d at 0x%X (want %d)", t.stride, blk.addr, CONFIG.REC_SIZE))
        return false
    end
    local tgt_idx = nil
    for k = 0, t.count - 1 do
        local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
        if is_target_record(r) then tgt_idx = k; break end
    end
    if tgt_idx == nil then return false end

    local tgt_addr = t.recbase + tgt_idx * t.stride
    local cur = read_mem(tgt_addr, t.stride)
    if not cur then
        log_err(string.format("cannot read target record @0x%X", tgt_addr))
        return false
    end
    if not is_target_record(cur) then
        log_err(string.format("record @0x%X no longer matches the bile-mortar fingerprint; refusing", tgt_addr))
        return false
    end
    local cur_n = u32_at(cur, CONFIG.OFF_NUM_PROJ)
    if cur_n < CONFIG.PROJ_MIN or cur_n > CONFIG.PROJ_MAX then
        log_err(string.format("num_projectiles=%d out of range @0x%X; refusing", cur_n, tgt_addr))
        return false
    end

    local already = (cur_n == want_proj)
    local ok_done = already
    if not already then
        ok_done = write_num_proj(tgt_addr, cur, want_proj)
    end
    if not ok_done then return false end

    register_copy(tgt_addr, tgt_idx)
    if state.target_type == nil then
        state.target_type = u32_at(cur, CONFIG.OFF_TYPE)
        state.proj_old = cur_n
        state.proj_new = want_proj
    end
    log(string.format("%s bug artillery @0x%X (idx %d, type %s): num_projectiles %d -> %d (mortars per shot)",
        already and "ALREADY" or "PATCHED", tgt_addr, tgt_idx, tostring(state.target_type),
        cur_n, want_proj))
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
        set_status(string.format(
            "OK - patch applied (revision %s): Bile Spewer now spawns %d bile mortars per shot (vanilla 1); expected salvo = %d (2 directions)",
            REVISION, want_proj, want_proj * 2))
    end
end

-- ---------------------------------------------------------------------------
-- 稳态: 按地址直读复查 + 重读 cfg(改了数值就立刻重打, 不用重开游戏)
-- ---------------------------------------------------------------------------
local function recheck()
    if rival_present() then
        set_status("SKIPPED - mods/hd2/bug_artillery_6rounds appeared; yielding to it")
        log("rival addon appeared (bug_artillery_6rounds); yielding")
        state.phase = "dead"
        return
    end
    local cfg = read_cfg()
    if cfg and cfg ~= want_proj then
        log(string.format("cfg changed: per-shot %d -> %d", want_proj, cfg))
        want_proj = cfg
    end

    local changed = false
    local i = 1
    while i <= #state.copies do
        local c = state.copies[i]
        local cur = read_mem(c.rec, CONFIG.REC_SIZE)
        if cur == nil or not is_target_record(cur) then
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
        state.proj_new = want_proj
        flush_status()
    end
end

-- ---------------------------------------------------------------------------
-- 主循环(单向收敛: init -> searching -> patched -> 休眠)
-- ---------------------------------------------------------------------------
local function tick()
    state.frames = state.frames + 1
    if state.phase == "init" then
        if rival_present() then
            ensure_cfg()
            set_status("SKIPPED - mods/hd2/bug_artillery_6rounds is also loaded; enable only ONE bile-salvo mod (this one = 2 per shot / 4 mortars)")
            log("rival addon present (bug_artillery_6rounds); yielding, no scan, no write")
            state.phase = "dead"
            return
        end
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
        tgt_thr   = hex_to_le_bytes(CONFIG.TGT_THR_HEX)
        local ok, msg = loader_gate()
        if not ok then set_status(msg); state.phase = "dead"; return end
        ensure_cfg()
        local cfg = read_cfg()
        if cfg then want_proj = cfg end
        state.phase = "searching"
        log("addon started revision " .. REVISION .. "; loader API "
            .. tostring(state.loader_api) .. " v" .. tostring(state.loader_version)
            .. "; per-shot=" .. tostring(want_proj))
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
