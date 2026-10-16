# -*- coding: utf-8 -*-
"""用 skill 的构建工具打包, 额外加入 thumbnail.png 图标(Arsenal 卡片显示用).

用法: python build_package.py
"""
import json
import os
import re
import sys
import uuid
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402  (路径解析: vendor/ 或环境变量)
SKILL_TOOLS = _env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

NAME = "mods/hd2/orbital_120mm_500kg"
GUID = "a914455b-75f8-4df8-9472-e0fc0bf64464"
DISPLAY = "Orbital 120mm HE Barrage - Eagle 500kg"
ENTRY = os.path.join(ROOT, "src", "orbital_120mm_500kg.lua")
ICON = os.path.join(ROOT, "dist", "thumbnail.png")
OUT = os.path.join(ROOT, "dist", "Orbital120mm-Eagle500kg.zip")

DESC = ("Orbital 120MM HE Barrage shells keep their vanilla 120mm trajectory, flight speed "
        "and model, but now detonate with the Eagle 500kg bomb explosion (sound, damage, "
        "radius and VFX all become 500kg). Client-side memory patch. Requires Bingus "
        "Shared Loader v15+ (API 1); run it on the HOST for the damage to actually apply.")


def main():
    body = BA.entry_source(NAME, open(ENTRY, "rb").read())
    resources = {NAME: A.envelope(body)}
    archive = A.make_archive(resources)

    manifest = {
        "Version": 1,
        "Guid": str(uuid.UUID(GUID)),
        "Name": DISPLAY,
        "Description": DESC,
        "IconPath": "thumbnail.png",
        "Options": [{
            "Name": DISPLAY,
            "Description": DESC,
            "Include": ["Addon"],
            "Image": "thumbnail.png",
        }],
    }

    files = {
        "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        "thumbnail.png": open(ICON, "rb").read(),
        "Addon/" + A.ARCHIVE_NAME: archive,
        "Addon/" + A.ARCHIVE_NAME + ".stream": b"",
        "Addon/" + A.ARCHIVE_NAME + ".gpu_resources": b"",
    }

    out = os.path.abspath(OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for path, content in sorted(files.items()):
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, content)

    print("Built", out)
    print("  archive bytes:", len(archive))
    print("  icon bytes   :", len(files["thumbnail.png"]))
    print("  resource hash: 0x%016X" % A.resource_hash(NAME))
    print("  guid         :", manifest["Guid"])


if __name__ == "__main__":
    main()
