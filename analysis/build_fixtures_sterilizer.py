# -*- coding: utf-8 -*-
"""生成 sterilizer_gas_damage 的离线夹具(直接来自当前构建的真实明文镜像)。

产出 analysis/fixtures/:
  sz_table_block.bin   DamageSettings 真实整表(649 条 x 76B, 文件形态 LDLD 块)
  sz_spray.bin         第 29 条 = DamageInfoType_Spray_Chem_Gun  (TX-41 灭菌器)  <- 目标
  sz_drone.bin         第 30 条 = DamageInfoType_Drone_Chem_Gun  (敌方化学无人机) <- 必须不动
"""
import os, struct

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
DL = os.path.join(HERE, "..", "vendor", "filediver", "datalibrary",
                  "generated_damage_settings.dl_bin")

TYPE_DAMAGE_SETTINGS = 0xE0A72CF0      # djb2("DamageSettings")
STRIDE = 76

blob = open(DL, "rb").read()
# DamageSettings 实例 magic 在 +60; 数据区 = magic+40; size = 16 + count*stride
MAGIC = 60
size = struct.unpack_from("<I", blob, MAGIC + 12)[0]
count = (size - 16) // STRIDE
data_off = MAGIC + 40
records = blob[data_off:data_off + count * STRIDE]
assert len(records) == count * STRIDE, (len(records), count)

print("count=%d stride=%d size=%d recbytes=%d" % (count, STRIDE, size, len(records)))


def make_block(recs):
    """文件形态: +24 的 u64 = 相对偏移 16 -> 记录起点 = magic+40。"""
    n = len(recs)
    sz = 16 + n * STRIDE
    head = b"LDLD" + struct.pack("<III", 1, TYPE_DAMAGE_SETTINGS, sz) + b"\x00" * 8
    return head + struct.pack("<QQ", 16, n) + b"".join(recs)


spray = records[29 * STRIDE:30 * STRIDE]
drone = records[30 * STRIDE:31 * STRIDE]


def show(tag, r):
    u32 = lambda o: struct.unpack_from("<I", r, o)[0]
    print("  %-8s type=%-3d damage=%-3d durable=%-3d AP=%s demo=%d fs=%d fi=%d elem=%d SEval=(%.2f,%.2f)" % (
        tag, u32(0), u32(4), u32(8), [u32(12 + i * 4) for i in range(4)],
        u32(28), u32(32), u32(36), u32(40),
        struct.unpack_from("<f", r, 48)[0], struct.unpack_from("<f", r, 56)[0]))


show("spray", spray)
show("drone", drone)

os.makedirs(FIX, exist_ok=True)
open(os.path.join(FIX, "sz_table_block.bin"), "wb").write(make_block(
    [records[i * STRIDE:(i + 1) * STRIDE] for i in range(count)]))
open(os.path.join(FIX, "sz_spray.bin"), "wb").write(spray)
open(os.path.join(FIX, "sz_drone.bin"), "wb").write(drone)
print("wrote sz_table_block.bin / sz_spray.bin / sz_drone.bin")
