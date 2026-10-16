# -*- coding: utf-8 -*-
"""
make_icon.py —— 把图像生成出来的方形图标处理成 Arsenal 用的 1024x1024 缩略图。

为什么要处理: 图像生成工具会在右下角打一个 "AI生成 / WorkBuddy" 水印。
本脚本用**水印左侧同样大小的区域**覆盖它(图标底部是黄黑警示条纹, 平移一段仍能接上),
所以右下角看起来是连续的条纹, 而不是被涂白。

用法:
    python analysis/make_icon.py --src "生成的图.png" --out dist/thumbnail_xxx.png
    python analysis/make_icon.py --src "生成的图.png" --out dist/thumbnail_xxx.png --shift 200

依赖: Pillow (装在隔离 venv 里, 见 HANDOVER.md)
    C:/Users/<你>/.workbuddy/binaries/python/envs/default/Scripts/python.exe analysis/make_icon.py ...
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# 水印区域(在 1024x1024 图上): 右下角
DEFAULT_BOX = (826, 950)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="图像生成出来的原始 png")
    ap.add_argument("--out", required=True, help="输出 png(建议放 dist/ 下)")
    ap.add_argument("--box", default="826,950", help="水印左上角坐标 x,y (默认 826,950)")
    ap.add_argument("--shift", type=int, default=200, help="从左侧平移多少像素来覆盖(默认 200)")
    args = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("[make_icon] 需要 Pillow。装在隔离 venv 里:\n"
              "  <managed-python> -m venv <managed-python>/envs/default\n"
              "  <venv>/Scripts/pip install Pillow", file=sys.stderr)
        return 2

    src = os.path.abspath(args.src)
    out = os.path.abspath(args.out)
    if not os.path.isfile(src):
        print("[make_icon] 找不到源图: %s" % src, file=sys.stderr)
        return 2

    x0, y0 = [int(v) for v in args.box.split(",")]
    img = Image.open(src).convert("RGB")
    w, h = img.size
    print("src %dx%d -> %s" % (w, h, out))
    patch = img.crop((x0 - args.shift, y0, w - args.shift, h))
    img.paste(patch, (x0, y0))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print("saved %s (%dx%d)" % (out, img.size[0], img.size[1]))
    print("打包时把 manifest 的 IconPath / Option.Image 指到它 (见 analysis/build_package_*.py)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
