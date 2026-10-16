# -*- coding: utf-8 -*-
"""test_sterilizer_sfx.py —— sterilizer_sfx.lua (v1.0.0) 的 lupa 离线仿真测试

用户需求(本套测试守着):
  TX-41 灭菌器 开火音效(firing.audio_event_start = 1773671782) 换成更明显的喷射音效。

本 addon 是**实验性**的: 它**不做 LDLD 表解析**(目标表 SprayWeaponComponentData
经实机内存普查确认不在内存), 而是直接在裸内存里找
  "firing audio_event_start  +  同一 SprayWeaponComponent / SprayWeaponStateInfo 内
    其它多个音效事件哈希共现"
的签名, 只改写那 4 个字节。

本套测试守着:
  1. ★ 只有佐证达标的命中才写 —— 孤立出现的 1773671782 绝不改(最重要的一条)
  2. 只写 4 个字节, 别的一个字节都不动
  3. 幂等 / cfg 热调 / 回读校验 / 找不到候选时不写
  4. 别的武器的音效事件(如 FLAM-40 的 firing event)不受影响

夹具由本文件**在内存里合成**(按 typelib 权威布局 + 离线明文里的真实哈希值),
不依赖外部 .bin。
"""
import os, re, struct, sys
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.environ.get("HD2_ADDON_SFX_SRC") or os.path.abspath(
    os.path.join(HERE, "..", "src", "sterilizer_sfx.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()

# --- 真实值(离线明文 entities/SprayWeaponComponentData.json) ------------------
AUDIO_NODE      = 1803865503
WARMUP_AUDIO    = 3435018303
FIRING_AUDIO    = 1773671782      # <- 要换掉的那个
FIRING_STOP     = 599097114
FIRING_CALL     = 418315309
COOLDOWN_AUDIO  = 1928837757
COOLDOWN_STOP   = 1851540683
VO_EVENT        = 3956223216
MUZZLE_LO, MUZZLE_HI = 3159809621, 2748406331   # 0xA3D15A3BBC56DE55 firing.muzzle_effect
OTHER_WEAPON_AUDIO = 1881104745                 # FLAM-40 的 firing event(不该被碰)

BASE, BOFF = 0x20000000, 0x1000
REGION_SIZE = 0x80000                     # 512 KB (2 个扫描块)
CHUNK = 262144
LOGDIR = (os.getenv("LOCALAPPDATA") or "") + "/CowboyBingus/Helldivers2/Logs/"
CFG = LOGDIR + "sterilizer_sfx.cfg"
DEFAULT_EVENT = 335829265

COMP_FIRING_OFF = 80 + 44                 # firing.audio_event_start 在组件内的偏移 = 124
COMP_LEN = 224


def U32(v):
    return struct.pack("<I", v & 0xFFFFFFFF)


def U64(lo, hi):
    return U32(lo) + U32(hi)


def F32(v):
    return struct.pack("<f", v)


def state56(a0, a1, callout=0, shake0=(0, 0), muzzle=(0, 0), wind=0):
    """SprayWeaponStateInfo (56B):
         shake(WeaponCameraShakeInfo 32B) = world_shake u64 + local_shake u64 + fpv_shake u64
                                            + inner_radius f32 + outer_radius f32
         muzzle_effect u64 | callout u32 | audio_event_start u32 | audio_event_stop u32 | wind u32
    """
    return (U64(*shake0) + U64(0, 0) + U64(0, 0) + F32(2.0) + F32(5.0)   # +0..+31
            + U64(*muzzle)                                                # +32..+39
            + U32(callout) + U32(a0) + U32(a1) + U32(wind))               # +40..+55


def sterilizer_component():
    """灭菌器的 SprayWeaponComponent (224B, typelib 权威布局)。"""
    b = U32(0) + U32(15) + U32(0) + U32(AUDIO_NODE) + F32(0.0) + U32(0)          # +0..+23
    b += state56(WARMUP_AUDIO, 0)                                                # +24..+79
    b += state56(FIRING_AUDIO, FIRING_STOP, callout=FIRING_CALL,
                 muzzle=(MUZZLE_LO, MUZZLE_HI))                                  # +80..+135
    b += state56(COOLDOWN_AUDIO, COOLDOWN_STOP)                                  # +136..+191
    b += U32(1) + U32(0) + U32(28) + U32(0) + U32(0) + U32(VO_EVENT) + U32(0) + U32(0)  # +192..+223
    assert len(b) == COMP_LEN, len(b)
    return b


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


# ---------------------------------------------------------------------------
# harness 驱动
# ---------------------------------------------------------------------------
def add_region(L, base, size, data=b"", prot=0x04):
    body = (data + b"\x00" * size)[:size]
    L.globals().HARNESS.add_region_hex(base, size, body.hex().upper(), prot)


def new_env():
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute(HARNESS_SRC)
    return L


def run(src=ADDON_SRC, frames=900, regions=None, loader=(1, 19), cfg=None,
        write_fail_addrs=()):
    L = new_env()
    L.execute("HARNESS.reset()")
    if loader is None:
        L.execute("HARNESS.clear_loader()")
    else:
        L.execute("HARNESS.set_loader(%d, %d)" % loader)
    L.execute('HARNESS.status_file = "sterilizer_sfx_STATUS.txt"')
    L.execute('HARNESS.log_file = "sterilizer_sfx.log"')
    for t in (regions or []):
        base, size, data = t[0], t[1], t[2]
        prot = t[3] if len(t) > 3 else 0x04
        add_region(L, base, size, data, prot)
    if cfg is not None:
        L.globals().CFG_TXT = cfg
        L.globals().CFG_PATH = CFG
        L.execute("HARNESS.preload_file(CFG_PATH, CFG_TXT)")
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
    m = re.search(r"patched_copies=(\d+)", status_text(L))
    return int(m.group(1)) if m else 0


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


class Checker:
    def __init__(self, name): self.name = name; self.fails = []
    def eq(self, got, want, what):
        if got != want: self.fails.append("%s: got %r want %r" % (what, got, want))
    def true(self, cond, what):
        if not cond: self.fails.append(what)
    def result(self): return (self.name, self.fails)


TESTS = []
def test(fn): TESTS.append(fn); return fn


# --- 场景构造 -----------------------------------------------------------------
def region_with_sterilizer(comp_off=BOFF):
    """区域: [comp_off] 处放灭菌器组件。"""
    return (BASE, REGION_SIZE, b"\x00" * comp_off + sterilizer_component())


def region_with_sterilizer_and_lone(comp_off=BOFF, lone_off=0x30000):
    """区域: 灭菌器组件 + 一个**孤立**的 FIRING_AUDIO(周围 1KB 内无任何佐证)。"""
    data = bytearray(REGION_SIZE)
    data[comp_off:comp_off + COMP_LEN] = sterilizer_component()
    data[lone_off:lone_off + 4] = U32(FIRING_AUDIO)
    return (BASE, REGION_SIZE, bytes(data))


def firing_addr(comp_off=BOFF):
    return BASE + comp_off + COMP_FIRING_OFF


REAL = None   # 每个测试自己构造


# ---------------------------------------------------------------------------
# 功能
# ---------------------------------------------------------------------------
@test
def t1_finds_and_swaps():
    L = run(regions=[region_with_sterilizer()])
    c = Checker("T1")
    c.true(status_head(L).startswith("OK - patch applied"), "status OK (%r)" % status_head(L))
    c.eq(patched(L), 1, "patched_copies == 1")
    got = abs_bytes(L, firing_addr(), 4)
    c.eq(u32(got, 0), DEFAULT_EVENT, "firing audio_event_start swapped")
    c.eq(stat_field(L, "swap_to"), str(DEFAULT_EVENT), "status swap_to")
    c.true("PATCHED sterilizer firing SFX" in log_text(L), "log has PATCHED line")
    return c.result()


@test
def t2_only_four_bytes_change():
    """★ 除目标那 4 个字节, 整个区域逐字节不动。"""
    L = run(regions=[region_with_sterilizer()])
    c = Checker("T2")
    orig = bytearray(REGION_SIZE)
    orig[BOFF:BOFF + COMP_LEN] = sterilizer_component()
    got = abs_bytes(L, BASE, REGION_SIZE)
    diff = [i for i in range(REGION_SIZE) if got[i] != orig[i]]
    tgt = BOFF + COMP_FIRING_OFF
    c.true(len(diff) == 4, "exactly 4 changed bytes (got %d: %s)" % (len(diff), diff[:8]))
    c.true(all(tgt <= d < tgt + 4 for d in diff),
           "every changed byte inside the target u32 @+%d (%s)" % (tgt, diff[:8]))
    c.eq(u32(abs_bytes(L, firing_addr(), 4), 0), DEFAULT_EVENT, "value swapped")
    return c.result()


@test
def t3_lone_hit_is_never_touched():
    """★★ 孤立出现的 1773671782(周围无佐证) 必须原封不动。"""
    L = run(regions=[region_with_sterilizer_and_lone()])
    c = Checker("T3")
    c.eq(patched(L), 1, "only the real component was patched")
    lone = abs_bytes(L, BASE + 0x30000, 4)
    c.eq(u32(lone, 0), FIRING_AUDIO, "lone occurrence stays vanilla")
    c.true("lone_hits_skipped=" in status_text(L), "status reports lone hits counter")
    return c.result()


@test
def t4_idempotent():
    L = run(regions=[region_with_sterilizer()], frames=900)
    c = Checker("T4")
    w1 = write_count(L)
    L.execute("HARNESS.frames(1800)")
    w2 = write_count(L)
    c.eq(w1, w2, "no extra writes after 3 more recheck cycles (%d==%d)" % (w1, w2))
    c.eq(u32(abs_bytes(L, firing_addr(), 4), 0), DEFAULT_EVENT, "still swapped")
    return c.result()


@test
def t5_cfg_overrides():
    L = run(regions=[region_with_sterilizer()], cfg="event=1881104745\n")
    c = Checker("T5")
    c.eq(u32(abs_bytes(L, firing_addr(), 4), 0), 1881104745, "cfg event applied")
    c.eq(stat_field(L, "swap_to"), "1881104745", "status swap_to from cfg")
    return c.result()


@test
def t6_cfg_hot_change_reapplies():
    """cfg 热调: 换成新事件 -> 记录被重打(指纹靠佐证复核, 不靠被改的值)。"""
    L = run(regions=[region_with_sterilizer()], cfg="event=335829265\n", frames=360)
    c = Checker("T6")
    c.eq(u32(abs_bytes(L, firing_addr(), 4), 0), 335829265, "initial swap")
    L.globals().CFG_TXT = "event=1881104745\n"
    L.globals().CFG_PATH = CFG
    L.execute("HARNESS.preload_file(CFG_PATH, CFG_TXT)")
    L.execute("HARNESS.frames(1200)")
    c.eq(u32(abs_bytes(L, firing_addr(), 4), 0), 1881104745, "hot-changed event applied")
    c.eq(patched(L), 1, "still exactly 1 tracked copy")
    return c.result()


@test
def t7_no_candidate_no_write():
    """区域里没有灭菌器组件 -> 不写任何字节, STATUS 不是 OK。"""
    L = run(regions=[(BASE, REGION_SIZE, b"\x11" * 4096)])
    c = Checker("T7")
    c.eq(patched(L), 0, "patched_copies == 0")
    c.eq(write_count(L), 0, "no writes")
    c.true(not status_head(L).startswith("OK"), "status not OK (%r)" % status_head(L))
    c.true("NO verified sterilizer weapon component" in status_text(L), "status explains it")
    return c.result()


@test
def t8_window_spanning_chunk_boundary():
    """★ 命中点紧贴 256KB 扫描块边界 -> 靠 OVERLAP 仍要能完整判定并改写。"""
    off = CHUNK - 128                      # 组件跨块边界
    L = run(regions=[region_with_sterilizer(comp_off=off)])
    c = Checker("T8")
    c.eq(patched(L), 1, "found across the chunk boundary")
    c.eq(u32(abs_bytes(L, BASE + off + COMP_FIRING_OFF, 4), 0), DEFAULT_EVENT, "swapped")
    return c.result()


@test
def t9_write_failure_refused():
    L = run(regions=[region_with_sterilizer()], write_fail_addrs=[firing_addr()])
    c = Checker("T9")
    c.true(not status_head(L).startswith("OK"), "status not OK (%r)" % status_head(L))
    c.eq(u32(abs_bytes(L, firing_addr(), 4), 0), FIRING_AUDIO, "record still vanilla")
    c.true("read-back mismatch" in log_text(L), "log mentions read-back mismatch")
    return c.result()


@test
def t10_other_weapons_audio_untouched():
    """别的武器的 firing event(如 FLAM-40 的 1881104745) 不受影响。"""
    data = bytearray(REGION_SIZE)
    data[BOFF:BOFF + COMP_LEN] = sterilizer_component()
    # 一份"别的武器"的状态(只有它自己的 event, 不含灭菌器佐证)
    data[0x20000:0x20000 + 4] = U32(OTHER_WEAPON_AUDIO)
    data[0x20004:0x20004 + 4] = U32(12345)
    L = run(regions=[(BASE, REGION_SIZE, bytes(data))])
    c = Checker("T10")
    c.eq(u32(abs_bytes(L, BASE + 0x20000, 4), 0), OTHER_WEAPON_AUDIO, "other weapon event untouched")
    c.eq(patched(L), 1, "only the sterilizer copy was patched")
    return c.result()


@test
def t11_no_global_pollution():
    L = run(regions=[region_with_sterilizer()], frames=200)
    c = Checker("T11")
    names = L.eval("(function() local o={} for k,v in pairs(_G) do o[#o+1]=k end table.sort(o) return table.concat(o, ',') end)()")
    names = set(str(names).split(","))
    for bad in ("flush_log", "scan_one_chunk", "process_hit", "write_event",
                "is_target_record", "tick", "want_event"):
        c.true(bad not in names, "no leaked global %r" % bad)
    c.true("_HD2_STERILIZER_SFX_FLUSH" in names, "unique flush global present")
    return c.result()


@test
def t12_loader_too_old_stops():
    L = run(regions=[region_with_sterilizer()], loader=(0, 14))
    c = Checker("T12")
    c.true(status_head(L).startswith("FAILED"), "status FAILED (%r)" % status_head(L))
    c.eq(write_count(L), 0, "no writes")
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
    ("M1_no_corroboration",
     [("                if n < CONFIG.MIN_CORROB then", "                if false then")],
     "去掉佐证判据 -> 孤立出现的音效值也会被误改"),
    ("M2_write_wrong_value",
     [("    if not write_mem(addr, u32_le(want_event)) then",
       "    if not write_mem(addr, u32_le(1234567)) then")],
     "写入了错误的事件值"),
    ("M3_no_readback",
     [("    if back == nil or u32_at(back, 0) ~= want_event then", "    if false then")],
     "去掉回读校验 -> 写入失败被漏过"),
    ("M4_eight_bytes",
     [("    if not write_mem(addr, u32_le(want_event)) then",
       "    if not write_mem(addr - CONFIG.WIN, u32_le(want_event)) then")],
     "写到错误偏移(窗口起点) -> 只改 4 字节的约束被破坏"),
]


def check_only_four_bytes(L):
    return (u32(abs_bytes(L, firing_addr(), 4), 0) == DEFAULT_EVENT
            and abs_bytes(L, BASE + BOFF - CONFIG_WIN_PY, CONFIG_WIN_PY + 4) ==
                b"\x00" * 4)


def check_target(L):
    return (patched(L) == 1
            and u32(abs_bytes(L, firing_addr(), 4), 0) == DEFAULT_EVENT)


def check_four_exact(L):
    if u32(abs_bytes(L, firing_addr(), 4), 0) != DEFAULT_EVENT:
        return False
    # 目标前 4 字节(组件内 warmup 末端) 必须没被动过
    return abs_bytes(L, firing_addr() - 4, 4) == U32(0)


def check_lone_untouched(L):
    return u32(abs_bytes(L, BASE + 0x30000, 4), 0) == FIRING_AUDIO


def check_writefail(L):
    return (not status_head(L).startswith("OK")
            and u32(abs_bytes(L, firing_addr(), 4), 0) == FIRING_AUDIO)


CONFIG_WIN_PY = 256

MUT_CASES = {
    "M1_no_corroboration": (
        lambda s: run(src=s, regions=[region_with_sterilizer_and_lone()]),
        check_lone_untouched),
    "M2_write_wrong_value": (
        lambda s: run(src=s, regions=[region_with_sterilizer()]),
        check_target),
    "M3_no_readback": (
        lambda s: run(src=s, regions=[region_with_sterilizer()],
                      write_fail_addrs=[firing_addr()]),
        check_writefail),
    "M4_eight_bytes": (
        lambda s: run(src=s, regions=[region_with_sterilizer()]),
        check_four_exact),
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
            passed += 1      # 变异导致运行期直接报错, 同样算被抓住
    print("=" * 66)
    print("通过 %d, 失败 %d" % (passed, total - passed))
    for n, f in fails:
        print("FAIL %s" % n)
        for x in f[:6]:
            print("   - %s" % x)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
