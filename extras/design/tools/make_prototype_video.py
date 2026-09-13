#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Видео-демонстрация ПРОТОТИПА (extras/design/prototype/manager-preview.ps1).

Рисуется не «похоже», а по тому же коду: те же координаты, тот же алгоритм фона,
тот же приём со «стеклом», тот же генератор случайных чисел .NET (сверен с PowerShell),
поэтому узор на фоне на Windows ляжет ровно так же.

Запуск:
    python3 extras/design/tools/make_prototype_video.py --still 8.0
    python3 extras/design/tools/make_prototype_video.py

Результат: extras/design/demo/prototype-demo.mp4
"""
import argparse
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ----------------------------------------------------------------------------- размеры (как в прототипе)
SCREEN_W, SCREEN_H = 1920, 1080
S = min(1.0, (SCREEN_W - 100) / 1180.0, (SCREEN_H - 100) / 700.0)   # масштаб прототипа
assert S == 1.0, 'для этого разрешения прототип рисует в масштабе 1:1'

BG_W, BG_H = SCREEN_W + 60, SCREEN_H + 60                 # холст фона в прототипе
CARD_W, CARD_H = 1180, 700
CARD_X, CARD_Y = (SCREEN_W - CARD_W) // 2, (SCREEN_H - CARD_H) // 2
PAD = 48
INNER = CARD_W - PAD
FPS, DURATION = 30, 26.0

C = {
    'text':    (233, 237, 251),
    'muted':   (142, 150, 184),
    'dim':     (104, 112, 145),
    'accent1': (122, 162, 247),
    'accent2': (167, 139, 250),
    'ok':      (134, 214, 160),
    'run':     (125, 211, 252),
    'warn':    (240, 196, 120),
    'card':    (16, 17, 27),
    'ink':     (11, 11, 18),
    'dark':    (12, 14, 24),
}

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.normpath(os.path.join(HERE, '..'))
OUT_DIR = os.path.join(DESIGN, 'demo')


# ----------------------------------------------------------------------------- генератор .NET
class NetRandom:
    """System.Random из .NET (тот, что использует PowerShell).

    Сверен с PowerShell: 60 чисел подряд совпадают. Благодаря этому узор фона
    в видео и в настоящем окне одинаковый.
    """
    MBIG = 2147483647
    MSEED = 161803398

    def __init__(self, seed):
        self.SeedArray = [0] * 56
        subtraction = self.MBIG if seed == -2147483648 else abs(seed)
        mj = self.MSEED - subtraction
        self.SeedArray[55] = mj
        mk = 1
        for i in range(1, 55):
            ii = (21 * i) % 55
            self.SeedArray[ii] = mk
            mk = mj - mk
            if mk < 0:
                mk += self.MBIG
            mj = self.SeedArray[ii]
        for _ in range(1, 5):
            for i in range(1, 56):
                self.SeedArray[i] -= self.SeedArray[1 + (i + 30) % 55]
                if self.SeedArray[i] < 0:
                    self.SeedArray[i] += self.MBIG
        self.inext, self.inextp = 0, 21

    def _internal(self):
        i = self.inext + 1
        if i >= 56:
            i = 1
        j = self.inextp + 1
        if j >= 56:
            j = 1
        ret = self.SeedArray[i] - self.SeedArray[j]
        if ret == self.MBIG:
            ret -= 1
        if ret < 0:
            ret += self.MBIG
        self.SeedArray[i] = ret
        self.inext, self.inextp = i, j
        return ret

    def sample(self):
        return self._internal() * (1.0 / self.MBIG)

    def next(self, max_value):
        return int(self.sample() * max_value)

    def next_range(self, min_value, max_value):
        """Next(min, max) из .NET — как в прототипе (одна выборка на диапазон)."""
        return int(self.sample() * (max_value - min_value)) + min_value


# ----------------------------------------------------------------------------- шрифты
FONT_PATH = {}

def ensure_fonts():
    # В прототипе шрифт Segoe UI (есть в Windows). Здесь его нет, поэтому берём
    # Inter — с кириллицей и близкой геометрией. Глифы «✕» и «·» проверим при отрисовке.
    for key, name in [('regular', 'Inter-Regular.ttf'), ('medium', 'Inter-Medium.ttf'),
                      ('semibold', 'Inter-SemiBold.ttf'), ('bold', 'Inter-Bold.ttf')]:
        for base in ('/tmp/fonts/inter', '/tmp/fonts'):
            p = os.path.join(base, name)
            if os.path.exists(p):
                FONT_PATH[key] = p
                break
    if len(FONT_PATH) < 4:
        raise SystemExit('нет шрифтов Inter — нужны Inter-Regular/Medium/SemiBold/Bold.ttf в /tmp/fonts/inter')


_CACHE = {}

def font(weight, size_px):
    key = (weight, round(size_px, 2))
    if key not in _CACHE:
        _CACHE[key] = ImageFont.truetype(FONT_PATH[weight], int(round(size_px)))
    return _CACHE[key]


def tw(text, weight, size_px):
    return font(weight, size_px).getlength(text)


# ----------------------------------------------------------------------------- фон (алгоритм прототипа)
def radial_alpha(w, h, cx, cy, rx, ry, alpha_center):
    """Аналог PathGradientBrush: яркость линейно падает от центра к краю эллипса."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    a = np.clip(1.0 - d, 0.0, 1.0) * alpha_center
    return np.clip(a, 0, 255).astype(np.uint8)


def build_background():
    """New-Background() из прототипа: градиент, два свечения, дорожки платы, затемнение центра."""
    yy = np.linspace(0, 1, BG_H)[:, None]
    arr = np.zeros((BG_H, BG_W, 3), dtype=np.float32)
    for c in range(3):
        arr[:, :, c] = C['ink'][c] * (1 - yy) + [18, 18, 28][c] * yy
    bg = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')

    # свечения (эллипсы PathGradientBrush)
    for (sx, sy, sr, alpha, col) in [(0.12, 0.88, 0.55, 46, (40, 80, 160)),
                                     (0.88, 0.10, 0.60, 34, (30, 70, 120))]:
        layer = Image.new('RGBA', bg.size, col + (0,))
        a = radial_alpha(BG_W, BG_H, BG_W * sx, BG_H * sy, BG_W * sr, BG_H * sr, alpha)
        layer.putalpha(Image.fromarray(a, 'L'))
        bg.alpha_composite(layer)

    # дорожки платы: только прямые углы; шаг и порядок случайных чисел — как в прототипе
    scale = 2                                   # рисуем вдвое крупнее и уменьшаем — сглаживание
    layers = {}
    for name, col, alpha in [('lit', C['accent1'], 70), ('mid', (86, 110, 170), 46), ('thin', (86, 110, 170), 30)]:
        layers[name] = Image.new('RGBA', (BG_W * scale, BG_H * scale), col + (0,))
    nodes = Image.new('RGBA', (BG_W * scale, BG_H * scale), C['accent1'] + (0,))
    dl = {k: ImageDraw.Draw(v) for k, v in layers.items()}
    dn = ImageDraw.Draw(nodes)

    rnd = NetRandom(7)
    step = 60
    for _ in range(240):
        x = rnd.next_range(0, BG_W // step) * step
        y = rnd.next_range(0, BG_H // step) * step
        for _ in range(rnd.next_range(2, 8)):
            direction = rnd.next_range(0, 4)
            dx, dy = [(step, 0), (-step, 0), (0, step), (0, -step)][direction]
            nx, ny = x + dx, y + dy
            if nx < 0 or nx > BG_W or ny < 0 or ny > BG_H:
                break
            roll = rnd.next_range(0, 100)
            name = 'lit' if roll < 10 else ('mid' if roll < 55 else 'thin')
            dl[name].line([(x * scale, y * scale), (nx * scale, ny * scale)],
                          fill=layers[name].getpixel((0, 0))[:3] + (255,), width=2 * scale)
            x, y = nx, ny
        dn.ellipse([(x * scale - 4), (y * scale - 4), (x * scale + 4), (y * scale + 4)],
                   fill=C['accent1'] + (90,))

    for name, alpha in [('lit', 70), ('mid', 46), ('thin', 30)]:
        layer = layers[name].resize((BG_W, BG_H), Image.LANCZOS)
        a = np.asarray(layer.getchannel('A'), dtype=np.float32) * (alpha / 255.0)
        layer.putalpha(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'L'))
        bg.alpha_composite(layer)
    nodes = nodes.resize((BG_W, BG_H), Image.LANCZOS)
    a = np.asarray(nodes.getchannel('A'), dtype=np.float32) * (90 / 255.0)
    nodes.putalpha(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'L'))
    bg.alpha_composite(nodes)

    # затемнение центра: окно должно читаться, фон — не спорить с ним
    dark = Image.new('RGBA', bg.size, (5, 5, 9, 0))
    a = radial_alpha(BG_W, BG_H, BG_W / 2, BG_H / 2, BG_W * 0.85, BG_H * 0.85, 150)
    dark.putalpha(Image.fromarray(a, 'L'))
    bg.alpha_composite(dark)
    return bg.convert('RGB')


# ----------------------------------------------------------------------------- рисование
def alpha_layer(size, color, alpha):
    return Image.new('RGBA', size, color + (alpha,))


def rounded_rect_layer(size, box, radius, fill=None, outline=None, width=1):
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius, fill=fill, outline=outline, width=width)
    return layer


def chip(draw_layer, box, text, color, font_px=16.5):
    x0, y0, x1, y1 = box
    h = y1 - y0
    rad = h / 2
    draw_layer.rounded_rectangle(box, rad, fill=color + (26,), outline=color + (90,), width=1)
    draw_layer.text(((x0 + x1) / 2, (y0 + y1) / 2), text, font=font('regular', font_px),
                    fill=color + (255,), anchor='mm')


def mask_rounded(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


# состояния задач — как в прототипе
TASKS = [
    dict(name='Первоначальная настройка ОС', t0=1.6, t1=3.6, start='12:41:03', end='12:47:21', result='ok',
         subs=['Настройки Edge', 'Панель задач и меню Пуск', 'Телеметрия', 'Макет профиля по умолчанию']),
    dict(name='Оптимизация и настройка ОС', t0=3.6, t1=5.6, start='12:47:21', end='12:55:02', result='ok',
         subs=['Удаление 33 приложений', 'OneDrive', 'Просмотр фотографий', 'Файл подкачки']),
    dict(name='Установка системных компонентов', t0=5.6, t1=10.6, start='12:55:02', end='13:07:44', result='ok',
         subs=['Visual C++ 2015-2022', 'DirectX', '.NET Framework 3.5', '.NET 8.0', 'OpenAL']),
    dict(name='Установка софта', t0=10.6, t1=16.6, start='13:07:44', end='13:21:10', result='warn',
         subs=['Google Chrome', 'Steam', 'WinRAR', 'qBittorrent', 'ShareX', 'K-Lite Codec Pack']),
    dict(name='Установка и активация Microsoft Office', t0=17.4, t1=21.4, start='13:21:40', end='13:34:55',
         result='ok', subs=['Скачивание Office Deployment Tool', 'Установка Word, Excel, PowerPoint',
                            'Привязка KMS', 'Активация']),
]
WARN_LINES = 'ShareX — установщик вернул код 1603 · K-Lite Codec Pack — ссылка не отвечает'


def task_state(task, t):
    if t < task['t0']:
        return 'waiting', 0.0
    if t < task['t1']:
        return 'run', (t - task['t0']) / (task['t1'] - task['t0'])
    return task['result'], 1.0


def progress(t):
    total = sum(min(1.0, task_state(x, t)[1]) / len(TASKS) for x in TASKS if task_state(x, t)[0] != 'waiting')
    return max(0.0, min(1.0, total))


def ease_io(x):
    x = max(0.0, min(1.0, x))
    return 3 * x * x - 2 * x * x * x


def state_icon(layer, cx, cy, r, state, t):
    d = ImageDraw.Draw(layer)
    if state == 'waiting':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=C['dim'] + (150,), width=2)
    elif state == 'run':
        spin_img, spin_pos = spinner(cx, cy, r, (t * 220) % 360)
        layer.alpha_composite(spin_img, spin_pos)
    elif state == 'ok':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=C['ok'] + (235,))
        d.line([(cx - r * 0.45, cy + r * 0.05), (cx - r * 0.08, cy + r * 0.45), (cx + r * 0.5, cy - r * 0.42)],
               fill=C['dark'] + (255,), width=3, joint='curve')
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=C['warn'] + (235,))
        d.line([(cx, cy - r * 0.5), (cx, cy + r * 0.15)], fill=C['dark'] + (255,), width=3)
        d.ellipse([cx - 2, cy + r * 0.42, cx + 2, cy + r * 0.42 + 4], fill=C['dark'] + (255,))


def spinner(cx, cy, r, angle):
    size = int(r * 2 + 8)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).arc([2, 2, size - 3, size - 3], angle, angle + 250, fill=C['run'] + (255,), width=3)
    return img, (int(cx - size / 2), int(cy - size / 2))


def draw_frame(bg, t):
    # --- фон со сдвигом (прототип: dx = 30 + 14·sin(0.25t), dy = 30 + 10·cos(0.21t))
    dx = int(30 + 14 * math.sin(t * 0.25))
    dy = int(30 + 10 * math.cos(t * 0.21))
    frame = bg.crop((dx, dy, dx + SCREEN_W, dy + SCREEN_H)).convert('RGBA')

    # --- «стекло»: уменьшить и растянуть (в GDI+ настоящего размытия нет)
    src = bg.crop((CARD_X + dx, CARD_Y + dy, CARD_X + dx + CARD_W, CARD_Y + dy + CARD_H))
    small = src.resize((max(1, CARD_W // 16), max(1, CARD_H // 16)), Image.BILINEAR)
    glass = small.resize((CARD_W, CARD_H), Image.BICUBIC).convert('RGBA')

    card = Image.new('RGBA', (CARD_W, CARD_H), (0, 0, 0, 0))
    card.paste(glass, (0, 0), mask_rounded((CARD_W, CARD_H), 30))
    card.alpha_composite(alpha_layer((CARD_W, CARD_H), C['card'], 204))

    # рамка и подсветка сверху
    card.alpha_composite(rounded_rect_layer((CARD_W, CARD_H), [0, 0, CARD_W - 1, CARD_H - 1], 30,
                                            outline=(255, 255, 255, 30), width=1))
    glow = Image.new('RGBA', (CARD_W, 40), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(40):
        gd.line([(0, i), (CARD_W, i)], fill=(255, 255, 255, int(18 * (1 - i / 40))))
    card.alpha_composite(glow, (0, 0))
    del gd

    # --- содержимое окна (координаты внутри окна) --------------------------
    content = Image.new('RGBA', (CARD_W, CARD_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(content)
    prog = progress(t)

    # логотип
    logo = Image.new('RGBA', (46, 46), (0, 0, 0, 0))
    ld = ImageDraw.Draw(logo)
    for i in range(46):
        k = i / 45
        col = tuple(int(C['accent1'][j] * (1 - k) + C['accent2'][j] * k) for j in range(3))
        ld.line([(i, 0), (i, 46)], fill=col + (255,))
    logo.putalpha(mask_rounded((46, 46), 13))
    content.alpha_composite(logo, (PAD, 44))
    d.text((PAD + 23, 44 + 23), 'W', font=font('bold', 26), fill=C['dark'] + (255,), anchor='mm')

    d.text((110, 44), 'WAD — автоматическая установка Windows', font=font('semibold', 27),
           fill=C['text'] + (255,), anchor='lt')
    d.text((110, 80), 'Режим Clean · Windows 11 · запуск с GitHub', font=font('regular', 16.5),
           fill=C['muted'] + (255,), anchor='lt')

    # состояние справа
    if t >= 17.2:
        pill_text, pill_col = 'Завершено с замечаниями', C['warn']
    elif t >= 16.6:
        pill_text, pill_col = 'Нужно внимание', C['warn']
    else:
        pill_text, pill_col = 'Идёт установка', C['run']
    pill_w = tw(pill_text, 'regular', 16.5) + 62
    pill_x = INNER - pill_w
    chip(d, [pill_x, 52, pill_x + pill_w, 92], pill_text, pill_col)
    dot_r = 5 + 1.6 * math.sin(t * 4)
    d.ellipse([pill_x + 18 - dot_r, 72 - dot_r, pill_x + 18 + dot_r, 72 + dot_r], fill=pill_col + (255,))

    # процент, счётчик, текущий шаг, полоса
    d.text((PAD, 108), f'{int(prog * 100)}%', font=font('bold', 76), fill=C['text'] + (255,), anchor='lt')
    done = sum(1 for x in TASKS if task_state(x, t)[0] in ('ok', 'warn'))
    d.text((PAD, 196), f'{done} из 5 задач', font=font('regular', 19), fill=C['muted'] + (255,), anchor='lt')

    step_x, step_w = PAD + 290, INNER - (PAD + 290)
    current = next((i for i, x in enumerate(TASKS) if task_state(x, t)[0] == 'run'), None)
    if current is not None:
        frac = task_state(TASKS[current], t)[1]
        subs = TASKS[current]['subs']
        step = f"{TASKS[current]['name']} · {subs[min(len(subs) - 1, int(frac * len(subs)))]}"
    elif t > 21.6:
        step = 'Все задачи выполнены'
    else:
        step = 'Подготовка…'
    while tw(step, 'regular', 19) > step_w and len(step) > 8:
        step = step[:-2]
    d.text((step_x, 120), step, font=font('regular', 19), fill=C['text'] + (230,), anchor='lt')

    bar_y, bar_h = 156, 12
    d.rounded_rectangle([step_x, bar_y, INNER, bar_y + bar_h], 0, fill=(255, 255, 255, 22))
    fill_w = int(step_w * prog)
    if fill_w > 4:
        bar = Image.new('RGBA', (fill_w, bar_h), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        for i in range(fill_w):
            k = i / max(1, fill_w - 1)
            col = tuple(int(C['accent1'][j] * (1 - k) + C['accent2'][j] * k) for j in range(3))
            bd.line([(i, 0), (i, bar_h)], fill=col + (255,))
        sheen = Image.new('RGBA', (220, bar_h), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sheen)
        for i in range(220):
            a = int(110 * math.sin(math.pi * i / 220) ** 1.0)
            sd.line([(i, 0), (i, bar_h)], fill=(255, 255, 255, a))
        sx = int(((t * 0.35) % 1.0) * (fill_w + 220)) - 110
        bar.alpha_composite(sheen, (sx, 0))
        content.alpha_composite(bar, (step_x, bar_y))

    elapsed = int(prog * 54)
    if prog >= 0.999:
        time_text = f'Всего заняло {elapsed} мин'
    else:
        time_text = f'Прошло {elapsed} мин · осталось примерно {max(1, int((1 - prog) * 48))} мин'
    d.text((INNER, 180), time_text, font=font('regular', 16), fill=C['dim'] + (255,), anchor='rt')

    # баннер с причиной сбоя
    if t >= 16.6:
        ease = ease_io((t - 16.6) / 0.5)
        by = 544 + int((1 - ease) * 14)
        content.alpha_composite(rounded_rect_layer((CARD_W, CARD_H), [PAD, by, INNER, by + 80], 14,
                                                    fill=C['warn'] + (30,), outline=C['warn'] + (110,)))
        d.rectangle([PAD, by + 10, PAD + 4, by + 70], fill=C['warn'] + (255,))
        state_icon(content, PAD + 34, by + 40, 13, 'warn', t)
        d.text((PAD + 62, by + 20), 'Установка софта завершилась с замечаниями: 2 программы не установились',
               font=font('semibold', 19), fill=C['text'] + (255,), anchor='lt')
        d.text((PAD + 62, by + 48), WARN_LINES, font=font('regular', 16.5), fill=C['warn'] + (240,), anchor='lt')
        d.text((INNER - 20, by + 40), 'Открыть журнал', font=font('regular', 16.5), fill=C['warn'] + (255,), anchor='rm')

    # список задач
    for i, task in enumerate(TASKS):
        y = 234 + i * (54 + 6)
        state = task_state(task, t)[0]
        if state == 'run':
            content.alpha_composite(rounded_rect_layer((CARD_W, CARD_H), [PAD, y, INNER, y + 54], 12,
                                                        fill=C['accent1'] + (24,), outline=C['accent1'] + (70,)))
        else:
            content.alpha_composite(rounded_rect_layer((CARD_W, CARD_H), [PAD, y, INNER, y + 54], 12,
                                                        fill=(255, 255, 255, 8)))
        state_icon(content, PAD + 30, y + 27, 12, state, t)
        name_col = C['muted'] if state == 'waiting' else C['text']
        d.text((PAD + 58, y + 27), task['name'], font=font('semibold', 21), fill=name_col + (255,), anchor='lm')
        if state == 'run':
            chip_text, chip_col = f"идёт · с {task['start'][:5]}", C['run']
        elif state == 'ok':
            chip_text, chip_col = f"готово · {task['end'][:5]}", C['ok']
        elif state == 'warn':
            chip_text, chip_col = f"замечания · {task['end'][:5]}", C['warn']
        else:
            chip_text, chip_col = 'ждёт', C['dim']
        chip_w = tw(chip_text, 'regular', 16.5) + 30
        chip(d, [INNER - 18 - chip_w, y + 14, INNER - 18, y + 40], chip_text, chip_col)

    # низ: подсказка и кнопки
    d.text((PAD, 660), 'Окно можно свернуть — установка продолжится', font=font('regular', 16.5),
           fill=C['dim'] + (255,), anchor='lt')
    btn2_text = 'Перезагрузить компьютер' if t >= 17.2 else 'Свернуть в фон'
    btn2_w = tw(btn2_text, 'semibold', 17) + 52
    btn2_x = INNER - btn2_w
    content.alpha_composite(rounded_rect_layer((CARD_W, CARD_H), [btn2_x, 640, btn2_x + btn2_w, 682], 12,
                                                fill=C['accent1'] + (235,)))
    d.text((btn2_x + btn2_w / 2, 661), btn2_text, font=font('semibold', 17), fill=C['dark'] + (255,), anchor='mm')
    btn1_text = 'Открыть журнал'
    btn1_w = tw(btn1_text, 'semibold', 17) + 48
    btn1_x = btn2_x - 14 - btn1_w
    content.alpha_composite(rounded_rect_layer((CARD_W, CARD_H), [btn1_x, 640, btn1_x + btn1_w, 682], 12,
                                                fill=(255, 255, 255, 14), outline=(255, 255, 255, 46)))
    d.text((btn1_x + btn1_w / 2, 661), btn1_text, font=font('semibold', 17), fill=C['text'] + (235,), anchor='mm')

    # крестик и подпись предпросмотра
    d.text((CARD_W - 34, 18), '✕', font=font('regular', 16), fill=C['muted'] + (160,), anchor='lt')
    d.text((PAD, CARD_H + 14), 'Предпросмотр интерфейса · прогресс имитируется · Esc — выход',
           font=font('regular', 13), fill=C['dim'] + (140,), anchor='lt')

    card.alpha_composite(content)
    frame.alpha_composite(card, (CARD_X, CARD_Y))

    # затемнение в начале и в конце — это монтаж, в самом прототипе его нет
    fade = min(max(0.0, t / 0.6), max(0.0, (DURATION - t) / 0.8), 1.0)
    if fade < 0.999:
        frame.alpha_composite(alpha_layer((SCREEN_W, SCREEN_H), (0, 0, 0), int(255 * (1 - fade))))
    return frame.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--still', type=float, default=None)
    ap.add_argument('--duration', type=float, default=DURATION)
    ap.add_argument('--fps', type=int, default=FPS)
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    ensure_fonts()
    print('рисую фон по алгоритму прототипа…')
    bg = build_background()
    bp = os.path.join(OUT_DIR, 'prototype-background.png')
    bg.save(bp)
    print(f'  {bp}')

    if args.still is not None:
        p = os.path.join(OUT_DIR, f'proto-still-{args.still:g}s.png')
        draw_frame(bg, args.still).save(p)
        print(f'  {p}')
        return

    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        sys.exit('нет ffmpeg (pip install imageio-ffmpeg)')

    out = os.path.join(OUT_DIR, 'prototype-demo.mp4')
    cmd = [ffmpeg, '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{SCREEN_W}x{SCREEN_H}',
           '-r', str(args.fps), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
           '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    total = int(args.duration * args.fps)
    print(f'рендер {total} кадров…')
    for i in range(total):
        proc.stdin.write(draw_frame(bg, i / args.fps).tobytes())
        if i % 120 == 0:
            print(f'  {i}/{total}')
    proc.stdin.close()
    err = proc.stderr.read().decode('utf-8', 'ignore')
    if proc.wait() != 0:
        print(err[-1500:])
        sys.exit('ffmpeg упал')
    print(f'  {out} — {os.path.getsize(out)//1024} КБ')


if __name__ == '__main__':
    main()
