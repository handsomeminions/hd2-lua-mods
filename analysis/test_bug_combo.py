# -*- coding: utf-8 -*-
"""
test_bug_combo.py —— 两个 mod 同时加载时的**同一记录共存**验证

  bug_artillery_6rounds   (v2.2.0) -> ProjectileSettings / 胆汁迫击炮射弹 / +28 num_projectiles
  bug_artillery_airburst  (v1.5.0) -> ProjectileSettings / **同一条记录** / +144 +152 +240 +208 +212

★ 关键: 两者改的是**同一条记录的不同字段**, 所以:
    * 任何一方复查时**只能动自己的字段**, 绝不整条回写;
    * 跑过多个复查周期后, 两边的改动必须**都还在**。
  这正是 v1.5.0(空爆) 与 v2.0.0(6发) 各自做的改动 —— 本测试是它们的回归防线。
"""
import os, sys, struct
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
SIX = open(os.path.abspath(os.path.join(HERE, "..", "src", "bug_artillery_6rounds.lua")),
           "r", encoding="utf-8").read()
AB = open(os.path.abspath(os.path.join(HERE, "..", "src", "bug_artillery_airburst.lua")),
          "r", encoding="utf-8").read()


def fx(n):
    return open(os.path.join(FIX, n), "rb").read()


BLOCK = fx("ba_table_block.bin")
TGT = fx("ba_target.bin")
FLAK = fx("ba_src_flak.bin")

STRIDE = 272
TGT_IDX = 29
REGION = 0x40000
BASE, BOFF = 0x20000000, 0x1000
LOGDIR = (os.getenv("LOCALAPPDATA") or "") + "/CowboyBingus/Helldivers2/Logs/"

OFF_NUM_PROJ = 28
AB_FIELDS = [(144, 4), (152, 4), (240, 1), (208, 4), (212, 4)]


def splice(base, src, fields):
    out = base
    for off, ln in fields:
        out = out[:off] + src[off:off + ln] + out[off + ln:]
    return out


# 两边的改动合在同一条记录上
EXPECTED = splice(TGT, FLAK, AB_FIELDS)
EXPECTED = EXPECTED[:OFF_NUM_PROJ] + struct.pack("<I", 3) + EXPECTED[OFF_NUM_PROJ + 4:]


def add_region(L, base, size, data=b"", prot=0x04):
    body = (data + b"\x00" * size)[:size]
    L.globals().HARNESS.add_region_hex(base, size, body.hex().upper(), prot)


def abs_bytes(L, addr, n):
    h = L.globals().HARNESS.abs_hex(addr, n)
    return bytes.fromhex(h) if h else None


def status_text(L, fname):
    return L.globals().HARNESS.get_file(LOGDIR + fname) or ""


def main():
    order = sys.argv[1] if len(sys.argv) > 1 else "six_first"
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute(HARNESS_SRC)
    L.execute("HARNESS.reset()")
    L.execute("HARNESS.set_loader(1, 19)")
    L.execute('HARNESS.status_file = "bug_artillery_6rounds_STATUS.txt"')
    L.execute('HARNESS.log_file = "bug_artillery_6rounds.log"')
    add_region(L, BASE, REGION, b"\x00" * BOFF + BLOCK)
    L.execute("HARNESS.install_update_hook()")
    L.globals().SIX = SIX
    L.globals().AB = AB
    if order == "six_first":
        L.execute("HARNESS.run_addon(SIX)")
        L.execute("HARNESS.run_addon(AB)")
    else:
        L.execute("HARNESS.run_addon(AB)")
        L.execute("HARNESS.run_addon(SIX)")

    L.execute("HARNESS.frames(900)")
    addr = BASE + BOFF + 40 + TGT_IDX * STRIDE

    fails = []
    def check(cond, msg):
        if not cond:
            fails.append(msg)

    got = abs_bytes(L, addr, STRIDE)
    check(got == EXPECTED, "both mods' changes present on the SAME record (%s)" % order)
    check(got is not None and got[OFF_NUM_PROJ:OFF_NUM_PROJ + 4] == b"\x03\x00\x00\x00",
          "num_projectiles (6rounds) == 3")
    check(got is not None and got[144:148] == FLAK[144:148], "explosion (airburst) taken from rocket")

    # 再跑 3 个复查周期(~1800 帧): 双方复查时都不得把对方的字段冲掉
    L.execute("HARNESS.frames(1800)")
    got2 = abs_bytes(L, addr, STRIDE)
    check(got2 == EXPECTED, "still intact after 3 more recheck cycles (no ping-pong)")

    s6 = status_text(L, "bug_artillery_6rounds_STATUS.txt")
    sab = status_text(L, "bug_artillery_airburst_STATUS.txt")
    check(s6.startswith("OK - patch applied"), "6rounds status OK (got %r)" % s6.split("\n")[0])
    check(sab.startswith("OK - patch applied"), "airburst status OK (got %r)" % sab.split("\n")[0])

    calls = L.eval("HARNESS.update_original_calls")
    check(calls == 2700, "update chain intact (%s calls for 2700 frames)" % calls)

    names = L.eval("(function() local o={} for k,v in pairs(_G) do o[#o+1]=k end return table.concat(o, ',') end)()")
    names = set(str(names).split(","))
    for g in ("_HD2_BUGARTY_FLUSH", "_HD2_BUG6R_FLUSH"):
        check(g in names, "global %s present" % g)

    if fails:
        print("combo[%s]: 失败 %d" % (order, len(fails)))
        for f in fails:
            print("   - %s" % f)
        return 1
    print("combo[%s]: 通过 (同一记录上两边的改动共存, 多个复查周期不互抢)" % order)
    return 0


if __name__ == "__main__":
    sys.exit(main())
