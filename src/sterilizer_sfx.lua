-- HD2-Addon: mods/hd2/sterilizer_sfx
-- ============================================================================
-- TX-41 灭菌器(Sterilizer) 开火音效 -> 换成更明显的喷射音效   【实验性 mod】
-- TX-41 Sterilizer: swap the weak-ish firing SFX for a punchier spray SFX
--
-- 用户需求: "把灭菌器的音效放大, 达到那种'明显喷气'的效果, 现在的声音不明显且软绵绵的"
--
-- ★ 先说清楚: "把原声放大"这件事 **数据层做不到**。链路如下(每一步都有证据):
--   1. 灭菌器的开火音效由武器组件里的三个"状态音效"决定:
--        SprayWeaponComponent -> SprayWeaponStateInfo[3]  (warmup / firing / cooldown)
--          warmup.audio_event_start   = 3435018303
--          firing.audio_event_start   = 1773671782   <- 这就是"喷气声"(要换掉的值)
--          firing.audio_event_stop    =  599097114
--          firing.callout_event_start =  418315309
--          cooldown.audio_event_start = 1928837757
--          SprayWeaponComponent.audio_node = 1803865503
--       (数据来自离线明文 entities/SprayWeaponComponentData.json —— 14 个实例逐一核对)
--   2. 这段数据属于 `SprayWeaponComponentData` 表(**ComponentData 家族**), 而
--      **实机全内存 LDLD 普查**(用户自己的日志 docs/ingame-2026-10-13/)显示:
--      内存里常驻的 37 张表**全是 `*Settings` 家族**(StatusEffectSettings / DamageSettings /
--      ProjectileSettings / ExplosionSettings / StratagemSettings / ...), **没有任何 `*ComponentData`**;
--      SprayWeaponComponentData 的类型哈希 `0x8E551126` **一次都没出现**。
--   3. 而且"音量"本身**不在任何数据字段里** —— 它编在 Wwise SoundBank 音频资源里。
--      (HD2 音效 mod 的正路是 `hd2-audio-modder` + Wwise 重新编码 `.wem`, 属于**资源替换**,
--       不是内存补丁 —— 本项目不产出那种包。)
--   => 结论: 想"放大原声"只能换资源; 内存能做的**最多是"换一个音效事件"**。
--
-- ★ 本 addon 做的事(实验性; 用户拍板"先试这条路"):
--   在**整个进程内存**里找"灭菌器武器组件"的字节特征, 把 firing 的
--   `audio_event_start`(原版 1773671782) 改写成**另一个更明显的喷射音效事件**
--   (默认 335829265 = 敌方化学无人机的喷毒音效, 调性最接近; 可用 cfg 热调)。
--
--   ⚠ 为什么这可能不成功(必须知道):
--     LDLD 普查只能发现"数据表", 发现不了"运行时实例的裸数据"。若游戏根本没把
--     firing.audio_event_start 留在内存里(例如播放时直接从只读映射取值),
--     则本 addon 会**一个候选都找不到** —— STATUS 会明确写 "no candidate found"。
--     那种情况下唯一出路是音频资源替换(见上)。
--
--   ★ 判据(避免误伤别的音效): 只有**命中值周围 ±256 字节内还出现至少一个"同组件佐证值"**
--     时才认账 —— 佐证 = 同一 SprayWeaponComponent / SprayWeaponStateInfo 里的其它音效事件:
--       { 599097114, 418315309, 1803865503, 3435018303, 1928837757, 3956223216 }
--     多个独立 Wwise 事件哈希共现是极强的信号(随机碰撞概率可忽略);
--     孤立出现的 1773671782 一律**跳过不改**(宁可漏, 不可错)。
--
--   ★ 只写 4 个字节: 命中地址处的 u32 -> 目标事件; 写完立即回读校验。
--     绝不整块回写(keep-guard)。
--
-- ★ 目标事件可在游戏运行时调, 不用重新打包:
--   日志目录里的 `sterilizer_sfx.cfg`:
--       event=335829265     # 要换成的音效事件(默认 = 敌方化学无人机喷毒音效)
--   改完保存, ~5 秒内自动重打。想试别的见同目录 README 的候选表。
--   填 1773671782 = 等于不改(恢复原版行为), 用来对照 A/B。
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存.
-- ============================================================================

local MOD_NAME = "mods/hd2/sterilizer_sfx"
local REVISION = "1.0.0"
local SINGLETON = "_HD2_STERILIZER_SFX"

if rawget(_G, SINGLETON) then return end
rawset(_G, SINGLETON, true)

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------
local CONFIG = {
    -- 目标: 灭菌器(TX-41) 开火状态(firing) 的音效事件
    EVENT_OLD     = 1773671782,   -- 原版 firing.audio_event_start (要替换掉的那个值)
    EVENT_DEFAULT = 335829265,    -- 默认换成: 敌方化学无人机(Drone_Chem_Gun) 的喷毒音效
    EVENT_MIN     = 1,
    EVENT_MAX     = 4294967295,

    -- ★ 佐证值: 与目标同处一个 SprayWeaponComponent / SprayWeaponStateInfo 的其它音效事件。
    --   命中 EVENT_OLD 后, 只有在同一窗口内**至少再出现 MIN_CORROB 个**才认账。
    --   多个独立 Wwise 事件哈希共现 -> 碰撞概率可忽略; 孤立命中一律跳过(宁可漏, 不可错)。
    CORROB = {
        599097114,      -- firing.audio_event_stop
        418315309,      -- firing.callout_event_start
        1803865503,     -- SprayWeaponComponent.audio_node
        3435018303,     -- warmup.audio_event_start
        1928837757,     -- cooldown.audio_event_start
        3956223216,     -- SprayWeaponComponent.last_drop_owner_vo_event
    },
    WIN        = 256,    -- 佐证窗口半径(字节)
    MIN_CORROB = 1,      -- 至少要几个佐证才认账

    -- 64 位佐证(用 lo/hi 两个 u32 写, 避开 Lua 的 float 精度问题):
    --   firing.muzzle_effect = 0xA3D15A3BBC56DE55
    --   ★ 这个值在本构建 SprayWeaponComponentData 的 14 个实例里**只属于灭菌器**,
    --     而且与 firing.audio_event_start 同处一个 56B 的 SprayWeaponStateInfo 里 -> 极强佐证。
    CORROB_U64 = {
        { 3159809621, 2748406331 },   -- 0xA3D15A3BBC56DE55  firing.muzzle_effect
    },

    -- 扫描参数(温和: 小步长 + 硬时间预算 + 空手退避; 打完即休眠)
    START_DELAY    = 120,
    CHUNK          = 262144,            -- 256 KB
    OVERLAP        = 1024,              -- 必须 > 2*WIN, 保证跨块的窗口不被截断
    BUDGET_SEARCH  = 0.002,             -- 每帧最多 2ms CPU
    SCAN_EVERY     = 2,                 -- 搜索期每 2 帧推进一步
    STEADY_CADENCE = 60,                -- 稳态每 60 帧(约1秒)唤醒一次
    RECHECK_EVERY  = 300,               -- 每 5 秒按地址直读复查 + 重读 cfg
    SELF_SKIP      = 65536,
    REGION_MIN     = 4096,

    CFG_NAME    = "sterilizer_sfx.cfg",
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

    hits = 0,                -- 通过佐证的候选数
    lone_hits = 0,           -- 命中过值但没佐证 -> 被跳过的次数
    rewrites = 0,            -- 稳态重写次数(游戏把值重置回去就会涨)
    first_addr = nil,        -- 第一个命中的地址(给 STATUS 看)
    copies = {},             -- { addr = , corrob = }

    next_recheck = 0,
}

-- 要写入的目标事件值(来自 cfg 文件; 没有就取默认)
local want_event = CONFIG.EVENT_DEFAULT

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

-- 读 cfg。返回目标事件值(整数); 缺失/非法 -> nil(用默认)。
--   写法: event=335829265     (也接受"整个文件里第一个裸数字"的简写)
local function read_cfg()
    local dir = env_dir()
    if not dir then return nil end
    local ok, f = pcall(io.open, dir .. CONFIG.CFG_NAME, "r")
    if not ok or not f then return nil end
    local txt = f:read("*a") or ""
    f:close()

    local v = nil
    for line in string.gmatch(txt, "[^\r\n]+") do
        if not string.match(line, "^%s*#") then          -- 跳过注释行
            local ev = string.match(line, "event%s*[=:]%s*(%d+)")
            if ev then v = tonumber(ev) end
        end
    end
    if v == nil then
        v = tonumber(string.match(txt, "(%d+)"))         -- 简写: 第一个裸数字
    end
    if v ~= nil and (v < CONFIG.EVENT_MIN or v > CONFIG.EVENT_MAX) then v = nil end
    return v
end

-- 首次运行时把默认值(带候选注释)写出来, 让用户知道能试什么
local function ensure_cfg()
    local dir = env_dir()
    if not dir then return end
    local ok, f = pcall(io.open, dir .. CONFIG.CFG_NAME, "r")
    if ok and f then f:close(); return end
    local ok2, w = pcall(io.open, dir .. CONFIG.CFG_NAME, "w")
    if ok2 and w then
        w:write("# TX-41 Sterilizer firing-SFX swap -- edit & save; re-applied within ~5s, no restart\n")
        w:write("# event : Wwise event played while FIRING (vanilla = 1773671782)\n")
        w:write("#   335829265  = enemy chem drone spray      <-- default\n")
        w:write("#   1881104745 = FLAM-40 flamethrower\n")
        w:write("#   3757506625 = flamethrower pistol\n")
        w:write("#   2970598254 = Crisper / Ripley flamer\n")
        w:write("#   1773671782 = vanilla sterilizer (A/B control, = no change)\n")
        w:write(string.format("event=%d\n", CONFIG.EVENT_DEFAULT))
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
    parts[#parts + 1] = string.format("looking_for=sterilizer FIRING audio_event_start (%d)", CONFIG.EVENT_OLD)
    parts[#parts + 1] = string.format("swap_to=%d (cfg-overridable)", want_event)
    parts[#parts + 1] = string.format("hits=%d  lone_hits_skipped=%d  rewrites=%d",
        state.hits, state.lone_hits, state.rewrites)
    if state.first_addr then
        parts[#parts + 1] = string.format("first_hit=0x%X", state.first_addr)
    end
    parts[#parts + 1] = string.format("patched_copies=%d", #state.copies)
    for i = 1, #state.copies do
        local c = state.copies[i]
        parts[#parts + 1] = string.format("  copy%d: @0x%X corrob=%d", i, c.addr, c.corrob)
    end
    if state.phase ~= "patched" then
        parts[#parts + 1] = "result: NO verified sterilizer weapon component found in memory yet."
        parts[#parts + 1] = "        (the game may not keep this data resident - see README)"
    end
    parts[#parts + 1] = "effect: while FIRING, the sterilizer plays the swapped Wwise event instead of"
    parts[#parts + 1] = "        its vanilla spray sound. Only 4 bytes are written per hit."
    parts[#parts + 1] = "scope: sterilizer only (matched by the co-located event-hash signature;"
    parts[#parts + 1] = "       a bare 1773671782 with no corroborating hash is never touched)."
    parts[#parts + 1] = "limit: the ORIGINAL sound cannot be amplified from memory - loudness lives"
    parts[#parts + 1] = "       inside the Wwise soundbank asset, not in any data field."
    parts[#parts + 1] = string.format("tune: edit %s (event=<id>) and save;", CONFIG.CFG_NAME)
    parts[#parts + 1] = "      1773671782 = vanilla (A/B control), 1881104745 = FLAM-40 flamethrower."
    parts[#parts + 1] = "note: SFX is client-side and purely local - nothing here is host-authoritative."
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "sterilizer_sfx_STATUS.txt", "w")
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
        local f = io.open(dir .. "sterilizer_sfx.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_STERILIZER_SFX_FLUSH = flush_log   -- 唯一名字, 不与其它 addon 的全局函数冲突

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
local old_pat = nil          -- u32_le(EVENT_OLD) 的 4 字节串
local corrob_pats = {}       -- 各个佐证值的 4 字节串
local process_hit            -- 前向声明(下面再赋值, 绝不带 local)

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

-- 数一数 sub 里出现了几个佐证值
local function corrob_in(sub)
    local n = 0
    for i = 1, #corrob_pats do
        if string.find(sub, corrob_pats[i], 1, true) then n = n + 1 end
    end
    return n
end

-- 在 256KB 块里找 EVENT_OLD; 命中且**窗口内佐证达标**才交给 process_hit。
-- 窗口跨块的情形交给下一块的重叠区(OVERLAP > 2*WIN)处理, 保证不漏。
local function scan_one_chunk(region_base, off, len)
    local data = read_mem(region_base + off, len)
    if not data then return end
    state.bytes_scanned = state.bytes_scanned + len
    local init = 1
    while true do
        local p = string.find(data, old_pat, init, true)
        if not p then break end
        init = p + 1
        local lo = p - CONFIG.WIN
        local hi = p + CONFIG.WIN
        if lo >= 1 and hi + 3 <= #data then          -- 窗口完整才判
            local addr = region_base + off + p - 1
            if not is_self_addr(addr) then
                local n = corrob_in(string.sub(data, lo, hi))
                if n < CONFIG.MIN_CORROB then
                    state.lone_hits = state.lone_hits + 1     -- 孤立命中 -> 跳过不改
                else
                    state.hits = state.hits + 1
                    local ok, err = pcall(process_hit, addr, n)
                    if not ok then log_err("hit error: " .. tostring(err)) end
                end
            end
        end
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
            log(string.format("pass %d done: scanned %.1f MB, hits=%d lone_skipped=%d copies=%d",
                state.pass, state.bytes_scanned / 1048576.0,
                state.hits, state.lone_hits, #state.copies))
            flush_status()
            if state.phase == "patched" then
                -- ★ 打完补丁不能立刻停: 必须把**当前这一轮**扫完再彻底停
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
-- 命中处理: 只写 4 个字节
-- ---------------------------------------------------------------------------
-- 说明: 本 addon **不做表解析** —— 目标不是 LDLD 表里的记录, 而是运行时组件实例里的裸 u32。
--       定位完全靠"值 + 周围佐证"(见 scan_one_chunk), 所以这里只需要"写 4 字节 + 回读"。

local function register_copy(addr, corrob)
    for i = 1, #state.copies do
        if state.copies[i].addr == addr then return false end
    end
    state.copies[#state.copies + 1] = { addr = addr, corrob = corrob }
    return true
end

-- 把 addr 处的 u32 改成 want_event —— **只写这 4 个字节**, 写完立刻回读校验。
local function write_event(addr)
    if not write_mem(addr, u32_le(want_event)) then
        log_err(string.format("write failed @0x%X", addr))
        return false
    end
    local back = read_mem(addr, 4)
    if back == nil or u32_at(back, 0) ~= want_event then
        log_err(string.format("read-back mismatch @0x%X", addr))
        return false
    end
    return true
end

-- 处理一个通过佐证的候选地址
process_hit = function(addr, corrob)
    local cur = read_mem(addr, 4)
    if not cur then return end
    local v = u32_at(cur, 0)
    if v == want_event then
        register_copy(addr, corrob)              -- 已经是目标值(幂等)
        return
    end
    if v ~= CONFIG.EVENT_OLD then return end     -- 已被别的东西改过 -> 不碰
    if not write_event(addr) then return end
    register_copy(addr, corrob)
    if state.first_addr == nil then state.first_addr = addr end
    log(string.format("PATCHED sterilizer firing SFX @0x%X (corrob=%d): %d -> %d",
        addr, corrob, v, want_event))
    if state.phase ~= "patched" then
        state.phase = "patched"
        state.next_recheck = state.frames + CONFIG.RECHECK_EVERY
        set_status(string.format(
            "OK - patch applied (revision %s): sterilizer firing SFX %d -> %d",
            REVISION, CONFIG.EVENT_OLD, want_event))
    end
end

-- ---------------------------------------------------------------------------
-- 稳态: 按地址直读复查 + 重读 cfg(改了数值就立刻重打, 不用重开游戏)
-- ---------------------------------------------------------------------------
local function recheck()
    local cfg = read_cfg()
    if cfg and cfg ~= want_event then
        log(string.format("cfg changed: event %d -> %d", want_event, cfg))
        want_event = cfg
    end

    local changed = false
    local i = 1
    while i <= #state.copies do
        local c = state.copies[i]
        -- 读目标前后一整个窗口, 用佐证复核"这个位置还是不是灭菌器组件"
        local win = read_mem(c.addr - CONFIG.WIN, CONFIG.WIN * 2 + 4)
        if win == nil then
            -- 窗口读不到(跨界/不可读) -> 退化为只读目标本身
            local cur = read_mem(c.addr, 4)
            if cur == nil then
                table.remove(state.copies, i); changed = true
            else
                local v = u32_at(cur, 0)
                if v == want_event then
                    i = i + 1
                elseif write_event(c.addr) then
                    state.rewrites = state.rewrites + 1; i = i + 1; changed = true
                else
                    table.remove(state.copies, i); changed = true
                end
            end
        else
            local n = corrob_in(win)
            local v = u32_at(win, CONFIG.WIN)
            if n < CONFIG.MIN_CORROB then
                log(string.format("copy @0x%X lost its corroborating signature; dropping", c.addr))
                table.remove(state.copies, i); changed = true
            elseif v ~= want_event then
                log(string.format("copy @0x%X value=%d, want %d; re-applying", c.addr, v, want_event))
                if write_event(c.addr) then
                    state.rewrites = state.rewrites + 1; i = i + 1; changed = true
                else
                    table.remove(state.copies, i); changed = true
                end
            else
                i = i + 1
            end
        end
    end

    if #state.copies == 0 and state.scan_stopped then
        log("all patched copies gone (weapon instance rebuilt?); restarting search")
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
    if changed then flush_status() end
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
            -- 准备搜索模式串, 并把它们登记为"自身地址"(避免扫到自己 Lua 堆里的这些字节)
            old_pat = u32_le(CONFIG.EVENT_OLD)
            corrob_pats = {}
            for i = 1, #CONFIG.CORROB do
                corrob_pats[#corrob_pats + 1] = u32_le(CONFIG.CORROB[i])
            end
            for i = 1, #CONFIG.CORROB_U64 do
                local pr = CONFIG.CORROB_U64[i]
                corrob_pats[#corrob_pats + 1] = u32_le(pr[1]) .. u32_le(pr[2])
            end
            register_self_pattern(old_pat)
            for i = 1, #corrob_pats do register_self_pattern(corrob_pats[i]) end
        end
        if not float_codec_selftest() then
            set_status("FAILED - float codec self-test failed; refusing to run")
            state.phase = "dead"; return
        end
        local ok, msg = loader_gate()
        if not ok then set_status(msg); state.phase = "dead"; return end
        ensure_cfg()
        local cfg = read_cfg()
        if cfg then want_event = cfg end
        state.phase = "searching"
        log("addon started revision " .. REVISION .. "; loader API "
            .. tostring(state.loader_api) .. " v" .. tostring(state.loader_version)
            .. "; target event=" .. tostring(want_event))
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
