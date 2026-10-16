# -*- coding: utf-8 -*-
"""
test_addon.py —— orbital_120mm_500kg.lua (v1.3.0) 的 lupa 离线仿真测试

在 LuaJIT 2.1 上跑真源码; harness.lua 提供假 FFI / 假内存 / 假 io / 帧驱动。

夹具全部来自**当前构建的真实 dl_bin**(analysis/ref/generated_projectile_settings.dl_bin):
  fixtures/orb_tgt194.bin     idx 135  120mm HE 火力网炮弹 (type 194)
  fixtures/orb_tgt137.bin     idx 136  120mm HE 火力网炮弹 (type 137)
  fixtures/orb_src500kg.bin   idx 12   飞鹰500kg炸弹 (type 239) —— 取它的爆炸配置当新爆炸
  fixtures/orb_decoy_napalm.bin idx 140 同名"120mm HE CANNON ROUND"但是凝固汽油弹 (type 234)
  fixtures/orb_decoy_super.bin  idx 344 同名但是某超级弹 (type 13)
  fixtures/orb_filler.bin     idx 0
  fixtures/orb_table_block.bin 真实整块 LDLD(350 条记录)

用户要求(本套测试守着):
  1) 打击后爆炸换成飞鹰500kg的爆炸(粒子/音效/伤害/范围)  -> +60/+144/+152/+156 取自源
  2) 打击弹道/攻击/模型/拖尾/飞行音效 保持原版 120mm     -> 除那 4 段外逐字节相同
"""
import os, sys, re, struct
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SRC_ENV = os.environ.get("HD2_ADDON_SRC")
SRC = SRC_ENV or os.path.abspath(os.path.join(HERE, "..", "src", "orbital_120mm_500kg.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()


def fx(name):
    return open(os.path.join(FIX, name), "rb").read()

TGT194 = fx("orb_tgt194.bin")
TGT137 = fx("orb_tgt137.bin")
SRC_R  = fx("orb_src500kg.bin")
DEC_NAP = fx("orb_decoy_napalm.bin")
DEC_SUP = fx("orb_decoy_super.bin")
FIL    = fx("orb_filler.bin")
BLOCK  = fx("orb_table_block.bin")

TYPE_PROJECTILE = 0xBD4042C2
TARGET_TYPES = (194, 137)
SOURCE_TYPE = 239
STRIDE = 272
REGION_SIZE = 0x40000
REAL_TGT194_IDX = 135
REAL_TGT137_IDX = 136

OFF_TYPE = 0
OFF_NAME_UPPER = 4
OFF_CAL = 24
OFF_SPEED = 32
OFF_MASS = 36
OFF_DRAG = 40
OFF_GRAV = 44
OFF_LIFE = 52
OFF_DMG = 60
OFF_TRAIL = 96
OFF_UNIT = 128
OFF_THR = 136
OFF_IMP = 144
OFF_PROX = 148
OFF_DELAY = 152
OFF_EXPIRE = 156
OFF_ARM = 160
OFF_AUDIO = 208

# 本 mod 只改这 4 段(0-based, (start, len))
SWAP = [(OFF_DMG, 4), (OFF_IMP, 4), (OFF_DELAY, 4), (OFF_EXPIRE, 4)]


def splice(base, src, off, ln):
    return base[:off] + src[off:off + ln] + base[off + ln:]


def splice_all(base, src):
    out = base
    for off, ln in SWAP:
        out = splice(out, src, off, ln)
    return out


PATCHED194 = splice_all(TGT194, SRC_R)
PATCHED137 = splice_all(TGT137, SRC_R)


def make_block(records, block_addr=0, file_form=True):
    n = len(records)
    size = 16 + n * STRIDE
    head = b"LDLD" + struct.pack("<III", 1, TYPE_PROJECTILE, size) + b"\x00" * 8
    ptr = 16 if file_form else (block_addr + 40)
    return head + struct.pack("<QQ", ptr, n) + b"".join(records)


def add_region(L, base, size, data=b"", prot=0x04):
    body = (data + b"\x00" * size)[:size]
    L.globals().HARNESS.add_region_hex(base, size, body.hex().upper(), prot)


def new_env():
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute(HARNESS_SRC)
    L.execute('HARNESS.status_file = "orbital_120mm_500kg_STATUS.txt"')
    L.execute('HARNESS.log_file = "orbital_120mm_500kg.log"')
    return L


def run(src=ADDON_SRC, frames=300, tables=None, loader=(1, 19), preload_loader_log=None,
        write_fail_addrs=()):
    L = new_env()
    L.execute("HARNESS.reset()")
    if loader is None:
        L.execute("HARNESS.clear_loader()")
    else:
        L.execute("HARNESS.set_loader(%d, %d)" % loader)
    for t in (tables or []):
        base, off, block = t[0], t[1], t[2]
        prot = t[3] if len(t) > 3 else 0x04
        add_region(L, base, REGION_SIZE, b"\x00" * off + block, prot)
    if preload_loader_log:
        L.globals().LOG_TEXT = preload_loader_log
        L.execute("HARNESS.preload_loader_log(LOG_TEXT)")
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


class Checker:
    def __init__(self, name): self.name = name; self.fails = []
    def eq(self, got, want, what):
        if got != want: self.fails.append("%s: got %r want %r" % (what, got, want))
    def true(self, cond, what):
        if not cond: self.fails.append(what)
    def result(self): return (self.name, self.fails)


TESTS = []
def test(fn): TESTS.append(fn); return fn


BASE, BOFF = 0x20000000, 0x1000


def real_addr(idx):
    return rec_base(BASE, BOFF) + idx * STRIDE


# ---------------------------------------------------------------------------
# 功能测试
# ---------------------------------------------------------------------------
@test
def t1_real_table_patch():
    """真实整表: 命中两条 120mm HE 炮弹, 把爆炸配置换成 500kg 的."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T1")
    c.eq(patched(L), 2, "patched records (2 x 120mm HE shells)")
    c.eq(stat_field(L, "source(500kg bomb) type"), str(SOURCE_TYPE), "source type in status")
    c.true(status_head(L).startswith("OK - patch applied"), "status head OK (%r)" % status_head(L))
    c.eq(abs_bytes(L, real_addr(REAL_TGT194_IDX), STRIDE), PATCHED194, "type194 record == expected")
    c.eq(abs_bytes(L, real_addr(REAL_TGT137_IDX), STRIDE), PATCHED137, "type137 record == expected")
    return c.result()


@test
def t2_only_explosion_changed():
    """除爆炸配置 4 段外, 整条记录必须与原版**逐字节相同**(弹道/速度/模型/拖尾/音效 全不动)."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T2")
    got = abs_bytes(L, real_addr(REAL_TGT194_IDX), STRIDE)
    c.true(got is not None, "record readable")
    if got is None:
        return c.result()
    swapped = set()
    for off, ln in SWAP:
        for i in range(off, off + ln):
            swapped.add(i)
    for i in range(STRIDE):
        if i not in swapped and got[i] != TGT194[i]:
            c.fails.append("byte %d changed (not in SWAP set)" % i)
            break
    # 逐字段点名(便于定位)
    for off, ln, name in [(OFF_TYPE, 4, "type"), (OFF_NAME_UPPER, 4, "name_upper"),
                          (OFF_CAL, 4, "calibre"), (OFF_SPEED, 4, "speed"), (OFF_MASS, 4, "mass"),
                          (OFF_DRAG, 4, "drag"), (OFF_GRAV, 4, "gravity"), (OFF_LIFE, 4, "life_time"),
                          (OFF_TRAIL, 8, "particle_trail"), (OFF_UNIT, 8, "projectile_unit_path"),
                          (OFF_THR, 4, "explosion_threshold_angle"), (OFF_PROX, 4, "explosion_proximity"),
                          (OFF_ARM, 4, "arming_distance"), (OFF_AUDIO, 4, "audio_trail_start")]:
        c.eq(got[off:off + ln], TGT194[off:off + ln], "%s unchanged" % name)
    c.eq(struct.unpack_from("<f", got, OFF_SPEED)[0], 400.0, "speed still 400 (vanilla 120mm)")
    c.eq(struct.unpack_from("<f", got, OFF_MASS)[0], 5000.0, "mass still 5000")
    c.eq(struct.unpack_from("<f", got, OFF_DRAG)[0], 0.0, "drag still 0")
    c.eq(struct.unpack_from("<f", got, OFF_GRAV)[0], 1.0, "gravity still 1")
    c.eq(struct.unpack_from("<f", got, OFF_LIFE)[0], 0.0, "life_time still 0")
    c.eq(struct.unpack_from("<f", got, OFF_THR)[0], 80.0, "explosion_threshold_angle still 80")
    # 爆炸配置确实变成了源的
    c.eq(got[OFF_DMG:OFF_DMG + 4], SRC_R[OFF_DMG:OFF_DMG + 4], "damage_info taken from 500kg")
    c.eq(got[OFF_IMP:OFF_IMP + 4], SRC_R[OFF_IMP:OFF_IMP + 4], "impact explosion from 500kg")
    c.eq(got[OFF_DELAY:OFF_DELAY + 4], SRC_R[OFF_DELAY:OFF_DELAY + 4], "fuse delay from 500kg")
    c.eq(got[OFF_EXPIRE:OFF_EXPIRE + 4], SRC_R[OFF_EXPIRE:OFF_EXPIRE + 4], "main explosion from 500kg")
    c.eq(round(struct.unpack_from("<f", got, OFF_DELAY)[0], 5), 0.8, "fuse delay now 0.8 (500kg)")
    c.eq(struct.unpack_from("<I", got, OFF_EXPIRE)[0], struct.unpack_from("<I", SRC_R, OFF_EXPIRE)[0],
         "main explosion index == 500kg's big blast")
    return c.result()


@test
def t3_same_name_decoys_untouched():
    """同名的凝固汽油弹/超级弹同时在表里: 一个字节都不动."""
    recs = [DEC_NAP, TGT194, TGT137, SRC_R, DEC_SUP, FIL]
    block = make_block(recs)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T3")
    c.eq(patched(L), 2, "exactly the two HE shells patched")
    base = rec_base(BASE, BOFF)
    c.eq(abs_bytes(L, base + 0 * STRIDE, STRIDE), DEC_NAP, "napalm (same name) untouched")
    c.eq(abs_bytes(L, base + 1 * STRIDE, STRIDE), PATCHED194, "type194 patched")
    c.eq(abs_bytes(L, base + 2 * STRIDE, STRIDE), PATCHED137, "type137 patched")
    c.eq(abs_bytes(L, base + 4 * STRIDE, STRIDE), DEC_SUP, "super shell (same name) untouched")
    return c.result()


@test
def t4_no_target_no_write():
    """表里没有目标时: 不得乱写."""
    block = make_block([DEC_NAP, DEC_SUP, FIL, DEC_NAP])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T4")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no memory writes")
    c.true("SEARCHING" in status_head(L), "status stays SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t5_mem_form_descriptor():
    """内存形态描述符(绝对指针)也能解析."""
    recs = [FIL, TGT194, DEC_NAP, TGT137, SRC_R, FIL]
    block = make_block(recs, block_addr=BASE + BOFF, file_form=False)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T5")
    c.eq(patched(L), 2, "patched records")
    c.eq(abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE), PATCHED194, "type194 patched")
    c.eq(abs_bytes(L, rec_base(BASE, BOFF) + 3 * STRIDE, STRIDE), PATCHED137, "type137 patched")
    return c.result()


@test
def t6_source_missing():
    """有目标但没有 500kg 源记录: 拒绝瞎打."""
    block = make_block([FIL, TGT194, TGT137, DEC_NAP])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T6")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no writes")
    c.true("source missing" in log_text(L), "log mentions missing source")
    return c.result()


@test
def t7_idempotent():
    """表里已是补丁形态: 登记但绝不重复写."""
    recs = [FIL, PATCHED194, PATCHED137, SRC_R, DEC_NAP]
    block = make_block(recs)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T7")
    c.eq(patched(L), 2, "registered as patched")
    c.eq(write_count(L), 0, "no writes (idempotent)")
    c.true("ALREADY" in log_text(L), "log says ALREADY")
    return c.result()


@test
def t8_two_table_copies():
    """内存里有两份射弹表: 两份都要打(共 4 条)."""
    b1, b2 = 0x20000000, 0x30000000
    mk = lambda: make_block([FIL, TGT194, TGT137, SRC_R, DEC_NAP])
    L = run(tables=[(b1, BOFF, mk()), (b2, BOFF, mk())], frames=600)
    c = Checker("T8")
    c.eq(patched(L), 4, "both copies patched (2 records each)")
    for b in (b1, b2):
        c.eq(abs_bytes(L, rec_base(b, BOFF) + 1 * STRIDE, STRIDE), PATCHED194, "copy 0x%X t194" % b)
        c.eq(abs_bytes(L, rec_base(b, BOFF) + 2 * STRIDE, STRIDE), PATCHED137, "copy 0x%X t137" % b)
    return c.result()


@test
def t9_write_fail_detected():
    """写入静默失败: 回读校验必须发现, 不得谎报成功."""
    block = make_block([FIL, TGT194, SRC_R, DEC_NAP])
    addr = rec_base(BASE, BOFF) + 1 * STRIDE
    L = run(tables=[(BASE, BOFF, block)], write_fail_addrs=[addr])
    c = Checker("T9")
    c.eq(patched(L), 0, "no false success")
    c.true("read-back mismatch" in log_text(L), "log mentions read-back mismatch")
    return c.result()


@test
def t10_readonly_page():
    """目标页只读: 临时解保护写入, 写完恢复原保护属性."""
    block = make_block([FIL, TGT194, TGT137, SRC_R, DEC_NAP])
    L = run(tables=[(BASE, BOFF, block, 0x02)])
    c = Checker("T10")
    c.eq(patched(L), 2, "patched on read-only page")
    c.eq(L.globals().HARNESS.region_prot(BASE), 0x02, "page protection restored")
    return c.result()


@test
def t11_loader_too_old():
    """loader API 0 (v14): 立刻停手, 不扫描不写入."""
    block = make_block([FIL, TGT194, SRC_R, DEC_NAP])
    L = run(tables=[(BASE, BOFF, block)], loader=(0, 14))
    c = Checker("T11")
    c.true("FAILED - Bingus Shared Loader too old" in status_head(L), "status FAILED (%r)" % status_head(L))
    c.eq(write_count(L), 0, "no writes")
    return c.result()


@test
def t12_loader_log_fallback():
    """拿不到 loader 全局表时: 退化为读 BingusSharedLoader.log 首行."""
    block = make_block([FIL, TGT194, SRC_R, DEC_NAP])
    L = run(tables=[(BASE, BOFF, block)], loader=None,
            preload_loader_log="Bingus Shared Loader loader-v19; API 1\nrest\n")
    c = Checker("T12")
    c.eq(patched(L), 1, "patched via log fallback")
    return c.result()


@test
def t13_recheck_reapplies():
    """补丁被冲掉: 稳态复查按地址直读发现并重打."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T13")
    addr = real_addr(REAL_TGT194_IDX)
    c.eq(patched(L), 2, "initial patch")
    L.globals().HARNESS.write_hex(addr, TGT194.hex().upper())
    L.execute("HARNESS.frames(400)")
    c.eq(abs_bytes(L, addr, STRIDE), PATCHED194, "patch re-applied")
    c.true("lost its patch; re-applying" in log_text(L), "log mentions re-apply")
    return c.result()


@test
def t14_all_copies_lost_rescan():
    """所有副本都没了(地图重载): 回到搜索态."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T14")
    c.eq(patched(L), 2, "initial patch")
    L.execute("HARNESS.drop_all_regions()")
    L.execute("HARNESS.frames(400)")
    c.true("SEARCHING - patched copies lost" in status_head(L),
           "status back to SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t15_status_and_log():
    """STATUS/日志必须把"改了什么/其余不动"写清楚."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T15")
    st = status_text(L)
    c.eq(stat_field(L, "patched_records"), "2", "patched_records=2 in status")
    c.true("flight(trajectory/arc/speed/range)_preserved=true" in st, "preserved flag in status")
    c.true("host-authoritative" in st, "host-authoritative note present")
    lg = log_text(L)
    c.true("PATCHED 120mm HE barrage shell" in lg, "log has PATCHED line")
    c.true("flight/model/speed untouched" in lg, "log says untouched")
    return c.result()


# ---------------------------------------------------------------------------
# 场景构造(供变异测试复用)
# ---------------------------------------------------------------------------
def scen_real(src):
    return run(src=src, tables=[(BASE, BOFF, BLOCK)])


def scen_name_only(src):
    """同名的凝固汽油弹排在真实目标前面"""
    block = make_block([DEC_NAP, TGT194, TGT137, SRC_R, FIL])
    return run(src=src, tables=[(BASE, BOFF, block)])


def scen_writefail(src):
    block = make_block([FIL, TGT194, SRC_R, DEC_NAP])
    return run(src=src, tables=[(BASE, BOFF, block)],
               write_fail_addrs=[rec_base(BASE, BOFF) + 1 * STRIDE])


def check_real(L):
    if patched(L) != 2:
        return False
    if abs_bytes(L, real_addr(REAL_TGT194_IDX), STRIDE) != PATCHED194:
        return False
    if abs_bytes(L, real_addr(REAL_TGT137_IDX), STRIDE) != PATCHED137:
        return False
    # 干扰项(凝固汽油弹/超级弹)必须原样
    if abs_bytes(L, real_addr(140), STRIDE) != DEC_NAP:
        return False
    if abs_bytes(L, real_addr(344), STRIDE) != DEC_SUP:
        return False
    return True


def check_writefail(L):
    return patched(L) == 0


MUTATIONS = [
    ("M1_target_audio_wrong",
     [("    TGT_AUDIO_STOP = 3741852184,", "    TGT_AUDIO_STOP = 4159288355,")],
     scen_real, check_real, "目标尾迹终止音效指纹写错 -> 找不到目标"),
    ("M2_source_name_wrong",
     [("    SRC_NAME_UPPER = 1027666422,", "    SRC_NAME_UPPER = 12345,")],
     scen_real, check_real, "源名称指纹写错 -> 取不到 500kg 源"),
    ("M3_trail_endianness",
     [('    TGT_TRAIL_HEX  = "68358A1CC55AFDDB",', '    TGT_TRAIL_HEX  = "DBFD5AC51C8A3568",')],
     scen_real, check_real, "拖尾哈希字节序搞反 -> 对不上"),
    ("M4_name_only_fingerprint",
     [("""    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.TGT_NAME_UPPER
       and u32_at(r, CONFIG.OFF_AUDIO_STOP) == CONFIG.TGT_AUDIO_STOP
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0)
       and string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) == tgt_trail""",
       """    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.TGT_NAME_UPPER""")],
     scen_name_only, check_real, "只按名字认记录 -> 打到同名的凝固汽油弹上"),
    ("M5_full_clone_guard_catches",
     [("""        out = string.sub(out, 1, f.off)
           .. string.sub(src, f.off + 1, f.off + f.len)
           .. string.sub(out, f.off + f.len + 1)""",
       """        out = string.sub(out, 1, 24) .. string.sub(src, 25)""")],
     scen_real, check_real, "改成整条克隆 -> 被 keep-guard 拦下(拒绝写入)"),
    ("M6_full_clone_no_guard",
     [("""        out = string.sub(out, 1, f.off)
           .. string.sub(src, f.off + 1, f.off + f.len)
           .. string.sub(out, f.off + f.len + 1)""",
       """        out = string.sub(out, 1, 24) .. string.sub(src, 25)"""),
      ("    if not keep_guard_ok(cur, new) then", "    if false then")],
     scen_real, check_real, "整条克隆且去掉 keep-guard -> 弹道/模型被改"),
    ("M7_wrong_offset_swapped",
     [('    { off = 144, len = 4, name = "explosion_type_on_impact" },',
       '    { off = 148, len = 4, name = "explosion_proximity" },')],
     scen_real, check_real, "偏移写错(打到近炸距离) -> 结果与预期不符"),
    ("M8_swap_speed_too",
     [('    { off = 60,  len = 4, name = "damage_info_type" },',
       '    { off = 32,  len = 4, name = "speed" },')],
     scen_real, check_real, "把速度也算进改写字段 -> 弹道被改(速度变 500)"),
    ("M9_drop_expire_swap",
     [('    { off = 156, len = 4, name = "explosion_type_expire" },', '')],
     scen_real, check_real, "漏掉主爆炸字段 -> 大爆炸没换成 500kg"),
    ("M10_no_readback_verify",
     [("""                        local back = read_mem(tgt_addr, t.stride)
                        if back ~= new then""",
       """                        local back = read_mem(tgt_addr, t.stride)
                        if false then""")],
     scen_writefail, check_writefail, "去掉回读校验 -> 写入失败被漏过"),
]


def main():
    npass = nfail = 0
    print("=" * 72); print("功能测试"); print("=" * 72)
    for fn in TESTS:
        name, fails = fn()
        if fails:
            nfail += 1; print("  [FAIL] %s" % name)
            for f in fails: print("         - %s" % f)
        else:
            npass += 1; print("  [ OK ] %s" % name)

    print("=" * 72); print("变异测试"); print("=" * 72)
    for tag, subs, scen, check, expect in MUTATIONS:
        s = ADDON_SRC
        ok = True
        for old, new in subs:
            if old not in s:
                ok = False; break
            s = s.replace(old, new, 1)
        if not ok:
            nfail += 1; print("  [FAIL] %s -> pattern not found" % tag); continue
        try:
            L = scen(s)
            if not check(L):
                npass += 1; print("  [ OK ] MUT:%s -> 已打破 (%s)" % (tag, expect))
            else:
                nfail += 1; print("  [FAIL] MUT:%s -> 未被发现! (%s)" % (tag, expect))
        except Exception as e:
            nfail += 1; print("  [FAIL] MUT:%s -> exception %s: %s" % (tag, type(e).__name__, e))

    print("-" * 72); print("通过 %d, 失败 %d" % (npass, nfail))
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
