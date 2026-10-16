# -*- coding: utf-8 -*-
"""打包 "胆汁喷涌虫 齐射档位选择" 合集 mod (Arsenal 多选项).

一个 ZIP, 两个可自由勾选的选项(在管理器里是同一 mod 下的两个开关):
  - FourRounds -> mods/hd2/bug_artillery_4rounds  (每发 2 枚 => 一次齐射 4 团)
  - SixRounds  -> mods/hd2/bug_artillery_6rounds  (每发 3 枚 => 一次齐射 6 团)

两个 addon 在合集里各自是**独立资源**(各自的 SINGLETON / 各自的 cfg), 与单独安装
BileSpewer-4Mortars.zip / BileSpewer-6Mortars.zip 时**完全一致**。
两者改的是同一条射弹记录的同一个字段, 所以: 只勾一个 = 该档位生效; 两个都勾 =
4 团版源码会自动让位给 6 团版(STATUS 首行 SKIPPED), 结果是 6 团。建议二选一。
"""
import json, os, sys, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import _env                      # noqa: E402
_env.add_skill_tools_to_path()
import hd2_archive as A          # noqa: E402
import build_addon as BA         # noqa: E402

GUID = "01845481-055a-41a8-8d63-b26764e74933"
DISPLAY = "Bile Spewer - Salvo Choice (4 or 6 Mortars)"
OUT = os.path.join(ROOT, "dist", "BileSpewer-Salvo-Choice.zip")

ICON = os.path.join(ROOT, "dist", "thumbnail_bug_salvo.png")

# (目录名, 选项显示名, 资源名, 源码, 选项图片, 说明)
CHOICES = [
    ("FourRounds", "4 Mortars Per Salvo",
     "mods/hd2/bug_artillery_4rounds",
     os.path.join(ROOT, "src", "bug_artillery_4rounds.lua"),
     os.path.join(ROOT, "dist", "thumbnail_bug_4rounds.png"),
     "Bile Spewer artillery throws 4 bile mortars per salvo (2 per shot x 2 shots, "
     "2 directions). Targeting, attack, flight arc/speed, the green bile blob shape, "
     "the audio and the impact explosion are byte-for-byte vanilla. Recommended if you "
     "want the extra mortars to stay visually separate."),
    ("SixRounds", "6 Mortars Per Salvo",
     "mods/hd2/bug_artillery_6rounds",
     os.path.join(ROOT, "src", "bug_artillery_6rounds.lua"),
     os.path.join(ROOT, "dist", "thumbnail_bug_6rounds.png"),
     "Bile Spewer artillery throws 6 bile mortars per salvo (3 per shot x 2 shots, "
     "2 directions). Same untouched aspects as the 4-mortar option. Checked by default "
     "if you liked the original 6-mortar version."),
]

DESC = ("Bile Spewer (and Nursing Spewer) artillery salvo - pick your round count. "
        "Enable ONE option below: '4 Mortars' (2 per shot) or '6 Mortars' (3 per shot). "
        "Both only change the per-shot projectile count of the vanilla bile mortar; "
        "targeting, attack, flight speed/arc, the green bile blob shape, the audio and the "
        "impact explosion stay vanilla. Combos with the 'Bile Spewer Mortar - RL-77 Airburst' "
        "mod: every bile mortar of the chosen option bursts into an RL-77 airburst cluster. "
        "If you tick BOTH options the 4-mortar addon auto-yields to the 6-mortar one "
        "(client-side memory patch; run it on the HOST for the damage to apply). "
        "Requires Bingus Shared Loader v15+ (API 1).")


def main():
    files = {}
    built = []

    # 顶层图标 (合集)
    files["manifest.json"] = None  # filled below
    files["thumbnail.png"] = open(ICON, "rb").read()

    options = []
    for folder, title, rname, srcpath, imgpath, desc in CHOICES:
        body = BA.entry_source(rname, open(srcpath, "rb").read())
        archive = A.make_archive({rname: A.envelope(body)})
        files[folder + "/" + A.ARCHIVE_NAME] = archive
        files[folder + "/" + A.ARCHIVE_NAME + ".stream"] = b""
        files[folder + "/" + A.ARCHIVE_NAME + ".gpu_resources"] = b""
        # 选项自己的小图标 (顶层)
        files[folder + ".png"] = open(imgpath, "rb").read()
        options.append({
            "Name": title,
            "Description": desc,
            "Image": folder + ".png",
            "Include": [folder],
        })
        built.append((folder, rname, len(archive), A.resource_hash(rname)))

    manifest = {
        "Version": 1,
        "Guid": str(uuid.UUID(GUID)),
        "Name": DISPLAY,
        "Description": DESC,
        "IconPath": "thumbnail.png",
        "Options": options,
    }
    files["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()

    out = os.path.abspath(OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for path, content in sorted(files.items()):
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, content)

    BA.check_display_name(DISPLAY)
    for c in CHOICES:
        BA.check_display_name(c[1])
    print("Built", out)
    for folder, rname, n, h in built:
        print("  [%s] %s" % (folder, rname))
        print("      archive bytes: %d   resource hash: 0x%016X" % (n, h))
    print("  guid         :", manifest["Guid"])
    print("  display name : %s  (ASCII-safe)" % DISPLAY)
    print("  options      :", [o["Name"] for o in options])


if __name__ == "__main__":
    main()
