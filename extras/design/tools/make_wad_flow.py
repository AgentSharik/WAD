#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Полный путь WAD в стиле Windows 11: приветствие → начальное окно → установка → GitHub.

Особенности:
  * фон — светлые обои в духе Windows 11 (абстрактные ленты, мягкие пятна);
  * окно — стиль Mica: полупрозрачное, берёт цвет обоев, без жёсткой тени, поэтому
    вытекает из фона, а не висит отдельной карточкой;
  * сначала на фоне проявляются слова приветствия, и только потом выступает окно;
  * строка состояния (шаги) — вместо белой полосы анимированная линия с бегущим светом;
  * кружки шагов крупные, журнал-консоль снизу убран;
  * системной полосы заголовка нет: знак WAD, название раздела и значки управления
    нарисованы внутри окна, поэтому ничего не «приклеено» сверху;
  * приветствие — 17,5 с: сначала чёрный экран, который потом перетекает в обои; все строки
    одного кегля (84), длинная фраза разбита на две строки; строки проявляются, стоят 2,1 с и
    уходят вверх с паузой 0,25 с между ними — как в первом входе в Windows;
  * «WAD» и «Приступаем» залиты тем же системным синим с фиолетовым (чуть глубже) и обведены
    белым, иначе слова растворялись в светлом фоне;
  * шрифт макета — Source Sans 3 (Segoe UI лицензионный, Selawik без кириллицы);
  * окно проступает из фона уже после приветствия и проявляется 2 с, а не «включается»;
  * начальное окно висит 5 с и кнопки «продолжить» не имеет — установка начинается сама;
  * в окне проекта список изменений — по одной записи на версию (0.4 / 0.3 / 0.2).

    python3 extras/design/tools/make_wad_flow.py --still 2.0     # кадр на секунде
    python3 extras/design/tools/make_wad_flow.py                 # весь ролик

Результат: extras/design/demo/wad-full.mp4
"""
import argparse
import math
import os
import subprocess
import sys

import subprocess as _sp

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

try:
    import segno
except ImportError:                      # библиотека нужна только для QR в окне проекта
    _sp.run([sys.executable, '-m', 'pip', 'install', '-q', 'segno'], check=False)
    try:
        import segno
    except ImportError:
        segno = None
        print('  segno не установилась — на месте QR будет заглушка')

# ----------------------------------------------------------------------------- размеры
W, H = 1920, 1080
FPS = 30

WIN_W, WIN_H = 1180, 720
WIN_X, WIN_Y = (W - WIN_W) // 2, (H - WIN_H) // 2
RADIUS = 10                     # Windows 11: скругление 8–10 px
TITLE_H = 52                    # полоса заголовка с кнопками окна
PAD = 56                        # внутренние отступы
INNER = WIN_X + WIN_W - PAD

# сценарий: текст (9 с) → окно (5 с) → установка → GitHub → растворение в фон
T_TEXT_END = 16.95              # приветствие полностью ушло
T_WIN_APPEAR = 17.70            # 0,75 с на экране только фон, потом окно начинает проступать
T_START = 19.30                 # окно проступило целиком (проявляется 1,6 с)
T_INSTALL = 25.30               # окно висит ровно 6 с, дальше само начинает установку
T_GITHUB = 48.90                # финал установки держится 1,6 с и окно уходит в проект
T_END = 54.40

# Семейство шрифта макета. Настоящий Segoe UI взять нельзя: он лицензионный и в песочнице
# его нет; Selawik (единственный совместимый по метрикам свободный аналог) без кириллицы.
# Поэтому — Source Sans 3: свободная, с полной кириллицей, по пропорциям ближе всего к Segoe UI.
# Поменять на другое семейство — одна строка: 'sourcesans3' | 'fira' | 'inter'.
FONT_FAMILY = 'sourcesans3'

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN_DIR = os.path.normpath(os.path.join(HERE, '..'))
OUT_DIR = os.path.join(DESIGN_DIR, 'demo')
FONT_DIR = os.path.expanduser('~/.cache/fonts')

# ----------------------------------------------------------------------------- палитра (Windows 11, светлая)
C = {
    'text':    (26, 28, 32),
    'text2':   (96, 104, 116),
    'text3':   (138, 146, 160),
    'accent':  (0, 103, 192),      # системный синий Windows 11
    'accent2': (116, 92, 231),     # для градиента
    'ok':      (16, 124, 65),      # зелёный Windows
    'warn':    (157, 93, 0),       # предупреждение Windows
    'err':     (196, 43, 28),      # ошибка Windows
    'card':    (255, 255, 255),
    'line':    (216, 220, 228),
}

FONTS = {}

FONT_SOURCES = {
    'Inter': 'https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip',
    'JetBrainsMono': 'https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip',
}


def _unzip_to(zip_path, mapping, need=('regular', 'medium', 'semibold', 'bold', 'extrabold')):
    """Распаковать нужные начертания из архива в FONT_DIR. mapping: как в FAMILIES."""
    import zipfile
    with zipfile.ZipFile(zip_path) as z:
        for kind in need:
            src = mapping[kind]
            dst = os.path.join(FONT_DIR, FONT_FAMILY + '-' + kind + '.ttf')
            with z.open(src) as fsrc, open(dst, 'wb') as fdst:
                fdst.write(fsrc.read())
            FONTS[kind] = dst


FAMILIES = {
    'sourcesans3': dict(
        url='https://github.com/adobe-fonts/source-sans/releases/download/3.052R/TTF-source-sans-3.052R.zip',
        files={'regular': 'TTF/SourceSans3-Regular.ttf', 'medium': 'TTF/SourceSans3-Medium.ttf',
               'semibold': 'TTF/SourceSans3-Semibold.ttf', 'bold': 'TTF/SourceSans3-Bold.ttf',
               'extrabold': 'TTF/SourceSans3-Black.ttf'},
        note='Source Sans 3 (Adobe, свободная, кириллица есть)'),
    'fira': dict(
        url='https://github.com/mozilla/Fira/archive/refs/heads/master.zip',
        files={'regular': 'Fira-master/ttf/FiraSans-Regular.ttf',
               'medium': 'Fira-master/ttf/FiraSans-Medium.ttf',
               'semibold': 'Fira-master/ttf/FiraSans-SemiBold.ttf',
               'bold': 'Fira-master/ttf/FiraSans-Bold.ttf',
               'extrabold': 'Fira-master/ttf/FiraSans-ExtraBold.ttf'},
        note='Fira Sans (Mozilla, кириллица есть)'),
    'inter': dict(url='https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip',
                  files={'regular': 'extras/ttf/Inter-Regular.ttf', 'medium': 'extras/ttf/Inter-Medium.ttf',
                         'semibold': 'extras/ttf/Inter-SemiBold.ttf', 'bold': 'extras/ttf/Inter-Bold.ttf',
                         'extrabold': 'extras/ttf/Inter-ExtraBold.ttf'},
                  note='Inter (кириллица есть, но формы дальше от Segoe)'),
}


def fetch_fonts():
    """Скачать выбранное семейство в ~/.cache/fonts. Без интернета — падаем на Inter."""
    import urllib.request
    if FONT_FAMILY not in FAMILIES:
        print('  неизвестное семейство шрифта:', FONT_FAMILY)
        return
    fam = FAMILIES[FONT_FAMILY]
    zip_path = os.path.join(FONT_DIR, FONT_FAMILY + '.zip')
    if not os.path.exists(zip_path):
        print('  качаю шрифт:', fam['note'], '…')
        try:
            with urllib.request.urlopen(fam['url'], timeout=90) as r, open(zip_path, 'wb') as f:
                f.write(r.read())
        except Exception as e:                       # noqa: BLE001 — сообщаем и живём дальше
            print('  не вышло скачать шрифт:', e)
            return
    _unzip_to(zip_path, fam['files'])


def fetch_inter():
    """Запасной путь: Inter (если выбранное семейство не скачалось)."""
    zip_path = os.path.join(FONT_DIR, 'Inter-4.1.zip')
    if not os.path.exists(zip_path):
        import urllib.request
        print('  качаю запасной шрифт Inter…')
        with urllib.request.urlopen('https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip',
                                    timeout=90) as r, open(zip_path, 'wb') as f:
            f.write(r.read())
    import zipfile
    with zipfile.ZipFile(zip_path) as z:
        for kind, name in (('regular', 'Inter-Regular.ttf'), ('medium', 'Inter-Medium.ttf'),
                           ('semibold', 'Inter-SemiBold.ttf'), ('bold', 'Inter-Bold.ttf'),
                           ('extrabold', 'Inter-ExtraBold.ttf')):
            dst = os.path.join(FONT_DIR, name)
            if not os.path.exists(dst):
                with z.open('extras/ttf/' + name) as fsrc, open(dst, 'wb') as fdst:
                    fdst.write(fsrc.read())
            FONTS[kind] = dst


def ensure_fonts():
    os.makedirs(FONT_DIR, exist_ok=True)
    fetch_fonts()
    if len(FONTS) < 5:
        print('  перехожу на Inter — в макете формы букв будут чуть иными, чем в Windows')
        fetch_inter()
    if len(FONTS) < 5:
        raise SystemExit('нет шрифтов: нужен интернет хотя бы на первый запуск')


_CACHE = {}


def font(kind, size):
    key = (kind, round(size, 1))
    if key not in _CACHE:
        _CACHE[key] = ImageFont.truetype(FONTS[kind], max(6, int(round(size))))
    return _CACHE[key]


def tw(text, kind, size):
    return font(kind, size).getlength(text)


def ease_io(x):
    x = max(0.0, min(1.0, x))
    return 3 * x * x - 2 * x * x * x


def ease_out(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


# ----------------------------------------------------------------------------- фон: обои в духе Windows 11
def build_wallpaper():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx, ny = xx / W, yy / H

    # база: очень светлый холодный градиент
    base = np.zeros((H, W, 3), dtype=np.float32)
    for c, (top, bottom) in enumerate([((214, 228, 250), (247, 250, 255)),
                                       ((226, 236, 253), (250, 252, 255)),
                                       ((244, 247, 255), (252, 253, 255))]):
        base[:, :, c] = top[c] * (1 - ny) + bottom[c] * ny

    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')

    # мягкие цветные пятна (как подсветка обоев Windows 11)
    blobs = [
        (0.22, 0.30, 0.55, 90, (120, 170, 255)),
        (0.78, 0.22, 0.50, 80, (150, 130, 255)),
        (0.62, 0.78, 0.60, 70, (130, 210, 245)),
        (0.12, 0.82, 0.45, 60, (175, 200, 255)),
    ]
    for (bx, by, br, alpha, col) in blobs:
        d = np.sqrt(((nx - bx) / br) ** 2 + ((ny - by) / br) ** 2)
        a = np.clip(1 - d, 0, 1) ** 2.2 * alpha
        layer = Image.new('RGBA', (W, H), col + (0,))
        layer.putalpha(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'L'))
        img.alpha_composite(layer)

    # ленты: широкие кривые с размытием — «цветок» Windows, но свой
    ribbons = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ribbons)
    import random
    rnd = random.Random(11)
    for i, (col, alpha, width) in enumerate([((90, 150, 240), 120, 150),
                                             ((140, 120, 240), 110, 120),
                                             ((110, 200, 235), 100, 100),
                                             ((60, 120, 220), 90, 70)]):
        pts = []
        ph = rnd.uniform(0, 6.28)
        amp = rnd.uniform(120, 260)
        base_y = H * rnd.uniform(0.2, 0.8)
        for x in range(-100, W + 100, 24):
            t = x / W * 6.28
            y = base_y + amp * math.sin(t * 0.8 + ph) * 0.5 + amp * 0.35 * math.sin(t * 2.1 + ph * 1.7)
            pts.append((x, y))
        rd.line(pts, fill=col + (alpha,), width=width, joint='curve')
    ribbons = ribbons.filter(ImageFilter.GaussianBlur(60))
    img.alpha_composite(ribbons)

    # лёгкое «зерно» убирает ступеньки на плавных переходах
    noise = (np.random.RandomState(3).rand(H, W, 1) - 0.5) * 5
    arr = np.asarray(img.convert('RGB'), dtype=np.float32) + noise
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB')


def build_mica(wallpaper):
    """Mica: под окном — размытые обои с лёгкой белой плёнкой и полосой заголовка чуть темнее."""
    region = wallpaper.crop((WIN_X, WIN_Y, WIN_X + WIN_W, WIN_Y + WIN_H))
    small = region.resize((WIN_W // 14, WIN_H // 14), Image.BILINEAR)
    blurred = small.resize((WIN_W, WIN_H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(6))

    card = Image.new('RGBA', (WIN_W, WIN_H), (0, 0, 0, 0))
    card.paste(Image.blend(blurred, Image.new('RGB', (WIN_W, WIN_H), (252, 253, 255)), 0.86),
               (0, 0), mask_rrect((WIN_W, WIN_H), RADIUS))
    card.alpha_composite(Image.new('RGBA', (WIN_W, WIN_H), (255, 255, 255, 40)))

    # рамка окна: тонкая светлая, как в Windows 11
    card.alpha_composite(rrect((WIN_W, WIN_H), [0, 0, WIN_W - 1, WIN_H - 1], RADIUS,
                               outline=(255, 255, 255, 210), width=1))
    card.alpha_composite(rrect((WIN_W, WIN_H), [1, 1, WIN_W - 2, WIN_H - 2], RADIUS - 1,
                               outline=(0, 0, 0, 12), width=1))
    return card


def build_shadow():
    """Очень мягкая тень: окно должно читаться, но не выглядеть наклейкой."""
    sh = Image.new('L', (W, H), 0)
    ImageDraw.Draw(sh).rounded_rectangle(
        [WIN_X - 10, WIN_Y + 14, WIN_X + WIN_W + 10, WIN_Y + WIN_H + 30], RADIUS + 12, fill=46)
    return sh.filter(ImageFilter.GaussianBlur(34))


def rgba(size, color=(0, 0, 0, 0)):
    return Image.new('RGBA', size, color)


def rrect(size, box, radius, fill=None, outline=None, width=1):
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius, fill=fill, outline=outline, width=width)
    return layer


def mask_rrect(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def mask_rrect_top(size, radius):
    """Скругление только сверху — для полосы заголовка."""
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] * 2], radius, fill=255)
    return m


# ----------------------------------------------------------------------------- данные
REPO = {
    'full': 'AgentSharik/WAD',
    'url': 'https://github.com/AgentSharik/WAD',
    'desc': 'Автоматическая установка и пост-установка Windows: один запуск и готовая система.',
    'lang': 'PowerShell', 'size_kb': 671, 'updated': '10.09.2026',
    'license': 'не выбрана', 'topics_count': 8,
    'topics': ['windows', 'powershell', 'automation', 'unattended-install',
               'post-install', 'windows-deployment', 'sysadmin', 'setup-scripts'],
    'fetched': '11 сентября 2026',
}

TASKS = [
    dict(name='Первоначальная настройка ОС', short='Настройка ОС', t0=0.8, t1=3.4,
         start='12:41:03', end='12:47:21', result='ok',
         subs=['Приветствие и фон Edge', 'Панель задач и меню Пуск', 'Телеметрия и Copilot', 'Макет профиля']),
    dict(name='Оптимизация и настройка ОС', short='Оптимизация ОС', t0=3.4, t1=6.0,
         start='12:47:21', end='12:55:02', result='ok',
         subs=['33 встроенных приложения', 'OneDrive', 'Просмотрщик фото', 'Файл подкачки']),
    dict(name='Установка системных компонентов', short='Компоненты', t0=6.0, t1=11.6,
         start='12:55:02', end='13:07:44', result='ok',
         subs=['Visual C++ 2015-2022', 'DirectX', '.NET Framework 3.5', '.NET 8.0', 'OpenAL']),
    dict(name='Установка софта', short='Софт', t0=11.6, t1=17.8,
         start='13:07:44', end='13:21:10', result='warn',
         subs=['Google Chrome', 'Steam', 'WinRAR', 'qBittorrent', 'ShareX', 'K-Lite Codec Pack'],
         failed=['ShareX', 'K-Lite Codec Pack']),
    dict(name='Установка и активация Microsoft Office', short='Microsoft Office', t0=17.8, t1=22.0,
         start='13:21:40', end='13:34:55', result='ok',
         subs=['Office Deployment Tool', 'Word, Excel, PowerPoint', 'Привязка KMS', 'Активация']),
]
INSTALL_LEN = 22.0
WARN_TITLE = 'Установка софта завершилась с замечаниями: 2 программы не установились'
WARN_LINES = 'ShareX — установщик вернул код 1603 · K-Lite Codec Pack — ссылка не отвечает'


def task_state(task, t):
    if t < task['t0']:
        return 'waiting', 0.0
    if t < task['t1']:
        return 'run', (t - task['t0']) / (task['t1'] - task['t0'])
    return task['result'], 1.0


def progress(t):
    parts = [min(1.0, task_state(x, t)[1]) / len(TASKS) for x in TASKS if task_state(x, t)[0] != 'waiting']
    return max(0.0, min(1.0, sum(parts)))


# ----------------------------------------------------------------------------- окно: общая часть
def draw_window_chrome(layer, d, phase, t, _kind=None):
    """Шапка окна нарисована внутри окна: системной полосы Windows нет.

    Слева — знак WAD и название раздела, справа — тонкие значки управления.
    Ни полосы, ни разделителя, ни затемнения: ничего «приклеенного» сверху.
    """
    ix, iy = PAD, 26
    size = 28
    icon = rgba((size, size))
    idr = ImageDraw.Draw(icon)
    for i in range(size):
        k = i / (size - 1)
        col = tuple(int(C['accent'][j] * (1 - k) + C['accent2'][j] * k) for j in range(3))
        idr.line([(i, 0), (i, size)], fill=col + (255,))
    icon.putalpha(mask_rrect((size, size), 7))
    layer.alpha_composite(icon, (ix, iy))
    d.text((ix + size / 2, iy + size / 2 + 1), 'W', font=font('bold', 15), fill=(255, 255, 255, 255), anchor='mm')

    cyy = iy + size / 2
    d.text((ix + size + 12, cyy), 'WAD', font=font('semibold', 19), fill=C['text'] + (240,), anchor='lm')
    wadw = tw('WAD', 'semibold', 19)
    d.text((ix + size + 12 + wadw + 10, cyy + 1), '· ' + phase, font=font('regular', 15.5),
           fill=C['text3'] + (235,), anchor='lm')

    # управление окном — просто значки по краю содержимого, без подложки
    step = 34
    for i in range(3):
        cxx = WIN_W - PAD - step * (2 - i) - step / 2
        hover = (i == 2 and T_START + 1.2 < t < T_START + 2.0)
        if hover:                                   # мягкий красный кружок, как в Windows 11
            layer.alpha_composite(rgba((30, 30), (196, 43, 28, 225)), (int(cxx - 15), int(cyy - 15)))
            layer.alpha_composite(rgba((30, 30), (196, 43, 28, 225)), (int(cxx - 15), int(cyy - 15)))
        col = (255, 255, 255, 245) if hover else C['text'] + (170,)
        if i == 0:                                  # свернуть
            d.line([(cxx - 6, cyy), (cxx + 6, cyy)], fill=col, width=1)
        elif i == 1:                                # развернуть
            d.rectangle([cxx - 5.5, cyy - 5.5, cxx + 5.5, cyy + 5.5], outline=col, width=1)
        else:                                       # закрыть
            d.line([(cxx - 6, cyy - 6), (cxx + 6, cyy + 6)], fill=col, width=1)
            d.line([(cxx - 6, cyy + 6), (cxx + 6, cyy - 6)], fill=col, width=1)


def draw_flow_line(layer, d, x0, x1, y, prog, t):
    """Анимированная линия состояния: без белой полосы, с бегущим светом по пройденной части."""
    span = x1 - x0
    filled = span * prog
    if filled > 2:
        bar = rgba((int(filled), 6))
        bd = ImageDraw.Draw(bar)
        # свет бежит слева направо: основание почти прозрачное, блик — ярче
        for i in range(int(filled)):
            k = i / max(1, filled - 1)
            col = tuple(int(C['accent'][j] * (1 - k) + C['accent2'][j] * k) for j in range(3))
            bd.line([(i, 2), (i, 4)], fill=col + (255,))
        head = int(((t * 0.45) % 1.0) * (filled + 260)) - 130
        sh = rgba((int(filled), 6))
        sd = ImageDraw.Draw(sh)
        for i in range(260):
            x = head + i
            if 0 <= x < filled:
                a = int(150 * math.sin(math.pi * i / 260))
                sd.line([(x, 1), (x, 5)], fill=(255, 255, 255, a))
        bar.alpha_composite(sh)
        layer.alpha_composite(bar, (int(x0), int(y - 3)))
    # «хвост» ждёт своей очереди — едва различимые точки, а не серая полоса
    if prog < 0.999:
        dots_x = x0 + filled
        while dots_x < x1:
            a = int(26 * (1 - (dots_x - (x0 + filled)) / max(1, span)))
            d.ellipse([dots_x, y - 1.5, dots_x + 3, y + 1.5], fill=C['text3'] + (max(8, a),))
            dots_x += 9


# ----------------------------------------------------------------------------- экран 1: приветствие
WELCOME_SIZE = 84                # один кегль на все строки приветствия — как у «Здравствуйте»
RISE_IN, RISE_OUT = 34, 24       # насколько строка «доезжает» по вертикали при появлении и уходе
# (t0, t1, t2, t3, строки, стиль): 0,9 с проявляется, 2,1 с стоит, 1,1 с уходит; между
# строками пауза 0,25 с. Полностью разнесены по времени: строки не накладываются, а длинные
# растворения убирают резкость — «плавно ушло, пауза, плавно пришло».
WELCOME = [
    # первая строка уходит синхронно с чёрным фоном (см. BLACK_FULL/BLACK_GONE) —
    # на светлых обоях она не появляется второй раз
    (0.40, 1.30, 3.30, 3.75, ['Здравствуйте'], 'ink'),
    (4.15, 5.05, 7.15, 8.25, ['Вас приветствует WAD'], 'wad'),
    (8.50, 9.40, 11.50, 12.60, ['WAD настроит Windows для вас,', 'можете отдохнуть'], 'wad'),
    (12.85, 13.75, 15.85, 16.95, ['Приступаем'], 'go'),
]
BLACK_FULL = 3.75                # до этой секунды фон чёрный: слово гаснет ровно к этому моменту
BLACK_GONE = 4.60                # чёрный уходит уже пустым — на светлых обоях текста не видно

# тот же системный синий и тот же фиолетовый, только чуть глубже: цвет не меняем,
# а белая обводка вокруг слова делает его заметным на светлом фоне
ACC_A = (0, 94, 184)
ACC_B = (104, 78, 222)


def black_amount(t):
    """Сколько чёрного лежит поверх обоев: 1 — сплошной чёрный, 0 — только обои."""
    if t <= BLACK_FULL:
        return 1.0
    if t >= BLACK_GONE:
        return 0.0
    return 1.0 - ease_io((t - BLACK_FULL) / (BLACK_GONE - BLACK_FULL))


def text_alpha(t, t0, t1, t2, t3):
    """Прозрачность и вертикальный сдвиг строки: вошла, постояла, ушла выше."""
    if t <= t0 or t >= t3:
        return 0.0, 0.0
    if t < t1:
        k = ease_io((t - t0) / (t1 - t0))
        return k, (1 - k) * RISE_IN
    if t <= t2:
        return 1.0, 0.0
    k = ease_io((t - t2) / (t3 - t2))
    return 1 - k, -k * RISE_OUT


def _text_box(text, kind, size, anchor, pad=18):
    """Рамка картинки под текст с нужным anchor и смещение, куда класть её на слой."""
    f = font(kind, size)
    box = f.getbbox(text, anchor=anchor)
    w, h = int(box[2] - box[0]) + pad * 2, int(box[3] - box[1]) + pad * 2
    return f, w, h, pad - box[0], pad - box[1]


def halo_text(layer, xy, text, kind, size, alpha, anchor='mm', blur=7.0):
    """Мягкое белое свечение под цветным текстом.

    Белая обводка (stroke_width) давала жёсткий контур вокруг каждой буквы — «белые углы».
    Здесь то же самое, но размытое: буквы так же выделяются на светлых обоях, а контура не видно.
    """
    f, w, h, ox, oy = _text_box(text, kind, size, anchor, pad=int(blur * 3))
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((ox, oy), text, font=f, fill=(255, 255, 255, int(190 * alpha)), anchor=anchor)
    layer.alpha_composite(im.filter(ImageFilter.GaussianBlur(blur)), (int(xy[0] - ox), int(xy[1] - oy)))


def grad_text(layer, xy, text, kind, size, col_a, col_b, alpha, anchor='mm'):
    """Текст, залитый градиентом, поверх белой обводки. xy — точка привязки, как у ImageDraw.text."""
    f, w, h, ox, oy = _text_box(text, kind, size, anchor)
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).text((ox, oy), text, font=f, fill=255, anchor=anchor)
    grad = Image.new('RGBA', (w, h))
    gd = ImageDraw.Draw(grad)
    for i in range(w):
        k = i / max(1, w - 1)
        gd.line([(i, 0), (i, h)], fill=tuple(int(col_a[j] * (1 - k) + col_b[j] * k) for j in range(3)) + (255,))
    grad.putalpha(mask.point(lambda v: int(v * alpha)))
    halo_text(layer, xy, text, kind, size, alpha * 0.95, anchor=anchor)
    layer.alpha_composite(grad, (int(xy[0] - ox), int(xy[1] - oy)))


def scene_text(wallpaper, t):
    frame = wallpaper.copy().convert('RGBA')
    b = black_amount(t)
    if b > 0.001:                                    # на старте экран чёрный…
        frame.alpha_composite(rgba((W, H), (0, 0, 0, int(255 * b))))
    layer = rgba((W, H))
    d = ImageDraw.Draw(layer)
    for (t0, t1, t2, t3, lines, style) in WELCOME:
        alpha, rise = text_alpha(t, t0, t1, t2, t3)
        if alpha <= 0.01:
            continue
        lh = WELCOME_SIZE * 1.16
        base = H / 2 - 40 + rise - lh * len(lines) / 2
        for i, line in enumerate(lines):
            cy = base + lh * (i + 0.5)
            if style == 'go':
                grad_text(layer, (W / 2, cy), line, 'bold', WELCOME_SIZE, ACC_A, ACC_B, alpha)
                uw = tw(line, 'bold', WELCOME_SIZE) * 0.9
                sweep = ease_io(max(0.0, min(1.0, (t - (t0 + 0.35)) / 1.0)))
                d.line([(W / 2 - uw / 2, cy + WELCOME_SIZE * 0.62),
                        (W / 2 - uw / 2 + uw * sweep, cy + WELCOME_SIZE * 0.62)],
                       fill=C['accent'] + (int(200 * alpha),), width=3)
                continue
            ink = C['text'] + (int(255 * alpha * (1 - b)),)      # тёмный текст на светлых обоях
            white = (255, 255, 255, int(255 * alpha * b))         # белый текст на чёрном
            # мягкая подсветка под тёмным текстом — на чёрном фоне не нужна
            if (1 - b) > 0.05:
                glow = rgba((W, H))
                ImageDraw.Draw(glow).text((W / 2 + 2, cy + 3), line, font=font('semibold', WELCOME_SIZE),
                                          fill=(255, 255, 255, int(150 * alpha * (1 - b))), anchor='mm')
                layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(3)))
            iw = line.find('WAD') if style == 'wad' else -1
            # ВАЖНО: текст с нулевой прозрачностью PIL не «пропускает», а затирает то, что уже нарисовано
            if iw < 0:
                if white[3] > 0:
                    d.text((W / 2, cy), line, font=font('semibold', WELCOME_SIZE), fill=white, anchor='mm')
                if ink[3] > 0:
                    d.text((W / 2, cy), line, font=font('semibold', WELCOME_SIZE), fill=ink, anchor='mm')
            else:
                before, word, after = line[:iw], line[iw:iw + 3], line[iw + 3:]
                wb, ww, wa = (tw(before, 'semibold', WELCOME_SIZE), tw(word, 'semibold', WELCOME_SIZE),
                              tw(after, 'semibold', WELCOME_SIZE))
                x0 = W / 2 - (wb + ww + wa) / 2
                for part, px in ((before, x0), (after, x0 + wb + ww)):
                    if part:
                        if white[3] > 0:
                            d.text((px, cy), part, font=font('semibold', WELCOME_SIZE), fill=white, anchor='lm')
                        if ink[3] > 0:
                            d.text((px, cy), part, font=font('semibold', WELCOME_SIZE), fill=ink, anchor='lm')
                grad_text(layer, (x0 + wb, cy), word, 'semibold', WELCOME_SIZE, ACC_A, ACC_B, alpha, anchor='lm')
    return frame, layer


# ----------------------------------------------------------------------------- экран 2: начальное окно
def scene_start(wallpaper, mica, shadow, t, appear=None):
    frame = wallpaper.copy().convert('RGBA')
    if appear is None:
        # окно не «включается», а постепенно проступает из обоев: 2 с от T_WIN_APPEAR до T_START
        appear = ease_out((t - T_WIN_APPEAR) / (T_START - T_WIN_APPEAR))

    sh = rgba((W, H))
    sh.putalpha(shadow.point(lambda v: int(v * appear)))
    frame.alpha_composite(sh)

    card = mica.copy()
    scale = 1.02 - 0.02 * appear                    # «вытекает»: чуть уменьшается при проявлении
    if scale < 0.999:
        card = card.resize((int(WIN_W * scale), int(WIN_H * scale)), Image.LANCZOS)
    content = rgba((WIN_W, WIN_H))
    d = ImageDraw.Draw(content)

    draw_window_chrome(content, d, 'установка Windows', t)

    x = PAD
    y = TITLE_H + 46
    d.text((x, y), 'Один запуск — и система готова', font=font('semibold', 38), fill=C['text'] + (255,))
    d.text((x, y + 56), 'Программа сама удалит лишнее, поставит нужные программы и настроит систему.',
           font=font('regular', 18), fill=C['text2'] + (255,))
    d.text((x, y + 84), 'Можно закрыть окно и вернуться к готовому компьютеру.',
           font=font('regular', 18), fill=C['text2'] + (255,))

    # одна кнопка — ссылка на проект: установку окно начинает само, «продолжить» не нужно
    by = WIN_H - PAD - 54
    sw = tw('Проект на GitHub', 'medium', 17) + 52
    sx = WIN_W - PAD - sw
    content.alpha_composite(rrect((WIN_W, WIN_H), [sx, by, sx + sw, by + 54], 8,
                                  fill=(255, 255, 255, 200), outline=(0, 0, 0, 26)))
    d.text((sx + sw / 2, by + 27), 'Проект на GitHub', font=font('medium', 17), fill=C['text'] + (240,), anchor='mm')

    # Содержимое окна живёт по одной кривой с самим окном: пока окно проступает,
    # вместе с ним проявляются и карточки, и строка фактов. Иначе получались рамки
    # без текста — текст догонял окно на секунду-две позже.
    def inner(offset, span=0.55):
        return ease_out(max(0.0, min(1.0, (appear - offset) / span)))

    # карточки «что будет сделано» — появляются друг за другом, но внутри проявления окна
    cy = y + 140
    cw = (WIN_W - PAD * 2 - 24) / 2
    cards = [
        ('Что установится', 'Chrome · Steam · WinRAR · qBittorrent · ShareX · K-Lite · Visual C++ · .NET 8 · Office'),
        ('Что настроится', '33 встроенных приложения и OneDrive удалятся · вернётся просмотрщик фото · '
                           'файл подкачки по объёму ОЗУ · браузер и меню'),
    ]
    for i, (title, body) in enumerate(cards):
        e = inner(0.10 + i * 0.12)
        if e <= 0.01:
            continue
        a_box = int(255 * e)
        bx = x + i * (cw + 24)
        content.alpha_composite(rrect((WIN_W, WIN_H), [bx, cy, bx + cw, cy + 176], 10,
                                      fill=(255, 255, 255, int(150 * e)), outline=(0, 0, 0, int(18 * e))))
        sub = rgba((WIN_W, WIN_H))
        sub.putalpha(int(255 * e))
        sub.alpha_composite(content.crop((int(bx), int(cy), int(bx + cw), int(cy + 176))), (int(bx), int(cy)))
        d.text((bx + 24, cy + 22), title, font=font('semibold', 19), fill=C['text'] + (int(255 * e),))
        # текст по ширине карточки
        words, lines, cur = body.split(' '), [], ''
        for wd in words:
            probe = (cur + ' ' + wd).strip()
            if tw(probe, 'regular', 16) > cw - 48:
                lines.append(cur)
                cur = wd
            else:
                cur = probe
        if cur:
            lines.append(cur)
        for j, line in enumerate(lines[:4]):
            d.text((bx + 24, cy + 58 + j * 26), line, font=font('regular', 16),
                   fill=C['text2'] + (int(255 * e),))

    # строка фактов — появляется вместе с окном, а не после него
    fy = cy + 210
    e_row = inner(0.26, 0.5)
    if e_row > 0.01:
        content.alpha_composite(rrect((WIN_W, WIN_H), [x, fy, WIN_W - PAD, fy + 76], 10,
                                     fill=(255, 255, 255, int(120 * e_row)),
                                     outline=(0, 0, 0, int(14 * e_row))))
    facts = [('Задач', '5'), ('Примерно', '45 минут'), ('Системы', 'Windows 10 / 11'),
             ('Ничего не нужно', 'только интернет')]
    fw = (WIN_W - PAD * 2 - 48) / 4
    for i, (k, v) in enumerate(facts):
        fx = x + 12 + i * fw
        if i:
            d.line([(fx - 12, fy + 16), (fx - 12, fy + 60)],
                   fill=(0, 0, 0, int(16 * e_row)), width=1)
        e = inner(0.26 + i * 0.05, 0.5)
        a = int(255 * max(0.0, e))
        d.text((fx, fy + 16), k, font=font('regular', 14), fill=C['text3'] + (a,))
        d.text((fx, fy + 36), v, font=font('semibold', 19), fill=C['text'] + (a,))

    # сноска
    d.text((x, WIN_H - PAD - 14), 'Нужны права администратора · Логи останутся в Документах',
           font=font('regular', 14.5), fill=C['text3'] + (255,))

    if appear < 0.999:
        content.putalpha(content.getchannel('A').point(lambda v: int(v * appear)))
    if content.size != card.size:
        content = content.resize(card.size, Image.LANCZOS)
    card.alpha_composite(content)
    if appear < 0.999:
        # сама подложка тоже проявляется — иначе посреди проявления висела бы пустая карточка
        card.putalpha(card.getchannel('A').point(lambda v: int(v * appear)))
    frame.alpha_composite(card, (WIN_X + (WIN_W - card.width) // 2, WIN_Y + (WIN_H - card.height) // 2))
    return frame


# ----------------------------------------------------------------------------- экран 3: установка
def scene_install(wallpaper, mica, shadow, t, base=None):
    frame = (base if base is not None else wallpaper).copy().convert('RGBA')
    frame.alpha_composite(rgba((W, H), (0, 0, 0, 0)))
    sh = rgba((W, H))
    sh.putalpha(shadow)
    frame.alpha_composite(sh)

    card = mica.copy()
    content = rgba((WIN_W, WIN_H))
    d = ImageDraw.Draw(content)
    draw_window_chrome(content, d, 'установка Windows', t)

    prog = progress(t)
    done = sum(1 for x in TASKS if task_state(x, t)[0] in ('ok', 'warn'))
    x = PAD
    y = TITLE_H + 40

    # заголовок и состояние
    if t >= INSTALL_LEN:
        state_text, state_col = 'Завершено с замечаниями', C['warn']
    elif t >= TASKS[3]['t1']:
        state_text, state_col = 'Нужно внимание', C['warn']
    else:
        state_text, state_col = 'Идёт установка', C['accent']
    d.text((x, y), 'Установка Windows', font=font('semibold', 27), fill=C['text'] + (255,))
    d.text((x, y + 38), 'Режим Clean · Windows 11', font=font('regular', 16.5), fill=C['text2'] + (255,))
    pill_w = tw(state_text, 'medium', 15.5) + 56
    content.alpha_composite(rrect((WIN_W, WIN_H), [WIN_W - PAD - pill_w, y + 6, WIN_W - PAD, y + 42], 18,
                                  fill=state_col + (22,), outline=state_col + (70,)))
    dot = 4 + 1.8 * math.sin(t * 4)
    d.ellipse([WIN_W - PAD - pill_w + 18 - dot, y + 24 - dot, WIN_W - PAD - pill_w + 18 + dot, y + 24 + dot],
              fill=state_col + (255,))
    d.text((WIN_W - PAD - pill_w + 34, y + 24), state_text, font=font('medium', 15.5),
           fill=state_col + (255,), anchor='lm')

    # ---- строка состояния: крупные кружки и анимированная линия вместо белой полосы
    sy = y + 104
    step_w = (WIN_W - PAD * 2 - 40) / 5
    R0 = 30                                     # кружки крупнее
    centers = [x + 20 + step_w * (i + 0.5) for i in range(5)]
    draw_flow_line(content, d, centers[0], centers[-1], sy + R0, prog, t)
    for i, task in enumerate(TASKS):
        st, frac = task_state(task, t)
        cxx, cyy = centers[i], sy + R0
        if st == 'waiting':
            d.ellipse([cxx - R0, cyy - R0, cxx + R0, cyy + R0], fill=(255, 255, 255, 235),
                      outline=(200, 208, 220, 235), width=2)
            d.text((cxx, cyy), str(i + 1), font=font('semibold', 22), fill=C['text3'] + (255,), anchor='mm')
        elif st == 'run':
            # пульсирующее кольцо вокруг активного шага
            pulse = 0.5 + 0.5 * math.sin(t * 3.2)
            rr = R0 + 7 + 4 * pulse
            d.ellipse([cxx - rr, cyy - rr, cxx + rr, cyy + rr], outline=C['accent'] + (int(70 + 60 * pulse),), width=3)
            d.ellipse([cxx - R0, cyy - R0, cxx + R0, cyy + R0], fill=C['accent'] + (255,))
            d.text((cxx, cyy), str(i + 1), font=font('semibold', 22), fill=(255, 255, 255, 255), anchor='mm')
        else:
            col = C['ok'] if st == 'ok' else C['warn']
            d.ellipse([cxx - R0, cyy - R0, cxx + R0, cyy + R0], fill=col + (255,))
            if st == 'ok':
                d.line([(cxx - 12, cyy + 1), (cxx - 3, cyy + 11), (cxx + 13, cyy - 9)],
                       fill=(255, 255, 255, 255), width=4, joint='curve')
            else:
                d.text((cxx, cyy), '!', font=font('bold', 26), fill=(255, 255, 255, 255), anchor='mm')
        # подписи
        d.text((cxx, cyy + R0 + 18), task['short'], font=font('medium', 16),
               fill=(C['text'] if st != 'waiting' else C['text3']) + (255,), anchor='mm')
        if st in ('ok', 'warn'):
            d.text((cxx, cyy + R0 + 40), task['end'][:5], font=font('regular', 14.5),
                   fill=(C['ok'] if st == 'ok' else C['warn']) + (255,), anchor='mm')

    # ---- крупно: текущая задача и проценты
    my = sy + R0 * 2 + 74
    cur = next((i for i, x2 in enumerate(TASKS) if task_state(x2, t)[0] == 'run'), None)
    if cur is not None:
        d.text((x, my), TASKS[cur]['name'], font=font('semibold', 30), fill=C['text'] + (255,))
        d.text((x, my + 44), 'выполняется сейчас — самая долгая часть установки',
               font=font('regular', 17), fill=C['text2'] + (255,))
    elif t >= INSTALL_LEN:
        d.text((x, my), 'Все задачи выполнены', font=font('semibold', 30), fill=C['ok'] + (255,))
    else:
        d.text((x, my), 'Начинаем установку', font=font('semibold', 30), fill=C['text'] + (255,))
        d.text((x, my + 44), 'проверяем систему и запускаем первый шаг',
               font=font('regular', 17), fill=C['text2'] + (255,))

    d.text((WIN_W - PAD, my - 6), f'{int(prog * 100)}%', font=font('bold', 62),
           fill=C['accent'] + (255,), anchor='ra')
    d.text((WIN_W - PAD, my + 70), f'{done} из 5 задач', font=font('regular', 17),
           fill=C['text2'] + (255,), anchor='ra')

    # ---- замечания и кнопка
    if t >= 17.95:
        ease = ease_io((t - 17.95) / 0.5)
        by = WIN_H - PAD - 54 - 96
        content.alpha_composite(rrect((WIN_W, WIN_H), [x, by, WIN_W - PAD, by + 92], 10,
                                      fill=(255, 249, 240, int(255 * ease)),
                                      outline=C['warn'] + (int(150 * ease),)))
        d.rectangle([x, by + 12, x + 3, by + 80], fill=C['warn'] + (int(255 * ease),))
        d.text((x + 22, by + 16), WARN_TITLE, font=font('semibold', 17.5),
               fill=C['text'] + (int(255 * ease),))
        d.text((x + 22, by + 46), WARN_LINES, font=font('regular', 15.5),
               fill=C['warn'] + (int(235 * ease),))
        d.text((x + 22, by + 68), 'Подробности — в журнале установки в папке «Документы»',
               font=font('regular', 14.5), fill=C['text2'] + (int(220 * ease),))

    # ---- состав текущей задачи: что именно делается прямо сейчас
    dy = my + 96
    active = cur if cur is not None else (4 if t >= INSTALL_LEN else None)
    if active is not None:
        task = TASKS[active]
        d.text((x, dy), 'Что делает эта задача', font=font('semibold', 16.5), fill=C['text2'] + (255,))
        cxx, cyy = x, dy + 30
        for j, sub in enumerate(task['subs']):
            wdt = tw(sub, 'regular', 15.5) + 46
            if cxx + wdt > WIN_W - PAD:
                cxx = x
                cyy += 42
            st2, frac2 = task_state(task, t)
            share = j / max(1, len(task['subs']))
            if st2 == 'waiting':
                done_item = False
            elif st2 == 'run':
                done_item = frac2 > (j + 0.15) / len(task['subs'])
            else:
                done_item = True
            bad = task.get('failed') and sub in task['failed'] and st2 == 'warn'
            if bad:
                fill, outline, tcol = (253, 240, 238), C['err'] + (120,), C['err']
            elif done_item:
                fill, outline, tcol = (240, 249, 242), C['ok'] + (90,), C['ok']
            else:
                fill, outline, tcol = (255, 255, 255, 150), (0, 0, 0, 16), C['text2']
            content.alpha_composite(rrect((WIN_W, WIN_H), [cxx, cyy, cxx + wdt, cyy + 34], 17,
                                          fill=fill + ((255,) if len(fill) == 3 else ()),
                                          outline=outline))
            # галочка/точка внутри чипа
            gx, gy = cxx + 18, cyy + 17
            if bad:
                d.line([(gx - 4, gy - 4), (gx + 4, gy + 4)], fill=C['err'] + (255,), width=2)
                d.line([(gx - 4, gy + 4), (gx + 4, gy - 4)], fill=C['err'] + (255,), width=2)
            elif done_item:
                d.line([(gx - 4, gy), (gx - 1, gy + 4), (gx + 5, gy - 4)], fill=C['ok'] + (255,), width=2, joint='curve')
            else:
                d.ellipse([gx - 3, gy - 3, gx + 3, gy + 3], outline=tcol + (200,), width=1)
            d.text((cxx + 32, cyy + 17), sub, font=font('regular', 15.5), fill=tcol + (240,), anchor='lm')
            cxx += wdt + 8

    # перезагрузка переехала в окно проекта: здесь только «Свернуть в фон»
    label = 'Свернуть в фон'
    bw = tw(label, 'semibold', 17) + 52
    content.alpha_composite(rrect((WIN_W, WIN_H), [WIN_W - PAD - bw, WIN_H - PAD - 54, WIN_W - PAD, WIN_H - PAD], 8,
                                  fill=C['accent'] + (255,)))
    d.text((WIN_W - PAD - bw / 2, WIN_H - PAD - 27), label, font=font('semibold', 17),
           fill=(255, 255, 255, 255), anchor='mm')
    note = ('Всё готово — открываю страницу проекта' if t >= INSTALL_LEN
            else 'Установка продолжится, даже если свернуть окно')
    d.text((x, WIN_H - PAD - 27), note, font=font('regular', 15), fill=C['text2'] + (255,), anchor='lm')

    card.alpha_composite(content)
    frame.alpha_composite(card, (WIN_X, WIN_Y))
    return frame


# ----------------------------------------------------------------------------- экран 4: проект (переработан)
def scene_github(wallpaper, mica, shadow, t, base=None):
    frame = (base if base is not None else wallpaper).copy().convert('RGBA')
    sh = rgba((W, H))
    sh.putalpha(shadow)
    frame.alpha_composite(sh)

    card = mica.copy()
    content = rgba((WIN_W, WIN_H))
    d = ImageDraw.Draw(content)
    draw_window_chrome(content, d, 'проект на GitHub', t)

    appear = ease_out((t - T_GITHUB) / 0.6) if T_GITHUB <= t else 0.0
    x = PAD
    y = TITLE_H + 44

    # имя репозитория и описание
    d.text((x, y), 'Проект на GitHub', font=font('semibold', 26), fill=C['text'] + (255,))
    name_w = tw(REPO['full'], 'medium', 19)
    d.text((x, y + 44), REPO['full'], font=font('medium', 19), fill=C['accent'] + (255,))
    content.alpha_composite(rrect((WIN_W, WIN_H), [x + name_w + 14, y + 42, x + name_w + 108, y + 74], 16,
                                  fill=C['accent'] + (20,), outline=C['accent'] + (60,)))
    d.text((x + name_w + 61, y + 58), 'публичный', font=font('medium', 14.5), fill=C['accent'] + (255,), anchor='mm')

    qs = 226
    qx = WIN_W - PAD - qs
    qy = y + 6
    text_w = qx - x - 36

    desc = REPO['desc']
    while tw(desc, 'regular', 18) > text_w and len(desc) > 12:
        desc = desc[:-2]
    if desc != REPO['desc']:
        desc = desc.rstrip(' ,.—') + '…'
    d.text((x, y + 112), desc, font=font('regular', 18), fill=C['text'] + (240,))
    d.text((x, y + 142), 'PowerShell + файл ответов, свой интерфейс, без сторонних сборок.',
           font=font('regular', 16.5), fill=C['text2'] + (255,))

    # характеристики: подписи словами, без символов, которых нет в шрифте
    stats = [('Язык', REPO['lang']), ('Размер', f"{REPO['size_kb']} КБ"),
             ('Обновлён', REPO['updated']), ('Лицензия', REPO['license'])]
    sy = y + 194
    bw2 = (text_w - 12) / 2
    for i, (k, v) in enumerate(stats):
        bx = x + (i % 2) * (bw2 + 12)
        by = sy + (i // 2) * 66
        content.alpha_composite(rrect((WIN_W, WIN_H), [bx, by, bx + bw2, by + 54], 8,
                                      fill=(255, 255, 255, 170), outline=(0, 0, 0, 16)))
        d.text((bx + 16, by + 12), k, font=font('regular', 14), fill=C['text3'] + (255,))
        d.text((bx + 16, by + 31), v, font=font('medium', 16.5), fill=C['text'] + (255,))

    # темы
    ty = sy + 186
    d.text((x, ty), 'Темы репозитория', font=font('semibold', 17), fill=C['text'] + (255,))
    tx, twy = x, ty + 28
    for topic in REPO['topics']:
        wdt = tw(topic, 'medium', 15) + 26
        if tx + wdt > x + text_w:
            tx = x
            twy += 40
        content.alpha_composite(rrect((WIN_W, WIN_H), [tx, twy, tx + wdt, twy + 34], 17,
                                      fill=C['accent'] + (16,), outline=C['accent'] + (48,)))
        d.text((tx + wdt / 2, twy + 17), topic, font=font('medium', 15), fill=C['accent'] + (230,), anchor='mm')
        tx += wdt + 9

    # QR и ссылка
    content.alpha_composite(rrect((WIN_W, WIN_H), [qx - 12, qy - 12, qx + qs + 12, qy + qs + 12], 12,
                                  fill=(255, 255, 255, 255), outline=(0, 0, 0, 20)))
    try:
        m = segno.make(REPO['url'], error='m').matrix
        n = len(m)
        cell = qs / n
        for r in range(n):
            for c in range(n):
                if m[r][c]:
                    px0, py0 = qx + c * cell, qy + r * cell
                    d.rectangle([px0, py0, px0 + cell + 0.5, py0 + cell + 0.5], fill=(26, 28, 32, 255))
    except Exception:
        d.text((qx + qs / 2, qy + qs / 2), 'QR', font=font('bold', 36), fill=(26, 28, 32, 255), anchor='mm')
    d.text((qx + qs / 2, qy + qs + 30), 'Наведите камеру телефона', font=font('regular', 15),
           fill=C['text2'] + (255,), anchor='mm')
    d.text((qx + qs / 2, qy + qs + 56), f"данные на {REPO['fetched']}", font=font('regular', 14),
           fill=C['text3'] + (255,), anchor='mm')

    # Истории изменений здесь намеренно нет: подписи вида «0.2 / 0.3 / 0.4» намекали на
    # нумерацию версий программы, а последняя строка налезала на подпись внизу окна.

    # кнопка одна: данные и так свежие из GitHub, а браузер на перезагружаемой машине не нужен
    by = WIN_H - PAD - 54
    rw = tw('Перезагрузить компьютер', 'semibold', 17) + 56
    rx = WIN_W - PAD - rw
    content.alpha_composite(rrect((WIN_W, WIN_H), [rx, by, WIN_W - PAD, by + 54], 8,
                                  fill=C['accent'] + (255,)))
    d.text((rx + rw / 2, by + 27), 'Перезагрузить компьютер', font=font('semibold', 17),
           fill=(255, 255, 255, 255), anchor='mm')
    d.text((x, WIN_H - PAD - 27), 'Всё готово — перезагрузка завершит настройку',
           font=font('regular', 15), fill=C['text2'] + (255,), anchor='lm')


    if appear < 0.999:
        content.putalpha(content.getchannel('A').point(lambda v: int(v * appear)))
    card.alpha_composite(content)
    frame.alpha_composite(card, (WIN_X, WIN_Y))
    return frame


# ----------------------------------------------------------------------------- сборка кадра
def render_frame(wallpaper, mica, shadow, t):
    if t < T_TEXT_END:
        # пока идёт приветствие — на экране только фон и текст, окна ещё нет
        frame, layer = scene_text(wallpaper, t)
        frame.alpha_composite(layer)
        return frame.convert('RGB')

    if t < T_INSTALL:
        # окно проявляется постепенно и уже после приветствия (см. T_WIN_APPEAR)
        return scene_start(wallpaper, mica, shadow, t).convert('RGB')

    if t < T_GITHUB:
        if t < T_INSTALL + 0.9:
            # окно не подменяется, а «перетекает»: старое растворяется в обои,
            # новое проявляется и подтягивается снизу на 14 px
            a = ease_io((t - T_INSTALL) / 0.9)
            prev = scene_start(wallpaper, mica, shadow, t).convert('RGBA')
            out = Image.blend(prev, wallpaper.convert('RGBA'), a * 0.9)
            ghost = scene_install(wallpaper, mica, shadow, t - T_INSTALL, base=rgba((W, H)))
            ghost.putalpha(ghost.getchannel('A').point(lambda v: int(v * a)))
            out.alpha_composite(ghost, (0, int(14 * (1 - a))))
            return out.convert('RGB')
        return scene_install(wallpaper, mica, shadow, t - T_INSTALL).convert('RGB')

    if t < T_GITHUB + 0.9:
        # такой же мягкий переход, как из начального окна в установку: старое растворяется,
        # новое подтягивается снизу-справа на 18 px
        a = ease_io((t - T_GITHUB) / 0.9)
        prev = scene_install(wallpaper, mica, shadow, T_GITHUB - T_INSTALL).convert('RGBA')
        out = Image.blend(prev, wallpaper.convert('RGBA'), a * 0.9)
        ghost = scene_github(wallpaper, mica, shadow, t, base=rgba((W, H)))
        ghost.putalpha(ghost.getchannel('A').point(lambda v: int(v * a)))
        out.alpha_composite(ghost, (int(18 * (1 - a)), int(18 * (1 - a))))
        return out.convert('RGB')
    frame = scene_github(wallpaper, mica, shadow, t).convert('RGB')
    # финал: окно так же растворяется в обои, как и появлялось — без затемнения в чёрное
    out = ease_io((t - (T_END - 1.6)) / 1.6)
    if out > 0.0:
        frame = Image.blend(frame, wallpaper.convert('RGB'), out)
    return frame


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--still', type=float)
    ap.add_argument('--fps', type=int, default=FPS)
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    ensure_fonts()
    print('рисую обои…')
    wallpaper = build_wallpaper()
    wallpaper.save(os.path.join(OUT_DIR, 'wallpaper-win11.png'))
    mica = build_mica(wallpaper)
    shadow = build_shadow()

    if args.still is not None:
        p = os.path.join(OUT_DIR, f'flow-{args.still:g}s.png')
        render_frame(wallpaper, mica, shadow, args.still).save(p)
        print(f'  {p}')
        return

    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        sys.exit('нет ffmpeg: pip install imageio-ffmpeg')

    out = os.path.join(OUT_DIR, 'wad-full.mp4')
    cmd = [ffmpeg, '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(args.fps), '-i', '-',
           '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-movflags', '+faststart', out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    total = int(T_END * args.fps)
    print(f'рендер {total} кадров ({T_END:g} с)…')
    for i in range(total):
        proc.stdin.write(render_frame(wallpaper, mica, shadow, i / args.fps).tobytes())
        if i % 150 == 0:
            print(f'  {i}/{total}')
    proc.stdin.close()
    err = proc.stderr.read().decode('utf-8', 'ignore')
    if proc.wait() != 0:
        print(err[-1500:])
        sys.exit('ffmpeg упал')
    print(f'  {out} — {os.path.getsize(out)//1024} КБ')


if __name__ == '__main__':
    main()
