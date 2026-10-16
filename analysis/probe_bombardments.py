# -*- coding: utf-8 -*-
"""标注整张 BombardmentComponentData 表: 实体 -> 战备名 + 参数 + 射弹名."""
import struct, json, glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _env

REF = os.path.join(HERE, "ref")
entities = open(_env.require(_env.ENTITIES_BIN, "实体数据 blob"), "rb").read()
proj = open(_env.require(_env.PROJ_BIN, "射弹表 dl_bin"), "rb").read()
TYPE_BOMBARDMENT = 0xCDBC43D8
TYPE_PROJECTILE = 0xBD4042C2

HD = _env.community()
trans = {}
for f in glob.glob(os.path.join(HD, "translations", "*.json")):
    j = json.load(open(f, encoding="utf-8"))
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(k, str) and k.isdigit(): trans[int(k)] = v
                walk(v)
        elif isinstance(o, list):
            for x in o: walk(x)
    walk(j)
name = lambda nu: trans.get(nu, "?%s" % nu)

# 战备 payload -> 战备名
st = json.load(open(os.path.join(HD, "settings", "generated_stratagem_settings.json"), encoding="utf-8"))
items = []
for sheet in st:
    for k, v in sheet.items():
        if isinstance(v, dict) and "items" in v: items += v["items"]
payload2name = {}
for it in items:
    for p in (it.get("payload") or []):
        payload2name.setdefault(p, name(it.get("name_upper")))

# 射弹 type -> 名
def find_block(blob, th):
    i = blob.find(b"LDLD" + struct.pack("<II", 1, th))
    ver, typ, size = struct.unpack_from("<III", blob, i + 4)
    return i, size
pmagic, psize = find_block(proj, TYPE_PROJECTILE)
ptr, cnt = struct.unpack_from("<QQ", proj, pmagic + 24)
stride = (psize - 16) // cnt
rb = pmagic + 24 + ptr
ptype = {}
for k in range(cnt):
    r = proj[rb + k * stride: rb + (k + 1) * stride]
    ptype[struct.unpack_from("<I", r, 0)[0]] = name(struct.unpack_from("<I", r, 4)[0])

# 轰炸表
bmagic, bsize = find_block(entities, TYPE_BOMBARDMENT)
base = bmagic + 24
A = 0
while True:
    hv, ix, pad = struct.unpack_from("<QII", entities, base + A * 16)
    if pad != 0 or ix > 65535: break
    A += 1
E = 192
N = (bsize - 16 * A) // E
print("buckets=%d records=%d" % (A, N))
print("%-22s %-3s %-4s %-4s %-6s %-7s %s" % ("stratagem", "rec", "bomb", "salv", "area", "height", "projectile_types"))
for k in range(A):
    hv, ix, pad = struct.unpack_from("<QII", entities, base + k * 16)
    if hv == 0: continue
    rec = entities[base + 16 * A + ix * E: base + 16 * A + (ix + 1) * E]
    nb = struct.unpack_from("<i", rec, 4)[0]
    ns = struct.unpack_from("<i", rec, 24)[0]
    ar = struct.unpack_from("<f", rec, 36)[0]
    fh = struct.unpack_from("<f", rec, 44)[0]
    pts = struct.unpack_from("<8I", rec, 64)
    stn = payload2name.get(hv, "0x%X" % hv)
    types = ", ".join("%s(%d)" % (ptype.get(t, "?"), t) for t in pts if t)
    print("%-22s %-3d %-4d %-4d %-6.0f %-7.0f %s" % (stn[:22], ix, nb, ns, ar, fh, types))
