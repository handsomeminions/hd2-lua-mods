# -*- coding: utf-8 -*-
"""test_sterilizer_gas_damage.py —— sterilizer_gas_damage.lua (v2.0.0) 的 lupa 离线仿真测试

用户需求(本套测试守着):
  (1) TX-41 灭菌器 的伤害提升为 G-4 毒气榴弹一样
        => DamageSettings / DamageInfoType_Spray_Chem_Gun / damage 1 -> 3
  (2) 灭菌器的毒气状态效果"施加量" -> 原版 2 倍 (0.5 -> 1.0), **只影响灭菌器**
        => DamageInfoType_Spray_Chem_Gun / SE[Gas].value   @+48 : 0.5 -> 1.0
                                        SE[Gas_Confusion].value @+56 : 0.5 -> 1.0
本套测试同时守着"绝不动别的记录/别的字节"(尤其紧邻的敌方 Drone_Chem_Gun 与 SE[1].type @+52)。

夹具来自**当前构建的真实明文镜像**(vendor/.../generated_damage_settings.dl_bin):
  fixtures/sz_table_block.bin   DamageSettings 真实整表(649 条 x 76B)
  fixtures/sz_spray.bin         第 29 条 = Spray_Chem_Gun (灭菌器, 目标)
  fixtures/sz_drone.bin         第 30 条 = Drone_Chem_Gun (敌方无人机, 数值相同, 必须不动)
"""
import os, re, struct, sys
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SRC = os.environ.get("HD2_ADDON_SZ_SRC") or os.path.abspath(
    os.path.join(HERE, "..", "src", "sterilizer_gas_damage.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()


def fx(n):
    return open(os.path.join(FIX, n), "rb").read()


BLOCK = fx("sz_table_block.bin")
SPRAY = fx("sz_spray.bin")
DRONE = fx("sz_drone.bin")

TYPE_DAMAGE = 0xE0A72CF0          # djb2("DamageSettings")
STRIDE = 76
RECORDS = 649
REGION_SIZE = 0x40000
SPRAY_IDX = 29
DRONE_IDX = 30
OFF_DAMAGE, OFF_DURABLE = 4, 8
OFF_AP, OFF_SE = 12, 44
OFF_SE0_TYPE, OFF_SE0_VALUE = 44, 48
OFF_SE1_TYPE, OFF_SE1_VALUE = 52, 56
OFF_SE2_TYPE, OFF_SE3_TYPE = 60, 68

BASE, BOFF = 0x20000000, 0x1000
LOGDIR = (os.getenv("LOCALAPPDATA") or "") + "/CowboyBingus/Helldivers2/Logs/"
CFG = LOGDIR + "sterilizer_gas_damage.cfg"
DEFAULT_DMG = 3
DEFAULT_GAS = 1.0
VANILLA_GAS = 0.5


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def f32(b, o):
    return struct.unpack_from("<f", b, o)[0]


def with_patch(rec, d=DEFAULT_DMG, g=DEFAULT_GAS):
    """应用本 mod 应有的全部改写: damage/durable(+4..+11) + 两条 SE value(+48/+56)。"""
    b = bytearray(rec)
    struct.pack_into("<II", b, OFF_DAMAGE, d, d)
    gb = struct.pack("<f", g)
    b[OFF_SE0_VALUE:OFF_SE0_VALUE + 4] = gb
    b[OFF_SE1_VALUE:OFF_SE1_VALUE + 4] = gb
    return bytes(b)


# 允许发生变化的字节集合
ALLOWED_DIFF = set(range(4, 12)) | set(range(48, 52)) | set(range(56, 60))


def synth_block(records):
    n = len(records)
    sz = 16 + n * STRIDE
    head = b"LDLD" + struct.pack("<III", 1, TYPE_DAMAGE, sz) + b"\x00" * 8
    return head + struct.pack("<QQ", 16, n) + b"".join(records)


def add_region(L, base, size, data=b"", prot=0x04):
    body = (data + b"\x00" * size)[:size]
    L.globals().HARNESS.add_region_hex(base, size, body.hex().upper(), prot)


def new_env():
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute(HARNESS_SRC)
    return L


def run(src=ADDON_SRC, frames=600, tables=None, loader=(1, 19), cfg=None,
        files=None, write_fail_addrs=()):
    L = new_env()
    L.execute("HARNESS.reset()")
    if loader is None:
        L.execute("HARNESS.clear_loader()")
    else:
        L.execute("HARNESS.set_loader(%d, %d)" % loader)
    L.execute('HARNESS.status_file = "sterilizer_gas_damage_STATUS.txt"')
    L.execute('HARNESS.log_file = "sterilizer_gas_damage.log"')
    for t in (tables or []):
        base, off, block = t[0], t[1], t[2]
        prot = t[3] if len(t) > 3 else 0x04
        add_region(L, base, REGION_SIZE, b"\x00" * off + block, prot)
    if cfg is not None:
        L.globals().CFG_TXT = cfg
        L.globals().CFG_PATH = CFG
        L.execute("HARNESS.preload_file(CFG_PATH, CFG_TXT)")
    for p, c in (files or {}).items():
        L.globals().FP = p
        L.globals().FC = c
        L.execute("HARNESS.preload_file(FP, FC)")
    for a in write_fail_addrs:
        L.execute("HARNESS.write_fail[%d] = true" % a)
    L.execute("HARNESS.install_update_hook()")
    L.globals().ADDON_SRC = src
    L.execute("HARNESS.run_addon(ADDON_SRC)")
    L.execute("HARNESS.frames(%d)" % frames)
    return L


# ---------------------------------------------------------------------------
# 观测助手
# ---------------------------------------------------------------------------
def patched(L):
    return L.globals().HARNESS.patched_records()


def status_text(L):
    return L.globals().HARNESS.status_text() or ""


def status_head(L):
    return L.globals().HARNESS.status_head() or ""


def log_text(L):
    L.globals().HARNESS.flush_addon_log()
    return L.globals().HARNESS.log_text() or ""


def write_count(L):
    return L.globals().HARNESS.write_count()


def abs_bytes(L, addr, n):
    h = L.globals().HARNESS.abs_hex(addr, n)
    return bytes.fromhex(h) if h else None


def stat_field(L, key):
    m = re.search(re.escape(key) + r"=([^\s]+)", status_text(L))
    return m.group(1) if m else None


def rec_base(region_base, off):
    return region_base + off + 40


def spray_addr():
    return rec_base(BASE, BOFF) + SPRAY_IDX * STRIDE


def drone_addr():
    return rec_base(BASE, BOFF) + DRONE_IDX * STRIDE


class Checker:
    def __init__(self, name): self.name = name; self.fails = []
    def eq(self, got, want, what):
        if got != want: self.fails.append("%s: got %r want %r" % (what, got, want))
    def true(self, cond, what):
        if not cond: self.fails.append(what)
    def result(self): return (self.name, self.fails)


TESTS = []
def test(fn): TESTS.append(fn); return fn


REAL = [(BASE, BOFF, BLOCK)]


# ---------------------------------------------------------------------------
# 功能
# ---------------------------------------------------------------------------
@test
def t1_real_table_patches():
    """真实整表: 灭菌器记录被改成 3/3 + 毒气施加量 1.0, STATUS 报 OK。"""
    L = run(tables=REAL)
    c = Checker("T1")
    c.true(status_head(L).startswith("OK - patch applied"), "status OK (%r)" % status_head(L))
    c.eq(patched(L), 1, "patched_records == 1")
    c.eq(stat_field(L, "damage"), "1->%d" % DEFAULT_DMG, "damage=1->3 in status")
    got = abs_bytes(L, spray_addr(), STRIDE)
    c.eq(u32(got, OFF_DAMAGE), DEFAULT_DMG, "damage == 3")
    c.eq(u32(got, OFF_DURABLE), DEFAULT_DMG, "durable_damage == 3")
    c.eq(round(f32(got, OFF_SE0_VALUE), 4), DEFAULT_GAS, "SE[Gas].value == 1.0")
    c.eq(round(f32(got, OFF_SE1_VALUE), 4), DEFAULT_GAS, "SE[Gas_Confusion].value == 1.0")
    c.eq(u32(got, OFF_SE0_TYPE), u32(SPRAY, OFF_SE0_TYPE), "SE[0].type unchanged")
    c.eq(u32(got, OFF_SE1_TYPE), u32(SPRAY, OFF_SE1_TYPE), "SE[1].type unchanged")
    c.true("PATCHED" in log_text(L), "log has PATCHED line")
    c.true("damage_info_type 28" in log_text(L), "log records damage_info_type 28")
    return c.result()


@test
def t2_only_allowed_bytes_change():
    """★ 除目标记录的 +4..+11 与 +48..+51/+56..+59 外, 整张表逐字节不动。"""
    L = run(tables=REAL)
    c = Checker("T2")
    for k in range(RECORDS):
        got = abs_bytes(L, rec_base(BASE, BOFF) + k * STRIDE, STRIDE)
        orig = BLOCK[40 + k * STRIDE: 40 + (k + 1) * STRIDE]
        if k == SPRAY_IDX:
            c.eq(got, with_patch(orig), "target record == vanilla + our patch")
            diff = [i for i in range(STRIDE) if got[i] != orig[i]]
            c.true(all(i in ALLOWED_DIFF for i in diff),
                   "every changed byte inside allowed set (%s)" % diff)
            c.true(4 in diff and 8 in diff, "damage(+4)/durable(+8) changed (%s)" % diff)
            c.true(50 in diff and 58 in diff, "SE values(+48/+56) changed (%s)" % diff)
            c.true(52 not in diff, "SE[1].type(+52) NOT touched (%s)" % diff)
        else:
            if got != orig:
                c.true(False, "record %d must be untouched" % k)
                break
    return c.result()


@test
def t3_drone_record_untouched():
    """★ 紧邻的敌方 Drone_Chem_Gun(数值完全相同) 必须原封不动。"""
    L = run(tables=REAL)
    c = Checker("T3")
    c.eq(abs_bytes(L, drone_addr(), STRIDE), DRONE, "drone record untouched")
    return c.result()


@test
def t4_status_reports_target():
    c = Checker("T4")
    L = run(tables=REAL)
    c.true("damage_info_type=28" in status_text(L), "status has damage_info_type=28")
    c.true("patched_records=1" in status_text(L), "status has patched_records=1")
    c.true("copy1: rec@0x" in status_text(L), "status lists the patched copy")
    c.true("host" in status_text(L), "host-authoritative note present")
    return c.result()


@test
def t5_idempotent():
    """幂等: 打上之后再跑多个周期, 不重复写。"""
    L = run(tables=REAL, frames=600)
    c = Checker("T5")
    w1 = write_count(L)
    L.execute("HARNESS.frames(1800)")
    w2 = write_count(L)
    c.eq(w1, w2, "no extra writes after 3 more recheck cycles (%d==%d)" % (w1, w2))
    c.eq(abs_bytes(L, spray_addr(), STRIDE), with_patch(SPRAY), "record still patched")
    return c.result()


@test
def t6_cfg_overrides():
    """cfg 覆盖: damage=5 / gas=2.5。"""
    L = run(tables=REAL, cfg="damage=5\ngas=2.5\n")
    c = Checker("T6")
    got = abs_bytes(L, spray_addr(), STRIDE)
    c.eq(u32(got, OFF_DAMAGE), 5, "damage == 5")
    c.eq(round(f32(got, OFF_SE0_VALUE), 4), 2.5, "gas == 2.5")
    c.eq(round(f32(got, OFF_SE1_VALUE), 4), 2.5, "gas (2nd SE) == 2.5")
    c.eq(stat_field(L, "damage"), "1->5", "status damage=1->5")
    c.eq(stat_field(L, "gas_buildup"), "0.5->2.500", "status gas_buildup=0.5->2.500")
    return c.result()


@test
def t7_cfg_invalid_falls_back():
    """cfg 非法(超范围/非数字) -> 退回默认, 不得乱写。"""
    c = Checker("T7")
    L = run(tables=REAL, cfg="damage=99999\ngas=99999\n")
    got = abs_bytes(L, spray_addr(), STRIDE)
    c.eq(u32(got, OFF_DAMAGE), DEFAULT_DMG, "out-of-range damage -> default 3")
    c.eq(round(f32(got, OFF_SE0_VALUE), 4), DEFAULT_GAS, "out-of-range gas -> default 1.0")
    L2 = run(tables=REAL, cfg="not-a-number\n")
    c.eq(u32(abs_bytes(L2, spray_addr(), STRIDE), OFF_DAMAGE), DEFAULT_DMG, "non-numeric -> default 3")
    return c.result()


@test
def t8_write_failure_refused():
    """写入静默失败 -> 回读校验必须抓住, 不报 OK。"""
    L = run(tables=REAL, write_fail_addrs=[spray_addr() + OFF_DAMAGE])
    c = Checker("T8")
    c.true(not status_head(L).startswith("OK"), "status is not OK (%r)" % status_head(L))
    c.eq(u32(abs_bytes(L, spray_addr(), STRIDE), OFF_DAMAGE), 1, "record still vanilla")
    c.true("read-back mismatch" in log_text(L), "log mentions read-back mismatch")
    return c.result()


@test
def t9_no_table_no_write():
    """表不存在 -> 不写任何字节。"""
    L = run(tables=[])
    c = Checker("T9")
    c.eq(patched(L), 0, "patched_records == 0")
    c.eq(write_count(L), 0, "no writes")
    c.true(status_head(L).startswith("SEARCHING"), "status still SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t10_no_global_pollution():
    """只应新增自己的唯一命名全局 + 单例。"""
    L = run(tables=REAL, frames=200)
    c = Checker("T10")
    names = L.eval("(function() local o={} for k,v in pairs(_G) do o[#o+1]=k end table.sort(o) return table.concat(o, ',') end)()")
    names = set(str(names).split(","))
    for bad in ("flush_log", "end_pass", "process_dmg_block", "patch_into_table",
                "write_damage", "is_target_record", "tick", "want_dmg"):
        c.true(bad not in names, "no leaked global %r" % bad)
    c.true("_HD2_STERILIZER_FLUSH" in names, "unique flush global present")
    return c.result()


@test
def t11_non_adjacent_candidates_refused():
    """两条候选的 DamageInfoType 不相邻 -> 拒绝写入(避免改错记录)。"""
    d99 = DRONE[:0] + struct.pack("<I", 99) + DRONE[4:]
    block = synth_block([SPRAY, d99])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T11")
    c.eq(patched(L), 0, "refused (patched==0)")
    c.true(not status_head(L).startswith("OK"), "status not OK")
    c.true("not adjacent" in log_text(L), "log says not adjacent")
    return c.result()


@test
def t12_too_many_candidates_refused():
    """超过 2 条候选 -> 拒绝(判据不确定, 宁可不动)。"""
    d29 = DRONE[:0] + struct.pack("<I", 29) + DRONE[4:]
    d31 = DRONE[:0] + struct.pack("<I", 31) + DRONE[4:]
    block = synth_block([SPRAY, d29, d31])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T12")
    c.eq(patched(L), 0, "refused (patched==0)")
    c.true("expected exactly 2" in log_text(L), "log says expected exactly 2")
    return c.result()


@test
def t13_already_patched_recognised():
    """记录已经是本 mod 的值(3/3) -> 认作 ALREADY, 不重复写。"""
    block = synth_block([with_patch(SPRAY), DRONE])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T13")
    c.true(status_head(L).startswith("OK - patch applied"), "status OK")
    c.eq(patched(L), 1, "patched_records == 1")
    c.eq(write_count(L), 0, "no writes (already at target)")
    c.true("ALREADY" in log_text(L), "log says ALREADY")
    return c.result()


@test
def t14_partial_fingerprint_match_refused():
    """★ 只有 1 条候选(另一条指纹不匹配) -> 必须拒绝, 绝不冒险改到敌方无人机那条。"""
    bad = SPRAY[:OFF_AP] + struct.pack("<I", 6) + SPRAY[OFF_AP + 4:]
    block = synth_block([bad, DRONE])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T14")
    c.eq(patched(L), 0, "nothing patched")
    c.eq(write_count(L), 0, "no writes")
    return c.result()


@test
def t15_loader_too_old_stops():
    """loader API 0 (v14) -> 立刻停手, 不扫不写。"""
    L = run(tables=REAL, loader=(0, 14))
    c = Checker("T15")
    c.true(status_head(L).startswith("FAILED"), "status FAILED (%r)" % status_head(L))
    c.eq(write_count(L), 0, "no writes")
    return c.result()


@test
def t16_legacy_cfg_single_number():
    """旧格式 cfg(单个裸数字) 仍被当作 damage; gas 用默认。"""
    L = run(tables=REAL, cfg="5\n")
    c = Checker("T16")
    got = abs_bytes(L, spray_addr(), STRIDE)
    c.eq(u32(got, OFF_DAMAGE), 5, "legacy '5' -> damage 5")
    c.eq(round(f32(got, OFF_SE0_VALUE), 4), DEFAULT_GAS, "gas stays default 1.0")
    return c.result()


@test
def t17_cfg_hot_change_reapplies():
    """★ 稳态热调 cfg: 3/1.0 打完 -> 改成 7/3.5 -> 记录被重打(指纹不被自己的改动冲掉)。"""
    L = run(tables=REAL, cfg="damage=3\ngas=1.0\n", frames=400)
    c = Checker("T17")
    c.eq(u32(abs_bytes(L, spray_addr(), STRIDE), OFF_DAMAGE), 3, "initial damage 3")
    c.eq(patched(L), 1, "1 tracked copy before hot change")
    L.globals().CFG_TXT = "damage=7\ngas=3.5\n"
    L.globals().CFG_PATH = CFG
    L.execute("HARNESS.preload_file(CFG_PATH, CFG_TXT)")
    L.execute("HARNESS.frames(1200)")
    got = abs_bytes(L, spray_addr(), STRIDE)
    c.eq(u32(got, OFF_DAMAGE), 7, "damage hot-changed to 7")
    c.eq(round(f32(got, OFF_SE0_VALUE), 4), 3.5, "gas hot-changed to 3.5")
    c.eq(round(f32(got, OFF_SE1_VALUE), 4), 3.5, "gas (2nd SE) hot-changed to 3.5")
    c.eq(patched(L), 1, "fingerprint survived the change (still exactly 1 copy)")
    return c.result()


@test
def t18_drone_se_values_untouched():
    """★ 敌方 Drone_Chem_Gun 的两条 SE value(也是 0.5) 绝不能被写。"""
    L = run(tables=REAL)
    c = Checker("T18")
    d = abs_bytes(L, drone_addr(), STRIDE)
    c.eq(round(f32(d, OFF_SE0_VALUE), 4), VANILLA_GAS, "drone SE[0].value stays 0.5")
    c.eq(round(f32(d, OFF_SE1_VALUE), 4), VANILLA_GAS, "drone SE[1].value stays 0.5")
    c.eq(d, DRONE, "drone record byte-identical to vanilla")
    return c.result()


@test
def t19_se_type_mismatch_refused():
    """两条候选的 SE 类型不一致(= 不是同一对) -> 拒绝写入。"""
    d = bytearray(DRONE)
    struct.pack_into("<I", d, OFF_SE1_TYPE, 77)      # 把 Drone 的 SE[1].type 改掉
    block = synth_block([SPRAY, bytes(d)])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T19")
    c.eq(patched(L), 0, "refused (patched==0)")
    c.true(not status_head(L).startswith("OK"), "status not OK")
    c.true("status-effect types differ" in log_text(L), "log says SE types differ")
    return c.result()


# ---------------------------------------------------------------------------
# 变异
# ---------------------------------------------------------------------------
def mutated(pairs):
    out = ADDON_SRC
    for a, b in pairs:
        if a not in out:
            raise RuntimeError("mutation anchor not found: %r" % a[:70])
        out = out.replace(a, b, 1)
    return out


MUTATIONS = [
    ("M1_identity_always_true",
     [("local function is_target_record(r)\n",
       "local function is_target_record(r)\n    return true\n")],
     "身份指纹失效 -> 命中整表 -> 必须靠 #hits>2 拒绝"),
    ("M2_durable_not_written",
     [("    local bytes = u32_le(n) .. u32_le(n)", "    local bytes = u32_le(n) .. u32_le(1)")],
     "只写 damage 不写 durable -> 记录不该通过 +4..+11 校验"),
    ("M3_pick_higher_type",
     [("    local chosen = (h2.ty < h1.ty) and h2 or h1",
       "    local chosen = (h2.ty > h1.ty) and h2 or h1")],
     "取 Type 较大者 = 敌方无人机 -> Drone 记录会被改"),
    ("M4_no_candidate_cap",
     [("    if #hits ~= 2 then", "    if false then")],
     "去掉候选数约束 -> 3 条候选时也会瞎选一条"),
    ("M5_no_readback",
     [("    if back == nil or u32_at(back, 0) ~= n or u32_at(back, 4) ~= n then",
       "    if false then")],
     "去掉回读校验 -> 写入失败被漏过"),
    ("M6_no_damage_write",
     [("local function write_damage(rec_addr, n)\n    local bytes = u32_le(n) .. u32_le(n)",
       "local function write_damage(rec_addr, n)\n    if true then return true end\n    local bytes = u32_le(n) .. u32_le(n)")],
     "write_damage 变成空操作 -> damage/durable 保持原版 1"),
    ("M7_no_gas_write",
     [("local function write_gas(rec_addr, g)\n    local want = f32_bits(g)",
       "local function write_gas(rec_addr, g)\n    if true then return true end\n    local want = f32_bits(g)")],
     "write_gas 变成空操作 -> 两条 SE value 保持 0.5"),
    ("M8_gas_written_at_wrong_offset",
     [("    if not write_mem(rec_addr + CONFIG.OFF_SE0_VALUE, bytes) then",
       "    if not write_mem(rec_addr + CONFIG.OFF_SE0_TYPE, bytes) then")],
     "毒气值写到 SE[0].type 上 -> 记录被破坏"),
    ("M9_gas_value_wrong",
     [("    local want = f32_bits(g)", "    local want = f32_bits(0.5)")],
     "毒气写成了原版 0.5 -> 等于没改"),
]


def _three_candidate_block():
    d29 = DRONE[:0] + struct.pack("<I", 29) + DRONE[4:]
    d31 = DRONE[:0] + struct.pack("<I", 31) + DRONE[4:]
    return synth_block([SPRAY, d29, d31])


def check_ok(L):
    return status_head(L).startswith("OK - patch applied") and patched(L) == 1


def check_8bytes(L):
    got = abs_bytes(L, spray_addr(), STRIDE)
    if got != with_patch(SPRAY):
        return False
    for k in (0, DRONE_IDX):
        if abs_bytes(L, rec_base(BASE, BOFF) + k * STRIDE, STRIDE) != BLOCK[40 + k * STRIDE: 40 + (k + 1) * STRIDE]:
            return False
    return True


def check_drone_untouched(L):
    return abs_bytes(L, drone_addr(), STRIDE) == DRONE


def check_writefail(L):
    return (not status_head(L).startswith("OK")) and u32(abs_bytes(L, spray_addr(), STRIDE), OFF_DAMAGE) == 1


def check_patched(L):
    return patched(L) == 1 and u32(abs_bytes(L, spray_addr(), STRIDE), OFF_DAMAGE) == DEFAULT_DMG


def check_gas(L):
    got = abs_bytes(L, spray_addr(), STRIDE)
    return (round(f32(got, OFF_SE0_VALUE), 4) == DEFAULT_GAS
            and round(f32(got, OFF_SE1_VALUE), 4) == DEFAULT_GAS)


def check_target_exact(L):
    return (abs_bytes(L, spray_addr(), STRIDE) == with_patch(SPRAY)
            and abs_bytes(L, drone_addr(), STRIDE) == DRONE)


MUT_CASES = {
    "M1_identity_always_true": (lambda s: run(src=s, tables=REAL), check_ok),
    "M2_durable_not_written": (lambda s: run(src=s, tables=REAL), check_8bytes),
    "M3_pick_higher_type": (lambda s: run(src=s, tables=REAL), check_drone_untouched),
    "M4_no_candidate_cap": (lambda s: run(src=s, tables=[(BASE, BOFF, _three_candidate_block())]),
                            lambda L: patched(L) == 0),
    "M5_no_readback": (lambda s: run(src=s, tables=REAL,
                                     write_fail_addrs=[spray_addr() + OFF_DAMAGE]), check_writefail),
    "M6_no_damage_write": (lambda s: run(src=s, tables=REAL), check_patched),
    "M7_no_gas_write": (lambda s: run(src=s, tables=REAL), check_gas),
    "M8_gas_written_at_wrong_offset": (lambda s: run(src=s, tables=REAL), check_target_exact),
    "M9_gas_value_wrong": (lambda s: run(src=s, tables=REAL), check_gas),
}


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    total = passed = 0
    fails = []
    for fn in TESTS:
        if only and not fn.__name__.startswith(only.lower()):
            continue
        name, f = fn()
        total += 1
        if f:
            fails.append((name, f))
        else:
            passed += 1
    for mname, pairs, desc in MUTATIONS:
        if only and not mname.lower().startswith(only.lower()):
            continue
        total += 1
        try:
            src = mutated(pairs)
            scen, check = MUT_CASES[mname]
            L = scen(src)
            if check(L):
                fails.append(("MUT:%s" % mname, ["变异未被抓住: " + desc]))
            else:
                passed += 1
        except RuntimeError:
            raise
        except Exception:
            passed += 1      # 变异导致运行期直接报错, 同样算"被抓住"
    print("=" * 66)
    print("通过 %d, 失败 %d" % (passed, total - passed))
    for n, f in fails:
        print("FAIL %s" % n)
        for x in f[:6]:
            print("   - %s" % x)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
