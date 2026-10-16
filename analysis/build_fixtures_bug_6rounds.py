# -*- coding: utf-8 -*-
"""为 bug_artillery_6rounds.lua 生成离线测试夹具。

数据来源(离线、可重复):
  analysis/ref/generated_entities.dl_bin  —— 游戏实体/组件明文镜像
  其中 WeaponDataComponentData 表(type hash 0x88E4DBB1)= LDLD + 索引 + 记录。

产出(analysis/fixtures/):
  ba6_table_real.bin      从真实镜像切出的**整块** WeaponDataComponentData 表(含索引+366条记录)
  ba6_rec_bile.bin        胆汁喷涌虫变体 CCAE5264ACD591B7 的真实 WeaponDataComponent 记录
  ba6_rec_nursing.bin     胆汁医护虫变体 CC7022FDD172089B 的真实记录
  ba6_rec_decoy.bin       干扰记录(真实记录, 但实体哈希不在目标内)
  ba6_rec_other.bin       nbr=1 的干扰记录
  ba6_table_block.bin     合成的整块表(索引+记录), 便于构造小场景
"""
import os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
FIX = os.path.join(HERE, "fixtures")
REF = os.path.join(HERE, "ref", "generated_entities.dl_bin")

TYPE_WDC = 0x88E4DBB1
IDX = 730          # ComponentIndexData 条数(typelib: 11680/16)
STRIDE = 1232      # WeaponDataComponent 大小(typelib)
REC_COUNT = 366

# 4 个目标实体(胆汁喷涌虫家族, 挂载同一条胆汁迫击炮武器 8536986223483970266)
TARGETS = {
    6927066342767148424:  "NursingSpewer2",
    14731312854664874139: "NursingSpewer",
    14748816422034837943: "BileSpewer",
    3939129929398354246:  "BileSpewer2",
}
BYTE_HASH = {   # 大端十六进制串(内存/文件里是小端 u64)
    "CCAE5264ACD591B7": 14748816422034837943,
    "36AA99CCE5E60146": 3939129929398354246,
    "CC7022FDD172089B": 14731312854664874139,
    "6021E22338333D88": 6927066342767148424,
}


def hex8be(u):
    return "".join("%02X" % ((u >> (8 * k)) & 0xFF) for k in range(7, -1, -1))


def le8(u):
    return struct.pack("<Q", u)


def main():
    os.makedirs(FIX, exist_ok=True)
    blob = open(REF, "rb").read()
    m = blob.find(b"LDLD" + struct.pack("<II", 1, TYPE_WDC))
    if m < 0:
        raise SystemExit("WeaponDataComponentData table not found in ref")
    ver, typ, size = struct.unpack_from("<III", blob, m + 4)
    assert typ == TYPE_WDC, hex(typ)
    block = blob[m: m + 24 + size]
    open(os.path.join(FIX, "ba6_table_real.bin"), "wb").write(block)
    print("ba6_table_real.bin   24+%d = %d bytes" % (size, len(block)))

    data = m + 24
    ent2idx = {}
    for i in range(IDX):
        h, idx, pad = struct.unpack_from("<QII", blob, data + i * 16)
        if h:
            ent2idx[h] = idx
    recbase = data + IDX * 16
    recs = {}
    for u, label in TARGETS.items():
        r = blob[recbase + ent2idx[u] * STRIDE: recbase + (ent2idx[u] + 1) * STRIDE]
        assert struct.unpack_from("<I", r, 140)[0] == 3, "expected nbr==3"
        recs[hex8be(u)] = r
    open(os.path.join(FIX, "ba6_rec_bile.bin"), "wb").write(recs["CCAE5264ACD591B7"])
    open(os.path.join(FIX, "ba6_rec_nursing.bin"), "wb").write(recs["CC7022FDD172089B"])

    # 干扰项: 真实记录, 但把身份字段改成"非目标"; 仍保留 nbr=3 的外观
    decoy = bytearray(recs["CCAE5264ACD591B7"])
    open(os.path.join(FIX, "ba6_rec_decoy.bin"), "wb").write(bytes(decoy))
    # nbr=1 的记录(不应被当成目标)
    other = bytearray(recs["CCAE5264ACD591B7"])
    struct.pack_into("<I", other, 140, 1)
    open(os.path.join(FIX, "ba6_rec_other.bin"), "wb").write(bytes(other))

    # ---- 合成整块表: 6 条记录, 64 条索引; 目标在 idx 0..3, 干扰实体在 idx 4 ----
    N_IDX = 64
    records = [recs["CCAE5264ACD591B7"], recs["36AA99CCE5E60146"],
               recs["CC7022FDD172089B"], recs["6021E22338333D88"],
               decoy, b"\x00" * STRIDE]
    tsize = N_IDX * 16 + len(records) * STRIDE
    head = b"LDLD" + struct.pack("<III", 1, TYPE_WDC, tsize) + b"\x00" * 8
    entries = bytearray(N_IDX * 16)
    def put(slot, enthash, recidx):
        struct.pack_into("<QII", entries, slot * 16, enthash, recidx, 0)
    put(3,  14748816422034837943, 0)   # BileSpewer
    put(7,  3939129929398354246,  1)   # BileSpewer2
    put(8,  14731312854664874139, 2)   # NursingSpewer
    put(21, 6927066342767148424,  3)   # NursingSpewer2
    put(5,  0x1111111111111111,   4)   # 干扰实体(不是目标)
    synth = head + bytes(entries) + b"".join(records)
    assert len(synth) == 24 + tsize, (len(synth), 24 + tsize)
    open(os.path.join(FIX, "ba6_table_block.bin"), "wb").write(synth)
    print("ba6_table_block.bin  %d bytes (idx=%d records=%d stride=%d)"
          % (len(synth), N_IDX, len(records), STRIDE))
    print("done")


if __name__ == "__main__":
    main()
