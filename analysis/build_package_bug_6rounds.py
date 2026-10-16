# -*- coding: utf-8 -*-
"""打包 bug_artillery_6rounds (胆汁喷涌虫 每梭 3 发 -> 6 发, 含图标)。

独立安装包: 只装它 => 6 枚原版胆汁迫击炮。
与 BileSpewer-RL77Airburst.zip 同时启用 => 6 枚空爆火箭弹。
"""
import json, os, sys, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402
_env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

NAME = "mods/hd2/bug_artillery_6rounds"
GUID = "fe9ac944-32e4-4388-99d3-c146780aeaed"
DISPLAY = "Bile Spewer - 6 Mortars Per Salvo"
ENTRY = os.path.join(ROOT, "src", "bug_artillery_6rounds.lua")
ICON = os.path.join(ROOT, "dist", "thumbnail_bug_6rounds.png")
OUT = os.path.join(ROOT, "dist", "BileSpewer-6Mortars.zip")

DESC = ("Bile Spewer (and Nursing Spewer) artillery salvos now throw 6 bile mortars instead of 3. "
        "ONLY the per-salvo round count changes: targeting, attack, flight speed/arc, the green bile "
        "blob shape, the audio and the impact explosion are byte-for-byte identical to vanilla. "
        "Combo: with the 'Bile Spewer Mortar - RL-77 Airburst' mod enabled, those 6 mortars each burst "
        "into an RL-77 airburst cluster; with it disabled they are 6 plain vanilla bile mortars. "
        "Client-side memory patch. Requires Bingus Shared Loader v15+ (API 1); run it on the HOST for "
        "the damage to apply.")


def main():
    body = BA.entry_source(NAME, open(ENTRY, "rb").read())
    archive = A.make_archive({NAME: A.envelope(body)})
    manifest = {
        "Version": 1,
        "Guid": str(uuid.UUID(GUID)),
        "Name": DISPLAY,
        "Description": DESC,
        "IconPath": "thumbnail.png",
        "Options": [{"Name": DISPLAY, "Description": DESC, "Include": ["Addon"], "Image": "thumbnail.png"}],
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
    BA.check_display_name(DISPLAY)
    print("Built", out)
    print("  archive bytes:", len(archive))
    print("  resource hash: 0x%016X" % A.resource_hash(NAME))
    print("  guid         :", manifest["Guid"])
    print("  name check   : OK (ASCII-safe)")


if __name__ == "__main__":
    main()
