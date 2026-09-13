#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Фоны для демо-ролика WAD: 1920x1080, тёмные, «в тему» проекта.

Четыре варианта одним прогоном:
    grid      — сетка с мягким свечением по углам
    circuit   — дорожки платы с узлами
    contours  — топографические линии (плавные волны)
    particles — узлы и связи, как схема сети

Запуск:  python3 extras/design/tools/make_wallpapers.py
Результат: extras/design/wallpapers/wall-<имя>.png + contact-sheet.png
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1920, 1080
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'wallpapers')
OUT = os.path.normpath(OUT)

INK = (11, 11, 18)          # базовый фон
INK2 = (18, 18, 28)         # низ градиента
LINE = (86, 110, 170)       # линии
GLOW = (137, 180, 250)      # акцент


def base_gradient():
    """Вертикальный градиент плюс мягкие цветные пятна — «дышит», но не мешает тексту."""
    y = np.linspace(0, 1, H)[:, None]
    img = np.zeros((H, W, 3), dtype=np.float32)
    for c in range(3):
        img[:, :, c] = INK[c] * (1 - y) + INK2[c] * y

    # два пятна свечения: слева снизу и справа сверху
    yy, xx = np.mgrid[0:H, 0:W]
    for (cx, cy, r, strength, color) in [
        (W * 0.12, H * 0.88, W * 0.55, 0.30, np.array([40, 80, 160])),
        (W * 0.88, H * 0.10, W * 0.60, 0.22, np.array([30, 70, 120])),
        (W * 0.50, H * 0.55, W * 0.75, 0.16, np.array([20, 30, 60])),
    ]:
        d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / r) ** 2)
        falloff = np.clip(1 - d, 0, 1) ** 2.2 * strength
        img += falloff[:, :, None] * color[None, None, :]
    return np.clip(img, 0, 255).astype(np.uint8)


def draw_grid(img):
    d = ImageDraw.Draw(img, 'RGBA')
    step = 60
    for x in range(0, W + step, step):
        d.line([(x, 0), (x, H)], fill=LINE + (44,), width=1)
    for y in range(0, H + step, step):
        d.line([(0, y), (W, y)], fill=LINE + (44,), width=1)
    # редкие яркие линии — «акцентные»
    for x in (0, step * 8, step * 16, step * 24, W):
        d.line([(x, 0), (x, H)], fill=GLOW + (74,), width=1)
    for y in (0, step * 9, H):
        d.line([(0, y), (W, y)], fill=GLOW + (74,), width=1)
    # свечение на пересечениях акцентных линий
    glow = Image.new('RGB', (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for x in (0, step * 8, step * 16, step * 24, W):
        for y in (0, step * 9, H):
            gd.ellipse([x - 90, y - 90, x + 90, y + 90], fill=(60, 100, 190))
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    return Image.blend(img, Image.blend(img, glow, 0.16), 0.9)


def draw_circuit(img):
    d = ImageDraw.Draw(img, 'RGBA')
    rng = random.Random(7)
    step = 60
    drawn = set()
    for _ in range(240):
        # старт всегда на узле сетки, движение только под прямым углом
        x = rng.randrange(0, W, step)
        y = rng.randrange(0, H, step)
        for _ in range(rng.randint(2, 7)):
            dx, dy = rng.choice([(step, 0), (-step, 0), (0, step), (0, -step)])
            nx, ny = x + dx, y + dy
            if not (0 <= nx <= W and 0 <= ny <= H):
                break
            key = (min(x, nx), min(y, ny), abs(dx), abs(dy))
            if key in drawn:
                x, y = nx, ny
                continue
            drawn.add(key)
            a = rng.choice([30, 44, 60])
            d.line([(x, y), (nx, ny)], fill=LINE + (a,), width=2)
            if rng.random() < 0.10:
                d.line([(x, y), (nx, ny)], fill=GLOW + (70,), width=2)
            x, y = nx, ny
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=GLOW + (90,))
    glow = img.filter(ImageFilter.GaussianBlur(9))
    return Image.blend(img, glow, 0.35)


def draw_contours(img):
    """Плавные ленты: линии текут по низу и растворяются к верху."""
    d = ImageDraw.Draw(img, 'RGBA')
    for i in range(26):
        y0 = H * 0.42 + i * 26
        amp = 40 + (i % 6) * 26
        phase = i * 0.55
        k = 1.7e-3 + (i % 4) * 3e-4
        pts = []
        for x in range(-20, W + 40, 12):
            y = y0 + amp * math.sin(x * k + phase) + 0.35 * amp * math.sin(x * k * 2.7 + phase * 1.7)
            pts.append((x, y))
        fade = 0.35 + 0.65 * min(1.0, i / 12)          # верхние ленты бледнее
        d.line(pts, fill=LINE + (int(16 + 26 * fade),), width=2)
        if i % 7 == 0:
            d.line(pts, fill=GLOW + (54,), width=2)
    glow = img.filter(ImageFilter.GaussianBlur(8))
    return Image.blend(img, glow, 0.26)


def draw_particles(img):
    d = ImageDraw.Draw(img, 'RGBA')
    rng = random.Random(19)
    pts = [(rng.uniform(0, W), rng.uniform(0, H)) for _ in range(130)]
    maxd = 300
    for i, (x1, y1) in enumerate(pts):
        for x2, y2 in pts[i + 1:]:
            dist = math.hypot(x1 - x2, y1 - y2)
            if dist < maxd:
                a = int(84 * (1 - dist / maxd))
                d.line([(x1, y1), (x2, y2)], fill=LINE + (a,), width=1)
    for x, y in pts:
        r = rng.choice([2, 2, 3, 4])
        d.ellipse([x - r, y - r, x + r, y + r], fill=GLOW + (215,))
    glow = img.filter(ImageFilter.GaussianBlur(7))
    return Image.blend(img, glow, 0.45)


def add_vignette(img, center_dark=0.34):
    """Центр темнее: окно по центру должно читаться, фон — не спорить с ним."""
    yy, xx = np.mgrid[0:H, 0:W]
    cx, cy = W / 2, H / 2
    r = np.sqrt(((xx - cx) / (W * 0.62)) ** 2 + ((yy - cy) / (H * 0.62)) ** 2)
    dark = 1 - center_dark * np.clip(1 - r, 0, 1) ** 1.6   # центр темнее
    edge = 0.72 + 0.28 * np.clip(r, 0, 1)                  # края чуть гаснут
    mult = dark * edge
    arr = np.asarray(img, dtype=np.float32) * mult[:, :, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def main():
    os.makedirs(OUT, exist_ok=True)
    makers = [('grid', draw_grid), ('circuit', draw_circuit),
              ('contours', draw_contours), ('particles', draw_particles)]
    paths = []
    for name, fn in makers:
        img = Image.fromarray(base_gradient(), 'RGB')
        img = fn(img)
        img = add_vignette(img)
        p = os.path.join(OUT, f'wall-{name}.png')
        img.save(p)
        paths.append((name, img))
        print(f'  {p}')

    # контактный лист 2×2 с подписями — чтобы выбирать одним взглядом
    tw, th = 640, 360
    sheet = Image.new('RGB', (tw * 2 + 30, (th + 34) * 2 + 10), (10, 10, 16))
    d = ImageDraw.Draw(sheet)
    try:
        from PIL import ImageFont
        f = ImageFont.truetype('/tmp/fonts/inter/Inter-Medium.ttf', 20)
    except Exception:
        f = None
    for i, (name, img) in enumerate(paths):
        cx = (i % 2) * (tw + 20) + 10
        cy = (i // 2) * (th + 34) + 10
        sheet.paste(img.resize((tw, th), Image.LANCZOS), (cx, cy))
        d.text((cx + 4, cy + th + 6), name, fill=(205, 214, 244), font=f)
    sp = os.path.join(OUT, 'contact-sheet.png')
    sheet.save(sp)
    print(f'  {sp}')


if __name__ == '__main__':
    main()
