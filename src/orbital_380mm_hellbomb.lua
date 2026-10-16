-- HD2-Addon: mods/hd2/orbital_380mm_hellbomb
-- ============================================================================
-- 轨道380MM高爆弹火力网 -> 地狱火炸弹(HELLBOMB)效果
-- Orbital 380MM HE Barrage -> Hellbomb explosion (every strike)
--
-- 效果: 轨道380MM高爆弹火力网的每一次打击, 爆炸都换成"地狱火炸弹"的爆炸
--       (核弹级弹坑 / 半径 17-25-45 / 专属火焰粒子 / 专属音效 / 同级伤害).
--
-- 原理(纯内存补丁, 禁用mod+Purge即可完全还原):
--   1. 扫描内存, 定位常驻的 ProjectileSettings(射弹表) 与 ExplosionSettings(爆炸表);
--   2. 运行时解析"地狱火爆炸"的 ExplosionType 枚举值 —— 用浮点半径三重指纹
--      (inner=17 / outer=25 / stagger=45, 核弹级) 在爆炸表里定位记录, 读其 +0 类型;
--      枚举下标随版本漂移(本构建 500kg 爆炸=193/277, 社区却是 117/168), 绝不写死;
--   3. 把"380mm HE CANNON ROUND"射弹(type 80/266, 即380mm火力网所用)的
--      explosion_type_on_impact(+144) 改写为地狱火爆炸.
--
-- 数据来源(离线核对: 游戏typelib + FileDiver明文镜像 + 社区JSON):
--   ProjectileInfo 272字节: +0 type, +4 name_upper, +144 explosion_type_on_impact,
--     +156 explosion_type_expire, +60 damage_info_type
--   ExplosionInfo 152字节: +0 type, +4 damage_type, +12 inner_radius, +16 outer_radius,
--     +20 stagger_radius, +40 particle_effect_path, +56 audio_event, +64 crater_type
--   380mm 火力网记录: num_bombs=3 num_salvos=5 projectile_types=(80,266,266)
--   ExplosionType_Hellbomb: inner=17 outer=25 stagger=45 crater=Nuke
--
-- 注意: "380mm HE CANNON ROUND"被 380mm火力网 与 行走火力网 共用, 故两者都会变地狱火.
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本addon只改内存, 不动磁盘文件.
-- ============================================================================

local MOD_NAME = "mods/hd2/orbital_380mm_hellbomb"
local REVISION = "1.0.1"
local SINGLETON = "_HD2_ORBITAL_380MM_HELLBOMB"

if rawget(_G, SINGLETON) then return end
rawset(_G, SINGLETON, true)

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------
local CONFIG = {
    TYPE_PROJECTILE = 0xBD4042C2,   -- djb2("ProjectileSettings")
    TYPE_EXPLOSION  = 0x2AEA2592,   -- djb2("ExplosionSettings")

    -- "380mm HE CANNON ROUND" 的本地化键哈希(校验目标射弹)
    NAME_380MM_UPPER = 2909856589,
    -- 380mm 火力网使用的射弹类型(离线数据; 打前用 name 校验, 对不上就不动)
    BARRAGE_380_TYPES = { 80, 266 },

    -- ProjectileInfo 字段偏移
    OFF_EXPL_IMPACT = 144,          -- explosion_type_on_impact
    OFF_NAME_UPPER  = 4,
    OFF_TYPE        = 0,

    -- ExplosionInfo 布局(FileDiver Go 源 + 当前构建 dl_bin 实测)
    --   记录在 payload+16 起, stride=152; (块 size 含尾部变长数组, 不能按 size/count 推 stride)
    EX_STRIDE = 152,
    EX_REC0 = 16,           -- payload 内第一条记录偏移(=descriptor 16)
    EX_OFF_TYPE = 0,
    EX_OFF_INNER = 16,
    EX_OFF_OUTER = 20,
    EX_OFF_STAGGER = 24,
    EX_OFF_PARTICLE = 56,   -- stingray.Hash [particles]
    EX_OFF_AUDIO = 64,      -- u32 资源哈希

    -- 地狱火爆炸指纹: 半径(核弹级) + 音频事件 + 粒子(资源哈希跨构建稳定)
    HB_INNER = 17.0,
    HB_OUTER = 25.0,
    HB_STAGGER = 45.0,
    HB_AUDIO = 1160336653,           -- 0x4529550D, 与社区 ExplosionType_Hellbomb 一致
    HB_PARTICLE_HEX = "4152B17F76EAE64F",   -- 0x4152B17F76EAE64F (stingray.Hash)

    -- 扫描参数
    START_DELAY = 120,
    CHUNK = 1048576,
    OVERLAP = 64,
    BUDGET_FAST = 0.006,
    BUDGET_SLOW = 0.002,
    PATCHED_PUMP_EVERY = 6,
    SELF_SKIP = 65536,
    REGION_MIN = 4096,
    RECHECK_EVERY = 300,

    LOG_DIR_ENV = "LOCALAPPDATA",
    LOG_SUBDIR = "/CowboyBingus/Helldivers2/Logs/",
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
    ri = 1, off = 0, pass = 0, bytes_scanned = 0,
    types_seen = {},
    proj_geom = nil,     -- {recbase=,count=,stride=}
    expl_geom = nil,
    hellbomb_type = nil,
    hellbomb_src = nil,
    copies = {},         -- {rec=,off_pt=,want=,kind=}
    scanned_sig = nil,

    next_recheck = 0,
}

-- ---------------------------------------------------------------------------
-- 日志/状态
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
    parts[#parts + 1] = string.format("scan_pass=%d region=%d/%s scanned_mb=%.1f",
        state.pass, state.ri, state.regions and #state.regions or "?",
        state.bytes_scanned / 1048576.0)
    parts[#parts + 1] = string.format("hellbomb_explosion_type=%s src=%s",
        tostring(state.hellbomb_type), tostring(state.hellbomb_src))
    parts[#parts + 1] = string.format("patched_records=%d", #state.copies)
    do
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
    for i = 1, #state.copies do
        local c = state.copies[i]
        parts[#parts + 1] = string.format("  copy%d: rec@0x%X off+%d", i, c.rec, c.off_pt)
    end
    parts[#parts + 1] = "effect: Orbital 380mm HE Barrage strikes explode like a Hellbomb"
    parts[#parts + 1] = "note: 380mm shells are SHARED with the Walking Barrage; both change. Host-side needed for damage"
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "orbital_380mm_hellbomb_STATUS.txt", "w")
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
        local f = io.open(dir .. "orbital_380mm_hellbomb.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_380MM_FLUSH = flush_log   -- 唯一名字, 不污染通用全局

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

-- "4152B17F76EAE64F" -> 8字节小端串(避免 64 位精度问题)
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

-- 单精度浮点 -> 4 字节小端(手写编码, 不用 pack/位运算)
local function f32_bytes(v)
    if v ~= v then return "\0\0\192\127" end          -- NaN
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

local function float_decoder_selftest()
    local cases = {
        { 0x3F800000, 1.0 }, { 0x3F000000, 0.5 }, { 0x41D80000, 27.0 },
        { 0x41880000, 17.0 }, { 0x41C80000, 25.0 }, { 0x42340000, 45.0 },
    }
    for i = 1, #cases do
        if bits_to_f32(cases[i][1]) ~= cases[i][2] then return false end
    end
    -- 编码自检
    if f32_bytes(17.0) ~= u32_le(0x41880000) then return false end
    if f32_bytes(45.0) ~= u32_le(0x42340000) then return false end
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
local MEM_IMAGE = 0x1000000
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
local process_hit
local end_pass

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
            state.regions[#state.regions + 1] = { base = base, size = rsize, image = (mtype == MEM_IMAGE) }
        end
        addr = base + rsize
        n = n + 1
        if n >= 4000 or os.clock() > budget then break end
    end
    if addr >= 0x7FFFFFFFFFF000 then state.enum_done = true end
    state.enum_cursor = addr
    if state.enum_done then
        local nimg = 0
        for i = 1, #state.regions do if state.regions[i].image then nimg = nimg + 1 end end
        table.sort(state.regions, function(a, b)
            if a.image ~= b.image then return (not a.image) end
            return a.size > b.size
        end)
        log(string.format("region enum done: %d regions (%d data-first, %d image last)",
            #state.regions, #state.regions - nimg, nimg))
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
                    if th == CONFIG.TYPE_PROJECTILE or th == CONFIG.TYPE_EXPLOSION then
                        process_hit({ addr = addr, type = th, size = size })
                    end
                end
            end
        end
        init = p + 1
    end
end

local function scan_pump(budget)
    if not state.enum_done then enum_regions_step(); return end
    if #state.regions == 0 then enum_regions_step(); return end
    local deadline = os.clock() + budget
    while os.clock() < deadline do
        if state.ri > #state.regions then
            state.ri = 1
            state.pass = state.pass + 1
            end_pass()
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
-- 通用: 由 LDLD 块头取 {recbase,count,stride}
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

-- 在爆炸表里定位地狱火爆炸(音频事件 + 粒子哈希 + 核弹级半径 三重指纹)
local function resolve_hellbomb(blk)
    local desc = read_mem(blk.addr + 24, 16)
    if not desc then return false end
    local count = u64_at(desc, 8)
    if count < 1 or count > 200000 then return false end
    local payload = read_mem(blk.addr + 24, blk.size)   -- 含 descriptor + 全部记录
    if not payload then return false end
    state.expl_geom = { count = count, stride = CONFIG.EX_STRIDE }

    local hb_part = hex_to_le_bytes(CONFIG.HB_PARTICLE_HEX)
    local hits = {}
    local limit = count
    if limit > 8000 then limit = 8000 end
    for k = 0, limit - 1 do
        local o = CONFIG.EX_REC0 + k * CONFIG.EX_STRIDE
        if o + CONFIG.EX_STRIDE > #payload then break end
        local o_audio = o + CONFIG.EX_OFF_AUDIO
        local o_part = o + CONFIG.EX_OFF_PARTICLE
        if u32_at(payload, o_audio) == CONFIG.HB_AUDIO
           and string.sub(payload, o_part + 1, o_part + 8) == hb_part then
            local inner = f32_at(payload, o + CONFIG.EX_OFF_INNER)
            local outer = f32_at(payload, o + CONFIG.EX_OFF_OUTER)
            local stag = f32_at(payload, o + CONFIG.EX_OFF_STAGGER)
            hits[#hits + 1] = { type = u32_at(payload, o + CONFIG.EX_OFF_TYPE), idx = k,
                inner = inner, outer = outer, stagger = stag }
        end
    end
    if #hits == 0 then
        log_err(string.format("hellbomb not found in explosion table@0x%X (count=%d); audio/particle mismatch",
            blk.addr, count))
        return false
    end
    state.hellbomb_type = hits[1].type
    state.hellbomb_src = string.format("block@0x%X idx#%d audio=%d radii=%.0f/%.0f/%.0f (%d cand)",
        blk.addr, hits[1].idx, CONFIG.HB_AUDIO, hits[1].inner, hits[1].outer, hits[1].stagger, #hits)
    log("resolved Hellbomb ExplosionType = " .. state.hellbomb_type .. " via " .. state.hellbomb_src)
    return true
end

-- 记录射弹表
local function record_projectile_table(blk)
    if state.proj_geom then return end
    local t = read_table(blk)
    if t then state.proj_geom = t end
end

-- 打补丁: 把 380mm 火力网射弹的 explosion_type_on_impact 改为地狱火
local function patch_380()
    if not state.hellbomb_type or not state.proj_geom then return end
    local t = state.proj_geom
    local data = read_mem(t.recbase, t.count * t.stride)
    if not data then return end
    local want = u32_le(state.hellbomb_type)
    for ti = 1, #CONFIG.BARRAGE_380_TYPES do
        local want_type = CONFIG.BARRAGE_380_TYPES[ti]
        for k = 0, t.count - 1 do
            local off = k * t.stride
            if u32_at(data, off + CONFIG.OFF_TYPE) == want_type then
                local nu = u32_at(data, off + CONFIG.OFF_NAME_UPPER)
                local rec_addr = t.recbase + off
                if nu ~= CONFIG.NAME_380MM_UPPER then
                    log_err(string.format("proj type %d name_upper=%d != 380mm(%d); skip",
                        want_type, nu, CONFIG.NAME_380MM_UPPER))
                    break
                end
                local already = false
                for ci = 1, #state.copies do
                    if state.copies[ci].rec == rec_addr then already = true end
                end
                if not already then
                    local cur = read_mem(rec_addr + CONFIG.OFF_EXPL_IMPACT, 4)
                    if cur == want then
                        state.copies[#state.copies + 1] = {
                            rec = rec_addr, off_pt = CONFIG.OFF_EXPL_IMPACT, want = want, kind = "expl" }
                    elseif write_mem(rec_addr + CONFIG.OFF_EXPL_IMPACT, want) then
                        local back = read_mem(rec_addr + CONFIG.OFF_EXPL_IMPACT, 4)
                        if back == want then
                            state.copies[#state.copies + 1] = {
                                rec = rec_addr, off_pt = CONFIG.OFF_EXPL_IMPACT, want = want, kind = "expl" }
                            log(string.format("PATCHED 380mm projectile type %d @0x%X explosion->Hellbomb(%d)",
                                want_type, rec_addr, state.hellbomb_type))
                        else
                            log_err(string.format("read-back mismatch @0x%X", rec_addr + CONFIG.OFF_EXPL_IMPACT))
                        end
                    else
                        log_err(string.format("write failed @0x%X", rec_addr + CONFIG.OFF_EXPL_IMPACT))
                    end
                end
                break
            end
        end
    end
    if #state.copies > 0 and state.phase ~= "patched" then
        state.phase = "patched"
        state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
        set_status("OK - patch applied (revision " .. REVISION
            .. "): Orbital 380mm HE Barrage strikes now explode like Hellbombs")
    end
end

function process_hit(h)
    if h.type == CONFIG.TYPE_EXPLOSION then
        if not state.hellbomb_type then resolve_hellbomb(h) end
        if state.hellbomb_type then patch_380() end
    else
        record_projectile_table(h)
        patch_380()
    end
end

function end_pass()
    if state.pass <= 3 or state.pass % 20 == 0 then
        log(string.format("pass %d done: scanned %.1f MB, %d copies, hellbomb=%s",
            state.pass, state.bytes_scanned / 1048576.0, #state.copies,
            tostring(state.hellbomb_type)))
        local ts = {}
        for th, c in pairs(state.types_seen) do
            ts[#ts + 1] = string.format("0x%08X x%d", th, c)
        end
        if #ts > 0 then log("LDLD types seen: " .. table.concat(ts, ", ")) end
    end
    if state.phase ~= "patched" then flush_status() end
end

-- ---------------------------------------------------------------------------
-- 稳态
-- ---------------------------------------------------------------------------
local function recheck()
    local changed = false
    local i = 1
    while i <= #state.copies do
        local c = state.copies[i]
        local cur = read_mem(c.rec + c.off_pt, #c.want)
        if cur == nil then
            table.remove(state.copies, i); changed = true
        elseif cur ~= c.want then
            log(string.format("copy @0x%X lost its patch; re-applying", c.rec + c.off_pt))
            if write_mem(c.rec + c.off_pt, c.want) then
                local back = read_mem(c.rec + c.off_pt, #c.want)
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
        log("all patched records gone; restarting search")
        state.phase = "searching"
        set_status("SEARCHING - all copies lost; rescanning")
    elseif changed then
        flush_status()
    end
end

-- ---------------------------------------------------------------------------
-- 主循环
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
        if not float_decoder_selftest() then
            set_status("FAILED - float codec self-test failed; refusing to run")
            state.phase = "dead"; return
        end
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
        local ok, err = pcall(scan_pump, CONFIG.BUDGET_FAST)
        if not ok then log_err("scan error: " .. tostring(err)) end
        if state.frames % 300 == 0 then flush_status() end
        return
    end
    if state.phase == "patched" then
        if state.frames >= state.next_recheck then
            state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
            local ok, err = pcall(recheck)
            if not ok then log_err("recheck error: " .. tostring(err)) end
        end
        if state.frames % CONFIG.PATCHED_PUMP_EVERY == 0 then
            local ok, err = pcall(scan_pump, CONFIG.BUDGET_SLOW)
            if not ok then log_err("maint scan error: " .. tostring(err)) end
        end
        if state.frames % 600 == 0 then flush_status() end
    end
end

-- ---------------------------------------------------------------------------
-- 挂 update 钩子
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
