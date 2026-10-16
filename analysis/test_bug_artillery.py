# -*- coding: utf-8 -*-
"""
test_bug_artillery.py —— bug_artillery_airburst.lua (v1.5.0) 的 lupa 离线仿真测试

在 LuaJIT 2.1 上跑真源码; harness.lua 提供假 FFI / 假内存 / 假 io / 帧驱动。

夹具全部来自**当前构建的真实 dl_bin**(generated_projectile_settings.dl_bin):
  fixtures/ba_target.bin        idx 29  胆汁迫击炮 ProjectileType_Bug_Artillery (type 344)
  fixtures/ba_src_flak.bin      idx 101 RL-77 空爆火箭 Flak 近炸模式 (type 312)
  fixtures/ba_src_cluster.bin   idx 102 RL-77 空爆火箭 Cluster 模式 (type 96, life 0.25)
  fixtures/ba_decoy.bin         idx 140 干扰项(口径50/质量1000 但拖尾/推进粒子/音频不同)
  fixtures/ba_filler.bin        idx 0
  fixtures/ba_table_block.bin   真实整块 LDLD(350 条记录)

用户要求(本套测试守着这三条):
  1) 【外形回退】弹体模型(+128) 与 飞行粒子(+72/+88/+96) **保持原版胆汁迫击炮**
     (原版 +128==0 无实体模型, 绿色团块来自 +72/+96 粒子)
  2) 【弹道不变】攻击方式/飞行速度/轨迹 与原版胆汁迫击炮**逐字节相同**
     (speed=30 mass=1000 drag=0 gravity=1 life=0, 近炸/引信/爆炸角度/解保距离 均不变)
  3) 【落地爆炸】+144 explosion_type_on_impact 取自 RL-77 的空爆集束爆炸
  4) 【子弹药】+152 explosion_delay(0->0.2) 与 +240 flags(0xB5->0x94) 取自火箭,
     让 25 枚子弹药按原版火箭物理抛射/飞溅
"""
import os, sys, re, struct
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SRC = os.environ.get("HD2_ADDON_BA_SRC") or os.path.abspath(
    os.path.join(HERE, "..", "src", "bug_artillery_airburst.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()


def fx(name):
    return open(os.path.join(FIX, name), "rb").read()

TGT   = fx("ba_target.bin")
SRC_R = fx("ba_src_flak.bin")
CLU   = fx("ba_src_cluster.bin")
DEC   = fx("ba_decoy.bin")
FIL   = fx("ba_filler.bin")
BLOCK = fx("ba_table_block.bin")

TYPE_PROJECTILE = 0xBD4042C2
TARGET_TYPE = 344
SOURCE_TYPE = 312
STRIDE = 272
REGION_SIZE = 0x40000
REAL_TGT_IDX = 29

OFF_NUM_PROJ = 28       # num_projectiles (u32) —— 别的 mod(6 发)可能改这里
OFF_UNIT = 128          # projectile_unit_path (u64)  —— 外形, v1.4.0 起不动
OFF_THRUSTER = 72       # particle_thruster_effect_path (u64) —— 绿团块, 不动
OFF_THR_LEN = 88        # particle_thruster_effect_length (f32) —— 不动
OFF_TRAIL = 96          # particle_trail_effect_path (u64) —— 绿团块, 不动
OFF_EXPL = 144          # explosion_type_on_impact (u32) —— 改
OFF_SPEED = 32
OFF_MASS = 36
OFF_DRAG = 40
OFF_GRAV = 44
OFF_LIFE = 52
OFF_THRESH = 136
OFF_PROX = 148
OFF_DELAY = 152         # explosion_delay (f32) —— 改(子弹药开关)
OFF_EXPIRE = 156
OFF_ARMING = 160
OFF_AUDIO_START = 208   # 飞行音效 —— 受 SWAP_FLIGHT_FX 控制
OFF_AUDIO_STOP = 212
OFF_FLAGS = 240         # flag 位域首字节 —— 改(子弹药开关)

# 与 addon 的 FLIGHT_GUARD 保持一致: 这些必须与原版**逐字节相同**
UNCHANGED = [(OFF_SPEED, 4), (OFF_MASS, 4), (OFF_DRAG, 4), (OFF_GRAV, 4), (OFF_LIFE, 4),
             (OFF_THRUSTER, 8), (OFF_THR_LEN, 4), (OFF_TRAIL, 8), (OFF_UNIT, 8),
             (OFF_THRESH, 4), (OFF_PROX, 4), (OFF_EXPIRE, 4), (OFF_ARMING, 4)]

# 与 addon 的 PATCH_FIELDS 保持一致
FIELDS_ALWAYS = [(OFF_EXPL, 4), (OFF_DELAY, 4), (OFF_FLAGS, 1)]
FIELDS_FX = [(OFF_AUDIO_START, 4), (OFF_AUDIO_STOP, 4)]


def splice(base, src, fields):
    out = base
    for off, ln in fields:
        out = out[:off] + src[off:off + ln] + out[off + ln:]
    return out


# 默认 SWAP_FLIGHT_FX = true —— 飞行音效也换成火箭的
PATCHED_TGT = splice(TGT, SRC_R, FIELDS_ALWAYS + FIELDS_FX)
PATCHED_TGT_NOFX = splice(TGT, SRC_R, FIELDS_ALWAYS)


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
    L.execute('HARNESS.status_file = "bug_artillery_airburst_STATUS.txt"')
    L.execute('HARNESS.log_file = "bug_artillery_airburst.log"')
    return L


def run(src=ADDON_SRC, frames=300, tables=None, loader=(1, 19), preload_loader_log=None,
        write_fail_addrs=()):
    """tables: [(region_base, off, block_bytes, prot)]"""
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
def t1_selective_patch_on_real_table():
    """真实整表: 落地爆炸+子弹药开关换成火箭的; 外形/弹道一律不动."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T1")
    c.eq(patched(L), 1, "patched records")
    c.eq(stat_field(L, "target(bug artillery) type"), str(TARGET_TYPE), "target type in status")
    c.eq(stat_field(L, "source(RL-77 airburst) type"), str(SOURCE_TYPE), "source type in status")
    c.true(status_head(L).startswith("OK - patch applied"), "status head OK (%r)" % status_head(L))
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.eq(got, PATCHED_TGT, "whole record == expected selective patch")
    c.true(got is not None and got[OFF_EXPL:OFF_EXPL + 4] == SRC_R[OFF_EXPL:OFF_EXPL + 4],
           "impact explosion taken from rocket")
    return c.result()


@test
def t2_shape_and_flight_preserved():
    """★ 核心回退断言: 模型(+128) 与 飞行粒子(+72/+88/+96) 必须是原版胆汁; 弹道也不动."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T2")
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.true(got is not None, "record readable")
    if got is None:
        return c.result()
    for off, ln in UNCHANGED:
        c.eq(got[off:off + ln], TGT[off:off + ln], "field @+%d unchanged" % off)
    # 点名(便于定位)
    c.eq(got[OFF_UNIT:OFF_UNIT + 8], TGT[OFF_UNIT:OFF_UNIT + 8], "model (+128) kept vanilla")
    c.eq(got[OFF_THRUSTER:OFF_THRUSTER + 8], TGT[OFF_THRUSTER:OFF_THRUSTER + 8],
         "thruster particle (+72) kept vanilla")
    c.eq(got[OFF_TRAIL:OFF_TRAIL + 8], TGT[OFF_TRAIL:OFF_TRAIL + 8],
         "trail particle (+96) kept vanilla")
    c.eq(got[OFF_UNIT:OFF_UNIT + 8], b"\x00" * 8, "model is still 0 (bile mortar has no unit model)")
    c.eq(struct.unpack_from("<f", got, OFF_SPEED)[0], 30.0, "speed still 30 (original mortar)")
    c.eq(struct.unpack_from("<f", got, OFF_LIFE)[0], 0.0, "life_time still 0 (no timed fuse)")
    c.eq(struct.unpack_from("<f", got, OFF_PROX)[0], 0.0, "proximity still 0 (no airburst-in-flight)")
    c.eq(got[:24], TGT[:24], "identity prefix unchanged")
    # 该改的确实改了
    c.eq(round(struct.unpack_from("<f", got, OFF_DELAY)[0], 3), 0.2, "explosion_delay now 0.2")
    c.eq(got[OFF_FLAGS], SRC_R[OFF_FLAGS], "flags now rocket's")
    return c.result()


@test
def t3_no_target_no_write():
    """表里没有胆汁迫击炮时: 不得乱写."""
    block = make_block([DEC, FIL, DEC, FIL])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T3")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no memory writes")
    c.true("SEARCHING" in status_head(L), "status stays SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t4_mem_form_descriptor():
    """内存形态描述符(绝对指针)也能解析."""
    recs = [FIL, TGT, DEC, SRC_R, FIL]
    block = make_block(recs, block_addr=BASE + BOFF, file_form=False)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T4")
    c.eq(patched(L), 1, "patched records")
    got = abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE)
    c.eq(got, PATCHED_TGT, "record patched correctly")
    return c.result()


@test
def t5_source_missing():
    """有目标但没有 RL-77 Flak 源记录(只有 Cluster 模式): 拒绝瞎打."""
    block = make_block([FIL, TGT, CLU, DEC])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T5")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no writes")
    c.true("source missing" in log_text(L), "log mentions missing source")
    return c.result()


@test
def t6_idempotent_already_patched():
    """表里已是补丁形态: 登记但绝不重复写."""
    recs = [FIL, PATCHED_TGT, SRC_R, DEC]
    block = make_block(recs)
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T6")
    c.eq(patched(L), 1, "registered as patched")
    c.eq(write_count(L), 0, "no writes (idempotent)")
    c.true("ALREADY" in log_text(L), "log says ALREADY")
    return c.result()


@test
def t7_two_table_copies():
    """内存里有两份射弹表: 两份都要打, 外形/弹道都保持不变."""
    b1, b2 = 0x20000000, 0x30000000
    mk = lambda: make_block([FIL, TGT, SRC_R, DEC, FIL])
    L = run(tables=[(b1, BOFF, mk()), (b2, BOFF, mk())], frames=600)
    c = Checker("T7")
    c.eq(patched(L), 2, "both copies patched")
    for b in (b1, b2):
        got = abs_bytes(L, rec_base(b, BOFF) + 1 * STRIDE, STRIDE)
        c.eq(got, PATCHED_TGT, "copy at 0x%X patched correctly" % b)
    return c.result()


@test
def t8_write_fail_detected():
    """写入静默失败: 回读校验必须发现, 不得谎报成功."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    addr = rec_base(BASE, BOFF) + 1 * STRIDE
    L = run(tables=[(BASE, BOFF, block)], write_fail_addrs=[addr])
    c = Checker("T8")
    c.eq(patched(L), 0, "no false success")
    c.true("read-back mismatch" in log_text(L), "log mentions read-back mismatch")
    return c.result()


@test
def t9_readonly_page_unprotect():
    """目标页只读: 临时解保护写入, 写完恢复原保护属性."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    L = run(tables=[(BASE, BOFF, block, 0x02)])
    c = Checker("T9")
    c.eq(patched(L), 1, "patched on read-only page")
    c.eq(L.globals().HARNESS.region_prot(BASE), 0x02, "page protection restored")
    return c.result()


@test
def t10_loader_too_old():
    """loader API 0 (v14): 立刻停手, 不扫描不写入."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    L = run(tables=[(BASE, BOFF, block)], loader=(0, 14))
    c = Checker("T10")
    c.true("FAILED - Bingus Shared Loader too old" in status_head(L), "status FAILED (%r)" % status_head(L))
    c.eq(write_count(L), 0, "no writes")
    c.eq(patched(L), 0, "no patch")
    return c.result()


@test
def t11_loader_gate_log_fallback():
    """拿不到 loader 全局表时: 退化为读 BingusSharedLoader.log 首行."""
    block = make_block([FIL, TGT, SRC_R, DEC])
    L = run(tables=[(BASE, BOFF, block)], loader=None,
            preload_loader_log="Bingus Shared Loader loader-v19; API 1\nrest\n")
    c = Checker("T11")
    c.eq(patched(L), 1, "patched via log fallback")
    return c.result()


@test
def t12_recheck_reapplies():
    """补丁被冲掉: 稳态复查按地址直读发现并重打."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T12")
    addr = real_target_addr()
    c.eq(patched(L), 1, "initial patch")
    L.globals().HARNESS.write_hex(addr, TGT.hex().upper())     # 游戏回写原版数据
    L.execute("HARNESS.frames(400)")
    got = abs_bytes(L, addr, STRIDE)
    c.eq(got, PATCHED_TGT, "patch re-applied")
    c.true("re-applying own fields" in log_text(L), "log mentions re-apply")
    return c.result()


@test
def t13_all_copies_lost_rescan():
    """所有副本都没了(地图重载): 回到搜索态."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T13")
    c.eq(patched(L), 1, "initial patch")
    L.execute("HARNESS.drop_all_regions()")
    L.execute("HARNESS.frames(400)")
    c.true("SEARCHING - patched copies lost" in status_head(L),
           "status back to SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t14_cluster_before_flak():
    """Cluster 模式(life 0.25)排在 Flak 前面: 必须仍选 Flak 近炸模式(life 1.5)."""
    block = make_block([FIL, TGT, CLU, SRC_R, DEC])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T14")
    c.eq(patched(L), 1, "patched")
    got = abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE)
    c.eq(got, PATCHED_TGT, "took explosion from FLAK variant, not cluster")
    return c.result()


@test
def t15_flight_audio_switch_off():
    """SWAP_FLIGHT_FX=false: 连飞行音效也保持原版胆汁; 外形/弹道照旧不变."""
    s = ADDON_SRC.replace("SWAP_FLIGHT_FX = true,", "SWAP_FLIGHT_FX = false,", 1)
    L = run(src=s, tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T15")
    c.eq(patched(L), 1, "patched")
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.eq(got, PATCHED_TGT_NOFX, "flight audio NOT swapped")
    for off, ln in UNCHANGED:
        c.eq(got[off:off + ln], TGT[off:off + ln], "field @+%d still unchanged" % off)
    c.eq(got[OFF_AUDIO_START:OFF_AUDIO_START + 4], TGT[OFF_AUDIO_START:OFF_AUDIO_START + 4],
         "flight audio start kept vanilla")
    return c.result()


@test
def t16_status_fields_and_log():
    """STATUS/日志必须把"改了什么/外形与弹道保持不变"写清楚(便于排障)."""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T16")
    st = status_text(L)
    c.eq(stat_field(L, "impact_explosion"), "%d->%d" % (
        struct.unpack_from("<I", TGT, OFF_EXPL)[0],
        struct.unpack_from("<I", SRC_R, OFF_EXPL)[0]), "explosion change in status")
    c.true("model_kept_vanilla_bile=true" in st, "model kept-vanilla flag in status")
    c.true("shape(model/particles)_preserved=true" in st, "shape preserved flag in status")
    c.true("flight(trajectory/speed/arc)_preserved=true" in st, "flight preserved flag in status")
    c.true("host-authoritative" in st, "host-authoritative note present")
    lg = log_text(L)
    c.true("PATCHED bug artillery" in lg, "log has PATCHED line")
    c.true("shape kept vanilla bile" in lg, "log says shape kept vanilla")
    c.true("flight preserved" in lg, "log says flight preserved")
    return c.result()


@test
def t17_recheck_keeps_foreign_field():
    """★ v1.5.0 共存断言: 复查只为自己的字段负责 —— 不得覆盖别的 mod 改在同一记录上的字段。

    这里模拟"6 发 mod"把同一条胆汁迫击炮射弹记录的 +28 num_projectiles 改成 3;
    本 addon 复查时必须**补回自己的字段**、同时**保住 +28**。
    """
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T17")
    addr = real_target_addr()
    c.eq(patched(L), 1, "initial patch")
    # 另一个 mod 的成果: +28 = 3
    foreign = TGT[:OFF_NUM_PROJ] + b"\x03\x00\x00\x00" + TGT[OFF_NUM_PROJ + 4:]
    # 把记录整体换成"原版 + 别人的 +28"(相当于玩家的补丁被游戏冲掉, 只剩别人的字段)
    L.globals().HARNESS.write_hex(addr, foreign.hex().upper())
    L.execute("HARNESS.frames(400)")
    want = splice(foreign, SRC_R, FIELDS_ALWAYS + FIELDS_FX)
    c.eq(abs_bytes(L, addr, STRIDE), want, "own fields re-applied AND foreign +28 preserved")
    c.eq(abs_bytes(L, addr, STRIDE)[OFF_NUM_PROJ:OFF_NUM_PROJ + 4], b"\x03\x00\x00\x00",
         "foreign +28 still 3")
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


def scen_cluster_first(src):
    block = make_block([FIL, TGT, CLU, SRC_R, DEC])
    return run(src=src, tables=[(BASE, BOFF, block)])


def check_real(L):
    """T1+T2 的关键断言: 补丁正确 + 外形/弹道未变"""
    if patched(L) != 1:
        return False
    got = abs_bytes(L, real_target_addr(), STRIDE)
    if got != PATCHED_TGT:
        return False
    if got[OFF_UNIT:OFF_UNIT + 8] != TGT[OFF_UNIT:OFF_UNIT + 8]:
        return False
    if got[OFF_THRUSTER:OFF_THRUSTER + 8] != TGT[OFF_THRUSTER:OFF_THRUSTER + 8]:
        return False
    if got[OFF_TRAIL:OFF_TRAIL + 8] != TGT[OFF_TRAIL:OFF_TRAIL + 8]:
        return False
    return True


def check_writefail(L):
    return patched(L) == 0


def check_cluster_first(L):
    if patched(L) != 1:
        return False
    got = abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE)
    return got == PATCHED_TGT


EXPL_LINE = '    { off = 144, len = 4, group = "explosion", name = "explosion_type_on_impact" },\n'
DELAY_LINE = '    { off = 152, len = 4, group = "submuni",   name = "explosion_delay" },\n'
FLAGS_LINE = '    { off = 240, len = 1, group = "submuni",   name = "flags" },\n'

MODEL_LINE = '    { off = 128, len = 8, group = "model",     name = "projectile_unit_path" },\n'
TRAIL_LINE = '    { off = 96,  len = 8, group = "particles", name = "particle_trail" },\n'

MUTATIONS = [
    ("M1_target_trail_wrong",
     [('TGT_TRAIL_HEX = "29354B9DC32A52AC",', 'TGT_TRAIL_HEX = "0000000000000000",')],
     scen_real, check_real, "目标拖尾指纹写错 -> 找不到目标"),
    ("M2_target_thruster_wrong",
     [('TGT_THR_HEX   = "758CA9293725AFE2",', 'TGT_THR_HEX   = "0000000000000000",')],
     scen_real, check_real, "目标推进粒子指纹写错 -> 找不到目标"),
    ("M3_source_trail_wrong",
     [('SRC_TRAIL_HEX = "BF87A56B321EFDC8",', 'SRC_TRAIL_HEX = "0000000000000000",')],
     scen_real, check_real, "源拖尾指纹写错 -> 取不到源"),
    ("M4_endianness_swapped",
     [('TGT_TRAIL_HEX = "29354B9DC32A52AC",', 'TGT_TRAIL_HEX = "AC522AC39D4B3529",')],
     scen_real, check_real, "字节序搞反 -> 64位哈希对不上"),
    ("M5_regression_model_swap",
     [(EXPL_LINE, MODEL_LINE + EXPL_LINE)],
     scen_real, check_real, "★ 回退被破坏(又去改模型) -> 被 keep-guard 拦下(模型/绿团块必须原版)"),
    ("M6_regression_particle_swap",
     [(DELAY_LINE, TRAIL_LINE + DELAY_LINE)],
     scen_real, check_real, "★ 又去改飞行粒子 -> 被 keep-guard 拦下"),
    ("M7_no_explosion_swap",
     [(EXPL_LINE, "")],
     scen_real, check_real, "不改爆炸 -> 落地仍是胆汁爆炸"),
    ("M8_drop_flags_swap",
     [(FLAGS_LINE, "")],
     scen_real, check_real, "漏掉子弹药 flags -> 25 枚子弹药飞不出去"),
    ("M9_full_clone_no_guard",
     [("    if not flight_guard_ok(cur, new) then", "    if false then"),
      ("    local new = build_patched(cur, src_rec)",
       "    local new = string.sub(cur, 1, 24) .. string.sub(src_rec, 25)")],
     scen_real, check_real, "整条克隆且去掉自检 -> 弹道/模型被改"),
    ("M10_drop_life_prox_filters",
     [("""       and near(f32_at(r, CONFIG.OFF_LIFE), CONFIG.SRC_LIFE, 0.03)
       and near(f32_at(r, CONFIG.OFF_EXPL_PROX), CONFIG.SRC_PROX, 0.1)""", "")],
     scen_cluster_first, check_cluster_first, "去掉寿命/近炸判据 -> 误选 Cluster 模式"),
    ("M11_no_readback_verify",
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
