# -*- coding: utf-8 -*-
"""打包 sterilizer_sfx (TX-41 灭菌器 开火音效替换, 含图标)。

实验性 mod: 在内存里找灭菌器武器组件的音效签名, 把 firing 的 audio_event_start
换成另一个更明显的 Wwise 事件。**不保证成功**(目标数据可能不驻留内存)。
"""
import json, os, sys, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402
_env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

NAME = "mods/hd2/sterilizer_sfx"
GUID = "43181292-a226-45de-9610-46a2de6cadfc"
DISPLAY = "TX-41 Sterilizer - Punchier Firing SFX"
ENTRY = os.path.join(ROOT, "src", "sterilizer_sfx.lua")
ICON = os.path.join(ROOT, "dist", "thumbnail_sterilizer_sfx.png")
OUT = os.path.join(ROOT, "dist", "Sterilizer-PunchierSFX.zip")

DESC = ("TX-41 Sterilizer: swaps its weak firing sound for a punchier spray SFX (default: the enemy chem "
        "drone's spray event 335829265; hot-swappable in sterilizer_sfx.cfg). "
        "EXPERIMENTAL: the vanilla firing event (1773671782) lives in the weapon component table, which the "
        "in-game memory scan showed is NOT resident in memory - so this mod instead searches raw process memory "
        "for the component's event-hash signature and rewrites the 4-byte event id only when several co-located "
        "hashes corroborate the hit. If nothing is found the STATUS file says so plainly. "
        "AMPLIFYING the original sound is NOT possible from memory - loudness lives inside the Wwise soundbank "
        "asset, so that requires the hd2-audio-modder + Wwise resource-replacement route instead. "
        "Only 4 bytes are ever written; client-side and purely local (SFX is not host-authoritative). "
        "Requires Bingus Shared Loader v15+ (API 1).")


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
