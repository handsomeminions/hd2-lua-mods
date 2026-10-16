# -*- coding: utf-8 -*-
"""
test_380mm.py —— orbital_380mm_hellbomb.lua 的 lupa 离线仿真测试

在 LuaJIT 2.1 上跑真源码; harness.lua 提供假 FFI/假内存。
夹具:
  * 射弹表用真实的 fx_proj_file.bin (含 380mm HE CANNON ROUND, type 80 idx138 / type 266 idx143)
  * 爆炸表用合成夹具(含一条半径=17/25/45 的"地狱火"记录, type=333)
"""
import os, sys, struct
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SRC = os.environ.get("HD2_ADDON_380_SRC") or os.path.abspath(
    os.path.join(HERE, "..", "src", "orbital_380mm_hellbomb.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()
FX_PROJ_FILE = open(os.path.join(FIX, "fx_proj_file.bin"), "rb").read()

TYPE_EXPLOSION = 0x2AEA2592
NAME_380MM = 2909856589
HB_TYPE = 242          # 夹具里"地狱火"的枚举值(= 当前构建实测值)
HB_AUDIO = 1160336653
HB_PARTICLE = bytes.fromhex("4152B17F76EAE64F")[::-1]   # LE
PROJ_BASE = 0x10000000; PROJ_OFF = 0x8000
EXPL_BASE = 0x14000000; EXPL_OFF = 0x8000


def build_expl_fixture():
    """合成爆炸表: 记录 stride=152, 半径@+16/+20/+24, 粒子@+56, 音频@+64."""
    N, stride = 24, 152
    recs = bytearray(N * stride)
    def put(idx, typ, dmg, inner, outer, stagger, audio, particle):
        o = idx * stride
        struct.pack_into("<II", recs, o, typ, dmg)
        struct.pack_into("<fff", recs, o + 16, inner, outer, stagger)
        recs[o + 56:o + 64] = particle
        struct.pack_into("<I", recs, o + 64, audio)
    put(5, HB_TYPE, 479, 17.0, 25.0, 45.0, HB_AUDIO, HB_PARTICLE)          # 地狱火
    put(7, 777, 12, 10.0, 25.0, 35.0, 0x11111111, b"\xAA" * 8)             # 干扰项
    put(9, 125, 479, 17.0, 25.0, 45.0, 0x22222222, b"\xBB" * 8)             # 同半径但音频不同
    size = 16 + N * stride
    block = b"LDLD" + struct.pack("<III", 1, TYPE_EXPLOSION, size) + b"\x00" * 8
    block += struct.pack("<QQ", 16, N)
    block += bytes(recs)
    return block, stride


EXPL_BLOCK, EX_STRIDE = build_expl_fixture()


def new_env():
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute(HARNESS_SRC)
    L.execute('HARNESS.status_file = "orbital_380mm_hellbomb_STATUS.txt"')
    L.execute('HARNESS.log_file = "orbital_380mm_hellbomb.log"')
    return L


def add_region(L, base, size, data=b""):
    body = (data + b"\x00" * size)[:size]
    L.globals().HARNESS.add_region_hex(base, size, body.hex().upper())


def run(src=ADDON_SRC, frames=700, with_expl=True):
    L = new_env()
    L.execute("HARNESS.reset()")
    L.execute("HARNESS.set_loader(1, 19)")
    add_region(L, PROJ_BASE, 0x40000, b"\x00" * PROJ_OFF + FX_PROJ_FILE)
    if with_expl:
        add_region(L, EXPL_BASE, 0x40000, b"\x00" * EXPL_OFF + EXPL_BLOCK)
    L.execute("HARNESS.install_update_hook()")
    L.globals().ADDON_SRC = src
    L.execute("HARNESS.run_addon(ADDON_SRC)")
    L.execute("HARNESS.frames(%d)" % frames)
    return L


def proj_recbase():
    ptr = int.from_bytes(FX_PROJ_FILE[24:32], "little")
    return PROJ_BASE + PROJ_OFF + 24 + ptr, 272


class Checker:
    def __init__(self, name): self.name = name; self.fails = []
    def eq(self, got, want, what):
        if got != want: self.fails.append("%s: got %r want %r" % (what, got, want))
    def result(self): return (self.name, self.fails)


TESTS = []
def test(fn): TESTS.append(fn); return fn


def _view(L):
    H = L.globals().HARNESS
    return {
        "hb": H.hellbomb_type(),
        "patched": H.patched_records(),
        "abs": lambda a, n: H.abs_hex(a, n),
        "status": H.status_text(),
        "flush": lambda: H.flush_addon_log(),
        "log": lambda: H.log_text(),
    }


@test
def t1_hellbomb_resolved_and_patched():
    """爆炸表里用半径指纹解析出地狱火, 并打到 380mm 射弹(type 80/266)的爆炸字段."""
    L = run(frames=700)
    v = _view(L)
    c = Checker("T1-380")
    c.eq(v["hb"], HB_TYPE, "resolved hellbomb explosion type")
    c.eq(v["patched"], 2, "patched records (types 80,266)")
    base, stride = proj_recbase()
    want = struct.pack("<I", HB_TYPE)
    for idx in (138, 143):
        got = bytes.fromhex(v["abs"](base + idx * stride + 144, 4))
        c.eq(got, want, "record idx%d explosion_type_on_impact" % idx)
    return c.result()


@test
def t2_no_explosion_table_no_patch():
    """没有爆炸表(拿不到地狱火值)时: 不得乱写."""
    L = run(frames=500, with_expl=False)
    v = _view(L)
    c = Checker("T2-380")
    c.eq(v["hb"], None, "no hellbomb resolved")
    c.eq(v["patched"], 0, "no patch")
    return c.result()


MUTATIONS = [
    ("M1_no_resolve",
     [("state.hellbomb_type = hits[1].type", "state.hellbomb_type = nil  -- (mutation)")],
     "resolve disabled"),
    ("M2_wrong_audio_hash",
     [("HB_AUDIO = 1160336653,", "HB_AUDIO = 12345,  -- (mutation)")],
     "audio fingerprint wrong"),
    ("M3_wrong_name_hash",
     [("NAME_380MM_UPPER = 2909856589,", "NAME_380MM_UPPER = 12345,  -- (mutation)")],
     "target name validation"),
    ("M4_only_one_type",
     [("BARRAGE_380_TYPES = { 80, 266 },", "BARRAGE_380_TYPES = { 80 },  -- (mutation)")],
     "misses second projectile type"),
    ("M5_wrong_particle",
     [('HB_PARTICLE_HEX = "4152B17F76EAE64F",', 'HB_PARTICLE_HEX = "0000000000000000",  -- (mutation)')],
     "particle fingerprint wrong"),
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
    for tag, subs, expect in MUTATIONS:
        s = ADDON_SRC
        ok = True
        for old, new in subs:
            if old not in s:
                ok = False; break
            s = s.replace(old, new, 1)
        if not ok:
            nfail += 1; print("  [FAIL] %s  -> pattern not found" % tag); continue
        try:
            L = run(src=s, frames=700)
            v = _view(L)
            broke = (v["hb"] != HB_TYPE) or (v["patched"] != 2)
            if broke:
                npass += 1; print("  [ OK ] MUT:%s -> 已打破 (%s)" % (tag, expect))
            else:
                nfail += 1; print("  [FAIL] MUT:%s -> 未被发现! (%s)" % (tag, expect))
        except Exception as e:
            nfail += 1; print("  [FAIL] MUT:%s -> exception %s" % (tag, e))
    print("-" * 72); print("通过 %d, 失败 %d" % (npass, nfail))
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
