#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Три дизайна интерфейса WAD + стартовое окно и окно «Проект на GitHub».

Каждый дизайн — это палитра, фон и раскладка экрана установки. Стартовое окно и окно
GitHub рисуются одним и тем же кодом, но в стиле выбранного дизайна, поэтому все
три видео показывают полный путь в своём оформлении.

    python3 extras/design/tools/make_designs.py --list
    python3 extras/design/tools/make_designs.py --design ring --scene start --still 2.0
    python3 extras/design/tools/make_designs.py --design day --video

Результат: extras/design/demo/design-<имя>.mp4 (или .png для отдельного кадра).
"""
import argparse
import io
import math
import os
import subprocess
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ----------------------------------------------------------------------------- размеры
W, H = 1920, 1080
CARD_W, CARD_H = 1180, 700
CARD_X, CARD_Y = (W - CARD_W) // 2, (H - CARD_H) // 2
PAD = 48
INNER = CARD_W - PAD
FPS = 30

# монтаж: [начальное окно] → [установка] → [GitHub]
# монтаж: стартовое окно → установка (последняя задача заканчивается на 22-й секунде
# экранного времени) → окно проекта на GitHub → затемнение
T_START, T_INSTALL, T_GITHUB, T_END = 4.5, 27.0, 28.5, 34.0

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN_DIR = os.path.normpath(os.path.join(HERE, '..'))
OUT_DIR = os.path.join(DESIGN_DIR, 'demo')
FONT_DIR = os.path.expanduser('~/.cache/fonts')

# ----------------------------------------------------------------------------- данные
# Реальные данные репозитория, полученные с GitHub 11 сентября 2026.
# Если цифры изменятся — их надо обновить здесь, а не выдумывать.
REPO = {
    'full': 'AgentSharik/WAD',
    'url': 'https://github.com/AgentSharik/WAD',
    'desc': 'Автоматическая установка и пост-установка Windows: один запуск и готовая система.',
    'stars': 0, 'forks': 0, 'size_kb': 671, 'lang': 'PowerShell',
    'pushed': '10 сентября 2026', 'license': 'не выбрана', 'public': True,
    'topics': ['windows', 'powershell', 'automation', 'unattended-install',
               'post-install', 'windows-deployment', 'sysadmin', 'setup-scripts'],
    'fetched': '11 сентября 2026',
}

TASKS = [
    dict(name='Первоначальная настройка ОС', t0=0.8, t1=3.2, start='12:41:03', end='12:47:21', result='ok'),
    dict(name='Оптимизация и настройка ОС', t0=3.2, t1=5.6, start='12:47:21', end='12:55:02', result='ok'),
    dict(name='Установка системных компонентов', t0=5.6, t1=11.0, start='12:55:02', end='13:07:44', result='ok'),
    dict(name='Установка софта', t0=11.0, t1=17.4, start='13:07:44', end='13:21:10', result='warn'),
    dict(name='Установка и активация Microsoft Office', t0=18.2, t1=22.0, start='13:21:40', end='13:34:55',
         result='ok'),
]
WARN_TITLE = 'Установка софта завершилась с замечаниями: 2 программы не установились'
WARN_LINES = 'ShareX — установщик вернул код 1603 · K-Lite Codec Pack — ссылка не отвечает'

PROGRAMS = ['Google Chrome', 'Steam', 'WinRAR', 'qBittorrent', 'ShareX', 'K-Lite Codec Pack',
            'Visual C++ 2015-2022', '.NET 8.0', 'Office LTSC 2024']
SETTINGS = ['Удаление 33 встроенных приложений', 'Полное удаление OneDrive',
            'Классический просмотр фотографий', 'Файл подкачки по объёму ОЗУ',
            'Настройки браузера, меню и панели задач']


# ----------------------------------------------------------------------------- шрифты
NEED_FONTS = {
    'Inter-Regular.ttf': 'https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip',
    'JetBrainsMono-Regular.ttf': 'https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip',
}
FONT_FILES = {}

def ensure_fonts():
    """Шрифты лежат в ~/.cache (не в репозитории): Inter — текстовый, JetBrains Mono — для терминала."""
    os.makedirs(FONT_DIR, exist_ok=True)
    if not os.path.exists(os.path.join(FONT_DIR, 'Inter-Regular.ttf')):
        _fetch_fonts()
    for key, name in [('regular', 'Inter-Regular.ttf'), ('medium', 'Inter-Medium.ttf'),
                      ('semibold', 'Inter-SemiBold.ttf'), ('bold', 'Inter-Bold.ttf'),
                      ('extrabold', 'Inter-ExtraBold.ttf'),
                      ('mono', 'JetBrainsMono-Regular.ttf'), ('mono-med', 'JetBrainsMono-Medium.ttf'),
                      ('mono-bold', 'JetBrainsMono-Bold.ttf'), ('mono-semi', 'JetBrainsMono-SemiBold.ttf')]:
        path = os.path.join(FONT_DIR, name)
        if not os.path.exists(path):
            # запасной вариант: Inter для всего, если моноширинный не скачался
            path = os.path.join(FONT_DIR, 'Inter-Regular.ttf' if key == 'regular' else 'Inter-Medium.ttf')
        FONT_FILES[key] = path


def _fetch_fonts():
    import zipfile
    print('  шрифты отсутствуют — скачиваю в ~/.cache/fonts')
    for marker, url in NEED_FONTS.items():
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                data = r.read()
            z = zipfile.ZipFile(io.BytesIO(data))
            for n in z.namelist():
                base = n.split('/')[-1]
                if base.lower().endswith('.ttf') and base.startswith(('Inter-', 'JetBrainsMono-')):
                    with open(os.path.join(FONT_DIR, base), 'wb') as f:
                        f.write(z.read(n))
        except Exception as e:
            print(f'    не скачался {marker}: {e}')


_CACHE = {}

def font(kind, size):
    key = (kind, round(size))
    if key not in _CACHE:
        _CACHE[key] = ImageFont.truetype(FONT_FILES[kind], max(6, int(round(size))))
    return _CACHE[key]


def tw(text, kind, size):
    return font(kind, size).getlength(text)


# ----------------------------------------------------------------------------- общее
def rgba_layer(size, color=(0, 0, 0, 0)):
    return Image.new('RGBA', size, color)


def rrect(size, box, radius, fill=None, outline=None, width=1):
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius, fill=fill, outline=outline, width=width)
    return layer


def mask_rrect(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def radial_alpha(w, h, cx, cy, rx, ry, alpha):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    return np.clip((1.0 - np.clip(d, 0, 1)) * alpha, 0, 255).astype(np.uint8)


class NetRandom:
    """.NET System.Random — тот же узор, что рисует прототип в PowerShell."""
    MBIG, MSEED = 2147483647, 161803398

    def __init__(self, seed):
        self.s = [0] * 56
        mj = self.MSEED - abs(seed)
        self.s[55] = mj
        mk = 1
        for i in range(1, 55):
            ii = (21 * i) % 55
            self.s[ii] = mk
            mk = mj - mk
            if mk < 0:
                mk += self.MBIG
            mj = self.s[ii]
        for _ in range(1, 5):
            for i in range(1, 56):
                self.s[i] -= self.s[1 + (i + 30) % 55]
                if self.s[i] < 0:
                    self.s[i] += self.MBIG
        self.i, self.j = 0, 21

    def _n(self):
        i = self.i + 1 if self.i + 1 < 56 else 1
        j = self.j + 1 if self.j + 1 < 56 else 1
        r = self.s[i] - self.s[j]
        if r == self.MBIG:
            r -= 1
        if r < 0:
            r += self.MBIG
        self.s[i] = r
        self.i, self.j = i, j
        return r

    def sample(self):
        return self._n() * (1.0 / self.MBIG)

    def next(self, mx):
        return int(self.sample() * mx)

    def next_range(self, mn, mx):
        return int(self.sample() * (mx - mn)) + mn


def ease_io(x):
    x = max(0.0, min(1.0, x))
    return 3 * x * x - 2 * x * x * x


def ease_out(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


def task_state(task, t):
    if t < task['t0']:
        return 'waiting', 0.0
    if t < task['t1']:
        return 'run', (t - task['t0']) / (task['t1'] - task['t0'])
    return task['result'], 1.0


def progress(t):
    total = sum(min(1.0, task_state(x, t)[1]) / len(TASKS) for x in TASKS if task_state(x, t)[0] != 'waiting')
    return max(0.0, min(1.0, total))


# ----------------------------------------------------------------------------- фоны
def bg_ring():
    """Тёмно-синий фон с мягким свечением и точечной сеткой."""
    yy = np.linspace(0, 1, H)[:, None]
    arr = np.zeros((H, W, 3), dtype=np.float32)
    for c in range(3):
        arr[:, :, c] = [8, 9, 16][c] * (1 - yy) + [15, 14, 26][c] * yy
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')

    for (sx, sy, sr, a, col) in [(0.18, 0.72, 0.62, 60, (46, 74, 168)),
                                 (0.82, 0.24, 0.55, 44, (86, 66, 150))]:
        lay = Image.new('RGBA', (W, H), col + (0,))
        lay.putalpha(Image.fromarray(radial_alpha(W, H, W * sx, H * sy, W * sr, H * sr, a), 'L'))
        img.alpha_composite(lay)

    grid = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    for x in range(0, W, 44):
        for y in range(0, H, 44):
            gd.point((x, y), fill=(140, 160, 220, 40))
    img.alpha_composite(grid)
    img.alpha_composite(alpha_vignette(150))
    return img


def bg_daylight():
    """Светлый фон: мягкий градиент, цветные пятна, тонкая «сетка» под наклоном."""
    yy = np.linspace(0, 1, H)[:, None]
    arr = np.zeros((H, W, 3), dtype=np.float32)
    for c in range(3):
        arr[:, :, c] = [232, 238, 250][c] * (1 - yy) + [247, 249, 254][c] * yy
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    for (sx, sy, sr, a, col) in [(0.16, 0.16, 0.60, 70, (120, 160, 255)),
                                 (0.86, 0.82, 0.62, 52, (170, 140, 250)),
                                 (0.55, 0.45, 0.70, 40, (140, 220, 220))]:
        lay = Image.new('RGBA', (W, H), col + (0,))
        lay.putalpha(Image.fromarray(radial_alpha(W, H, W * sx, H * sy, W * sr, H * sr, a), 'L'))
        img.alpha_composite(lay)
    mesh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    md = ImageDraw.Draw(mesh)
    for i in range(-H, W, 66):
        md.line([(i, 0), (i + H, H)], fill=(120, 140, 200, 26), width=1)
    img.alpha_composite(mesh)
    return img


def bg_console():
    """Почти чёрный фон с едва заметными строками развёртки и зелёным отливом."""
    yy = np.linspace(0, 1, H)[:, None]
    arr = np.zeros((H, W, 3), dtype=np.float32)
    for c in range(3):
        arr[:, :, c] = [6, 8, 8][c] * (1 - yy) + [10, 13, 13][c] * yy
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    lay = Image.new('RGBA', (W, H), (40, 160, 120, 0))
    lay.putalpha(Image.fromarray(radial_alpha(W, H, W * 0.5, H * 0.62, W * 0.75, H * 0.7, 34), 'L'))
    img.alpha_composite(lay)
    scan = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    for y in range(0, H, 3):
        sd.line([(0, y), (W, y)], fill=(180, 255, 220, 8))
    img.alpha_composite(scan)
    img.alpha_composite(alpha_vignette(170))
    return img


def alpha_vignette(alpha):
    lay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    lay.putalpha(Image.fromarray(radial_alpha(W, H, W / 2, H / 2, W * 0.95, H * 0.95, alpha), 'L'))
    return lay


# ----------------------------------------------------------------------------- дизайны
RING = dict(
    key='ring', title='Кольцо',
    bg=bg_ring, dark=True, radius=28,
    card=(14, 15, 25, 210),
    text=(233, 237, 251), muted=(142, 150, 184), dim=(104, 112, 145),
    accent=(122, 162, 247), accent2=(167, 139, 250),
    ok=(134, 214, 160), run=(125, 211, 252), warn=(240, 196, 120), err=(240, 142, 160),
    text_kind='regular', head_kind='semibold', num_kind='bold', mono_kind='mono',
    glass=True, note='тёмная тема · числом по центру',
)

DAY = dict(
    key='day', title='Светлый',
    bg=bg_daylight, dark=False, radius=26,
    card=(255, 255, 255, 246),
    text=(26, 32, 48), muted=(103, 112, 134), dim=(140, 148, 168),
    accent=(37, 99, 235), accent2=(124, 92, 246),
    ok=(22, 163, 74), run=(14, 116, 214), warn=(202, 138, 4), err=(220, 38, 38),
    text_kind='regular', head_kind='semibold', num_kind='bold', mono_kind='mono',
    glass=False, note='светлая тема · шаги сверху',
)

CONSOLE = dict(
    key='console', title='Терминал',
    bg=bg_console, dark=True, radius=14,
    card=(9, 12, 12, 232),
    text=(214, 232, 222), muted=(126, 150, 142), dim=(92, 112, 106),
    accent=(45, 212, 160), accent2=(96, 226, 200),
    ok=(74, 222, 128), run=(56, 189, 248), warn=(250, 204, 21), err=(248, 113, 113),
    text_kind='mono', head_kind='mono-semi', num_kind='mono-bold', mono_kind='mono',
    glass=False, note='терминальный стиль · построчный журнал',
)

DESIGNS = {d['key']: d for d in (RING, DAY, CONSOLE)}


# ----------------------------------------------------------------------------- мелочи рисования
def chip(d, box, text, color, size=16.5, kind='medium', fill_alpha=24, outline_alpha=90):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, (y1 - y0) / 2, fill=color + (fill_alpha,), outline=color + (outline_alpha,), width=1)
    d.text(((x0 + x1) / 2, (y0 + y1) / 2), text, font=font(kind, size), fill=color + (255,), anchor='mm')


def tag(d, box, text, color, size=15.5, kind='mono-med'):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, 8, fill=color + (26,), outline=color + (80,), width=1)
    d.text(((x0 + x1) / 2, (y0 + y1) / 2), text, font=font(kind, size), fill=color + (255,), anchor='mm')


def state_dot(d, cx, cy, r, state, t, pal):
    if state == 'waiting':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=pal['dim'] + (170,), width=2)
    elif state == 'run':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=pal['run'] + (90,), width=2)
        a = (t * 300) % 360
        d.arc([cx - r, cy - r, cx + r, cy + r], a, a + 260, fill=pal['run'] + (255,), width=3)
    elif state == 'ok':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=pal['ok'] + (255,))
        d.line([(cx - r * .45, cy + r * .05), (cx - r * .08, cy + r * .45), (cx + r * .5, cy - r * .42)],
               fill=(255, 255, 255, 255) if not pal['dark'] else pal['card'][:3] + (255,), width=3, joint='curve')
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=pal['warn'] + (255,))
        dark = pal['card'][:3] + (255,)
        d.line([(cx, cy - r * .5), (cx, cy + r * .1)], fill=dark, width=3)
        d.ellipse([cx - 2, cy + r * .38, cx + 2, cy + r * .38 + 4], fill=dark)


def bg_with_drift(bg, t, zoom=0.02, speed=0.22):
    z = 1.0 + zoom * ease_io(min(1.0, t / 30.0))
    bw, bh = int(W * z), int(H * z)
    img = bg.resize((bw, bh), Image.BILINEAR)
    left = (bw - W) // 2 + int(14 * math.sin(t * speed))
    top = (bh - H) // 2 + int(10 * math.cos(t * speed * 0.85))
    return img.crop((left, top, left + W, top + H))


def card_layer(pal, bg, t):
    """Подложка окна. У тёмных дизайнов — «стекло», у светлого — плотная карточка с тенью."""
    scene = rgba_layer((W, H))
    box = (CARD_X, CARD_Y, CARD_X + CARD_W, CARD_Y + CARD_H)
    if pal['glass']:
        src = bg.crop(box)
        small = src.resize((CARD_W // 12, CARD_H // 12), Image.BILINEAR)
        glass = small.resize((CARD_W, CARD_H), Image.BICUBIC).convert('RGBA')
        card = rgba_layer((CARD_W, CARD_H))
        card.paste(glass, (0, 0), mask_rrect((CARD_W, CARD_H), pal['radius']))
        card.alpha_composite(rgba_layer((CARD_W, CARD_H), pal['card']))
    else:
        card = rgba_layer((CARD_W, CARD_H), pal['card'])
        card.putalpha(mask_rrect((CARD_W, CARD_H), pal['radius']))
        # тень: в настоящем окне это несколько полупрозрачных скруглённых прямоугольников
        shadow = rgba_layer((W, H))
        sd = ImageDraw.Draw(shadow)
        for i, a in enumerate((26, 16, 9)):
            sd.rounded_rectangle([box[0] - 8 - i * 6, box[1] + 14 - i * 4,
                                  box[2] + 8 + i * 6, box[3] + 26 + i * 6],
                                 pal['radius'] + 8 + i * 4, fill=(40, 50, 90, a))
        scene.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    outline = (255, 255, 255, 34) if pal['dark'] else (60, 80, 140, 26)
    card.alpha_composite(rrect((CARD_W, CARD_H), [0, 0, CARD_W - 1, CARD_H - 1], pal['radius'],
                               outline=outline, width=1))
    scene.alpha_composite(card, (CARD_X, CARD_Y))
    return scene


# ----------------------------------------------------------------------------- окна: старт
def scene_start(pal, bg, t):
    scene = bg_with_drift(bg, t).convert('RGBA')
    scene.alpha_composite(card_layer(pal, scene, t))
    layer = rgba_layer((W, H))
    d = ImageDraw.Draw(layer)
    x, y = CARD_X + PAD, CARD_Y + PAD

    appear = ease_out(t / 0.7)
    slide = int((1 - appear) * 18)

    # логотип и название
    logo = rgba_layer((64, 64))
    ld = ImageDraw.Draw(logo)
    for i in range(64):
        k = i / 63
        col = tuple(int(pal['accent'][j] * (1 - k) + pal['accent2'][j] * k) for j in range(3))
        ld.line([(i, 0), (i, 64)], fill=col + (255,))
    logo.putalpha(mask_rrect((64, 64), 16))
    layer.alpha_composite(logo, (x, y + slide))
    d.text((x + 32, y + 32 + slide), 'W', font=font('bold', 34),
           fill=(255, 255, 255, 255) if pal['dark'] else (255, 255, 255, 255), anchor='mm')
    d.text((x + 82, y + 10 + slide), 'WAD', font=font(pal['head_kind'], 32), fill=pal['text'] + (255,))
    d.text((x + 82, y + 46 + slide), 'Автоматическая установка Windows',
           font=font(pal['text_kind'], 17), fill=pal['muted'] + (255,))

    # заголовок
    d.text((x, y + 120 + slide), 'Один запуск — и система готова',
           font=font(pal['head_kind'], 42), fill=pal['text'] + (255,))
    d.text((x, y + 182 + slide),
           'Программа сама удалит лишнее, поставит нужные программы и настроит систему.',
           font=font(pal['text_kind'], 19), fill=pal['muted'] + (255,))
    d.text((x, y + 212 + slide),
           'Участие человека не требуется — можно закрыть окно и вернуться к готовому компьютеру.',
           font=font(pal['text_kind'], 19), fill=pal['muted'] + (255,))

    # факты
    facts = ['5 задач', '≈ 45 минут', 'Windows 10 / 11', 'PowerShell 5.1', 'нужен интернет']
    fx = x
    for f in facts:
        w = tw(f, 'medium', 16.5) + 34
        chip(d, [fx, y + 262 + slide, fx + w, y + 262 + 38 + slide], f, pal['accent'], size=16.5)
        fx += w + 12

    # две колонки: что установится / что настроится
    col_y = y + 336 + slide
    d.text((x, col_y), 'Что будет установлено', font=font(pal['head_kind'], 20), fill=pal['text'] + (255,))
    py = col_y + 40
    px = x
    for prog in PROGRAMS:
        w = tw(prog, 'regular', 16) + 30
        if px + w > x + 470:
            px = x
            py += 40
        chip(d, [px, py, px + w, py + 34], prog, pal['muted'], size=16, fill_alpha=20, outline_alpha=70)
        px += w + 10

    cx2 = x + 520
    d.text((cx2, col_y), 'Что будет настроено', font=font(pal['head_kind'], 20), fill=pal['text'] + (255,))
    sy = col_y + 40
    for item in SETTINGS:
        d.ellipse([cx2 + 2, sy + 8, cx2 + 10, sy + 16], fill=pal['accent'] + (255,))
        d.text((cx2 + 24, sy), item, font=font(pal['text_kind'], 17.5), fill=pal['text'] + (230,))
        sy += 30          # шаг меньше прежнего: последняя строка не заходит на кнопки

    # кнопки (на 16 px выше прежнего — иначе заезжали на подпись снизу)
    by = CARD_Y + CARD_H - PAD - 72
    primary = 'Начать установку'
    pw = tw(primary, 'semibold', 19) + 66
    d.rounded_rectangle([INNER + CARD_X - pw, by, INNER + CARD_X, by + 56], 14, fill=pal['accent'] + (255,))
    d.text((INNER + CARD_X - pw / 2, by + 28), primary, font=font('semibold', 19),
           fill=(255, 255, 255, 255), anchor='mm')
    secondary = 'GitHub проекта'
    sw = tw(secondary, 'medium', 18) + 54
    sx2 = INNER + CARD_X - pw - 14 - sw
    d.rounded_rectangle([sx2, by, sx2 + sw, by + 56], 14,
                        fill=(255, 255, 255, 16) if pal['dark'] else (255, 255, 255, 200),
                        outline=(255, 255, 255, 60) if pal['dark'] else (37, 99, 235, 70), width=1)
    d.text((sx2 + sw / 2, by + 28), secondary, font=font('medium', 18), fill=pal['text'] + (240,), anchor='mm')

    d.text((x, CARD_Y + CARD_H - PAD - 22),
           'Нужны права администратора · Логи останутся в Документах · Никакие данные никуда не отправляются',
           font=font(pal['text_kind'], 14.5), fill=pal['dim'] + (255,))

    if appear < 0.999:
        layer.putalpha(layer.getchannel('A').point(lambda v: int(v * appear)))
    scene.alpha_composite(layer)
    return scene


# ----------------------------------------------------------------------------- окна: установка
def scene_install_ring(pal, bg, t):
    scene = bg_with_drift(bg, t).convert('RGBA')
    scene.alpha_composite(card_layer(pal, scene, t))
    layer = rgba_layer((W, H))
    d = ImageDraw.Draw(layer)
    left, top = CARD_X + PAD, CARD_Y + 40

    # шапка
    d.text((left, top), 'Установка Windows', font=font(pal['head_kind'], 26), fill=pal['text'] + (255,))
    d.text((left, top + 36), 'Режим Clean · Windows 11 · запуск с GitHub',
           font=font(pal['text_kind'], 16.5), fill=pal['muted'] + (255,))

    prog = progress(t)
    if t >= 22.4:
        pill, pill_col = 'Завершено с замечаниями', pal['warn']
    elif t >= 21.8:
        pill, pill_col = 'Нужно внимание', pal['warn']
    else:
        pill, pill_col = 'Идёт установка', pal['run']
    w = tw(pill, 'medium', 16.5) + 60
    chip(d, [CARD_X + INNER - w, top + 6, CARD_X + INNER, top + 46], pill, pill_col, size=16.5)
    dot = 5 + 1.6 * math.sin(t * 4)
    d.ellipse([CARD_X + INNER - w + 18 - dot, top + 26 - dot, CARD_X + INNER - w + 18 + dot, top + 26 + dot],
              fill=pill_col + (255,))

    # кольцо прогресса
    cx, cy, R0, thick = CARD_X + 250, top + 200, 132, 18
    d.ellipse([cx - R0, cy - R0, cx + R0, cy + R0], outline=(255, 255, 255, 22), width=thick)
    steps = 120
    ang = -90
    for i in range(int(steps * prog)):
        a0 = ang + i * (360 / steps)
        k = i / max(1, steps - 1)
        col = tuple(int(pal['accent'][j] * (1 - k) + pal['accent2'][j] * k) for j in range(3))
        d.arc([cx - R0, cy - R0, cx + R0, cy + R0], a0, a0 + 360 / steps + 1.2, fill=col + (255,), width=thick)
    d.text((cx, cy - 18), f'{int(prog * 100)}', font=font(pal['num_kind'], 84), fill=pal['text'] + (255,), anchor='mm')
    d.text((cx, cy + 44), '% готово', font=font(pal['text_kind'], 17), fill=pal['muted'] + (255,), anchor='mm')
    done = sum(1 for x in TASKS if task_state(x, t)[0] in ('ok', 'warn'))
    d.text((cx, cy + 74), f'{done} из 5 задач', font=font(pal['text_kind'], 16.5), fill=pal['dim'] + (255,), anchor='mm')

    # текущая задача
    cur = next((x for x in TASKS if task_state(x, t)[0] == 'run'), None)
    if cur:
        d.text((CARD_X + 250, cy + R0 + 34), cur['name'], font=font('medium', 21), fill=pal['text'] + (255,), anchor='mm')
        d.text((CARD_X + 250, cy + R0 + 64), 'выполняется…', font=font(pal['text_kind'], 16), fill=pal['run'] + (255,), anchor='mm')
    elif t > 22.4:
        d.text((CARD_X + 250, cy + R0 + 34), 'Все задачи выполнены', font=font('medium', 21), fill=pal['text'] + (255,), anchor='mm')
        d.text((CARD_X + 250, cy + R0 + 64), 'можно перезагружать компьютер', font=font(pal['text_kind'], 16), fill=pal['ok'] + (255,), anchor='mm')

    # список задач справа — вертикальный шаг
    lx = CARD_X + 560
    ly = top + 92
    d.line([(lx + 11, ly + 10), (lx + 11, ly + 4 * 62 + 10)], fill=(255, 255, 255, 30), width=2)
    for i, task in enumerate(TASKS):
        st, frac = task_state(task, t)
        yy = ly + i * 62
        state_dot(d, lx + 11, yy + 10, 10, st, t, pal)
        col = pal['text'] if st != 'waiting' else pal['muted']
        d.text((lx + 40, yy), task['name'], font=font('medium', 19.5), fill=col + (255,))
        if st == 'ok':
            d.text((lx + 40, yy + 24), f"готово · {task['end'][:5]}", font=font(pal['text_kind'], 15), fill=pal['ok'] + (255,))
        elif st == 'run':
            d.text((lx + 40, yy + 24), f"идёт · с {task['start'][:5]}", font=font(pal['text_kind'], 15), fill=pal['run'] + (255,))
        elif st == 'warn':
            d.text((lx + 40, yy + 24), f"замечания · 2 · {task['end'][:5]}", font=font(pal['text_kind'], 15), fill=pal['warn'] + (255,))
        else:
            d.text((lx + 40, yy + 24), 'ждёт своей очереди', font=font(pal['text_kind'], 15), fill=pal['dim'] + (255,))

    # баннер с причиной
    if t >= 17.6:
        ease = ease_io((t - 17.6) / 0.5)
        by = CARD_Y + CARD_H - 150 + int((1 - ease) * 12)
        layer.alpha_composite(rrect((W, H), [left, by, CARD_X + INNER, by + 76], 14,
                                    fill=pal['warn'] + (28,), outline=pal['warn'] + (110,)))
        d.rectangle([left, by + 10, left + 4, by + 66], fill=pal['warn'] + (255,))
        state_dot(d, left + 34, by + 38, 12, 'warn', t, pal)
        d.text((left + 62, by + 14), WARN_TITLE, font=font(pal['head_kind'], 18.5), fill=pal['text'] + (255,))
        d.text((left + 62, by + 42), WARN_LINES, font=font(pal['text_kind'], 16), fill=pal['warn'] + (240,))
        d.text((CARD_X + INNER - 20, by + 38), 'Открыть журнал', font=font('medium', 16.5),
               fill=pal['warn'] + (255,), anchor='rm')

    # кнопка
    label = 'Перезагрузить компьютер' if t >= 22.4 else 'Свернуть в фон'
    bw = tw(label, 'semibold', 17) + 52
    bx = CARD_X + INNER - bw
    layer.alpha_composite(rrect((W, H), [bx, CARD_Y + CARD_H - 66, CARD_X + INNER, CARD_Y + CARD_H - 24], 12,
                                fill=pal['accent'] + (235,)))
    d.text((bx + bw / 2, CARD_Y + CARD_H - 45), label, font=font('semibold', 17),
           fill=(255, 255, 255, 255), anchor='mm')
    d.text((left, CARD_Y + CARD_H - 45), 'Прогресс считает менеджер: задача «сбой» — это замечания в логе',
           font=font(pal['text_kind'], 14.5), fill=pal['dim'] + (255,))

    scene.alpha_composite(layer)
    return scene


def scene_install_day(pal, bg, t):
    scene = bg_with_drift(bg, t).convert('RGBA')
    scene.alpha_composite(card_layer(pal, scene, t))
    layer = rgba_layer((W, H))
    d = ImageDraw.Draw(layer)
    x, y = CARD_X + PAD, CARD_Y + 40

    d.text((x, y), 'Установка Windows', font=font(pal['head_kind'], 26), fill=pal['text'] + (255,))
    d.text((x, y + 36), 'Режим Clean · Windows 11 · шаги слева направо',
           font=font(pal['text_kind'], 16.5), fill=pal['muted'] + (255,))
    prog = progress(t)
    if t >= 22.4:
        pill, pill_col = 'Завершено с замечаниями', pal['warn']
    elif t >= 21.8:
        pill, pill_col = 'Нужно внимание', pal['warn']
    else:
        pill, pill_col = 'Идёт установка', pal['run']
    w = tw(pill, 'medium', 16.5) + 60
    chip(d, [CARD_X + INNER - w, y + 6, CARD_X + INNER, y + 46], pill, pill_col, size=16.5, fill_alpha=30)

    # горизонтальные шаги
    sy = y + 110
    step_w = (INNER - PAD) / 5
    d.line([(x + step_w / 2, sy + 22), (CARD_X + INNER - step_w / 2, sy + 22)],
           fill=(40, 60, 110, 40), width=3)
    done_all = sum(1 for x2 in TASKS if task_state(x2, t)[0] in ('ok', 'warn'))
    run_idx = next((i for i, x2 in enumerate(TASKS) if task_state(x2, t)[0] == 'run'), None)
    # линия «прогресса» идёт от первого шага до текущего, а не до конца
    if run_idx is not None:
        frac = task_state(TASKS[run_idx], t)[1]
        end_x = x + step_w * (run_idx + 0.5 + frac)
    elif done_all == len(TASKS):
        end_x = CARD_X + INNER - step_w / 2
    elif done_all > 0:
        end_x = x + step_w * (done_all - 0.5)
    else:
        end_x = x + step_w / 2
    d.line([(x + step_w / 2, sy + 22), (end_x, sy + 22)], fill=pal['accent'] + (255,), width=3)
    for i, task in enumerate(TASKS):
        st, frac = task_state(task, t)
        cxx = x + step_w * (i + 0.5)
        r = 22
        if st == 'waiting':
            d.ellipse([cxx - r, sy, cxx + r, sy + 2 * r], fill=(255, 255, 255, 255),
                      outline=(150, 165, 200, 160), width=2)
            d.text((cxx, sy + r), str(i + 1), font=font('semibold', 17), fill=pal['muted'] + (255,), anchor='mm')
        elif st == 'run':
            d.ellipse([cxx - r, sy, cxx + r, sy + 2 * r], fill=pal['accent'] + (255,))
            d.text((cxx, sy + r), str(i + 1), font=font('semibold', 17), fill=(255, 255, 255, 255), anchor='mm')
            d.arc([cxx - r - 6, sy - 6, cxx + r + 6, sy + 2 * r + 6], (t * 300) % 360, (t * 300) % 360 + 250,
                  fill=pal['accent'] + (200,), width=3)
        else:
            col = pal['ok'] if st == 'ok' else pal['warn']
            d.ellipse([cxx - r, sy, cxx + r, sy + 2 * r], fill=col + (255,))
            if st == 'ok':
                d.line([(cxx - 9, sy + 22), (cxx - 2, sy + 30), (cxx + 10, sy + 13)], fill=(255, 255, 255, 255), width=3, joint='curve')
            else:
                d.text((cxx, sy + r), '!', font=font('bold', 20), fill=(255, 255, 255, 255), anchor='mm')
        label = task['name'].replace('Установка и активация Microsoft Office', 'Microsoft Office')
        label = label.replace('Установка системных компонентов', 'Системные компоненты').replace('Первоначальная настройка ОС', 'Настройка ОС').replace('Оптимизация и настройка ОС', 'Оптимизация ОС').replace('Установка софта', 'Установка софта')
        # подпись в две строки
        words = label.split()
        line1, line2 = words[0], ' '.join(words[1:])
        if len(line2) > 16:
            line2 = line2[:15] + '…'
        d.text((cxx, sy + 56), line1, font=font('medium', 15.5), fill=pal['text'] + (255,), anchor='mm')
        if line2:
            d.text((cxx, sy + 76), line2, font=font('medium', 15.5), fill=pal['text'] + (255,), anchor='mm')
        if st in ('ok', 'warn'):
            d.text((cxx, sy + 98), task['end'][:5], font=font(pal['text_kind'], 13.5),
                   fill=(pal['ok'] if st == 'ok' else pal['warn']) + (255,), anchor='mm')

    # крупно: текущая задача и время
    cy = y + 260
    cur = next((i for i, x2 in enumerate(TASKS) if task_state(x2, t)[0] == 'run'), None)
    if cur is not None:
        d.text((x, cy), TASKS[cur]['name'], font=font(pal['head_kind'], 30), fill=pal['text'] + (255,))
        d.text((x, cy + 44), 'выполняется прямо сейчас — это самая долгая часть',
               font=font(pal['text_kind'], 17), fill=pal['muted'] + (255,))
    elif t > 22.4:
        d.text((x, cy), 'Все задачи выполнены', font=font(pal['head_kind'], 30), fill=pal['ok'] + (255,))
        d.text((x, cy + 44), 'замечания по одной задаче — в журнале', font=font(pal['text_kind'], 17), fill=pal['muted'] + (255,))
    else:
        d.text((x, cy), 'Подготовка к работе…', font=font(pal['head_kind'], 30), fill=pal['text'] + (255,))

    d.text((CARD_X + INNER, cy + 6), f'{int(prog * 100)}%', font=font(pal['num_kind'], 64), fill=pal['accent'] + (255,), anchor='ra')
    d.text((CARD_X + INNER, cy + 78), f'{done_all} из 5 задач', font=font(pal['text_kind'], 17), fill=pal['muted'] + (255,), anchor='ra')

    # полоса
    bar_y = cy + 120
    d.rounded_rectangle([x, bar_y, CARD_X + INNER, bar_y + 12], 6, fill=(40, 60, 110, 28))
    fw = int((CARD_X + INNER - x) * prog)
    if fw > 6:
        bar = rgba_layer((fw, 12))
        bd = ImageDraw.Draw(bar)
        for i in range(fw):
            k = i / max(1, fw - 1)
            col = tuple(int(pal['accent'][j] * (1 - k) + pal['accent2'][j] * k) for j in range(3))
            bd.line([(i, 0), (i, 12)], fill=col + (255,))
        layer.alpha_composite(bar, (x, bar_y))

    # последние записи журнала — вместо дублирующей таблицы задач
    ly = y + 400
    d.line([(x, ly - 16), (CARD_X + INNER, ly - 16)], fill=(40, 60, 110, 26), width=1)
    d.text((x, ly - 40), 'Последние записи журнала', font=font(pal['head_kind'], 17),
           fill=pal['text'] + (255,))
    shown = [line for line in LOG_LINES if line[2] != 'sep'][-4:]
    for i, (ts, text, kind) in enumerate(shown):
        col = {'ok': pal['ok'], 'info': pal['muted'], 'warn': pal['warn']}[kind]
        d.text((x, ly + i * 26), ts, font=font(pal['mono_kind'], 15), fill=pal['dim'] + (255,))
        d.text((x + 90, ly + i * 26), text, font=font(pal['text_kind'], 16), fill=col + (255,))

    # баннер
    if t >= 17.6:
        ease = ease_io((t - 17.6) / 0.5)
        by = CARD_Y + CARD_H - 150 + int((1 - ease) * 12)
        layer.alpha_composite(rrect((W, H), [x, by, CARD_X + INNER, by + 74], 14,
                                    fill=pal['warn'] + (26,), outline=pal['warn'] + (120,)))
        d.rectangle([x, by + 10, x + 4, by + 64], fill=pal['warn'] + (255,))
        d.text((x + 24, by + 14), WARN_TITLE, font=font(pal['head_kind'], 18.5), fill=pal['text'] + (255,))
        d.text((x + 24, by + 42), WARN_LINES, font=font(pal['text_kind'], 16), fill=pal['warn'] + (240,))
        d.text((CARD_X + INNER - 20, by + 37), 'Открыть журнал', font=font('medium', 16.5),
               fill=pal['accent'] + (255,), anchor='rm')

    label = 'Перезагрузить компьютер' if t >= 22.4 else 'Свернуть в фон'
    bw = tw(label, 'semibold', 17) + 52
    bx = CARD_X + INNER - bw
    layer.alpha_composite(rrect((W, H), [bx, CARD_Y + CARD_H - 66, CARD_X + INNER, CARD_Y + CARD_H - 24], 12,
                                fill=pal['accent'] + (255,)))
    d.text((bx + bw / 2, CARD_Y + CARD_H - 45), label, font=font('semibold', 17), fill=(255, 255, 255, 255), anchor='mm')
    d.text((x, CARD_Y + CARD_H - 45), 'Окно можно свернуть — установка продолжится',
           font=font(pal['text_kind'], 15), fill=pal['muted'] + (255,))

    scene.alpha_composite(layer)
    return scene


LOG_LINES = [
    ('12:55:02', 'install-sys-components.ps1 — старт модуля', 'info'),
    ('12:55:03', 'Visual C++ 2015-2022 — скачано 24 МБ, установка', 'info'),
    ('12:55:41', 'Visual C++ 2015-2022 — код возврата 0', 'ok'),
    ('12:56:10', 'DirectX — установка из архива', 'info'),
    ('12:57:02', 'DirectX — код возврата 0', 'ok'),
    (':', '', 'sep'),
    ('12:58:30', '.NET Framework 3.5 — включение компонента', 'info'),
    ('12:59:12', '.NET Framework 3.5 — готово', 'ok'),
    ('13:00:05', '.NET 8.0 — скачивание 58 МБ', 'info'),
    ('13:01:20', '.NET 8.0 — установка', 'info'),
    ('13:02:44', '.NET 8.0 — код возврата 0', 'ok'),
    ('13:03:10', 'OpenAL — установка', 'info'),
    ('13:04:02', 'OpenAL — код возврата 0', 'ok'),
    ('13:07:44', 'ИТОГ: замечаний нет — задача выполнена', 'ok'),
]


def scene_install_console(pal, bg, t):
    """Терминальный стиль: слева состояние и задачи, справа живой журнал."""
    scene = bg_with_drift(bg, t, zoom=0.012, speed=0.16).convert('RGBA')

    m = 40
    frame = rgba_layer((W, H))
    fd = ImageDraw.Draw(frame)
    fd.rectangle([m, m, W - m, H - m], outline=(45, 212, 160, 46), width=1)
    fd.rectangle([m + 1, m + 1, W - m - 1, H - m - 1], outline=(45, 212, 160, 18), width=1)
    scene.alpha_composite(frame)

    layer = rgba_layer((W, H))
    d = ImageDraw.Draw(layer)
    x = m + 40                      # левая колонка
    col_w = 640                     # её ширина: полоса и задачи
    jx = x + col_w + 40             # правая колонка: журнал
    jw = (W - m - 40) - jx
    y = m + 34
    prog = progress(t)
    done = sum(1 for it in TASKS if task_state(it, t)[0] in ('ok', 'warn'))

    # строка состояния
    d.text((x, y), 'WAD', font=font('mono-bold', 26), fill=pal['accent'] + (255,))
    d.text((x + tw('WAD', 'mono-bold', 26) + 14, y + 7), 'v0.4', font=font('mono', 16), fill=pal['muted'] + (255,))
    d.text((x + 150, y + 4), 'РЕЖИМ CLEAN', font=font('mono-semi', 19), fill=pal['text'] + (255,))
    d.text((x + 340, y + 4), 'WINDOWS 11', font=font('mono', 19), fill=pal['muted'] + (255,))
    status = 'ЗАВЕРШЕНО С ЗАМЕЧАНИЯМИ' if t >= 22.4 else ('НУЖНО ВНИМАНИЕ' if t >= 21.8 else 'УСТАНОВКА ИДЁТ')
    scol = pal['warn'] if t >= 21.8 else pal['run']
    sw = tw(status, 'mono-semi', 19)
    d.text((W - m - 40 - sw - 16, y + 4), status, font=font('mono-semi', 19), fill=scol + (255,))
    if (t * 2) % 1 > 0.5:           # курсор после текста, а не поверх него
        d.text((W - m - 40 - sw + 2, y + 4), '_', font=font('mono-semi', 19), fill=scol + (255,))
    d.line([(x, y + 42), (W - m - 40, y + 42)], fill=(45, 212, 160, 60), width=1)

    # сегментная полоса + проценты (внутри левой колонки)
    by = y + 70
    segs, seg_w, gap = 22, 22, 5
    for i in range(segs):
        sx = x + i * (seg_w + gap)
        k = i / (segs - 1)
        col = tuple(int(pal['accent'][j] * (1 - k) + pal['accent2'][j] * k) for j in range(3))
        d.rectangle([sx, by, sx + seg_w, by + 24], fill=(col + (255,)) if k <= prog else (255, 255, 255, 14))
    d.text((x + col_w, by - 4), f'{int(prog * 100)}%', font=font('mono-bold', 34),
           fill=pal['accent'] + (255,), anchor='ra')
    d.text((x + col_w, by + 40), f'{done}/5 задач выполнено', font=font('mono', 16),
           fill=pal['muted'] + (255,), anchor='ra')

    # задачи — левая колонка
    ty = by + 74
    for i, task in enumerate(TASKS):
        st, _ = task_state(task, t)
        ry = ty + i * 40
        mark, col = {'ok': ('[ok]', pal['ok']), 'run': ('[>>]', pal['run']),
                     'warn': ('[!!]', pal['warn']), 'waiting': ('[--]', pal['dim'])}[st]
        d.text((x, ry), mark, font=font('mono-semi', 17), fill=col + (255,))
        d.text((x + 62, ry), task['name'], font=font('mono', 17),
               fill=(pal['text'] if st != 'waiting' else pal['muted']) + (255,))
        if st in ('ok', 'warn'):
            d.text((x + col_w, ry), task['end'][:5], font=font('mono', 16), fill=col + (220,), anchor='ra')

    # журнал — правая колонка
    d.text((jx, by - 30), 'ЖУРНАЛ · C:\\Windows\\Setup\\Scripts', font=font('mono', 15), fill=pal['dim'] + (255,))
    layer.alpha_composite(rrect((W, H), [jx, by, jx + jw, H - m - 130], 10,
                                fill=(0, 0, 0, 110), outline=(45, 212, 160, 40)))
    visible = int(min(len(LOG_LINES), 4 + t * 1.8))
    ly = by + 18
    for ts, text, kind in LOG_LINES[:visible]:
        if kind == 'sep':
            d.line([(jx + 16, ly + 8), (jx + jw - 16, ly + 8)], fill=(255, 255, 255, 18), width=1)
            ly += 18
            continue
        col = {'ok': pal['ok'], 'info': pal['text'], 'warn': pal['warn']}[kind]
        d.text((jx + 16, ly), ts, font=font('mono', 15), fill=pal['dim'] + (255,))
        d.text((jx + 100, ly), text, font=font('mono', 15), fill=col + (235,))
        ly += 23

    # замечания — строкой внизу, во всю ширину
    if t >= 17.6:
        ease = ease_io((t - 17.6) / 0.5)
        by2 = H - m - 106 + int((1 - ease) * 10)
        layer.alpha_composite(rrect((W, H), [x, by2, W - m - 40, by2 + 56], 8,
                                    fill=pal['warn'] + (26,), outline=pal['warn'] + (120,)))
        d.text((x + 16, by2 + 9), '!! ' + WARN_TITLE, font=font('mono-semi', 17), fill=pal['warn'] + (255,))
        d.text((x + 16, by2 + 31), WARN_LINES, font=font('mono', 14.5), fill=pal['warn'] + (200,))

    scene.alpha_composite(layer)
    return scene


# ----------------------------------------------------------------------------- окна: GitHub
def qr_matrix(text):
    """QR-код на ссылку репозитория — segno, если установлен, иначе None."""
    try:
        import segno
        return segno.make(text, error='m').matrix
    except Exception:
        return None


def scene_github(pal, bg, t):
    scene = bg_with_drift(bg, t).convert('RGBA')
    scene.alpha_composite(card_layer(pal, scene, t))
    layer = rgba_layer((W, H))
    d = ImageDraw.Draw(layer)
    x, y = CARD_X + PAD, CARD_Y + PAD
    right = CARD_X + INNER

    appear = ease_out((t - T_GITHUB) / 0.6)
    slide = int((1 - appear) * 16)

    # QR справа: всё остальное содержимое не заходит под него
    qs = 236
    qx, qy = right - qs, y + 40 + slide
    text_w = qx - x - 40

    # шапка
    logo = rgba_layer((44, 44))
    ld = ImageDraw.Draw(logo)
    for i in range(44):
        k = i / 43
        col = tuple(int(pal['accent'][j] * (1 - k) + pal['accent2'][j] * k) for j in range(3))
        ld.line([(i, 0), (i, 44)], fill=col + (255,))
    logo.putalpha(mask_rrect((44, 44), 11))
    layer.alpha_composite(logo, (x, y + slide))
    d.text((x + 22, y + 22 + slide), 'W', font=font('bold', 24), fill=(255, 255, 255, 255), anchor='mm')
    d.text((x + 60, y + 4 + slide), 'Проект на GitHub', font=font(pal['head_kind'], 26), fill=pal['text'] + (255,))
    name_w = tw(REPO['full'], pal['mono_kind'], 17)
    d.text((x + 60, y + 40 + slide), REPO['full'], font=font(pal['mono_kind'], 17), fill=pal['accent'] + (255,))
    tag(d, [x + 60 + name_w + 14, y + 38 + slide, x + 60 + name_w + 104, y + 68 + slide],
        'публичный', pal['muted'], size=14)

    # описание: ширина ограничена QR справа — при нехватке места ставим многоточие
    desc = REPO['desc']
    while tw(desc, pal['text_kind'], 18.5) > text_w and len(desc) > 12:
        desc = desc[:-2]
    if desc != REPO['desc']:
        desc = desc.rstrip(' ,.—') + '…'
    d.text((x, y + 112 + slide), desc, font=font(pal['text_kind'], 18.5), fill=pal['text'] + (235,))
    d.text((x, y + 140 + slide), 'PowerShell + файл ответов, свой интерфейс, никаких сторонних сборок.',
           font=font(pal['text_kind'], 16.5), fill=pal['muted'] + (255,))

    # цифры: две колонки, три строки — вписываются по ширине текста
    stats = [('★', f"{REPO['stars']} звёзд"), ('⌘', REPO['lang']),
             ('⑂', f"{REPO['forks']} форков"), ('◧', f"{REPO['size_kb']} КБ"),
             ('⟳', 'обновлён 10.09.2026'), ('⚖', 'лицензия не выбрана')]
    sy = y + 186 + slide
    for i, (icon, text) in enumerate(stats):
        bx = x + (i % 2) * (text_w // 2 + 8)
        by = sy + (i // 2) * 44
        bw = text_w // 2
        layer.alpha_composite(rrect((W, H), [bx, by, bx + bw, by + 36], 10,
                                    fill=(255, 255, 255, 12) if pal['dark'] else (240, 244, 252, 255),
                                    outline=(255, 255, 255, 26) if pal['dark'] else (37, 99, 235, 30)))
        d.text((bx + 14, by + 18), icon, font=font(pal['mono_kind'], 15), fill=pal['accent'] + (255,), anchor='lm')
        d.text((bx + 38, by + 18), text, font=font(pal['text_kind'], 15.5), fill=pal['text'] + (235,), anchor='lm')

    # темы — ниже третьей строки статистики
    ty = sy + 136
    d.text((x, ty), 'Темы репозитория', font=font(pal['head_kind'], 17.5), fill=pal['text'] + (255,))
    tx, twy = x, ty + 30
    for topic in REPO['topics']:
        w = tw(topic, pal['mono_kind'], 14.5) + 26
        if tx + w > x + text_w:
            tx = x
            twy += 34
        tag(d, [tx, twy, tx + w, twy + 28], topic, pal['accent'], size=14.5)
        tx += w + 8

    # как поставить — три шага
    hy = twy + 52
    d.text((x, hy), 'Как поставить у себя', font=font(pal['head_kind'], 17.5), fill=pal['text'] + (255,))
    steps = ['Скачать loader.ps1 со страницы репозитория',
             'Запустить его: права администратора запросятся сами',
             'Дождаться окна менеджера и нажать «Начать установку»']
    for i, step in enumerate(steps):
        sy2 = hy + 34 + i * 30
        d.ellipse([x + 2, sy2 + 3, x + 22, sy2 + 23], outline=pal['accent'] + (170,), width=1)
        d.text((x + 12, sy2 + 13), str(i + 1), font=font('semibold', 13), fill=pal['accent'] + (255,), anchor='mm')
        d.text((x + 34, sy2 + 4), step, font=font(pal['text_kind'], 16), fill=pal['text'] + (225,))

    # QR и подпись
    layer.alpha_composite(rrect((W, H), [qx - 14, qy - 14, qx + qs + 14, qy + qs + 14], 16, fill=(255, 255, 255, 255)))
    m = qr_matrix(REPO['url'])
    if m:
        n = len(m)
        cell = qs / n
        for r in range(n):
            for c in range(n):
                if m[r][c]:
                    px0, py0 = qx + c * cell, qy + r * cell
                    d.rectangle([px0, py0, px0 + cell + 0.5, py0 + cell + 0.5], fill=(17, 22, 34, 255))
    else:
        d.text((qx + qs / 2, qy + qs / 2), 'QR', font=font('bold', 40), fill=(17, 22, 34, 255), anchor='mm')
    d.text((qx + qs / 2, qy + qs + 34), 'Наведите камеру телефона', font=font(pal['text_kind'], 16),
           fill=pal['muted'] + (255,), anchor='mm')
    d.text((qx + qs / 2, qy + qs + 60), REPO['url'].replace('https://', ''), font=font(pal['mono_kind'], 14),
           fill=pal['dim'] + (255,), anchor='mm')

    # кнопки
    by = CARD_Y + CARD_H - PAD - 62
    primary = 'Открыть в браузере'
    pw = tw(primary, 'semibold', 18) + 56
    layer.alpha_composite(rrect((W, H), [right - pw, by, right, by + 52], 13, fill=pal['accent'] + (255,)))
    d.text((right - pw / 2, by + 26), primary, font=font('semibold', 18), fill=(255, 255, 255, 255), anchor='mm')
    second = 'Проверить обновления'
    sw2 = tw(second, 'medium', 17) + 48
    sx3 = right - pw - 14 - sw2
    layer.alpha_composite(rrect((W, H), [sx3, by, sx3 + sw2, by + 52], 13,
                                fill=(255, 255, 255, 16) if pal['dark'] else (255, 255, 255, 210),
                                outline=(255, 255, 255, 60) if pal['dark'] else (37, 99, 235, 60)))
    d.text((sx3 + sw2 / 2, by + 26), second, font=font('medium', 17), fill=pal['text'] + (235,), anchor='mm')

    d.text((x, CARD_Y + CARD_H - PAD - 18),
           f"Данные с GitHub на {REPO['fetched']}",
           font=font(pal['text_kind'], 14.5), fill=pal['dim'] + (255,))

    if appear < 0.999:
        layer.putalpha(layer.getchannel('A').point(lambda v: int(v * appear)))
    scene.alpha_composite(layer)
    return scene


INSTALL_SCENES = {'ring': scene_install_ring, 'day': scene_install_day, 'console': scene_install_console}


# ----------------------------------------------------------------------------- сборка кадра
def build_background(pal):
    return pal['bg']()


def render_frame(pal, bg, t):
    if t < T_START:
        return scene_start(pal, bg, t).convert('RGB')
    if t < T_INSTALL:
        inst = INSTALL_SCENES[pal['key']]
        if t < T_START + 0.45:                      # плавный переход от старта
            a = ease_io((t - T_START) / 0.45)
            base = scene_start(pal, bg, T_START - 0.01).convert('RGBA')
            nxt = inst(pal, bg, 0.0).convert('RGBA')
            return Image.blend(base, nxt, a).convert('RGB')
        return inst(pal, bg, t - T_START).convert('RGB')
    if t < T_GITHUB:
        inst = INSTALL_SCENES[pal['key']]
        if t < T_INSTALL + 0.45:
            a = ease_io((t - T_INSTALL) / 0.45)
            return Image.blend(inst(pal, bg, T_INSTALL - T_START).convert('RGBA'),
                               scene_github(pal, bg, T_GITHUB).convert('RGBA'), a).convert('RGB')
        return inst(pal, bg, t - T_START).convert('RGB')
    frame = scene_github(pal, bg, t).convert('RGBA')
    fade = min(max(0.0, t / 0.6), max(0.0, (T_END - t) / 1.0), 1.0)
    if fade < 0.999:
        frame.alpha_composite(rgba_layer((W, H), (0, 0, 0, int(255 * (1 - fade)))))
    return frame.convert('RGB')


def write_video(pal, out_path, duration=T_END, fps=FPS):
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        sys.exit('нет ffmpeg: pip install imageio-ffmpeg')
    bg = build_background(pal)
    cmd = [ffmpeg, '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(fps), '-i', '-',
           '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-movflags', '+faststart', out_path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    total = int(duration * fps)
    for i in range(total):
        proc.stdin.write(render_frame(pal, bg, i / fps).tobytes())
        if i % 150 == 0:
            print(f'    {i}/{total}')
    proc.stdin.close()
    err = proc.stderr.read().decode('utf-8', 'ignore')
    if proc.wait() != 0:
        print(err[-1200:])
        sys.exit('ffmpeg упал')
    print(f'  {out_path} — {os.path.getsize(out_path)//1024} КБ')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--design', choices=sorted(DESIGNS))
    ap.add_argument('--scene', choices=['start', 'install', 'github'], default='install')
    ap.add_argument('--still', type=float)
    ap.add_argument('--video', action='store_true')
    ap.add_argument('--all', action='store_true')
    args = ap.parse_args()

    if args.list or not args.design:
        for k, d in DESIGNS.items():
            print(f'  {k:8s} {d["title"]:10s} — {d["note"]}')
        return

    ensure_fonts()
    os.makedirs(OUT_DIR, exist_ok=True)
    pal = DESIGNS[args.design]
    bg = build_background(pal)

    if args.still is not None:
        if args.scene == 'start':
            img = scene_start(pal, bg, args.still)
        elif args.scene == 'github':
            img = scene_github(pal, bg, T_GITHUB + args.still)
        else:
            img = INSTALL_SCENES[pal['key']](pal, bg, args.still)
        p = os.path.join(OUT_DIR, f'design-{pal["key"]}-{args.scene}.png')
        img.convert('RGB').save(p)
        print(f'  {p}')
        return

    if args.video or args.all:
        write_video(pal, os.path.join(OUT_DIR, f'design-{pal["key"]}.mp4'))
        # кадр-обложка
        render_frame(pal, bg, 10.0).save(os.path.join(OUT_DIR, f'design-{pal["key"]}-cover.png'))
        print(f'  обложка: design-{pal["key"]}-cover.png')


if __name__ == '__main__':
    main()
