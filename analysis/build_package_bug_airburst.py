# -*- coding: utf-8 -*-
"""打包 bug_artillery_airburst (胆汁迫击炮 -> RL-77 空爆火箭, 含图标)."""
import json, os, sys, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402
_env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

NAME = "mods/hd2/bug_artillery_airburst"
GUID = "8cf04434-8f4e-43d5-8493-22aaace62e20"
DISPLAY = "Bile Spewer Mortar - RL-77 Airburst"
ENTRY = os.path.join(ROOT, "src", "bug_artillery_airburst.lua")
ICON = os.path.join(ROOT, "dist", "thumbnail_bug_airburst.png")
OUT = os.path.join(ROOT, "dist", "BileSpewer-RL77Airburst.zip")

DESC = ("Bile Spewer bile mortars keep their ORIGINAL look (the green bile blob: original model "
        "and flight particles) and their ORIGINAL flight (same attack, speed and arc), but now "
        "burst into the RL-77 airburst cluster on impact: the 25 bomblets carry the original "
        "airburst-rocket physics, arcing out with random spread, bouncing off terrain and "
        "exploding irregularly, exactly like the real RL-77. One mortar = one cluster burst. "
        "Client-side memory patch. Requires Bingus Shared Loader v15+ (API 1); run it on the "
        "HOST for the damage to apply.")


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
    print("Built", out)
    print("  archive bytes:", len(archive))
    print("  resource hash: 0x%016X" % A.resource_hash(NAME))
    print("  guid         :", manifest["Guid"])
    BA.check_display_name(DISPLAY)
    print("  name check   : OK (ASCII-safe)")


if __name__ == "__main__":
    main()
