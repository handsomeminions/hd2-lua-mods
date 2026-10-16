# -*- coding: utf-8 -*-
"""从当前构建的 dl_bin 解析射弹表 + 轰炸表, 用本地化表解名(地面真值)."""
import struct, json, glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _env

REF = os.path.join(HERE, "ref")
entities = open(_env.require(_env.ENTITIES_BIN, "实体数据 blob"), "rb").read()
proj = open(_env.require(_env.PROJ_BIN, "射弹表 dl_bin"), "rb").read()

TYPE_BOMBARDMENT = 0xCDBC43D8
TYPE_PROJECTILE = 0xBD4042C2
TARGET = 3259427501513118129   # 0x2D3BD00B1ED411B1 120mm 火力网 payload


def find_block(blob, th):
    sig = b"LDLD" + struct.pack("<II", 1, th)
    i = blob.find(sig)
    assert i >= 0, "type 0x%08X not found" % th
    ver, typ, size = struct.unpack_from("<III", blob, i + 4)
    return i, size


def load_trans():
    HD = _env.community()
    trans = {}
    for f in glob.glob(os.path.join(HD, "translations", "*.json")):
        try:
            j = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        def walk(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    if isinstance(k, str) and k.isdigit():
                        trans[int(k)] = v
                    walk(v)
            elif isinstance(o, list):
                for x in o:
                    walk(x)
        walk(j)
    return trans


trans = load_trans()


def name_of(nu):
    return trans.get(nu, "<unknown %s>" % nu)


# ---- 射弹表: type(枚举下标) -> name_upper ----
pmagic, psize = find_block(proj, TYPE_PROJECTILE)
ptr, cnt = struct.unpack_from("<QQ", proj, pmagic + 24)
stride = (psize - 16) // cnt
recs_base = pmagic + 24 + ptr
type2name = {}
type2phys = {}
for k in range(cnt):
    r = proj[recs_base + k * stride: recs_base + (k + 1) * stride]
    t = struct.unpack_from("<I", r, 0)[0]
    nu = struct.unpack_from("<I", r, 4)[0]
    cal = struct.unpack_from("<f", r, 24)[0]
    spd = struct.unpack_from("<f", r, 32)[0]
    mass = struct.unpack_from("<f", r, 36)[0]
    type2name[t] = nu
    type2phys[t] = (cal, spd, mass)
print("projectile table: count=%d stride=%d" % (cnt, stride))

for t in [194, 137, 239, 170, 140, 97, 108, 210, 192, 193]:
    nu = type2name.get(t)
    if nu is None:
        print("  type %3d: <无此射弹记录>" % t)
    else:
        print("  type %3d: %-46s cal=%5.1f speed=%6.1f mass=%6.1f" % (
            t, name_of(nu)[:46], *type2phys[t]))

# ---- 轰炸表: 目标记录全字段 ----
bmagic, bsize = find_block(entities, TYPE_BOMBARDMENT)
base = bmagic + 24
A = 0
while True:
    hv, ix, pad = struct.unpack_from("<QII", entities, base + A * 16)
    if pad != 0 or ix > 65535:
        break
    A += 1
E = 192
N = (bsize - 16 * A) // E
idx = None
for k in range(A):
    hv, ix, pad = struct.unpack_from("<QII", entities, base + k * 16)
    if hv == TARGET:
        idx = ix
print("\nbombardment table: buckets=%d records=%d stride=%d target_record=%d" % (A, N, E, idx))
rec = entities[base + 16 * A + idx * E: base + 16 * A + (idx + 1) * E]


def u32(o): return struct.unpack_from("<I", rec, o)[0]
def i32(o): return struct.unpack_from("<i", rec, o)[0]
def f32(o): return struct.unpack_from("<f", rec, o)[0]

print("  +0  : %d" % u32(0))
print("  +4  num_bombs    = %d" % i32(4))
print("  +8  bomb_interval= %.3f" % f32(8))
print("  +12            = %d (u32) / %.3f (f32)" % (u32(12), f32(12)))
print("  +16            = %d / %.3f" % (u32(16), f32(16)))
print("  +20            = %d / %.3f" % (u32(20), f32(20)))
print("  +24 num_salvos   = %d" % i32(24))
print("  +28 salvo_interval=%.3f" % f32(28))
print("  +32            = %d / %.3f" % (u32(32), f32(32)))
print("  +36 area_size    = %.3f" % f32(36))
print("  +40            = %.3f" % f32(40))
print("  +44 fire_height  = %.3f" % f32(44))
print("  +48            = %.3f" % f32(48))
print("  +52            = %.3f" % f32(52))
print("  +56            = %.3f" % f32(56))
print("  +60 fire_from_ship=%d" % u32(60))
print("  +64 projectile_types[8] = %s" % (struct.unpack_from("<8I", rec, 64),))
for i, t in enumerate(struct.unpack_from("<8I", rec, 64)):
    if t:
        nu = type2name.get(t)
        print("        [%d] %3d  %s" % (i, t, name_of(nu) if nu else "?"))
print("  +96..+191 hex:", rec[96:192].hex())
