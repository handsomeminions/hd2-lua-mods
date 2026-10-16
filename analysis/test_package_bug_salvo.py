# -*- coding: utf-8 -*-
"""test_package_bug_salvo.py —— 合集包(Arsenal 多选项) BileSpewer-Salvo-Choice.zip 的离线校验

校验三层:
  A. 包结构 + manifest V1 规范 (对照 HD2 Modding Wiki 的 Options/Include 语义)
  B. 两个选项各自的 .patch_0 里, 发布正文与 src/*.lua **逐字节一致**
  C. 双选共存: 把**两个**发布正文加载进同一份 Lua 状态 (模拟用户在管理器里两个都勾选),
     两种加载顺序各跑一遍 ——
        * 4 团版必须自动让位 (STATUS 首行 SKIPPED), 不再扫描/写入;
        * 6 团版必须正常生效 (num_projectiles 1->3);
        * 射弹记录最终 = 6 团, 且除 +28 外逐字节保持原版;
        * update 钩子链完好。
"""
import json, os, re, struct, sys, uuid, zipfile
from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "vendor", "hd2-lua-mod", "tools"))
import hd2_archive as A          # noqa: E402

ZIP = os.environ.get("HD2_SALVO_ZIP") or os.path.join(ROOT, "dist", "BileSpewer-Salvo-Choice.zip")
ARCHIVE = A.ARCHIVE_NAME                       # 9ba626afa44a3aa3.patch_0

NAME4 = "mods/hd2/bug_artillery_4rounds"
NAME6 = "mods/hd2/bug_artillery_6rounds"
GUID = "01845481-055a-41a8-8d63-b26764e74933"
FOLDER4, FOLDER6 = "FourRounds", "SixRounds"

SRC4 = open(os.path.join(ROOT, "src", "bug_artillery_4rounds.lua"), "rb").read()
SRC6 = open(os.path.join(ROOT, "src", "bug_artillery_6rounds.lua"), "rb").read()

FIX = os.path.join(HERE, "fixtures")
HARNESS_SRC = open(os.path.join(HERE, "harness.lua"), "r", encoding="utf-8").read()
LOGDIR = (os.getenv("LOCALAPPDATA") or "") + "/CowboyBingus/Helldivers2/Logs/"

# 与 test_bug_4rounds / combo 一致的夹具
TGT = open(os.path.join(FIX, "ba_target.bin"), "rb").read()
BLOCK = open(os.path.join(FIX, "ba_table_block.bin"), "rb").read()
STRIDE = 272
TGT_IDX = 29
REGION = 0x40000
BASE, BOFF = 0x20000000, 0x1000
OFF_NUM_PROJ = 28
ILLEGAL = set('\\/:*?"<>|')


# ---------------------------------------------------------------------------
# A. 包结构 + manifest
# ---------------------------------------------------------------------------
def check_package(fails):
    c = lambda cond, msg: fails.append(msg) if not cond else None
    z = zipfile.ZipFile(ZIP)
    names = z.namelist()

    c("manifest.json" in names, "manifest.json 在包根")
    m = json.loads(z.read("manifest.json").decode("utf-8"))

    c(m.get("Version") == 1, "manifest Version == 1 (got %r)" % m.get("Version"))
    try:
        c(str(uuid.UUID(m["Guid"])) == GUID, "Guid 匹配 (got %r)" % m.get("Guid"))
    except Exception as e:
        c(False, "Guid 非法: %r (%s)" % (m.get("Guid"), e))
    nm = m.get("Name") or ""
    c(nm and nm.isascii(), "Name 非空且 ASCII (got %r)" % nm)
    c(not (ILLEGAL & set(nm)), "Name 不含 Windows 非法字符")
    c(bool(m.get("Description")), "Description 非空")
    c(m.get("IconPath") in names, "IconPath %r 在包内" % m.get("IconPath"))

    opts = m.get("Options")
    c(isinstance(opts, list) and len(opts) == 2, "Options 是 2 项的列表 (got %r)" % (type(opts).__name__))
    if not (isinstance(opts, list) and len(opts) == 2):
        return None
    seen = {}
    for o in opts:
        onm = o.get("Name") or ""
        c(bool(onm), "option 有 Name")
        c(onm.isascii() and not (ILLEGAL & set(onm)), "option Name 合法 (%r)" % onm)
        c(bool(o.get("Description")), "option %r 有 Description" % onm)
        inc = o.get("Include")
        c(isinstance(inc, list) and len(inc) == 1, "option %r Include 是 1 项列表 (%r)" % (onm, inc))
        if isinstance(inc, list) and inc:
            folder = inc[0]
            c(folder in (FOLDER4, FOLDER6), "option Include 目录名合法 (%r)" % folder)
            c(folder + "/" + ARCHIVE in names, "%s/%s 存在" % (folder, ARCHIVE))
            img = o.get("Image")
            c(img in names, "option %r Image %r 在包内" % (onm, img))
            seen[folder] = o
    c(set(seen) == {FOLDER4, FOLDER6}, "两个选项目录齐全 (%r)" % sorted(seen))

    # 两个 patch 必须内容不同 (各自独立资源)
    if FOLDER4 + "/" + ARCHIVE in names and FOLDER6 + "/" + ARCHIVE in names:
        b4 = z.read(FOLDER4 + "/" + ARCHIVE)
        b6 = z.read(FOLDER6 + "/" + ARCHIVE)
        c(b4 != b6, "两个选项的 patch 内容不同")
        c(z.read(FOLDER4 + "/" + ARCHIVE + ".stream") == b"", "FourRounds .stream 空伴生文件")
        c(z.read(FOLDER6 + "/" + ARCHIVE + ".gpu_resources") == b"", "SixRounds .gpu_resources 空伴生文件")

    # B. 发布正文 == 源码
    def body_of(entry_name, want_hash):
        data = z.read(entry_name)
        p = A.parse(data)
        for e in p["entries"]:
            if e["name"] == want_hash:
                return e["body"], p["count"]
        return None, p["count"]

    b4, n4 = body_of(FOLDER4 + "/" + ARCHIVE, A.resource_hash(NAME4))
    b6, n6 = body_of(FOLDER6 + "/" + ARCHIVE, A.resource_hash(NAME6))
    c(b4 is not None, "FourRounds patch 含资源 %s" % NAME4)
    c(b6 is not None, "SixRounds patch 含资源 %s" % NAME6)
    c(b4 == SRC4, "FourRounds 发布正文 == 源码")
    c(b6 == SRC6, "SixRounds 发布正文 == 源码")
    c(n4 == 1 and n6 == 1, "每个 patch 只含 1 个资源 (got %d/%d)" % (n4, n6))
    return (b4, b6)


# ---------------------------------------------------------------------------
# C. 双选共存 (同一 Lua 状态)
# ---------------------------------------------------------------------------
def _add_region(L, base, size, data=b"", prot=0x04):
    body = (data + b"\x00" * size)[:size]
    L.globals().HARNESS.add_region_hex(base, size, body.hex().upper(), prot)


def _abs_bytes(L, addr, n):
    h = L.globals().HARNESS.abs_hex(addr, n)
    return bytes.fromhex(h) if h else None


def combo_case(order, pub4, pub6):
    fails = []
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute(HARNESS_SRC)
    L.execute("HARNESS.reset()")
    L.execute("HARNESS.set_loader(1, 19)")
    _add_region(L, BASE, REGION, b"\x00" * BOFF + BLOCK)
    L.execute("HARNESS.install_update_hook()")
    L.globals().PUB4 = pub4.decode("utf-8")
    L.globals().PUB6 = pub6.decode("utf-8")
    if order == "four_first":
        L.execute("HARNESS.run_addon(PUB4)")
        L.execute("HARNESS.run_addon(PUB6)")
    else:
        L.execute("HARNESS.run_addon(PUB6)")
        L.execute("HARNESS.run_addon(PUB4)")
    L.execute("HARNESS.frames(1500)")   # 含多个 5s 复查周期

    addr = BASE + BOFF + 40 + TGT_IDX * STRIDE
    got = _abs_bytes(L, addr, STRIDE)
    ok = True
    if got != TGT[:OFF_NUM_PROJ] + struct.pack("<I", 3) + TGT[OFF_NUM_PROJ + 4:]:
        fails.append("%s: 最终记录 != 6 团 (%r)" % (order, got[:34].hex() if got else None))
        ok = False
    if not (got and got[OFF_NUM_PROJ:OFF_NUM_PROJ + 4] == b"\x03\x00\x00\x00"):
        fails.append("%s: num_projectiles != 3" % order)

    s4 = L.globals().HARNESS.get_file(LOGDIR + "bug_artillery_4rounds_STATUS.txt") or ""
    s6 = L.globals().HARNESS.get_file(LOGDIR + "bug_artillery_6rounds_STATUS.txt") or ""
    h4 = s4.split("\n")[0] if s4 else ""
    h6 = s6.split("\n")[0] if s6 else ""
    if not h4.startswith("SKIPPED"):
        fails.append("%s: 4 团版未让位 (首行 %r)" % (order, h4))
    if not h6.startswith("OK - patch applied"):
        fails.append("%s: 6 团版未生效 (首行 %r)" % (order, h6))
    if not re.search(r"projectiles_per_shot=1->3", s6):
        fails.append("%s: 6 团版 STATUS 缺 projectiles_per_shot=1->3" % order)

    calls = L.eval("HARNESS.update_original_calls")
    if calls != 1500:
        fails.append("%s: update 钩子链断裂 (%s != 1500)" % (order, calls))

    # 再跑 3 个复查周期, 确认没有"让位后又被拉回来"的抖动
    L.execute("HARNESS.frames(1800)")
    got2 = _abs_bytes(L, addr, STRIDE)
    if got2 != got:
        fails.append("%s: 复查周期后记录发生漂移" % order)
    return ok, fails


# ---------------------------------------------------------------------------
def main():
    if not os.path.exists(ZIP):
        print("缺少安装包: %s" % ZIP)
        return 1
    all_fails = []
    bodies = check_package(all_fails)
    print("[A/B] 包结构 + manifest + 发布正文: %s" % ("通过" if not all_fails else "失败"))
    for f in all_fails:
        print("   - %s" % f)

    if bodies and bodies[0] and bodies[1]:
        for order in ("four_first", "six_first"):
            ok, fails = combo_case(order, bodies[0], bodies[1])
            print("[C] 双选共存(%s): %s" % (order, "通过" if ok and not fails else "失败"))
            for f in fails:
                print("   - %s" % f)
            all_fails += fails
    else:
        all_fails.append("无法取到发布正文, 跳过共存测试")

    print("=" * 60)
    if all_fails:
        print("合集包校验: 失败 %d" % len(all_fails))
        return 1
    print("合集包校验: 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
