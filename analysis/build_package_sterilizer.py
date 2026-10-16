# -*- coding: utf-8 -*-
"""打包 sterilizer_gas_damage (TX-41 灭菌器 -> G-4 毒气榴弹伤害, 含图标)。

独立安装包: 装上后灭菌器每次命中的直接伤害 1 -> 3(= G-4 毒气榴弹的爆炸伤害)。
"""
import json, os, sys, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402
_env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

NAME = "mods/hd2/sterilizer_gas_damage"
GUID = "d369d2c7-93a1-455a-a61a-ba3c7d47e991"
DISPLAY = "TX-41 Sterilizer - G-4 Damage + 2x Gas"
ENTRY = os.path.join(ROOT, "src", "sterilizer_gas_damage.lua")
ICON = os.path.join(ROOT, "dist", "thumbnail_sterilizer.png")
OUT = os.path.join(ROOT, "dist", "Sterilizer-G4GasDamage.zip")

DESC = ("TX-41 Sterilizer: (1) raises the direct damage of its caustic spray to G-4 Gas Grenade level "
        "(damage 1 -> 3, the exact value the G-4 gas grenade's explosion uses), and "
        "(2) doubles the gas status buildup of its spray (0.5 -> 1.0, so targets get gassed twice as fast). "
        "STERILIZER-ONLY: the enemy chem drone fires from a separate record (Drone_Chem_Gun) and is left "
        "byte-for-byte untouched; the shared global gas effect is NOT modified. "
        "Armour penetration, demolition, knockback, the SE types, the spray visuals, the audio and the range "
        "are all untouched. Range note: the spray duration is produced by the muzzle VFX particle - there is no "
        "range field anywhere in the data tables for spray weapons, so it cannot be changed from memory. "
        "Gas DURATION lives on the shared global effect and cannot be changed for the sterilizer alone. "
        "Both numbers are tunable at runtime via sterilizer_gas_damage.cfg (damage=3 / gas=1.0), no repack, "
        "no restart. Client-side memory patch. Requires Bingus Shared Loader v15+ (API 1); run it on the HOST "
        "for the damage to apply.")


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
