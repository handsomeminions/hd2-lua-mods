# -*- coding: utf-8 -*-
"""
analysis/_env.py —— HD2 mod 工作区的路径解析层(可迁移)。

优先级: 环境变量  >  工作区内的 vendor/  >  旧机器的绝对路径(兼容)
所以在任何机器/任何盘符下, 只要 vendor/ 跟着工作区一起搬, 脚本就照常工作。

提供:
    ROOT           工作区根
    SKILL_DIR      技能目录(hd2-lua-mod)
    SKILL_TOOLS    技能里的 tools/ (hd2_archive.py / build_addon.py / inspect_patch.py)
    REF_DIR        反编译产物(typelib_all.json / dl_type_names.txt / dl_library.dl_typelib ...)
    ENTITIES_BIN   游戏实体数据 blob(46 MB, 在 analysis/ref/)
    FD_DIR         FileDiver 明文镜像(含 *.go 字段名源码 + enum/ + generated_*.dl_bin)
    COMMUNITY_DIR  社区解好的 JSON(settings/ entities/ enums/ components/ translations/)

命令行自检:  python analysis/_env.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VENDOR = os.path.join(ROOT, "vendor")

# 旧机器上的位置(仅作兜底; 新机器上 vendor/ 会命中)
_LEGACY = {
    "skill": r"C:/Users/rouge/.workbuddy/skills/hd2-lua-mod",
    "fd": r"C:/Users/rouge/AppData/Local/Temp/hd2mod/filediver/datalibrary",
    "community": r"C:/Users/rouge/AppData/Local/Temp/hd2mod/HelldiversData/data",
    "ref": r"C:/Users/rouge/AppData/Local/Temp/hd2mod/ref",
}


def _first_existing(*cands):
    for c in cands:
        if c and os.path.exists(c):
            return c
    return None


def _resolve(env_name, rel_under_vendor, legacy_key):
    v = os.environ.get(env_name)
    if v:
        return v
    return _first_existing(
        os.path.join(VENDOR, rel_under_vendor) if rel_under_vendor else None,
        _LEGACY.get(legacy_key),
    )


SKILL_DIR = _resolve("HD2_SKILL_DIR", "hd2-lua-mod", "skill")
SKILL_TOOLS = os.path.join(SKILL_DIR, "tools") if SKILL_DIR else None

REF_DIR = _resolve("HD2_REF_DIR", "ref", "ref")
FD_DIR = _resolve("HD2_FD_DIR", os.path.join("filediver", "datalibrary"), "fd")
COMMUNITY_DIR = _resolve("HD2_COMMUNITY_DIR", os.path.join("community", "data"), "community")

# 实体 blob: 工作区内 analysis/ref/ 是唯一权威副本(46 MB)
ENTITIES_BIN = os.path.join(HERE, "ref", "generated_entities.dl_bin")
PROJ_BIN = os.path.join(HERE, "ref", "generated_projectile_settings.dl_bin")


def require(path, what, hint=None):
    if path and os.path.exists(path):
        return path
    msg = "[_env] 找不到 %s:\n        %s" % (what, path)
    if hint:
        msg += "\n        " + hint
    msg += "\n        先跑:  python vendor/restore.py      (还原压缩副本)\n" \
           "        或设环境变量 HD2_SKILL_DIR / HD2_REF_DIR / HD2_FD_DIR / HD2_COMMUNITY_DIR"
    raise SystemExit(msg)


def add_skill_tools_to_path():
    p = require(SKILL_TOOLS, "技能 tools/ (hd2_archive.py / build_addon.py)")
    if p not in sys.path:
        sys.path.insert(0, p)
    return p


def community(*parts):
    require(COMMUNITY_DIR, "社区数据目录", "迁移时可能被删以省体积")
    return os.path.join(COMMUNITY_DIR, *parts)


def filediver(*parts):
    require(FD_DIR, "FileDiver 明文镜像目录")
    return os.path.join(FD_DIR, *parts)


def summary():
    def mark(p, need_dir=True):
        if not p:
            return "MISSING"
        ok = os.path.isdir(p) if need_dir else os.path.isfile(p)
        return ("OK   " if ok else "MISS ") + p

    return {
        "ROOT": ROOT,
        "SKILL_TOOLS": mark(SKILL_TOOLS),
        "REF_DIR": mark(REF_DIR),
        "FD_DIR": mark(FD_DIR),
        "COMMUNITY_DIR": mark(COMMUNITY_DIR),
        "ENTITIES_BIN": mark(ENTITIES_BIN, need_dir=False),
        "PROJ_BIN": mark(PROJ_BIN, need_dir=False),
    }


def main():
    print("=" * 72)
    print("HD2 mod 工作区路径自检")
    print("=" * 72)
    s = summary()
    for k, v in s.items():
        print("  %-14s %s" % (k, v))
    print("-" * 72)
    bad = [k for k, v in s.items() if v.startswith("MISS")]
    if bad:
        print("缺失: %s" % ", ".join(bad))
        print("跑  python vendor/restore.py  还原；仍缺则看 HANDOVER.md 附录(重新获取上游数据)。")
        return 1
    print("全部就绪。可以跑测试 / 打包了。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
