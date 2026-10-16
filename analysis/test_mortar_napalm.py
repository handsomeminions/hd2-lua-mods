# -*- coding: utf-8 -*-
"""
test_mortar_napalm.py —— mortar_sentry_napalm.lua 的 lupa 离线仿真测试

在 LuaJIT 2.1 上跑真源码; harness.lua 提供假 FFI / 假内存 / 假 io / 帧驱动。

夹具全部来自**当前构建的真实 dl_bin**(analysis/ref/generated_projectile_settings.dl_bin):
  fixtures/ms_target.bin        idx 90   A/M-12 迫击哨戒炮炮弹 (type 346, "40mm HE MORTAR")
  fixtures/ms_src_napalm.bin    idx 140  凝固汽油弹壳 (type 234) —— 取它的 +144 当新爆炸
  fixtures/ms_decoy.bin         idx 67   同名干扰项(也是 "40mm HE MORTAR", 但是机器人迫击炮壳 cal40/mass750)
  fixtures/ms_filler.bin        idx 0
  fixtures/ms_table_block.bin   真实整块 LDLD(350 条记录)

用户要求(本套测试守着):
  1) 落地爆炸换成"轨道凝固汽油弹火力网单颗汽油弹"的爆炸 -> +144 取自源
  2) 索敌/飞行轨迹/速度/模型/拖尾/音效 等等**一律不动** -> 除 +144 外逐字节相同
"""
import os, sys, re, struct
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SRC = os.environ.get("HD2_ADDON_MS_SRC") or os.path.abspath(
    os.path.join(HERE, "..", "src", "mortar_sentry_napalm.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()


def fx(name):
    return open(os.path.join(FIX, name), "rb").read()

TGT   = fx("ms_target.bin")
SRC_R = fx("ms_src_napalm.bin")
DEC   = fx("ms_decoy.bin")
FIL   = fx("ms_filler.bin")
BLOCK = fx("ms_table_block.bin")

TYPE_PROJECTILE = 0xBD4042C2
TARGET_TYPE = 346
SOURCE_TYPE = 234
STRIDE = 272
REGION_SIZE = 0x40000
REAL_TGT_IDX = 90
REAL_SRC_IDX = 140

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
OFF_EXPL = 144
OFF_PROX = 148
OFF_DELAY = 152
OFF_EXPIRE = 156
OFF_ARMING = 160
OFF_AUDIO = 208

# 补丁只动这一段
PATCH_RANGE = (OFF_EXPL, OFF_EXPL + 4)


def splice(base, src, off, ln):
    return base[:off] + src[off:off + ln] + base[off + ln:]


PATCHED_TGT = splice(TGT, SRC_R, OFF_EXPL, 4)


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
    L.execute('HARNESS.status_file = "mortar_sentry_napalm_STATUS.txt"')
    L.execute('HARNESS.log_file = "mortar_sentry_napalm.log"')
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


def real_target_addr():
    return rec_base(BASE, BOFF) + REAL_TGT_IDX * STRIDE


# ---------------------------------------------------------------------------
# 功能测试
# ---------------------------------------------------------------------------
@test
def t1_real_table_patch():
    """真实整表: 命中 A/M-12 炮弹并把 +144 换成凝固汽油弹的爆炸."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T1")
    c.eq(patched(L), 1, "patched records")
    c.eq(stat_field(L, "target(mortar sentry shell) type"), str(TARGET_TYPE), "target type in status")
    c.eq(stat_field(L, "source(napalm shell) type"), str(SOURCE_TYPE), "source type in status")
    c.true(status_head(L).startswith("OK - patch applied"), "status head OK (%r)" % status_head(L))
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.eq(got, PATCHED_TGT, "whole record == expected single-field patch")
    c.true(got is not None and got[OFF_EXPL:OFF_EXPL + 4] == SRC_R[OFF_EXPL:OFF_EXPL + 4],
           "impact explosion taken from napalm shell")
    return c.result()


@test
def t2_only_explosion_changed():
    """除 +144 外, 整条记录必须与原版**逐字节相同**(索敌/弹道/速度/模型/拖尾/音效 全不动)."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T2")
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.true(got is not None, "record readable")
    if got is None:
        return c.result()
    lo, hi = PATCH_RANGE
    left = got[:lo] == TGT[:lo]
    right = got[hi:] == TGT[hi:]
    c.true(left, "bytes before +%d unchanged" % lo)
    c.true(right, "bytes after +%d unchanged" % hi)
    # 逐字段点名(便于定位)
    for off, ln, name in [(OFF_TYPE, 4, "type"), (OFF_NAME_UPPER, 4, "name_upper"),
                          (OFF_CAL, 4, "calibre"), (OFF_SPEED, 4, "speed"), (OFF_MASS, 4, "mass"),
                          (OFF_DRAG, 4, "drag"), (OFF_GRAV, 4, "gravity"), (OFF_LIFE, 4, "life_time"),
                          (OFF_DMG, 4, "damage_info"), (OFF_TRAIL, 8, "particle_trail"),
                          (OFF_UNIT, 8, "projectile_unit_path"), (OFF_PROX, 4, "explosion_proximity"),
                          (OFF_DELAY, 4, "explosion_delay"), (OFF_EXPIRE, 4, "explosion_type_expire"),
                          (OFF_ARMING, 4, "arming_distance"), (OFF_AUDIO, 4, "audio_trail_start")]:
        c.eq(got[off:off + ln], TGT[off:off + ln], "%s unchanged" % name)
    c.eq(struct.unpack_from("<f", got, OFF_SPEED)[0], 100.0, "speed still 100")
    c.eq(struct.unpack_from("<f", got, OFF_GRAV)[0], 6.0, "gravity still 6")
    c.eq(round(struct.unpack_from("<f", got, OFF_DRAG)[0], 2), 0.25, "drag still 0.25")
    return c.result()


@test
def t3_same_name_decoys_untouched():
    """同名 4 条("40mm HE MORTAR")同时在时: 只打 A/M-12 那条, 干扰项一个字节都不动."""
    recs = [DEC, FIL, TGT, SRC_R, FIL]          # DEC 排在最前(同名)
    block = make_block(recs)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T3")
    c.eq(patched(L), 1, "exactly one record patched")
    base = rec_base(BASE, BOFF)
    c.eq(abs_bytes(L, base + 0 * STRIDE, STRIDE), DEC, "decoy (same name) untouched")
    c.eq(abs_bytes(L, base + 2 * STRIDE, STRIDE), PATCHED_TGT, "real target patched")
    return c.result()


@test
def t4_no_target_no_write():
    """表里没有目标时: 不得乱写."""
    block = make_block([DEC, FIL, DEC, FIL])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T4")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no memory writes")
    c.true("SEARCHING" in status_head(L), "status stays SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t5_mem_form_descriptor():
    """内存形态描述符(绝对指针)也能解析."""
    recs = [FIL, TGT, DEC, SRC_R, FIL]
    block = make_block(recs, block_addr=BASE + BOFF, file_form=False)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T5")
    c.eq(patched(L), 1, "patched records")
    c.eq(abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE), PATCHED_TGT, "record patched")
    return c.result()


@test
def t6_source_missing():
    """有目标但没有凝固汽油弹壳: 拒绝瞎打."""
    block = make_block([FIL, TGT, DEC, FIL])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T6")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no writes")
    c.true("source missing" in log_text(L), "log mentions missing source")
    return c.result()


@test
def t7_idempotent():
    """表里已是补丁形态: 登记但绝不重复写."""
    recs = [FIL, PATCHED_TGT, SRC_R, DEC]
    block = make_block(recs)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T7")
    c.eq(patched(L), 1, "registered as patched")
    c.eq(write_count(L), 0, "no writes (idempotent)")
    c.true("ALREADY" in log_text(L), "log says ALREADY")
    return c.result()


@test
def t8_two_table_copies():
    """内存里有两份射弹表: 两份都要打."""
    b1, b2 = 0x20000000, 0x30000000
    mk = lambda: make_block([FIL, TGT, SRC_R, DEC, FIL])
    L = run(tables=[(b1, BOFF, mk()), (b2, BOFF, mk())], frames=600)
    c = Checker("T8")
    c.eq(patched(L), 2, "both copies patched")
    for b in (b1, b2):
        c.eq(abs_bytes(L, rec_base(b, BOFF) + 1 * STRIDE, STRIDE), PATCHED_TGT,
             "copy at 0x%X patched" % b)
    return c.result()


@test
def t9_write_fail_detected():
    """写入静默失败: 回读校验必须发现, 不得谎报成功."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    addr = rec_base(BASE, BOFF) + 1 * STRIDE
    L = run(tables=[(BASE, BOFF, block)], write_fail_addrs=[addr])
    c = Checker("T9")
    c.eq(patched(L), 0, "no false success")
    c.true("read-back mismatch" in log_text(L), "log mentions read-back mismatch")
    return c.result()


@test
def t10_readonly_page():
    """目标页只读: 临时解保护写入, 写完恢复原保护属性."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    L = run(tables=[(BASE, BOFF, block, 0x02)])
    c = Checker("T10")
    c.eq(patched(L), 1, "patched on read-only page")
    c.eq(L.globals().HARNESS.region_prot(BASE), 0x02, "page protection restored")
    return c.result()


@test
def t11_loader_too_old():
    """loader API 0 (v14): 立刻停手, 不扫描不写入."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    L = run(tables=[(BASE, BOFF, block)], loader=(0, 14))
    c = Checker("T11")
    c.true("FAILED - Bingus Shared Loader too old" in status_head(L), "status FAILED (%r)" % status_head(L))
    c.eq(write_count(L), 0, "no writes")
    return c.result()


@test
def t12_loader_log_fallback():
    """拿不到 loader 全局表时: 退化为读 BingusSharedLoader.log 首行."""
    block = make_block([FIL, TGT, SRC_R, DEC])
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
    addr = real_target_addr()
    c.eq(patched(L), 1, "initial patch")
    L.globals().HARNESS.write_hex(addr, TGT.hex().upper())
    L.execute("HARNESS.frames(400)")
    c.eq(abs_bytes(L, addr, STRIDE), PATCHED_TGT, "patch re-applied")
    c.true("lost its patch; re-applying" in log_text(L), "log mentions re-apply")
    return c.result()


@test
def t14_all_copies_lost_rescan():
    """所有副本都没了(地图重载): 回到搜索态."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T14")
    c.eq(patched(L), 1, "initial patch")
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
    c.eq(stat_field(L, "impact_explosion"), "%d->%d" % (
        struct.unpack_from("<I", TGT, OFF_EXPL)[0],
        struct.unpack_from("<I", SRC_R, OFF_EXPL)[0]), "explosion change in status")
    c.true("flight(targeting/arc/speed)_preserved=true" in st, "preserved flag in status")
    c.true("host-authoritative" in st, "host-authoritative note present")
    lg = log_text(L)
    c.true("PATCHED mortar sentry shell" in lg, "log has PATCHED line")
    c.true("targeting/flight/visuals untouched" in lg, "log says untouched")
    return c.result()


# ---------------------------------------------------------------------------
# 场景构造(供变异测试复用)
# ---------------------------------------------------------------------------
def scen_real(src):
    return run(src=src, tables=[(BASE, BOFF, BLOCK)])


def scen_writefail(src):
    block = make_block([FIL, TGT, SRC_R, DEC])
    return run(src=src, tables=[(BASE, BOFF, block)],
               write_fail_addrs=[rec_base(BASE, BOFF) + 1 * STRIDE])


def scen_name_only(src):
    """同名干扰项排在真实目标前面"""
    block = make_block([DEC, TGT, SRC_R, FIL])
    return run(src=src, tables=[(BASE, BOFF, block)])


def check_real(L):
    if patched(L) != 1:
        return False
    return abs_bytes(L, real_target_addr(), STRIDE) == PATCHED_TGT


def check_writefail(L):
    return patched(L) == 0


MUTATIONS = [
    ("M1_target_trail_wrong",
     [('TGT_TRAIL_HEX  = "7E7C55538A04ACFD",', 'TGT_TRAIL_HEX  = "0000000000000000",')],
     scen_real, check_real, "目标拖尾指纹写错 -> 找不到目标"),
    ("M2_source_trail_wrong",
     [('SRC_TRAIL_HEX  = "68358A1CC55AFDDB",', 'SRC_TRAIL_HEX  = "0000000000000000",')],
     scen_real, check_real, "源拖尾指纹写错 -> 取不到源"),
    ("M3_endianness_swapped",
     [('TGT_TRAIL_HEX  = "7E7C55538A04ACFD",', 'TGT_TRAIL_HEX  = "FDAC048A53557C7E",')],
     scen_real, check_real, "字节序搞反 -> 64位哈希对不上"),
    ("M4_name_only_fingerprint",
     [("""    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.TGT_NAME_UPPER
       and near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5)
       and near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5)
       and near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0)
       and string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) == tgt_trail
       and u32_at(r, CONFIG.OFF_AUDIO_START) == CONFIG.TGT_AUDIO""",
       """    return u32_at(r, CONFIG.OFF_NAME_UPPER) == CONFIG.TGT_NAME_UPPER""")],
     scen_name_only, lambda L: patched(L) == 1 and
        abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE) == PATCHED_TGT,
     "只按名字认记录 -> 打到同名的干扰项上(物理量+资源哈希才是唯一的)"),
    ("M5_full_clone_guard_catches",
     [("        out = string.sub(out, 1, f.off)\n           .. string.sub(src, f.off + 1, f.off + f.len)\n           .. string.sub(out, f.off + f.len + 1)",
       "        out = string.sub(out, 1, 24) .. string.sub(src, 25)")],
     scen_real, check_real, "改成整条克隆 -> 被 keep-guard 拦下(拒绝写入)"),
    ("M6_full_clone_no_guard",
     [("        out = string.sub(out, 1, f.off)\n           .. string.sub(src, f.off + 1, f.off + f.len)\n           .. string.sub(out, f.off + f.len + 1)",
       "        out = string.sub(out, 1, 24) .. string.sub(src, 25)"),
      ("    if not keep_guard_ok(cur, new) then", "    if false then")],
     scen_real, check_real, "整条克隆且去掉 keep-guard -> 弹道/模型被改"),
    ("M7_wrong_offset_touched",
     [("{ off = 144, len = 4, name = \"explosion_type_on_impact\" },",
       "{ off = 148, len = 4, name = \"oops\" },")],
     scen_real, check_real, "偏移写错(打到近炸距离) -> 被 keep-guard 拦下"),
    ("M8_no_readback_verify",
     [("""        local back = read_mem(tgt_addr, t.stride)
        if back ~= new then""",
       """        local back = read_mem(tgt_addr, t.stride)
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
