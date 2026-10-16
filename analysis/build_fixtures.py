# -*- coding: utf-8 -*-
"""从 FileDiver 明文镜像提取真实数据, 生成 lupa 仿真夹具.

夹具全部用真实字节(实机同款数据), 再按测试需要变形:
  fx_baseline.bin    : 文件形态射弹表 + 轰炸表(原样)
  fx_memform.bin     : 内存形态射弹表(描述符=绝对指针, 记录搬走)
  fx_multicopy.bin   : 两份轰炸表副本
  fx_notarget.bin    : 轰炸表但目标实体哈希被抹掉
  fx_decoy.bin       : 含错误类型哈希的诱饵块
"""
import struct, os, json, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "ref")
FIX = os.path.join(HERE, "fixtures")
os.makedirs(FIX, exist_ok=True)

ENTITIES = os.path.join(REF, "generated_entities.dl_bin")
PROJ = os.path.join(REF, "generated_projectile_settings.dl_bin")

def dlsum(name):
    r = 5381
    for ch in name:
        r = (r * 33 + ord(ch)) & 0xFFFFFFFF
    return (r - 5381) & 0xFFFFFFFF

TH_BOMB = dlsum("BombardmentComponentData")
TH_PROJ = dlsum("ProjectileSettings")

def find_block(blob, th):
    sig = b"LDLD" + struct.pack("<II", 1, th)
    i = blob.find(sig)
    assert i >= 0, "type 0x%08X not found" % th
    ver, typ, size = struct.unpack_from("<III", blob, i + 4)
    assert ver == 1 and typ == th
    return i, size

ent = open(ENTITIES, "rb").read()
proj = open(PROJ, "rb").read()

bmagic, bsize = find_block(ent, TH_BOMB)
bomb_block = ent[bmagic: bmagic + 24 + bsize]
print("bombardment block: %d bytes (magic+%d in blob)" % (len(bomb_block), bmagic))

pmagic, psize = find_block(proj, TH_PROJ)
proj_block = proj[pmagic: pmagic + 24 + psize]
print("projectile block: %d bytes" % len(proj_block))

# --- 校验: 轰炸表里目标实体的记录与已知值一致 -------------------------------
TARGET = 3259427501513118129
base = bmagic + 24
A = 0
while True:
    hv, ix, pad = struct.unpack_from("<QII", ent, base + A * 16)
    if pad != 0 or ix > 65535:
        break
    A += 1
E = 192
N = (bsize - 16 * A) // E
print("buckets=%d records=%d stride=%d" % (A, N, E))
idx = None
for k in range(A):
    hv, ix, pad = struct.unpack_from("<QII", ent, base + k * 16)
    if hv == TARGET:
        idx = ix
assert idx is not None
rec = ent[base + 16 * A + idx * E: base + 16 * A + (idx + 1) * E]
nb = struct.unpack_from("<I", rec, 4)[0]
bi = struct.unpack_from("<f", rec, 8)[0]
ns = struct.unpack_from("<I", rec, 24)[0]
si = struct.unpack_from("<f", rec, 28)[0]
ar = struct.unpack_from("<f", rec, 36)[0]
fh = struct.unpack_from("<f", rec, 44)[0]
pts = struct.unpack_from("<8I", rec, 64)
print("record#%d: num_bombs=%d interval=%.2f salvos=%d salvo_int=%.1f area=%.0f height=%.0f" %
      (idx, nb, bi, ns, si, ar, fh))
print("projectile_types:", pts)
assert (nb, ns) == (3, 5) and abs(bi - 0.75) < 1e-6 and pts[0] != 0

# --- 校验: 射弹表里500kg炸弹 -------------------------------------------------
ptr, cnt = struct.unpack_from("<QQ", proj, pmagic + 24)
stride = (psize - 16) // cnt
recs_base = pmagic + 24 + ptr
bomb_type = None
for k in range(cnt):
    r = proj[recs_base + k * stride: recs_base + (k + 1) * stride]
    nu = struct.unpack_from("<I", r, 4)[0]
    if nu == 1027666422:
        mass = struct.unpack_from("<f", r, 36)[0]
        cal = struct.unpack_from("<f", r, 24)[0]
        spd = struct.unpack_from("<f", r, 32)[0]
        assert mass == 500 and cal == 50 and spd == 500, (mass, cal, spd)
        bomb_type = struct.unpack_from("<I", r, 0)[0]
print("500kg bomb: ProjectileType =", bomb_type, "(record #%d of %d)" %
      ([k for k in range(cnt) if struct.unpack_from('<I', proj, recs_base + k*stride + 4)[0] == 1027666422][0], cnt))

# --- 生成夹具 ----------------------------------------------------------------
def pad_to(b, n, fill=b"\xAA"):
    if len(b) >= n:
        return b
    return b + fill * (n - len(b))

# 1) baseline: 原样两块
open(os.path.join(FIX, "fx_proj_file.bin"), "wb").write(proj_block)
open(os.path.join(FIX, "fx_bomb.bin"), "wb").write(bomb_block)

# 2) memform: 描述符改成绝对指针, 记录搬到"别处"
recs = proj_block[24 + 16:]
mem = bytearray(proj_block)
struct.pack_into("<QQ", mem, 24, 0x14000000, cnt)     # 绝对指针
mem[24 + 16:] = b"\xBB" * len(recs)                    # 原记录区填垃圾
open(os.path.join(FIX, "fx_proj_mem.bin"), "wb").write(bytes(mem))
open(os.path.join(FIX, "fx_proj_mem_records.bin"), "wb").write(recs)

# 3) multicopy: 同一块复制一份(逐字节相同, 模拟内存里的两份副本)
open(os.path.join(FIX, "fx_bomb_copy2.bin"), "wb").write(bomb_block)

# 4) notarget: 抹掉目标实体对应的桶项
nt = bytearray(bomb_block)
for k in range(A):
    off = 24 + k * 16
    hv = struct.unpack_from("<Q", nt, off)[0]
    if hv == TARGET:
        struct.pack_into("<QII", nt, off, 0, 0, 0)
        print("notarget fixture: zeroed bucket #%d (index %d)" % (k, struct.unpack_from('<QII', ent, base + k*16)[1]))
        break
open(os.path.join(FIX, "fx_bomb_notarget.bin"), "wb").write(bytes(nt))

# 5) decoy: 错误类型哈希的 LDLD 块
decoy = bytearray(b"\xCC" * 1024)
decoy[0:4] = b"LDLD"
struct.pack_into("<III", decoy, 4, 1, 0x12345678, 1024 - 24)
open(os.path.join(FIX, "fx_decoy.bin"), "wb").write(bytes(decoy))

# 6) selfheap: 假Lua堆区(自检测测试用): 内含 "LDLD" 字面量 + 一份可解析的轰炸块
selfheap = bytearray(b"\x00" * 0x10000)
lua_lit_off = 0x100
selfheap[lua_lit_off:lua_lit_off + 4] = b"LDLD"
fake_blk_off = 0x1000
selfheap[fake_blk_off:fake_blk_off + len(bomb_block)] = bomb_block
open(os.path.join(FIX, "fx_selfheap.bin"), "wb").write(bytes(selfheap))
json.dump({"lua_lit_off": lua_lit_off, "fake_blk_off": fake_blk_off},
          open(os.path.join(FIX, "fx_selfheap.json"), "w"))

# 7) drift: 漂移构建的轰炸表 —— num_salvos=6/area=31(平衡性改动), 指纹应仍接受
dr = bytearray(bomb_block)
rec_off = 24 + 16 * A + idx * E
struct.pack_into("<I", dr, rec_off + 24, 6)          # num_salvos 5 -> 6
struct.pack_into("<f", dr, rec_off + 36, 31.0)       # area_size 27 -> 31
open(os.path.join(FIX, "fx_bomb_drift.bin"), "wb").write(bytes(dr))

# 8) shifted: projectile_types 偏移漂移(+64 -> +72), 测试反推
#    做法: 把记录里 +64..+96 的32字节后移8字节, 前面补0(仅改目标记录)
sh = bytearray(bomb_block)
old = bytes(sh[rec_off + 64: rec_off + 96])
sh[rec_off + 64: rec_off + 96] = b"\x00" * 32
sh[rec_off + 72: rec_off + 104] = old
open(os.path.join(FIX, "fx_bomb_shifted.bin"), "wb").write(bytes(sh))

meta = {"bomb_type": bomb_type, "target_index": idx, "buckets": A, "records": N,
        "stride": E, "proj_count": cnt, "proj_stride": stride,
        "proj_size": psize, "bomb_size": bsize}
json.dump(meta, open(os.path.join(FIX, "meta.json"), "w"), indent=1)
print("\nmeta:", json.dumps(meta))
print("fixtures written to", FIX)
