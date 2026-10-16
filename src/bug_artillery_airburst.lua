-- HD2-Addon: mods/hd2/bug_artillery_airburst
-- ============================================================================
-- 胆汁喷涌虫(Bile Spewer) 的"胆汁迫击炮" -> 空爆火箭弹(RL-77)
-- Bile Spewer bile mortar (ProjectileType_Bug_Artillery) -> RL-77 Airburst Rocket
--
-- 效果(用户的明确要求):
--   1) 【外形 = 原版绿色胆汁迫击炮】(v1.4.0 回退)
--      ⇒ 弹体模型 + 飞行粒子 **全部保持原版胆汁迫击炮**, 一个字节都不动:
--          +128 projectile_unit_path  原版 = 0   (胆汁迫击炮**本就无实体模型**)
--          +72  particle_thruster_effect_path   推进/飞行粒子  ← "绿色团块"就是它
--          +88  particle_thruster_effect_length 推进粒子长度
--          +96  particle_trail_effect_path      拖尾粒子
--      ★ 历史: v1.1.0~v1.3.0 曾把 +128 换成火箭模型、+72/+88/+96 换成火箭粒子,
--        想做出"完整空爆火箭"外形; 实机结果是**火箭模型不渲染(丢失)**,
--        而绿团块又被换掉了 ⇒ 弹体看不见。
--        本版按要求**回退**: 拿回原版胆汁迫击炮的外形(那个绿色团块),
--        **其余照旧**(落地爆炸 = 空爆集束、子弹药用原版火箭物理抛射、弹道不动)。
--   2) 【弹道不变】攻击方式 / 飞行速度 / 轨迹 与原版胆汁迫击炮**逐字节相同**
--      (speed=30 drag=0 gravity=1 life_time=0 全部保留; 不做近炸、不做定时)
--   3) 【落地爆炸】落地(命中)炸开时, 用 RL-77 空爆火箭的爆炸方式
--      (explosion_type_on_impact -> RL-77 那颗空爆集束爆炸: 半径 3/5/7, 炸开 25 枚子弹药)
--   4) 【子弹药物理】25 枚子弹药必须有**碰撞 + 随意无规律飞溅**, 与原版 RL-77 完全一致。
--      ★ 机制厘清: 子弹药"用哪条记录、怎么飞"由【爆炸记录】决定, 不由胆汁射弹决定。
--        ExplosionType_AirburstCluster 里写着:
--          num_shrapnel_projectiles = 25
--          shrapnel_projectile_type = ProjectileType_AirburstCluster_Bomb
--        而 AirburstCluster_Bomb 这条射弹记录自带全部飞溅物理(已自动生效):
--          speed25 mass100 drag0.5 gravity×4  life0.8s(±70% **随机**)
--          arming_distance15  hit_only_ground1  allow_long_distance_travel1
--          surface_impact=explosion_medium  ricochet=solid_medium  max_ricochets1
--          ricochet_threshold 90°/20  angle_loss0.2
--          ricochet_spread 垂直3° / 水平15°   <- 这就是"随意无规律"
--        所以**子弹药自身的物理无需我们改**, 只要落地爆炸指向 AirburstCluster 即得。
--      ★ 但"生成开关"必须跟着火箭换, 否则子弹药会粘在原地炸、飞不出去:
--          +152 explosion_delay   胆汁 0 -> 火箭 0.2
--          +240 flags(bit0 inherit_velocity / bit5 explosions_inherit_velocity)
--                                 胆汁 0xB5 -> 火箭 0x94
--
--   一句话: "外形/飞行都是原来的胆汁迫击炮, 落地炸成空爆集束, 子弹药飞溅如原版".
--
-- 原理(纯内存补丁; 禁用 mod + Purge 即完全还原, 不改任何磁盘文件):
--   1. 扫描内存, 定位常驻的 ProjectileSettings(射弹表, LDLD 类型哈希 0xBD4042C2);
--   2. 在表里按"跨构建稳定"的指纹(64位资源哈希 + 物理量)定位两条记录:
--        - 目标: 胆汁迫击炮 ProjectileType_Bug_Artillery
--                指纹 = 无名(name_upper==0) + 口径50 + 初速30 + 质量1000
--                       + 推进粒子哈希 758CA9293725AFE2 + 拖尾粒子哈希 AC522AC39D4B3529
--                       + 尾迹音频 3340293219
--        - 源:   RL-77 空爆火箭(Flak 近炸模式) ProjectileType_Grenade_85mm_AirburstCluster
--                指纹 = 口径85 + 质量3300 + 初速250 + 寿命1.5s + 近炸2m
--                       + 拖尾粒子哈希 C8FD1E326BA587BF + 尾迹音频 1680798988
--   3. **只改写目标记录的这 3 组字段**(不是整条克隆):
--        +144 u32 explosion_type_on_impact    <- 源(空爆集束爆炸枚举)   [总是]
--        +152 f32 explosion_delay             <- 源(0.2, 子弹药抛射时机) [总是]
--        +240 u8  flags(bit0/bit5)            <- 源(0x94, 初速度继承方式) [总是]
--        +208/+212 飞行音效                    <- 源                        [仅当 SWAP_FLIGHT_FX]
--      **外形(+128/+72/+88/+96) 与飞行物理一律不碰**, 并在写入前做一次
--      "这些字段未被改动"的**逐字节自检**, 自检不过就拒绝写入 —— 硬保证.
--
-- 关键数值(离线三方交叉核对: 游戏 typelib + FileDiver 明文镜像 + 社区 JSON, 并与 wiki 逐项吻合;
--          所有用到的偏移都做过"全表复现"验证, 命中率 ~100%):
--   ProjectileInfo 大小 272 字节; 字段偏移:
--     +0 type(u32)  +4 name_upper  +8 name_cased  +12 short_name  +16 hud_icon(u64)
--     +24 calibre   +32 speed  +36 mass  +40 drag  +44 gravity_multiplier  +52 life_time
--     +60 damage_info_type  +72 particle_thruster(u64)  +88 thruster_length
--     +96 particle_trail(u64)  +128 projectile_unit_path(u64)  +136 explosion_threshold_angle
--     +144 explosion_type_on_impact  +148 explosion_proximity  +152 explosion_delay
--     +156 explosion_type_expire  +160 arming_distance  +208/+212 audio_trail_start/stop
--   目标(胆汁迫击炮, 本构建 type=344): 原用 ExplosionType_Bug_Artillery(半径 1/8/14)
--   源  (RL-77 空爆, 本构建 type=312): 用 ExplosionType_AirburstCluster(半径 3/5/7, 25 枚子弹药)
--   枚举下标随版本漂移, 故本 addon 一个枚举值都不写死, 全部靠上述内容指纹定位.
--
-- 依赖: Bingus Shared Loader v15+ (API 1). 本 addon 只改内存.
-- ============================================================================

local MOD_NAME = "mods/hd2/bug_artillery_airburst"
local REVISION = "1.5.0"
local SINGLETON = "_HD2_BUG_ARTILLERY_AIRBURST"

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
    OFF_THRUSTER    = 72,           -- stingray.Hash(u64) 推进/飞行粒子(绿团块来源之一)
    OFF_TRAIL       = 96,           -- stingray.Hash(u64) 粒子拖尾资源哈希(绿团块来源之一)
    OFF_UNIT        = 128,          -- stingray.Hash(u64) 弹体模型资源哈希(原版胆汁=0, 无模型)
    OFF_EXPL_IMPACT = 144,          -- explosion_type_on_impact (枚举, 会漂移)
    OFF_EXPL_PROX   = 148,          -- explosion_proximity (f32)
    OFF_EXPL_DELAY  = 152,          -- explosion_delay (f32) —— 起爆延迟, 影响子弹药抛出时机
    OFF_EXPL_EXPIRE = 156,          -- explosion_type_expire (枚举)
    OFF_AUDIO_START = 208,          -- audio_trail_event_start (u32 资源哈希)
    OFF_AUDIO_STOP  = 212,          -- audio_trail_event_stop  (u32 资源哈希)
    OFF_FLAGS       = 240,          -- flag 位域首字节 (bit0..bit7, 见 CONFIG 头注释)

    -- 目标(胆汁迫击炮)指纹: 64位资源哈希用十六进制表示(避免 LuaJIT 53位精度问题)
    -- 注: 这里写的是 hex8_be 形式(与内存字节序相反的渲染), 与 TGT_TRAIL_HEX 约定一致
    TGT_TRAIL_HEX = "29354B9DC32A52AC",
    TGT_THR_HEX   = "758CA9293725AFE2",   -- +72 推进粒子(绿团块来源)
    TGT_AUDIO     = 3340293219,
    TGT_CAL       = 50.0,
    TGT_SPEED     = 30.0,
    TGT_MASS      = 1000.0,

    -- 子弹药生成开关(见下 +240 flags / +152 delay)。
    -- 目的: 让胆汁迫击炮落地后, **25 枚子弹药用原版空爆火箭的那套物理**抛出去,
    -- 有碰撞、有随机散射、有无规律飞溅 —— 而不是像胆汁原版那样"就地一炸"。
    --   源(RL-77 空爆火箭) +240 = 0x94, +152 delay = 0.2
    --   目标(胆汁迫击炮) +240 = 0xB5, +152 delay = 0.0
    -- ★ +240 各 bit(已用 246 条社区记录 + 本构建明文逐条比对, 命中率 >99%):
    --     bit0 inherit_velocity            bit1 ignore_terminal_velocity
    --     bit2 remove_thruster_instantly   bit3 remove_trail_instantly
    --     bit4 projectile_unit_auto_remove bit5 explosions_inherit_velocity
    --     bit6 project_decal               bit7 (未用, 恒 1)
    --   胆汁 bit0/bit5 = 1,1 而火箭 = 0,0; 这两项决定"爆散/飞溅"的初速度继承方式,
    --   换成火箭那套后 25 枚子弹药的抛射才与 RL-77 完全一致。
    TGT_DELAY = 0.0,                -- 胆汁原版起爆延迟(落地立即)
    TGT_FLAGS = 0xB5,               -- 胆汁原版 +240
    SRC_FLAGS = 0x94,               -- RL-77 空爆火箭 +240(bit0/bit5 归零)
    -- +152 f32 的 4 字节小端表示(指纹里直接比对字节, 免得依赖运行时的浮点打包)
    TGT_DELAY_LE = "\0\0\0\0",              -- 0.0  -> 00 00 00 00
    SRC_DELAY_LE = "\205\204\76\62",        -- 0.2  -> CD CC 4C 3E

    -- 源(RL-77 空爆火箭, Flak 近炸模式)指纹
    SRC_TRAIL_HEX = "BF87A56B321EFDC8",
    SRC_AUDIO     = 1680798988,
    SRC_CAL       = 85.0,
    SRC_MASS      = 3300.0,
    SRC_LIFE      = 1.5,
    SRC_PROX      = 2.0,

    REC_SIZE = 272,

    -- 【外形】是否把飞行音效也换成火箭的(+208/+212)。
    -- v1.4.0 起 **外形(+128 模型 / +72/+88/+96 粒子)已固定保持原版胆汁迫击炮**,
    -- 不再受本开关影响 —— 本开关现在**只管飞行音效**这最后一项。
    --   true  = 飞行时用火箭的飞行音效(默认, 沿用户 v1.3.0 的设置)
    --   false = 连飞行音效也保持原版胆汁迫击炮
    SWAP_FLIGHT_FX = true,

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

-- 要改写的字段: 从"源"(RL-77)记录里取这几段字节, 覆盖到"目标"记录的同位置
--   group="explosion" : 落地爆炸 (总是)
--   group="submuni"   : 子弹药抛射物理开关 (总是 —— 25 枚子弹药的碰撞/散射/飞溅)
--   group="flight_fx" : 仅飞行音效, 受 SWAP_FLIGHT_FX 控制
--
-- ★ v1.4.0 回退: **不再改写 +128 模型 / +72/+88/+96 粒子** —— 它们整组保持原版
--   胆汁迫击炮(绿色团块), 并已加入下面的 FLIGHT_GUARD 做逐字节自检。
--
-- ★ group="submuni" 才是"子弹药物理与原版一致"的关键:
--   落地爆炸(explosion_type_on_impact)只决定"抛出 25 枚子弹药"这个**事实**;
--   子弹药**怎么飞**(碰撞/跳弹/随机散射)本身是那条子弹药射弹记录(ProjectileType_
--   AirburstCluster_Bomb)自带的, 会自动生效, 无需我们改。
--   真正需要跟着火箭走的是这两个"生成开关":
--     +152 explosion_delay  —— 胆汁原版 0 (落地立刻炸); 火箭 0.2 (先延迟再抛)
--     +240 flag 位域        —— 胆汁 bit0 inherit_velocity=1 / bit5 explosions_inherit_velocity=1;
--                              火箭两者皆 0。这两项决定子弹药初速度是否继承母弹速度,
--                              直接影响"是否被母弹速度带着飞、是否散得开"。
--   不换这两项 → 胆汁落地后子弹药会"粘在原地炸", 看起来像没飞溅。
local PATCH_FIELDS = {
    { off = 144, len = 4, group = "explosion", name = "explosion_type_on_impact" },
    { off = 152, len = 4, group = "submuni",   name = "explosion_delay" },
    { off = 240, len = 1, group = "submuni",   name = "flags" },
    { off = 208, len = 4, group = "flight_fx", name = "audio_trail_event_start" },
    { off = 212, len = 4, group = "flight_fx", name = "audio_trail_event_stop" },
}

-- 哪些 group 需要实际写入
local function group_enabled(g)
    if g == "flight_fx" then return CONFIG.SWAP_FLIGHT_FX end
    return true
end

-- "外形 + 弹道必须与原版一致"的硬保证: 写盘前核对这几段在新内容里与原文**逐字节相同**.
-- 覆盖: 弹道(speed/mass/drag/gravity/life/爆炸角度/近炸/引信/解保) 
--     + 【外形】弹体模型(+128) 与 飞行粒子(+72/+88/+96) —— v1.4.0 回退项
-- 注: +152 explosion_delay 与 +240 flags 归 group="submuni" 主动改写, 故不在表内;
--     +148 explosion_proximity 在表内(胆汁恒 0, 保持不做近炸)。
local FLIGHT_GUARD = {
    { 32, 4 }, { 36, 4 }, { 40, 4 }, { 44, 4 }, { 52, 4 },
    { 72, 8 }, { 88, 4 }, { 96, 8 }, { 128, 8 },
    { 136, 4 }, { 148, 4 }, { 156, 4 }, { 160, 4 },
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
    done_blocks = {},        -- block addr -> true (已成功处理)

    target_type = nil,       -- 目标记录自身 +0 类型(用于日志/STATUS)
    source_type = nil,
    source_desc = nil,
    expl_old = nil,          -- 原版命中爆炸枚举
    expl_new = nil,          -- 改后的命中爆炸枚举(= RL-77 空爆集束)
    model_new = nil,         -- 保持原版的模型资源哈希(16进制字符串; v1.4.0 起不再改写)
    thr_new = nil,           -- 保持原版的推进粒子哈希(16进制字符串)
    trail_new = nil,         -- 保持原版的拖尾粒子哈希(16进制字符串)
    delay_old = nil,         -- 原版起爆延迟
    delay_new = nil,         -- 改后起爆延迟(火箭的 0.2)
    flags_old = nil,         -- 原版 +240 flags
    flags_new = nil,         -- 改后 +240 flags(火箭的 0x94)
    copies = {},             -- {rec=, want=(272字节新内容), idx=, blk=}

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
    end
    parts[#parts + 1] = string.format("target(bug artillery) type=%s | source(RL-77 airburst) type=%s",
        tostring(state.target_type), tostring(state.source_type))
    if state.source_desc then parts[#parts + 1] = "source_src=" .. state.source_desc end
    if state.expl_new then
        parts[#parts + 1] = string.format("impact_explosion=%s->%s (airburst cluster)",
            tostring(state.expl_old), tostring(state.expl_new))
        parts[#parts + 1] = string.format("submuni_physics_swapped delay %s->%s flags %s->%s (25 bomblets get rocket scatter/collision)",
            tostring(state.delay_old), tostring(state.delay_new),
            tostring(state.flags_old), tostring(state.flags_new))
        parts[#parts + 1] = string.format("model_kept_vanilla_bile=true (unit=%s) particles_kept_vanilla thruster=%s trail=%s (green blob kept)",
            tostring(state.model_new), tostring(state.thr_new), tostring(state.trail_new))
        parts[#parts + 1] = string.format("flight(trajectory/speed/arc)_preserved=true  shape(model/particles)_preserved=true  flight_audio_swapped=%s",
            tostring(CONFIG.SWAP_FLIGHT_FX))
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
    parts[#parts + 1] = "effect: Bile Spewer bile mortars keep their ORIGINAL look (green bile blob) and"
    parts[#parts + 1] = "        ORIGINAL flight (speed/arc), but burst into the RL-77 airburst cluster"
    parts[#parts + 1] = "        (25 bomblets with the rocket's scatter/collision) on impact"
    parts[#parts + 1] = "note: damage is host-authoritative; host needs this mod for real damage to count"
    return table.concat(parts, "\n") .. "\n"
end

local function flush_status()
    local dir = env_dir()
    if not dir then return end
    pcall(function()
        local f = io.open(dir .. "bug_artillery_airburst_STATUS.txt", "w")
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
        local f = io.open(dir .. "bug_artillery_airburst.log", "w")
        if f then
            for i = 1, #log_lines do f:write(log_lines[i] .. "\n") end
            f:close()
        end
    end)
end
_G._HD2_BUGARTY_FLUSH = flush_log   -- 唯一名字, 不与其它 addon 的全局函数冲突

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

-- "29354B9DC32A52AC" -> 8 字节小端串(不经过 Lua number, 避免 53 位精度截断)
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

-- 单精度浮点 -> 4 字节小端(手写编码, 无位运算)
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
        { 0x41880000, 17.0 }, { 0x41C80000, 25.0 }, { 0x42340000, 45.0 },
        { 0x42480000, 50.0 }, { 0x42F00000, 120.0 },
    }
    for i = 1, #cases do
        if bits_to_f32(cases[i][1]) ~= cases[i][2] then return false end
    end
    if f32_bytes(50.0) ~= u32_le(0x42480000) then return false end
    if f32_bytes(1.5) ~= u32_le(0x3FC00000) then return false end
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
        -- 数据区优先(大块优先), 映像/代码段垫底兜底
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
            -- 一轮完整扫描结束
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
                -- 单向收敛: 已打完, 且本轮完整扫描也走完(覆盖内存里所有副本) -> 休眠
                state.scan_stopped = true
                log("scan stopped: patch applied and a full pass completed")
                return
            end
            -- 空手退避: 每轮完整扫描之间逐渐拉长间隔(2/4/8/.../64 秒)
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
-- 表解析: 由 LDLD 块头取 {recbase,count,stride} (DLArray 形态)
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
local tgt_trail, src_trail   -- 拖尾粒子 8 字节小端串
local tgt_thr                -- 推进粒子 8 字节小端串(胆汁原版; v1.4.0 起不再改写)
local src_flags              -- 源 +240 那一字节(打完补丁后就是它)
local src_delay              -- 源 +152 f32 小端串(打完补丁后就是它)

-- 目标指纹: 必须对"原版"和"已打过补丁"两种形态**都**成立(否则打完就认不出自己,
-- 幂等/复查全废).
-- v1.4.0 起我们**只**改写 +144/+152/+240(以及可选的 +208/+212 音效),
-- 外形(+128 模型 / +72/+88/+96 粒子)保持原版, 所以这几项按**原版值**严格比对。
local function is_target_record(r)
    if not (u32_at(r, CONFIG.OFF_NAME_UPPER) == 0) then return false end
    if not (u32_at(r, CONFIG.OFF_NAME_CASED) == 0) then return false end
    if not near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5) then return false end
    if not near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5) then return false end
    if not near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0) then return false end
    -- 拖尾粒子 / 推进粒子: 必须是胆汁原版那一对(它们不再被改写)
    if string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) ~= tgt_trail then return false end
    if string.sub(r, CONFIG.OFF_THRUSTER + 1, CONFIG.OFF_THRUSTER + 8) ~= tgt_thr then return false end
    -- 飞行音效: 胆汁的 或 火箭的(可被 SWAP_FLIGHT_FX 改写)
    local au = u32_at(r, CONFIG.OFF_AUDIO_START)
    if au ~= CONFIG.TGT_AUDIO and au ~= CONFIG.SRC_AUDIO then return false end
    -- 起爆延迟: 胆汁的(0) 或 火箭的(0.2)
    local dl = string.sub(r, CONFIG.OFF_EXPL_DELAY + 1, CONFIG.OFF_EXPL_DELAY + 4)
    if dl ~= CONFIG.TGT_DELAY_LE and dl ~= src_delay then return false end
    -- flags: 胆汁的 或 火箭的
    local fl = string.byte(r, CONFIG.OFF_FLAGS + 1)
    if fl ~= CONFIG.TGT_FLAGS and fl ~= src_flags then return false end
    return true
end

local function is_source_record(r)
    return string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) == src_trail
       and u32_at(r, CONFIG.OFF_AUDIO_START) == CONFIG.SRC_AUDIO
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.SRC_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.SRC_MASS, 1.0)
       and near(f32_at(r, CONFIG.OFF_LIFE), CONFIG.SRC_LIFE, 0.03)
       and near(f32_at(r, CONFIG.OFF_EXPL_PROX), CONFIG.SRC_PROX, 0.1)
end

-- 幂等判据: 目标记录的"身份+弹道"特征在打补丁前后都不变(我们只动模型/爆炸/可选视觉),
-- 所以 is_target_record 对"原版"和"已打过补丁"两种形态都成立; 是否已打过靠"新内容 == 现内容"判定.

-- ---------------------------------------------------------------------------
-- 构造"打完补丁后的记录": 从 cur 出发, 只把 PATCH_FIELDS 指定的几段换成 src 的
-- ---------------------------------------------------------------------------
local function build_patched(cur, src)
    local out = cur
    for i = 1, #PATCH_FIELDS do
        local f = PATCH_FIELDS[i]
        if group_enabled(f.group) then
            out = string.sub(out, 1, f.off)
               .. string.sub(src, f.off + 1, f.off + f.len)
               .. string.sub(out, f.off + f.len + 1)
        end
    end
    return out
end

-- 硬保证: 弹道相关的字段必须与原文逐字节相同(否则说明字段表/偏移出了问题, 拒绝写入)
local function flight_guard_ok(cur, new)
    for i = 1, #FLIGHT_GUARD do
        local g = FLIGHT_GUARD[i]
        if string.sub(cur, g[1] + 1, g[1] + g[2]) ~= string.sub(new, g[1] + 1, g[1] + g[2]) then
            return false
        end
    end
    return true
end

-- 确认"该改的确实改了": 新内容里的 命中爆炸 + 子弹药开关 必须等于源的对应字段
-- (v1.4.0 起不再要求 模型/粒子 等于源 —— 它们保持原版胆汁)
local function patch_applied_ok(new, src)
    if string.sub(new, CONFIG.OFF_EXPL_IMPACT + 1, CONFIG.OFF_EXPL_IMPACT + 4)
       ~= string.sub(src, CONFIG.OFF_EXPL_IMPACT + 1, CONFIG.OFF_EXPL_IMPACT + 4) then return false end
    -- 子弹药抛射开关: 起爆延迟 + flags 必须换成火箭的
    -- (否则 25 枚子弹药不起飞、不飞溅, 只是原地爆一下)
    if string.sub(new, CONFIG.OFF_EXPL_DELAY + 1, CONFIG.OFF_EXPL_DELAY + 4)
       ~= string.sub(src, CONFIG.OFF_EXPL_DELAY + 1, CONFIG.OFF_EXPL_DELAY + 4) then return false end
    if string.byte(new, CONFIG.OFF_FLAGS + 1) ~= string.byte(src, CONFIG.OFF_FLAGS + 1) then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- 打补丁: 只改写目标记录的少数几个字段
-- ---------------------------------------------------------------------------
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
    if tgt_idx == nil then return false end          -- 目标不在, 本块无需处理
    for k = 0, t.count - 1 do
        if k ~= tgt_idx then
            local r = string.sub(data, k * t.stride + 1, (k + 1) * t.stride)
            if is_source_record(r) then src_idx = k; break end
        end
    end
    if src_idx == nil then
        log_err(string.format("target found (idx %d) but RL-77 airburst source missing in table@0x%X",
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
    if not flight_guard_ok(cur, new) then
        log_err(string.format("flight-guard failed @0x%X: trajectory fields would change; refusing", tgt_addr))
        return false
    end
    if state.target_type == nil then
        state.target_type = u32_at(cur, CONFIG.OFF_TYPE)
        state.source_type = u32_at(src_rec, CONFIG.OFF_TYPE)
        state.expl_old = u32_at(cur, CONFIG.OFF_EXPL_IMPACT)
        state.expl_new = u32_at(new, CONFIG.OFF_EXPL_IMPACT)
        state.model_new = "0x" .. hex8_be(new, CONFIG.OFF_UNIT)
        state.thr_new = "0x" .. hex8_be(new, CONFIG.OFF_THRUSTER)
        state.trail_new = "0x" .. hex8_be(new, CONFIG.OFF_TRAIL)
        state.delay_old = string.format("%.2f", f32_at(cur, CONFIG.OFF_EXPL_DELAY))
        state.delay_new = string.format("%.2f", f32_at(new, CONFIG.OFF_EXPL_DELAY))
        state.flags_old = string.format("0x%02X", string.byte(cur, CONFIG.OFF_FLAGS + 1))
        state.flags_new = string.format("0x%02X", string.byte(new, CONFIG.OFF_FLAGS + 1))
        state.source_desc = string.format(
            "cal=%.0f spd=%.0f mass=%.0f life=%.2f prox=%.1f (idx %d)",
            f32_at(src_rec, CONFIG.OFF_CAL), f32_at(src_rec, CONFIG.OFF_SPEED),
            f32_at(src_rec, CONFIG.OFF_MASS), f32_at(src_rec, CONFIG.OFF_LIFE),
            f32_at(src_rec, CONFIG.OFF_EXPL_PROX), src_idx)
    end
    if not patch_applied_ok(new, src_rec) then
        log_err(string.format("field patch incomplete @0x%X: model/particles/explosion not taken from source; refusing",
            tgt_addr))
        return false
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
    -- 去重登记
    local seen = false
    for i = 1, #state.copies do if state.copies[i].rec == tgt_addr then seen = true end end
    if not seen then
        state.copies[#state.copies + 1] = { rec = tgt_addr, want = new, idx = tgt_idx, blk = blk.addr }
    end
    log(string.format("%s bug artillery @0x%X (idx %d, type %s): shape kept vanilla bile (unit %s / thr %s / trail %s), impact explosion %s->%s (airburst cluster), submuni delay %s->%s flags %s->%s (25 bomblets w/ rocket scatter), flight preserved [src idx %d]",
        is_already and "ALREADY" or "PATCHED", tgt_addr, tgt_idx, tostring(state.target_type),
        tostring(state.model_new), tostring(state.thr_new), tostring(state.trail_new),
        tostring(state.expl_old), tostring(state.expl_new),
        tostring(state.delay_old), tostring(state.delay_new),
        tostring(state.flags_old), tostring(state.flags_new), src_idx))
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
            .. "): Bile Spewer bile mortars now look like airburst rockets and burst into an airburst cluster on impact")
    end
end

-- ---------------------------------------------------------------------------
-- 稳态: 只按已记录的地址直读复查(绝不再跑全表解析)
-- ---------------------------------------------------------------------------
-- 本 addon 实际改写的字段(受 SWAP_FLIGHT_FX 等开关影响) —— 复查时只为它们负责
local owned_fields = {}
for i = 1, #PATCH_FIELDS do
    if group_enabled(PATCH_FIELDS[i].group) then owned_fields[#owned_fields + 1] = PATCH_FIELDS[i] end
end

-- 从 cur 出发, 只把"自己负责的字段"按 want 补齐; 返回 (new, need_rewrite)
local function rebuild_owned(cur, want)
    if cur == nil then return nil, false end
    local out = cur
    local need = false
    for i = 1, #owned_fields do
        local f = owned_fields[i]
        local wb = string.sub(want, f.off + 1, f.off + f.len)
        if string.sub(cur, f.off + 1, f.off + f.len) ~= wb then
            out = string.sub(out, 1, f.off) .. wb .. string.sub(out, f.off + f.len + 1)
            need = true
        end
    end
    return out, need
end

local function recheck()
    local changed = false
    local i = 1
    while i <= #state.copies do
        local c = state.copies[i]
        local cur = read_mem(c.rec, #c.want)
        -- ★ v1.5.0: 只为**自己负责的那几段字段**负责 —— 从"当前字节"出发，
        --   只把属于自己的字段按 c.want 补齐, 绝不整条回写.
        --   (否则会把别的 mod 改在同一记录上的字段覆盖掉, 两边每 5 秒互抢.)
        local new, need = rebuild_owned(cur, c.want)
        if cur == nil or not is_target_record(cur) then
            table.remove(state.copies, i); changed = true
        elseif need then
            log(string.format("copy @0x%X lost (some of) its patch; re-applying own fields", c.rec))
            if write_mem(c.rec, new) then
                local back = read_mem(c.rec, #new)
                local _, still = rebuild_owned(back, c.want)
                if still then table.remove(state.copies, i); changed = true
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
        tgt_trail = hex_to_le_bytes(CONFIG.TGT_TRAIL_HEX)
        src_trail = hex_to_le_bytes(CONFIG.SRC_TRAIL_HEX)
        tgt_thr   = hex_to_le_bytes(CONFIG.TGT_THR_HEX)
        src_flags = CONFIG.SRC_FLAGS
        src_delay = CONFIG.SRC_DELAY_LE
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
        -- 稳态: 每 60 帧唤醒一次
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
