# -*- coding: utf-8 -*-
"""
vendor/restore.py —— 把 vendor 里的压缩副本还原成"可直接用"的目录。

为什么需要它: 迁移时为了体积, 可以把两个大目录删掉, 只带压缩包过来。
  * vendor/community/data/                        (~241 MB, 社区解好的 JSON)
      -> 可由 vendor/community-data.zip (7.8 MB) 还原
  * analysis/ref/generated_entities.dl_bin        (~46 MB, 游戏实体数据 blob)
      -> 可由 vendor/filediver/datalibrary/generated_entities.dl_bin.gz (0.9 MB) 还原

用法:
    python vendor/restore.py            # 缺什么补什么(已有则跳过)
    python vendor/restore.py --check    # 只检查, 不写
    python vendor/restore.py --force    # 强制重新解压
"""
import gzip
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))

COMMUNITY_ZIP = os.path.join(HERE, "community-data.zip")
COMMUNITY_DIR = os.path.join(HERE, "community", "data")
ENTITIES_GZ = os.path.join(HERE, "filediver", "datalibrary", "generated_entities.dl_bin.gz")
ENTITIES_BIN = os.path.join(ROOT, "analysis", "ref", "generated_entities.dl_bin")


def human(n):
    return "%.1f MB" % (n / 1048576.0)


def dir_size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def restore_community(force, check):
    if os.path.isdir(COMMUNITY_DIR) and os.listdir(COMMUNITY_DIR) and not force:
        print("  [skip] vendor/community/data/ 已存在 (%s)" % human(dir_size(COMMUNITY_DIR)))
        return True
    if not os.path.isfile(COMMUNITY_ZIP):
        print("  [FAIL] 找不到 %s" % COMMUNITY_ZIP)
        return False
    if check:
        print("  [need] vendor/community/data/ 缺失 (可用 %s 还原)" % os.path.basename(COMMUNITY_ZIP))
        return False
    print("  解压 community-data.zip -> vendor/community/data/ ...")
    os.makedirs(os.path.dirname(COMMUNITY_DIR), exist_ok=True)
    with zipfile.ZipFile(COMMUNITY_ZIP) as z:
        z.extractall(os.path.join(HERE, "community"))
    print("    done: %s" % human(dir_size(COMMUNITY_DIR)))
    return True


def restore_entities(force, check):
    if os.path.isfile(ENTITIES_BIN) and not force:
        print("  [skip] analysis/ref/generated_entities.dl_bin 已存在 (%s)"
              % human(os.path.getsize(ENTITIES_BIN)))
        return True
    if not os.path.isfile(ENTITIES_GZ):
        print("  [FAIL] 找不到 %s" % ENTITIES_GZ)
        return False
    if check:
        print("  [need] analysis/ref/generated_entities.dl_bin 缺失 (可用 %s 还原)"
              % os.path.basename(ENTITIES_GZ))
        return False
    print("  解压 generated_entities.dl_bin.gz -> analysis/ref/ ...")
    os.makedirs(os.path.dirname(ENTITIES_BIN), exist_ok=True)
    with gzip.open(ENTITIES_GZ, "rb") as fi, open(ENTITIES_BIN, "wb") as fo:
        shutil.copyfileobj(fi, fo, 1024 * 1024)
    print("    done: %s" % human(os.path.getsize(ENTITIES_BIN)))
    return True


def main():
    force = "--force" in sys.argv
    check = "--check" in sys.argv
    print("=" * 68)
    print("HD2 mod 工作区 vendor 还原  (ROOT=%s)" % ROOT)
    print("=" * 68)
    ok1 = restore_community(force, check)
    ok2 = restore_entities(force, check)
    print("-" * 68)
    if ok1 and ok2:
        print("全部就绪。")
        if not check:
            print("下一步自检: python analysis/_env.py")
        return 0
    print("有缺失。若上面提示 [need]，说明你为了省体积删过它们 —— 重跑本脚本(不带 --check)即可。")
    print("若提示 [FAIL] 找不到压缩包，说明连压缩包也没带过来，需要重新获取(见 HANDOVER.md 附录)。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
