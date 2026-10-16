# -*- coding: utf-8 -*-
"""打包 mortar_sentry_napalm (A/M-12 迫击哨戒炮 -> 落地炸成轨道凝固汽油弹效果, 含图标)."""
import json, os, sys, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402
_env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

NAME = "mods/hd2/mortar_sentry_napalm"
GUID = "0208faf4-f89b-416e-8806-2f242d394ef2"
DISPLAY = "Mortar Sentry - Napalm Impact"
ENTRY = os.path.join(ROOT, "src", "mortar_sentry_napalm.lua")
ICON = os.path.join(ROOT, "dist", "thumbnail_mortar_napalm.png")
OUT = os.path.join(ROOT, "dist", "MortarSentry-NapalmImpact.zip")

DESC = ("A/M-12 Mortar Sentry shells now burst with the Orbital Napalm Barrage's single-bomb "
        "impact effect (napalm blast + burning fire area). Targeting, flight arc, speed, model "
        "and trail all stay vanilla. Client-side memory patch. Requires Bingus Shared Loader "
        "v15+ (API 1); run it on the HOST for the damage to apply.")


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
