# -*- coding: utf-8 -*-
"""
test_bug_4rounds.py —— bug_artillery_4rounds.lua (v1.0.0) 的 lupa 离线仿真测试

★ 与 `bug_artillery_6rounds`(每发 3 枚) 同靶同逻辑, 只把默认"每次开火枚数"改成 2:
  **ProjectileSettings / ProjectileType_Bug_Artillery / +28 num_projectiles**
  额外守住一条: 若"6 发版"也已加载, 本 addon 必须**让位**(不扫描/不写入) —— 见 T19。

夹具来自**当前构建的真实明文镜像**(analysis/ref/generated_projectile_settings.dl_bin):
  fixtures/ba_table_block.bin   真实整块射弹表(350 条, 目标在 idx 29)
  fixtures/ba_target.bin        胆汁迫击炮射弹记录(num_projectiles=1)
  fixtures/ba_decoy.bin         干扰项(口径50/质量1000 但拖尾/推进粒子/音频不同)
  fixtures/ba_filler.bin        idx 0
  fixtures/ba_src_flak.bin      RL-77 空爆火箭(不能被误伤)

用户要求(本套测试守着):
  1) 胆汁喷涌虫一次齐射变成 4 团 (每次开火 2 枚 × 齐射 2 次)
  2) 除 +28 外**逐字节不动**(索敌/弹道/外形/音效/爆炸 全部不受影响)
  3) 数值可在游戏运行时通过 cfg 文件调整, 不用重打包
"""
import os, sys, re, struct
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SRC = os.environ.get("HD2_ADDON_4R_SRC") or os.path.abspath(
    os.path.join(HERE, "..", "src", "bug_artillery_4rounds.lua"))
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
ADDON_SRC = open(SRC, "r", encoding="utf-8").read()


def fx(name):
    return open(os.path.join(FIX, name), "rb").read()


TGT = fx("ba_target.bin")
DEC = fx("ba_decoy.bin")
FIL = fx("ba_filler.bin")
FLAK = fx("ba_src_flak.bin")
BLOCK = fx("ba_table_block.bin")

TYPE_PROJECTILE = 0xBD4042C2
TARGET_TYPE = 344
STRIDE = 272
REGION_SIZE = 0x40000
REAL_TGT_IDX = 29
OFF_NUM_PROJ = 28
OFF_CAL = 24
OFF_SPEED = 32

LOGDIR = (os.getenv("LOCALAPPDATA") or "") + "/CowboyBingus/Helldivers2/Logs/"
CFG = LOGDIR + "bug_artillery_4rounds.cfg"
DEFAULT_PER_SHOT = 2


def with_proj(rec, n):
    return rec[:OFF_NUM_PROJ] + struct.pack("<I", n) + rec[OFF_NUM_PROJ + 4:]


EXPDEF = with_proj(TGT, 2)   # 默认(每次 2 枚)
EXP3 = with_proj(TGT, 3)       # 仅 T16 显式 cfg=3 用
EXP6 = with_proj(TGT, 6)


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
    L.execute('HARNESS.status_file = "bug_artillery_4rounds_STATUS.txt"')
    L.execute('HARNESS.log_file = "bug_artillery_4rounds.log"')
    return L


def run(src=ADDON_SRC, frames=400, tables=None, loader=(1, 19), preload_loader_log=None,
        write_fail_addrs=(), cfg=None, files=None):
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


def get_file(L, path):
    return L.globals().HARNESS.get_file(path)


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
    """真实整表: 胆汁迫击炮射弹的 num_projectiles 1 -> 2。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T1")
    c.eq(patched(L), 1, "patched records")
    c.eq(stat_field(L, "target(bug artillery projectile) type"), str(TARGET_TYPE), "target type")
    c.true(status_head(L).startswith("OK - patch applied"), "status head OK (%r)" % status_head(L))
    c.eq(stat_field(L, "projectiles_per_shot"), "1->2", "per-shot 1->2 in status")
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.eq(got, EXPDEF, "whole record == expected")
    return c.result()


@test
def t2_only_num_projectiles_changed():
    """★ 核心断言: 除 +28 外逐字节不变(弹道/外形/音效/爆炸 全不受影响)。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T2")
    got = abs_bytes(L, real_target_addr(), STRIDE)
    c.true(got is not None, "record readable")
    if got is None:
        return c.result()
    diff = [k for k in range(STRIDE) if got[k] != TGT[k]]
    c.eq(diff, [28], "only byte 28 differs")
    c.eq(struct.unpack_from("<I", got, OFF_NUM_PROJ)[0], 2, "num_projectiles == 2")
    c.eq(struct.unpack_from("<f", got, OFF_CAL)[0], 50.0, "calibre still 50")
    c.eq(struct.unpack_from("<f", got, OFF_SPEED)[0], 30.0, "speed still 30")
    c.eq(got[:28], TGT[:28], "everything before +28 unchanged")
    c.eq(got[32:], TGT[32:], "everything after +31 unchanged")
    return c.result()


@test
def t3_cfg_override_value():
    """cfg 文件里的数字覆盖默认值(设 6 => 每次开火 6 枚 = 12 团)。"""
    L = run(tables=[(BASE, BOFF, BLOCK)], cfg="6\n")
    c = Checker("T3")
    c.eq(stat_field(L, "projectiles_per_shot"), "1->6", "per-shot 1->6 from cfg")
    c.eq(abs_bytes(L, real_target_addr(), STRIDE), EXP6, "record uses cfg value")
    return c.result()


@test
def t4_cfg_invalid_falls_back():
    """cfg 内容非法(超范围/非数字): 退回默认值 3, 不得乱写。"""
    for bad in ("999\n", "0\n", "hello\n"):
        L = run(tables=[(BASE, BOFF, BLOCK)], cfg=bad)
        c = Checker("T4(%r)" % bad)
        c.eq(abs_bytes(L, real_target_addr(), STRIDE), EXPDEF, "falls back to default 2")
        if c.fails:
            return c.result()
    return Checker("T4").result()


@test
def t5_cfg_created_when_missing():
    """没有 cfg 文件时: 用默认值, 并把默认值写出来给用户看。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T5")
    c.eq(abs_bytes(L, real_target_addr(), STRIDE), EXPDEF, "default 2 applied")
    c.eq((get_file(L, CFG) or "").strip(), str(DEFAULT_PER_SHOT), "cfg file written with default")
    return c.result()


@test
def t6_no_target_no_write():
    """表里没有胆汁迫击炮射弹时: 不得乱写。"""
    block = make_block([FIL, DEC, FLAK, FIL])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T6")
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no memory writes")
    c.true("SEARCHING" in status_head(L), "status stays SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t7_rocket_record_not_touched():
    """RL-77 空爆火箭(和胆汁迫击炮同口径区间的其它射弹)绝不能被误伤。"""
    block = make_block([FIL, FLAK, TGT, DEC])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T7")
    c.eq(patched(L), 1, "only the bile mortar patched")
    c.eq(abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE), FLAK, "rocket record untouched")
    c.eq(abs_bytes(L, rec_base(BASE, BOFF) + 3 * STRIDE, STRIDE), DEC, "decoy untouched")
    return c.result()


@test
def t8_idempotent():
    """已是补丁形态: 登记但绝不重复写。"""
    block = make_block([FIL, EXPDEF, DEC])
    L = run(tables=[(BASE, BOFF, block)])
    c = Checker("T8")
    c.eq(patched(L), 1, "registered")
    c.eq(write_count(L), 0, "no writes (idempotent)")
    c.true("ALREADY" in log_text(L), "log says ALREADY")
    return c.result()


@test
def t9_two_table_copies():
    """内存有两份射弹表: 两份都要打。"""
    b1, b2 = 0x20000000, 0x28000000
    mk = lambda: make_block([FIL, TGT, DEC, FIL])
    L = run(tables=[(b1, BOFF, mk()), (b2, BOFF, mk())], frames=800)
    c = Checker("T9")
    c.eq(patched(L), 2, "both copies patched")
    for b in (b1, b2):
        c.eq(abs_bytes(L, rec_base(b, BOFF) + 1 * STRIDE, STRIDE), EXPDEF, "copy 0x%X patched" % b)
    return c.result()


@test
def t10_write_fail_detected():
    """写入静默失败: 回读校验必须发现, 不得谎报成功。"""
    block = make_block([FIL, TGT, DEC])
    addr = rec_base(BASE, BOFF) + 1 * STRIDE + OFF_NUM_PROJ
    L = run(tables=[(BASE, BOFF, block)], write_fail_addrs=[addr])
    c = Checker("T10")
    c.eq(patched(L), 0, "no false success")
    c.true("read-back mismatch" in log_text(L), "log mentions read-back mismatch")
    return c.result()


@test
def t11_readonly_page_unprotect():
    """目标页只读: 临时解保护写入, 写完恢复原保护属性。"""
    block = make_block([FIL, TGT, DEC])
    L = run(tables=[(BASE, BOFF, block, 0x02)])
    c = Checker("T11")
    c.eq(patched(L), 1, "patched on read-only page")
    c.eq(L.globals().HARNESS.region_prot(BASE), 0x02, "page protection restored")
    return c.result()


@test
def t12_loader_too_old():
    """loader API 0 (v14): 立刻停手, 不扫描不写入。"""
    block = make_block([FIL, TGT, DEC])
    L = run(tables=[(BASE, BOFF, block)], loader=(0, 14))
    c = Checker("T12")
    c.true("FAILED - Bingus Shared Loader too old" in status_head(L), "status FAILED (%r)" % status_head(L))
    c.eq(write_count(L), 0, "no writes")
    c.eq(patched(L), 0, "no patch")
    return c.result()


@test
def t13_loader_gate_log_fallback():
    """拿不到 loader 全局表时: 退化为读 BingusSharedLoader.log 首行。"""
    block = make_block([FIL, TGT, DEC])
    L = run(tables=[(BASE, BOFF, block)], loader=None,
            preload_loader_log="Bingus Shared Loader loader-v19; API 1\nrest\n")
    c = Checker("T13")
    c.eq(patched(L), 1, "patched via log fallback")
    return c.result()


@test
def t14_recheck_reapplies():
    """补丁被冲掉: 稳态复查按地址直读发现并重打。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T14")
    addr = real_target_addr()
    c.eq(patched(L), 1, "initial patch")
    L.globals().HARNESS.write_hex(addr, TGT.hex().upper())
    L.execute("HARNESS.frames(400)")
    c.eq(abs_bytes(L, addr, STRIDE), EXPDEF, "patch re-applied")
    return c.result()


@test
def t15_all_copies_lost_rescan():
    """所有副本都没了(地图重载): 回到搜索态。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T15")
    c.eq(patched(L), 1, "initial patch")
    L.execute("HARNESS.drop_all_regions()")
    L.execute("HARNESS.frames(400)")
    c.true("SEARCHING - patched copies lost" in status_head(L),
           "status back to SEARCHING (%r)" % status_head(L))
    return c.result()


@test
def t16_runtime_cfg_change():
    """★ 运行时改 cfg: 不重开游戏、不重打包, ~5 秒内自动重打为新值。"""
    L = run(tables=[(BASE, BOFF, BLOCK)], cfg="3\n")
    c = Checker("T16")
    addr = real_target_addr()
    c.eq(abs_bytes(L, addr, STRIDE), EXP3, "initial 3")
    L.globals().NEWCFG = "6\n"
    L.globals().CFG_PATH = CFG
    L.execute("HARNESS.preload_file(CFG_PATH, NEWCFG)")
    L.execute("HARNESS.frames(400)")          # 覆盖到下一次 recheck
    c.eq(abs_bytes(L, addr, STRIDE), EXP6, "re-applied as 6 after cfg change")
    c.true("cfg changed: per-shot 3 -> 6" in log_text(L), "log mentions cfg change")
    return c.result()


@test
def t17_status_and_log_fields():
    """STATUS/日志把"改了什么 / 怎么调 / 什么没变"写清楚(便于排障)。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T17")
    st = status_text(L)
    c.true("projectiles_per_shot=1->2" in st, "per-shot change in status")
    c.true("bug_artillery_4rounds.cfg" in st, "mentions cfg file")
    c.true("UNCHANGED" in st, "states nothing else changed")
    c.true("host-authoritative" in st, "host-authoritative note")
    lg = log_text(L)
    c.true("PATCHED" in lg and "num_projectiles 1 -> 2" in lg, "log has PATCHED line")
    return c.result()


@test
def t18_no_global_pollution():
    """只准新增自己唯一命名的全局 + update。"""
    L = run(tables=[(BASE, BOFF, BLOCK)])
    c = Checker("T18")
    names = L.eval("(function() local o={} for k,v in pairs(_G) do o[#o+1]=k end table.sort(o) return table.concat(o, ',') end)()")
    names = set(n.strip() for n in str(names).split(","))
    c.true("_HD2_BUG_ARTILLERY_4ROUNDS" in names, "singleton global present")
    c.true("_HD2_BUG4R_FLUSH" in names, "unique flush global present")
    for bad in ("flush_log", "end_pass", "process_proj_block", "set_num_proj", "tick",
                "RIVAL_SINGLETON", "rival_present"):
        c.true(bad not in names, "no leaked global %r" % bad)
    return c.result()


@test
def t19_rival_6rounds_yields():
    """★ 互斥: 若"6 发版"(每发 3 枚)已在跑, 本 addon 必须让位 —— 不扫描、不写入、不碰记录。"""
    block = make_block([FIL, TGT, DEC])
    L = new_env()
    L.execute("HARNESS.reset()")
    L.execute("HARNESS.set_loader(1, 19)")
    add_region(L, BASE, REGION_SIZE, b"\x00" * BOFF + block)
    L.globals().RIVAL = "_HD2_BUG_ARTILLERY_6ROUNDS"
    L.execute("_G[RIVAL] = true")            # 模拟 6 发版已加载
    L.execute("HARNESS.install_update_hook()")
    L.globals().ADDON_SRC = ADDON_SRC
    L.execute("HARNESS.run_addon(ADDON_SRC)")
    L.execute("HARNESS.frames(400)")
    c = Checker("T19")
    c.true(status_head(L).startswith("SKIPPED"), "status SKIPPED (%r)" % status_head(L))
    c.eq(patched(L), 0, "no patch")
    c.eq(write_count(L), 0, "no writes")
    c.eq(abs_bytes(L, rec_base(BASE, BOFF) + 1 * STRIDE, STRIDE), TGT, "target record untouched")
    return c.result()


# ---------------------------------------------------------------------------
# 场景构造(供变异测试复用)
# ---------------------------------------------------------------------------
def scen_real(src):
    return run(src=src, tables=[(BASE, BOFF, BLOCK)])


def check_real(L):
    """T1+T2 的关键断言: 打上了 + 只有 +28 变了 + 值=2"""
    if patched(L) != 1:
        return False
    got = abs_bytes(L, real_target_addr(), STRIDE)
    if got != EXPDEF:
        return False
    if [k for k in range(STRIDE) if got[k] != TGT[k]] != [28]:
        return False
    return True


def scen_cfg(src):
    return run(src=src, tables=[(BASE, BOFF, BLOCK)], cfg="6\n")


def check_cfg(L):
    return abs_bytes(L, real_target_addr(), STRIDE) == EXP6


def scen_decoy(src):
    block = make_block([FIL, FLAK, DEC, FIL])
    return run(src=src, tables=[(BASE, BOFF, block)])


def check_decoy(L):
    return patched(L) == 0 and write_count(L) == 0


def scen_writefail(src):
    block = make_block([FIL, TGT, DEC])
    return run(src=src, tables=[(BASE, BOFF, block)],
               write_fail_addrs=[rec_base(BASE, BOFF) + 1 * STRIDE + OFF_NUM_PROJ])


def check_writefail(L):
    return patched(L) == 0


MUTATIONS = [
    ("M1_target_trail_wrong",
     [('TGT_TRAIL_HEX = "29354B9DC32A52AC",', 'TGT_TRAIL_HEX = "0000000000000000",')],
     scen_real, check_real, "目标拖尾指纹写错 -> 找不到目标"),
    ("M2_target_audio_wrong",
     [("    TGT_AUDIO     = 3340293219,", "    TGT_AUDIO     = 12345,")],
     scen_real, check_real, "目标音频指纹写错 -> 找不到目标"),
    ("M3_endianness_swapped",
     [('TGT_TRAIL_HEX = "29354B9DC32A52AC",', 'TGT_TRAIL_HEX = "AC522AC39D4B3529",')],
     scen_real, check_real, "字节序搞反 -> 64 位哈希对不上"),
    ("M4_wrong_offset",
     [("    OFF_NUM_PROJ      = 28,", "    OFF_NUM_PROJ      = 32,")],
     scen_real, check_real, "偏移写错 -> 改了速度而不是发数"),
    ("M5_oversized_write",
     [("    if not write_mem(rec_addr + CONFIG.OFF_NUM_PROJ, u32_le(n)) then",
       "    if not write_mem(rec_addr + CONFIG.OFF_NUM_PROJ, u32_le(n) .. \"\\0\\0\\0\\0\") then")],
     scen_real, check_real, "写超长字节 -> 把 +32 的速度也冲掉了"),
    ("M6_no_readback_verify",
     [("""    local back = read_mem(rec_addr, CONFIG.REC_SIZE)
    if back == nil or u32_at(back, CONFIG.OFF_NUM_PROJ) ~= n then""",
       """    local back = read_mem(rec_addr, CONFIG.REC_SIZE)
    if false then""")],
     scen_writefail, check_writefail, "去掉回读校验 -> 写入失败被漏过"),
    ("M7_noop_default",
     [("    PROJ_PER_SHOT_DEFAULT = 2,", "    PROJ_PER_SHOT_DEFAULT = 1,")],
     scen_real, check_real, "默认值没改(仍是1) -> 什么都没变"),
    ("M8_identity_disabled",
     [("""local function is_target_record(r)
    if u32_at(r, CONFIG.OFF_NAME_UPPER) ~= 0 then return false end
    if u32_at(r, CONFIG.OFF_NAME_CASED) ~= 0 then return false end
    if not near(f32_at(r, CONFIG.OFF_CAL), CONFIG.TGT_CAL, 0.5) then return false end
    if not near(f32_at(r, CONFIG.OFF_SPEED), CONFIG.TGT_SPEED, 0.5) then return false end
    if not near(f32_at(r, CONFIG.OFF_MASS), CONFIG.TGT_MASS, 1.0) then return false end
    if string.sub(r, CONFIG.OFF_TRAIL + 1, CONFIG.OFF_TRAIL + 8) ~= tgt_trail then return false end
    if string.sub(r, CONFIG.OFF_THRUSTER + 1, CONFIG.OFF_THRUSTER + 8) ~= tgt_thr then return false end
    local au = u32_at(r, CONFIG.OFF_AUDIO_START)
    if au ~= CONFIG.TGT_AUDIO and au ~= CONFIG.SRC_AUDIO then return false end
    return true
end""", """local function is_target_record(r)
    return true
end""")],
     scen_decoy, check_decoy, "身份指纹整体失效 -> 随便抓一条记录就改"),
    ("M9_cfg_ignored",
     [("    local n = tonumber(string.match(txt, \"(%d+)\"))",
       "    local n = nil")],
     scen_cfg, check_cfg, "cfg 被忽略 -> 用户调不了数值"),
]


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    npass = nfail = 0
    print("=" * 72); print("功能测试"); print("=" * 72)
    for fn in TESTS:
        if only and not fn.__name__.startswith(only.lower()):
            continue
        name, fails = fn()
        if fails:
            nfail += 1; print("  [FAIL] %s" % name)
            for f in fails: print("         - %s" % f)
        else:
            npass += 1; print("  [ OK ] %s" % name)

    if not only:
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
