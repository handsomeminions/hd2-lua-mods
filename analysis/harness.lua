-- ============================================================================
-- harness.lua —— lupa 离线仿真环境(由 test_addon.py 先加载, 再加载 addon)
--
-- 提供:
--   * 类型严格的假 FFI(ffi.cdef/new/cast/string + kernel32 桩)
--     —— 指针参数传裸 number 会报错, 复现真实 FFI 的严格性(抓 6.4 类 bug)
--   * 假内存(区域表, 二进制全在 Lua 侧, 不跨 Python 边界)
--   * VirtualQuery 区域枚举(带"下一个区域"语义, 与真实 API 一致)
--   * io.open 捕获(不落盘)
--   * 字符串地址注册表(自检测测试用)
--   * 读/写失败注入
-- ============================================================================

HARNESS = {
    mem = {},            -- 区域数组 {base=,size=,data=,prot=,state=}
    files = {},          -- io捕获 path->content
    str_addrs = {},      -- [字符串值] -> 地址
    next_str_addr = 0x13000100,
    read_fail = {},      -- [addr]=true 读取失败注入
    write_fail = {},     -- [addr]=true 写入静默失败注入(返回成功但不写)
    write_log = {},      -- 写入记录 {addr=,bytes=}
    loader = { api = 1, version = 19 },
    update_original_calls = 0,
}

function HARNESS.reset()
    HARNESS.mem = {}
    HARNESS.files = {}
    HARNESS.read_fail = {}
    HARNESS.write_fail = {}
    HARNESS.write_log = {}
    HARNESS.update_original_calls = 0
    HARNESS.loader = { api = 1, version = 19 }
end

function HARNESS.hex_to_bytes(hex)
    return (hex:gsub("%x%x", function(p) return string.char(tonumber(p, 16)) end))
end

function HARNESS.bytes_to_hex(s)
    return (s:gsub(".", function(c) return string.format("%02X", string.byte(c)) end))
end

function HARNESS.add_region_hex(base, size, hexdata, prot, state)
    local data = HARNESS.hex_to_bytes(hexdata)
    if #data < size then
        data = data .. string.rep("\0", size - #data)
    elseif #data > size then
        data = string.sub(data, 1, size)
    end
    HARNESS.mem[#HARNESS.mem + 1] = {
        base = base, size = size, data = data,
        prot = prot or 0x04, state = state or 0x1000,
    }
end

function HARNESS.find_region(addr)
    for i = 1, #HARNESS.mem do
        local r = HARNESS.mem[i]
        if addr >= r.base and addr < r.base + r.size then return r end
    end
    return nil
end

function HARNESS.next_region_from(addr)
    -- 真实 VirtualQuery 语义: 地址不在区域里时返回下一个区域
    local best = nil
    for i = 1, #HARNESS.mem do
        local r = HARNESS.mem[i]
        if r.base + r.size > addr then
            if best == nil or r.base < best.base then best = r end
        end
    end
    return best
end

function HARNESS.read(addr, size)
    if HARNESS.read_fail[addr] then return nil end
    local r = HARNESS.find_region(addr)
    if not r then return nil end
    local off = addr - r.base
    if off + size > r.size then return nil end   -- 跨区域边界视为失败
    return string.sub(r.data, off + 1, off + size)
end

function HARNESS.write(addr, bytes)
    if HARNESS.write_fail[addr] then
        HARNESS.write_log[#HARNESS.write_log + 1] = { addr = addr, bytes = bytes, dropped = true }
        return true    -- 静默失败: 报告成功但不写
    end
    local r = HARNESS.find_region(addr)
    if not r then return false end
    local off = addr - r.base
    if off + #bytes > r.size then return false end
    local d = r.data
    r.data = string.sub(d, 1, off) .. bytes .. string.sub(d, off + #bytes + 1)
    HARNESS.write_log[#HARNESS.write_log + 1] = { addr = addr, bytes = bytes, dropped = false }
    return true
end

function HARNESS.region_bytes_hex(base, off, n)
    local r = HARNESS.find_region(base)
    if not r then return nil end
    return HARNESS.bytes_to_hex(string.sub(r.data, off + 1, off + n))
end

function HARNESS.abs_hex(addr, n)
    -- 按"绝对地址"读 n 字节(自动换算 region 内偏移), 供测试断言补丁结果
    local r = HARNESS.find_region(addr)
    if not r then return nil end
    local off = addr - r.base
    if off + n > r.size then return nil end
    return HARNESS.bytes_to_hex(string.sub(r.data, off + 1, off + n))
end

function HARNESS.flush_addon_log()
    -- addon 各自暴露唯一名字的落盘函数(避免互相覆盖); 逐个尝试
    for _, name in ipairs({ "_HD2_380MM_FLUSH", "_HD2_120MM_FLUSH", "_HD2_BUGARTY_FLUSH",
                            "_HD2_MORTAR_NAPALM_FLUSH", "_HD2_BUG6R_FLUSH", "flush_log" }) do
        local f = rawget(_G, name)
        if type(f) == "function" then pcall(f) end
    end
end

function HARNESS.write_hex(addr, hex)
    return HARNESS.write(addr, HARNESS.hex_to_bytes(hex))
end

function HARNESS.region_prot(base)
    local r = HARNESS.find_region(base)
    return r and r.prot or nil
end

function HARNESS.drop_all_regions()
    HARNESS.mem = {}
end

function HARNESS.get_file(path)
    return HARNESS.files[path]
end

function HARNESS.preload_file(path, content)
    HARNESS.files[path] = content
end

-- ---------------------------------------------------------------------------
-- 假 FFI
-- ---------------------------------------------------------------------------
local obj_counter = 0

local ffi_stub = {}

function ffi_stub.cdef() end

-- 数组缓冲区: 行为逼近真实 cdata char[]/int[]/SIZE_T[]
--   * 字符串背书(读路径 O(1)); 一旦发生数字下标写, 才展开成字节表
--   * 数字下标读按元素宽度做无符号小端(olds[0] 取 u32 是典型用法)
--   * .data 读 = 整块字节串; .data 写 = 从字节串载入
local buf_mt = {}
buf_mt.__index = function(self, k)
    if k == "data" then
        if self.__bytes then
            local out = {}
            for i = 0, self.__n - 1 do out[i + 1] = string.char(self.__bytes[i] or 0) end
            return table.concat(out)
        end
        return self.__str or string.rep("\0", self.__n)
    end
    if type(k) == "number" then
        local es = self.__esize
        local off = k * es
        local v, mul = 0, 1
        if self.__bytes then
            for i = 0, es - 1 do
                v = v + (self.__bytes[off + i] or 0) * mul
                mul = mul * 256
            end
        else
            local s = self.__str or ""
            for i = 0, es - 1 do
                v = v + (string.byte(s, off + i + 1) or 0) * mul
                mul = mul * 256
            end
        end
        return v
    end
    return rawget(self, k)
end
buf_mt.__newindex = function(self, k, v)
    if k == "data" then
        self.__str = v
        self.__bytes = nil
        return
    end
    if type(k) == "number" then
        if not self.__bytes then
            self.__bytes = {}
        end
        local es = self.__esize
        local off = k * es
        v = math.floor(v) % 4294967296
        for i = 0, es - 1 do
            self.__bytes[off + i] = v % 256
            v = math.floor(v / 256)
        end
        return
    end
    rawset(self, k, v)
end

local function make_buf(nbytes, esize)
    obj_counter = obj_counter + 1
    return setmetatable({
        __ffi = true, __ptr = obj_counter, __kind = "buf",
        __n = nbytes, __esize = esize or 1,
        __str = string.rep("\0", nbytes), __bytes = nil,
    }, buf_mt)
end

function ffi_stub.new(ctype, n)
    if ctype == "char[?]" then
        return make_buf(n, 1)
    elseif ctype == "SIZE_T[1]" then
        return make_buf(8, 8)
    elseif ctype == "unsigned int[1]" then
        return make_buf(4, 4)
    elseif ctype == "MEMORY_BASIC_INFORMATION" then
        obj_counter = obj_counter + 1
        return { __ffi = true, __ptr = obj_counter, __kind = "struct",
                 BaseAddress = 0, AllocationBase = 0, AllocationProtect = 0,
                 __alignment1 = 0, RegionSize = 0, State = 0, Protect = 0,
                 Type = 0, __alignment2 = 0 }
    end
    error("ffi.new: unsupported type " .. tostring(ctype))
end

function ffi_stub.cast(ctype, v)
    if ctype == "uintptr_t" then
        if type(v) == "number" then return v end
        if type(v) == "table" and v.__ptr ~= nil then return v.__ptr end
        error("ffi.cast(uintptr_t): bad value " .. type(v))
    end
    if ctype == "const char *" then
        if type(v) == "string" then
            local a = HARNESS.str_addrs[v]
            if not a then
                a = HARNESS.next_str_addr
                HARNESS.next_str_addr = a + 4096
                HARNESS.str_addrs[v] = a
            end
            return { __ptr = a, __ffi = true }
        end
        error("ffi.cast(const char *): bad value " .. type(v))
    end
    -- 指针类型: 允许 number -> 指针(真实FFI合法), 也允许 cdata 对象
    if type(ctype) == "string" and ctype:find("%*") then
        if type(v) == "number" then
            return { __ptr = v, __ffi = true }
        end
        if type(v) == "table" and v.__ffi then
            return { __ptr = v.__ptr, __ffi = true, __obj = v }
        end
        error("ffi.cast(" .. ctype .. "): cannot cast " .. type(v))
    end
    return v
end

function ffi_stub.string(buf, n)
    if type(buf) == "table" and buf.__kind == "buf" then
        return string.sub(buf.data, 1, n)
    end
    error("ffi.string: bad buffer " .. type(buf))
end

function require(name)
    if name == "ffi" then return ffi_stub end
    error("module not found: " .. tostring(name))
end

-- kernel32 桩: 指针参数必须是 cdata 对象(传裸number报错 —— 6.4)
local function as_ptr(v, what)
    if type(v) == "table" and v.__ptr ~= nil then return v end
    error("cannot convert " .. type(v) .. " to pointer in " .. what, 2)
end

local C_stub = {}

function C_stub.GetCurrentProcess()
    return { __ptr = 0x0FF1CE, __ffi = true }
end

function C_stub.VirtualQuery(addr, mbi, len)
    addr = as_ptr(addr, "VirtualQuery")
    local obj = mbi.__obj or mbi
    local a = addr.__ptr
    local r = HARNESS.find_region(a)
    if not r then r = HARNESS.next_region_from(a) end
    if not r then return 0 end
    obj.BaseAddress = r.base
    obj.AllocationBase = r.base
    obj.AllocationProtect = r.prot
    obj.RegionSize = r.size
    obj.State = r.state
    obj.Protect = r.prot
    obj.Type = 0x20000    -- MEM_PRIVATE
    return 48
end

function C_stub.ReadProcessMemory(proc, addr, buf, size, nread)
    addr = as_ptr(addr, "ReadProcessMemory")
    buf = as_ptr(buf, "ReadProcessMemory")
    if nread ~= nil then nread = as_ptr(nread, "ReadProcessMemory") end
    local data = HARNESS.read(addr.__ptr, size)
    if not data then
        if nread then (nread.__obj or nread).data = string.rep("\0", 8) end
        return 0
    end
    local obj = buf.__obj or buf
    obj.data = data
    if nread then
        local no = nread.__obj or nread
        no.data = string.rep("\0", 7) .. string.char(size % 256)  -- 小端计数
    end
    return 1
end

function C_stub.WriteProcessMemory(proc, addr, buf, size, nwr)
    addr = as_ptr(addr, "WriteProcessMemory")
    buf = as_ptr(buf, "WriteProcessMemory")
    if nwr ~= nil then nwr = as_ptr(nwr, "WriteProcessMemory") end
    local obj = buf.__obj or buf
    local bytes = string.sub(obj.data, 1, size)
    local ok = HARNESS.write(addr.__ptr, bytes)
    if nwr then
        local no = nwr.__obj or nwr
        no.data = string.rep("\0", 7) .. string.char(ok and (size % 256) or 0)
    end
    if ok then return 1 end
    return 0
end

function C_stub.VirtualProtect(addr, size, prot, oldp)
    addr = as_ptr(addr, "VirtualProtect")
    if oldp ~= nil then oldp = as_ptr(oldp, "VirtualProtect") end
    local r = HARNESS.find_region(addr.__ptr)
    if not r then return 0 end
    if oldp then (oldp.__obj or oldp).data = string.char(r.prot % 256, 0, 0, 0) end
    r.prot = prot
    return 1
end

-- 把 kernel32 桩挂到假 ffi 上(addon 里 C = ffi.C)
ffi_stub.C = C_stub

-- ---------------------------------------------------------------------------
-- io.open 捕获(不落盘; Lua 的 fopen 打不开中文路径的坑也顺带绕开)
-- ---------------------------------------------------------------------------
local real_io_open = io.open
io.open = function(path, mode)
    mode = mode or "r"
    if mode:find("r") then
        local content = HARNESS.files[path]
        if content == nil then return nil end
        local pos = 1
        return {
            read = function(self, fmt)
                if fmt == "*l" or fmt == "l" then
                    local nl = string.find(content, "\n", pos, true)
                    local line
                    if nl then
                        line = string.sub(content, pos, nl - 1)
                        pos = nl + 1
                    else
                        line = string.sub(content, pos)
                        pos = #content + 1
                    end
                    return line
                end
                local chunk = string.sub(content, pos)
                pos = #content + 1
                return chunk
            end,
            close = function() end,
        }
    end
    if mode:find("w") then HARNESS.files[path] = "" end
    if HARNESS.files[path] == nil then HARNESS.files[path] = "" end
    return {
        write = function(self, ...)
            local args = { ... }
            for i = 1, #args do
                HARNESS.files[path] = HARNESS.files[path] .. tostring(args[i])
            end
        end,
        close = function() end,
    }
end

-- ---------------------------------------------------------------------------
-- addon 加载与帧驱动
-- ---------------------------------------------------------------------------
function HARNESS.set_loader(api, ver)
    HARNESS.loader = { api = api, version = ver }
    _G.CowboyBingusModLoader = HARNESS.loader
end

function HARNESS.clear_loader()
    _G.CowboyBingusModLoader = nil
end

function HARNESS.preload_loader_log(text)
    local dir = os.getenv("LOCALAPPDATA") or ""
    HARNESS.preload_file(dir .. "/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log", text)
end

function HARNESS.run_addon(src)
    local chunk = loadstring(src)
    if not chunk then error("addon source does not compile") end
    chunk()
end

FRAMES = 0
function HARNESS.install_update_hook()
    FRAMES = 0
    update = function()
        FRAMES = FRAMES + 1
        HARNESS.update_original_calls = HARNESS.update_original_calls + 1
    end
end

function HARNESS.frames(n)
    for i = 1, n do update() end
    return FRAMES
end

function HARNESS.status_path()
    local dir = os.getenv("LOCALAPPDATA") or ""
    return dir .. "/CowboyBingus/Helldivers2/Logs/" .. (HARNESS.status_file or "orbital_120mm_500kg_STATUS.txt")
end

function HARNESS.log_path()
    local dir = os.getenv("LOCALAPPDATA") or ""
    return dir .. "/CowboyBingus/Helldivers2/Logs/" .. (HARNESS.log_file or "orbital_120mm_500kg.log")
end

function HARNESS.hellbomb_type()
    return tonumber(string.match(HARNESS.status_text(), "hellbomb_explosion_type=(%d+)"))
end

function HARNESS.patched_records()
    return tonumber(string.match(HARNESS.status_text(), "patched_records=(%d+)")) or 0
end

function HARNESS.status_head()
    local c = HARNESS.get_file(HARNESS.status_path())
    if not c then return nil end
    return string.match(c, "^[^\n]*")
end

function HARNESS.status_text()
    return HARNESS.get_file(HARNESS.status_path()) or ""
end

function HARNESS.patched_copies()
    return tonumber(string.match(HARNESS.status_text(), "patched_copies=(%d+)"))
end

function HARNESS.bomb_type_status()
    return tonumber(string.match(HARNESS.status_text(), "bomb_projectile_type=(%d+)"))
end

function HARNESS.proj_clones()
    return tonumber(string.match(HARNESS.status_text(), "proj_clones=(%d+)")) or 0
end

function HARNESS.write_count()
    return #HARNESS.write_log
end

function HARNESS.log_text()
    return HARNESS.get_file(HARNESS.log_path()) or ""
end
