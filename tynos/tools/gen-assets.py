#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TinyOS 品牌视觉素材生成器（可复现构建）

生成内容（与 live-build config 目录对应）：
  - 三套壁纸：深色 / 浅色 / 极光（1920x1080 PNG）
  - Plymouth 开机动画：品牌标识 + 进度条前景/背景

依赖：Pillow（Debian: apt install python3-pil）
随机种子固定，任何环境产出一致，因此仓库无需提交二进制素材。

用法：
    python3 gen-assets.py [--config-dir ../config] [--force]
"""
import argparse
import math
import os
import random
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("缺少 Pillow：请执行 apt install -y python3-pil")

W, H = 1920, 1080
LOGO_SIZE = 512

DARK_BG = (11, 15, 26)
LIGHT_BG = (250, 251, 253)
AURORA_BG = (8, 10, 34)
TEAL = (79, 209, 197)
VIOLET = (139, 124, 246)
BLUE = (94, 158, 255)


# --------------------------------------------------------------------------
# 基础绘制工具
# --------------------------------------------------------------------------
def linear_gradient(w, h, c1, c2, angle_deg, lut_n=2048):
    """按角度生成线性渐变（Pillow 无角度渐变，这里做投影计算）"""
    rad = math.radians(angle_deg)
    dx, dy = math.cos(rad), math.sin(rad)
    proj = [x * dx + y * dy for x, y in ((0, 0), (w, 0), (0, h), (w, h))]
    pmin, pmax = min(proj), max(proj)
    span = max(pmax - pmin, 1e-9)

    lut = []
    for i in range(lut_n):
        t = i / (lut_n - 1)
        lut.append((
            round(c1[0] + (c2[0] - c1[0]) * t),
            round(c1[1] + (c2[1] - c1[1]) * t),
            round(c1[2] + (c2[2] - c1[2]) * t),
            255,
        ))

    img = Image.new("RGBA", (w, h))
    px = img.load()
    last = lut_n - 1
    scale = last / span
    for y in range(h):
        base = y * dy - pmin
        for x in range(w):
            idx = int((x * dx + base) * scale)
            px[x, y] = lut[idx if 0 <= idx <= last else (0 if idx < 0 else last)]
    return img


def stroke(base, pts, width, color, alpha):
    """在独立图层上描一条宽线后做 alpha 合成（模拟发光叠加）"""
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).line(
        pts, fill=(color[0], color[1], color[2], alpha),
        width=int(width), joint="curve",
    )
    return Image.alpha_composite(base, layer)


def ribbon(base, color, thick, y_base, amp, phase, samples=30):
    """水平柔和光带：多遍叠加，越宽越淡"""
    for p in range(4):
        alpha = max(6, 12 - p * 3)
        pts = []
        for i in range(samples):
            t = i / (samples - 1)
            pts.append((t * W, y_base + math.sin(t * 2.4 + phase) * amp + t * (H * 0.08)))
        base = stroke(base, pts, thick + p * 34, color, alpha)
    return base


def edge_fade(base, bg, size, alpha=210):
    """四周以背景色渐隐，消除硬边"""
    w, h = base.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(size):
        a = int(alpha * (1 - i / size))
        col = (bg[0], bg[1], bg[2], a)
        d.line([(i, 0), (i, h)], fill=col)                 # 左
        d.line([(w - 1 - i, 0), (w - 1 - i, h)], fill=col)  # 右
        d.line([(0, i), (w, i)], fill=col)                  # 上
        d.line([(0, h - 1 - i), (w, h - 1 - i)], fill=col)  # 下
    return Image.alpha_composite(base, layer)


def specks(img, count, lo, hi, seed):
    """细颗粒 / 星点"""
    rnd = random.Random(seed)
    px = img.load()
    for _ in range(count):
        x = rnd.randrange(0, img.width)
        y = rnd.randrange(0, img.height)
        v = rnd.randint(lo, hi)
        px[x, y] = (v, v, v, 255)
    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.convert("RGB").save(path, "PNG", optimize=True)
    print("  [生成] %s" % path)


# --------------------------------------------------------------------------
# 三套壁纸
# --------------------------------------------------------------------------
def make_dark(path):
    img = linear_gradient(W, H, DARK_BG, (28, 40, 68), 60)
    img = ribbon(img, TEAL, 8, 300, 140, 0.0)
    img = ribbon(img, VIOLET, 7, 560, 120, 1.8)
    img = ribbon(img, BLUE, 6, 760, 90, 3.4)
    img = edge_fade(img, DARK_BG, 260)
    img = specks(img, 2200, 35, 85, 20261019)
    save(img, path)


def make_light(path):
    img = linear_gradient(W, H, LIGHT_BG, (232, 238, 247), 45)
    img = ribbon(img, (13, 148, 136), 10, 280, 150, 0.5)
    img = ribbon(img, (167, 139, 250), 9, 580, 130, 2.1)
    img = ribbon(img, (96, 165, 250), 7, 800, 100, 4.2)
    img = edge_fade(img, LIGHT_BG, 300)
    img = specks(img, 900, 205, 235, 20261019)
    save(img, path)


def make_aurora(path):
    img = linear_gradient(W, H, AURORA_BG, (34, 24, 80), 90)
    rnd = random.Random(11)
    palette = [(94, 230, 190), (124, 108, 255), (255, 120, 200), (110, 180, 255)]

    # 极光帷幕：垂直波浪笔触
    for b in range(16):
        col = palette[b % 4]
        x_base = 60 + b * 120 + rnd.randint(-40, 40)
        y_top = 30 + rnd.randint(-30, 60)
        y_bot = 560 + rnd.randint(-60, 160)
        for p in range(3):
            alpha = max(5, 13 - p * 4)
            pts = []
            for i in range(12):
                t = i / 11.0
                pts.append((x_base + math.sin(t * 3.0 + b) * 34, y_top + t * (y_bot - y_top)))
            img = stroke(img, pts, 14 + p * 30, col, alpha)

    # 星点
    d = ImageDraw.Draw(img)
    for _ in range(220):
        x, y = rnd.randrange(0, W), rnd.randrange(0, 600)
        a, s = rnd.randint(70, 220), rnd.randint(1, 2)
        d.ellipse([x, y, x + s, y + s], fill=(255, 255, 255, a))

    # 双层山脊剪影
    d.polygon([(0, H), (0, 800), (260, 690), (600, 810), (960, 640),
               (1300, 800), (1660, 700), (W, 820), (W, H)], fill=(5, 6, 20, 255))
    d.polygon([(0, H), (0, 930), (520, 830), (1150, 950), (W, 860), (W, H)],
              fill=(3, 4, 14, 255))

    img = edge_fade(img, AURORA_BG, 200)
    img = specks(img, 1800, 40, 90, 20261019)
    save(img, path)


# --------------------------------------------------------------------------
# Plymouth 标识与进度条
# --------------------------------------------------------------------------
def hexagon(cx, cy, rad):
    return [(cx + rad * math.cos(math.radians(60 * i - 30)),
             cy + rad * math.sin(math.radians(60 * i - 30))) for i in range(6)]


def make_logo(path):
    s = LOGO_SIZE
    img = Image.new("RGBA", (s, s), DARK_BG + (255,))
    cx = cy = s / 2
    rad = 186

    # 外发光（多遍递增宽度、低透明度）+ 主描边
    for p in range(3):
        layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(
            hexagon(cx, cy, rad),
            outline=(TEAL[0], TEAL[1], TEAL[2], 26 - p * 8),
            width=14 - p * 4,
        )
        img = Image.alpha_composite(img, layer)

    main = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(main).polygon(hexagon(cx, cy, rad),
                                 outline=(TEAL[0], TEAL[1], TEAL[2], 255), width=6)
    img = Image.alpha_composite(img, main)

    inner = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(inner).polygon(hexagon(cx, cy, rad - 30),
                                  outline=(VIOLET[0], VIOLET[1], VIOLET[2], 70), width=3)
    img = Image.alpha_composite(img, inner)

    # 字母 T（几何构图，不依赖字体），用渐变填充
    mask = Image.new("L", (s, s), 0)
    md = ImageDraw.Draw(mask)
    md.rectangle([0.300 * s, 0.340 * s, 0.700 * s, 0.420 * s], fill=255)
    md.rectangle([0.455 * s, 0.340 * s, 0.545 * s, 0.700 * s], fill=255)
    grad = linear_gradient(s, s, TEAL, VIOLET, 45)
    img = Image.composite(grad, img, mask)

    save(img, path)


def make_bar(path, color, size=(100, 6)):
    img = Image.new("RGBA", size, color + (255,))
    save(img, path)


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="生成 TinyOS 品牌视觉素材")
    ap.add_argument("--config-dir", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "config"),
        help="live-build config 目录（素材写入其 includes.chroot 下）")
    ap.add_argument("--force", action="store_true", help="已存在也重新生成")
    args = ap.parse_args()

    root = os.path.abspath(args.config_dir)
    inc = os.path.join(root, "includes.chroot", "usr", "share")
    targets = [
        (os.path.join(inc, "wallpapers/TinyOS-Dark/contents/images/1920x1080.png"), make_dark),
        (os.path.join(inc, "wallpapers/TinyOS-Light/contents/images/1920x1080.png"), make_light),
        (os.path.join(inc, "wallpapers/TinyOS-Aurora/contents/images/1920x1080.png"), make_aurora),
        (os.path.join(inc, "plymouth/themes/tinyos/logo.png"), make_logo),
        (os.path.join(inc, "plymouth/themes/tinyos/bar_fg.png"),
         lambda p: make_bar(p, TEAL)),
        (os.path.join(inc, "plymouth/themes/tinyos/bar_bg.png"),
         lambda p: make_bar(p, (34, 40, 56))),
    ]

    print("[TinyOS] 生成品牌视觉素材 -> %s" % inc)
    for path, fn in targets:
        if os.path.exists(path) and not args.force:
            print("  [跳过] %s" % path)
            continue
        fn(path)
    print("[TinyOS] 视觉素材生成完成")


if __name__ == "__main__":
    main()
