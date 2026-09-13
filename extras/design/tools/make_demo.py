#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Демо-ролик нового интерфейса WAD: фуллскрин-фон + крупное окно по центру.

Кадры рисуются напрямую (PIL, без браузера) и склеиваются ffmpeg.
Запуск:
    python3 extras/design/tools/make_demo.py --still 7.0     # один кадр, для проверки
    python3 extras/design/tools/make_demo.py                 # весь ролик

Вывод: extras/design/demo/wad-demo.mp4, poster.png
"""
import argparse
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ----------------------------------------------------------------------------- размеры
W, H = 1920, 1080
FPS = 30
DURATION = 26.0
CARD_W, CARD_H = 1180, 700
CARD_X, CARD_Y = (W - CARD_W) // 2, (H - CARD_H) // 2
PAD = 48
INNER_R = CARD_W - PAD          # правый край содержимого
STAMP = 12 * 3600 + 41 * 60     # «время суток» для подписей в задачах

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.normpath(os.path.join(HERE, '..'))
BG_PATH = os.path.join(DESIGN, 'wallpapers', 'wall-circuit.png')
OUT_DIR = os.path.join(DESIGN, 'demo')

# ----------------------------------------------------------------------------- цвета
C = {
    'text':    (233, 237, 251),
    'muted':   (142, 150, 184),
    'dim':     (104, 112, 145),
    'accent1': (122, 162, 247),
    'accent2': (167, 139, 250),
    'ok':      (134, 214, 160),
    'run':     (125, 211, 252),
    'warn':    (240, 196, 120),
    'err':     (240, 142, 160),
    'card':    (16, 17, 27),
}

FONTS = {}


def ensure_fonts():
    """Inter — современный шрифт с кириллицей. Если нет — DejaVu, чтобы ролик всё равно собрался."""
    wanted = {'regular': 'Inter-Regular.ttf', 'medium': 'Inter-Medium.ttf',
              'semibold': 'Inter-SemiBold.ttf', 'bold': 'Inter-Bold.ttf',
              'extrabold': 'Inter-ExtraBold.ttf'}
    paths = {}
    for key, fname in wanted.items():
        for base in ('/tmp/fonts/inter', '/tmp/fonts'):
            p = os.path.join(base, fname)
            if os.path.exists(p):
                paths[key] = p
                break
    if len(paths) < len(wanted):
        # запасной вариант: системные DejaVu (кириллица есть)
        dejavu = '/usr/share/fonts/truetype/dejavu'
        paths = {'regular': f'{dejavu}/DejaVuSans.ttf', 'medium': f'{dejavu}/DejaVuSans.ttf',
                 'semibold': f'{dejavu}/DejaVuSans-Bold.ttf', 'bold': f'{dejavu}/DejaVuSans-Bold.ttf',
                 'extrabold': f'{dejavu}/DejaVuSans-Bold.ttf'}
        print('  Inter не найден — беру DejaVu (кириллица поддерживается)')
    return paths


def font(weight, size):
    key = (weight, size)
    if key not in FONTS:
        FONTS[key] = ImageFont.truetype(ensure_fonts()[weight], size)
    return FONTS[key]


def tw(draw, text, weight, size):
    return draw.textlength(text, font=font(weight, size))


# ----------------------------------------------------------------------------- шкала задач
# t0/t1 — секунды ролика, когда задача начинается и заканчивается
TASKS = [
    dict(name='Первоначальная настройка ОС', t0=1.6, t1=3.6, tstart='12:41:03', tend='12:47:21',
         subs=['Настройки Edge', 'Панель задач и меню Пуск', 'Телеметрия', 'Макет профиля по умолчанию'],
         result='ok'),
    dict(name='Оптимизация и настройка ОС', t0=3.6, t1=5.6, tstart='12:47:21', tend='12:55:02',
         subs=['Удаление 33 встроенных приложений', 'OneDrive', 'Просмотр фотографий (DISM)', 'Файл подкачки'],
         result='ok'),
    dict(name='Установка системных компонентов', t0=5.6, t1=10.6, tstart='12:55:02', tend='13:07:44',
         subs=['Visual C++ 2015–2022', 'DirectX', '.NET Framework 3.5', '.NET 8.0', 'OpenAL'],
         result='ok'),
    dict(name='Установка софта', t0=10.6, t1=16.6, tstart='13:07:44', tend='13:21:10',
         subs=['Google Chrome', 'Steam', 'WinRAR', 'qBittorrent', 'ShareX', 'K-Lite Codec Pack'],
         result='warn', warn=['ShareX — установщик вернул код 1603',
                              'K-Lite Codec Pack — ссылка не отвечает']),
    dict(name='Установка и активация Microsoft Office', t0=17.4, t1=21.4, tstart='13:21:40', tend='13:34:55',
         subs=['Скачивание Office Deployment Tool', 'Установка Word, Excel, PowerPoint',
               'Привязка KMS', 'Активация'],
         result='ok'),
]
SUM_LABEL = '5'


def ease_out(t):
    return 1 - (1 - t) ** 3


def ease_io(t):
    return 3 * t * t - 2 * t * t * t


def clamp01(x):
    return max(0.0, min(1.0, x))


def task_state(task, t):
    """Состояние задачи в момент времени t: waiting | run | ok | warn"""
    if t < task['t0']:
        return 'waiting', 0.0
    if t < task['t1']:
        return 'run', (t - task['t0']) / (task['t1'] - task['t0'])
    return task['result'], 1.0


def overall_progress(t):
    """Общий процент: равные доли, внутри задачи — плавный ход."""
    n = len(TASKS)
    total = 0.0
    for task in TASKS:
        state, frac = task_state(task, t)
        if state == 'waiting':
            continue
        total += min(1.0, frac) / n
    return clamp01(total)


def clock(seconds):
    t = STAMP + int(seconds)
    return f'{(t // 3600) % 24:02d}:{(t // 60) % 60:02d}:{t % 60:02d}'


# ----------------------------------------------------------------------------- фон и подложка
def load_bg():
    bg = Image.open(BG_PATH).convert('RGB')
    return bg.resize((W, H), Image.LANCZOS)


def background_frame(bg, t):
    """Медленный наезд + лёгкая пульсация — фон живой, но не отвлекает."""
    zoom = 1.0 + 0.055 * ease_io(clamp01(t / DURATION))
    bw, bh = int(W * zoom), int(H * zoom)
    frame = bg.resize((bw, bh), Image.BILINEAR)
    left = (bw - W) // 2 + int(12 * math.sin(t * 0.25))
    top = (bh - H) // 2 + int(8 * math.cos(t * 0.21))
    return frame.crop((left, top, left + W, top + H))


def make_card(bg):
    """Стеклянная подложка: размытие фона под окном + затемнение + рамка + тень."""
    blurred = bg.filter(ImageFilter.GaussianBlur(46))
    region = blurred.crop((CARD_X, CARD_Y, CARD_X + CARD_W, CARD_Y + CARD_H))

    card = Image.new('RGBA', (CARD_W, CARD_H), (0, 0, 0, 0))
    glass = Image.blend(region.convert('RGB'), Image.new('RGB', region.size, C['card']), 0.80)
    mask = Image.new('L', (CARD_W, CARD_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, CARD_W - 1, CARD_H - 1], 30, fill=255)
    card.paste(glass, (0, 0), mask)

    # тонкая рамка + намёк на подсветку сверху
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, CARD_W - 1, CARD_H - 1], 30, outline=(255, 255, 255, 26), width=1)
    d.rounded_rectangle([1, 1, CARD_W - 2, CARD_H - 2], 29, outline=(255, 255, 255, 10), width=1)
    top_glow = Image.new('RGBA', (CARD_W, 120), (0, 0, 0, 0))
    gd = ImageDraw.Draw(top_glow)
    for i in range(120):
        gd.line([(0, i), (CARD_W, i)], fill=(255, 255, 255, int(16 * (1 - i / 120))))
    card.alpha_composite(top_glow, (0, 0))

    # тень
    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [CARD_X - 6, CARD_Y + 18, CARD_X + CARD_W + 6, CARD_Y + CARD_H + 34], 40, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(38))
    return card, shadow


# ----------------------------------------------------------------------------- рисование содержимого
def rounded_chip(d, box, text, color, bg_alpha=26, radius=16, size=16.5, pad_x=14):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius, fill=color + (bg_alpha,), outline=color + (70,), width=1)
    d.text(((x0 + x1) / 2, (y0 + y1) / 2 + 1), text, font=font('medium', size),
           fill=color, anchor='mm')


def draw_spinner(d, cx, cy, r, angle, color):
    d.arc([cx - r, cy - r, cx + r, cy + r], angle, angle + 250, fill=color, width=3)


def draw_state_icon(d, cx, cy, r, state, t):
    if state == 'waiting':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=C['dim'] + (150,), width=2)
    elif state == 'run':
        draw_spinner(d, cx, cy, r, (t * 360 * 1.5) % 360, C['run'])
    elif state == 'ok':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=C['ok'] + (235,))
        d.line([(cx - r * 0.45, cy + r * 0.05), (cx - r * 0.08, cy + r * 0.45),
                (cx + r * 0.5, cy - r * 0.42)], fill=(10, 12, 20, 255), width=3, joint='curve')
    elif state == 'warn':
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=C['warn'] + (235,))
        d.line([(cx, cy - r * 0.5), (cx, cy + r * 0.15)], fill=(10, 12, 20, 255), width=3)
        d.ellipse([cx - 1.6, cy + r * 0.42, cx + 1.6, cy + r * 0.42 + 3.2], fill=(10, 12, 20, 255))


def draw_content(t, banner_ease, card_reveal):
    """Содержимое окна с прозрачностью — композитится поверх подложки."""
    layer = Image.new('RGBA', (CARD_W, CARD_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # ---- шапка
    logo_box = [PAD, 44, PAD + 46, 90]
    d.rounded_rectangle(logo_box, 13, fill=None, outline=C['accent1'] + (120,), width=1)
    for i in range(46):                                   # градиентная заливка логотипа
        k = i / 46
        col = tuple(int(C['accent1'][j] * (1 - k) + C['accent2'][j] * k) for j in range(3))
        d.line([(PAD + i, 45), (PAD + i, 89)], fill=col + (255,))
    d.text((PAD + 23, 68), 'W', font=font('bold', 26), fill=(12, 14, 24, 255), anchor='mm')

    d.text((PAD + 62, 44), 'WAD — автоматическая установка Windows',
           font=font('semibold', 27), fill=C['text'] + (255,))
    d.text((PAD + 62, 80), 'Режим Clean · Windows 11 · запуск с GitHub',
           font=font('regular', 16.5), fill=C['muted'] + (255,))

    # ---- состояние справа
    prog = overall_progress(t)
    if t >= 17.2:
        pill_text, pill_col = 'Завершено с замечаниями', C['warn']
    elif t >= 16.9:
        pill_text, pill_col = 'Нужно внимание', C['warn']
    else:
        pill_text, pill_col = 'Идёт установка', C['run']
    pw = tw(d, pill_text, 'medium', 16.5) + 62
    px1, py0, py1 = INNER_R, 52, 92
    px0 = px1 - pw
    d.rounded_rectangle([px0, py0, px1, py1], 20, fill=pill_col + (26,), outline=pill_col + (90,), width=1)
    dot_r = 5 + (1.6 * math.sin(t * 4) if pill_col != C['warn'] else 0)
    d.ellipse([px0 + 18 - dot_r, 72 - dot_r, px0 + 18 + dot_r, 72 + dot_r], fill=pill_col + (255,))
    d.text((px0 + 34, 72), pill_text, font=font('medium', 16.5), fill=pill_col, anchor='lm')

    # ---- крупный процент и текущий шаг
    d.text((PAD, 108), f'{int(prog * 100)}%', font=font('extrabold', 76), fill=C['text'] + (255,))
    done = sum(1 for x in TASKS if task_state(x, t)[0] in ('ok', 'warn'))
    d.text((PAD, 196), f'{done} из {SUM_LABEL} задач',
           font=font('regular', 19), fill=C['muted'] + (255,))

    step_x = PAD + 290
    step_w = INNER_R - step_x
    current = None
    for task in TASKS:
        state, frac = task_state(task, t)
        if state == 'run':
            current = (task, frac)
            break
    if current:
        task, frac = current
        idx = min(len(task['subs']) - 1, int(frac * len(task['subs'])))
        step = f'{task["name"]} · {task["subs"][idx]}'
    else:
        step = 'Все задачи выполнены' if t > 21.6 else 'Подготовка…'
    while tw(d, step, 'regular', 19) > step_w and len(step) > 8:
        step = step[:-2]
    d.text((step_x, 120), step, font=font('regular', 19), fill=C['text'] + (230,))

    bar_y0, bar_y1 = 156, 168
    d.rounded_rectangle([step_x, bar_y0, INNER_R, bar_y1], 6, fill=(255, 255, 255, 22))
    fill_w = int(step_w * prog)
    if fill_w > 4:
        bar = Image.new('RGBA', (fill_w, bar_y1 - bar_y0), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        for i in range(fill_w):
            k = i / max(1, fill_w - 1)
            col = tuple(int(C['accent1'][j] * (1 - k) + C['accent2'][j] * k) for j in range(3))
            bd.line([(i, 0), (i, bar_y1 - bar_y0)], fill=col + (255,))
        # блик рисуем отдельным слоем и подмешиваем: ImageDraw на RGBA заменяет пиксели,
        # а не смешивает их — иначе в полосе прорезается дырка
        sheen = Image.new('RGBA', bar.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sheen)
        sheen_x = int(((t * 0.35) % 1.0) * (fill_w + 220)) - 110
        for i in range(220):
            x = sheen_x + i
            if 0 <= x < fill_w:
                a = int(90 * math.sin(math.pi * i / 220))
                sd.line([(x, 0), (x, bar_y1 - bar_y0)], fill=(255, 255, 255, a))
        bar.alpha_composite(sheen)
        layer.alpha_composite(bar, (step_x, bar_y0))
    elapsed = int(prog * 54)
    if prog >= 0.999:
        rest = f'Всего заняло {elapsed} мин'
    else:
        rest = f'Прошло {elapsed} мин · осталось примерно {max(1, int((1 - prog) * 48))} мин'
    d.text((INNER_R, 180), rest, font=font('regular', 16), fill=C['dim'] + (255,), anchor='ra')

    # ---- баннер предупреждения
    if banner_ease > 0.01:
        by = 544 + int((1 - banner_ease) * 14)
        bh = 80
        box = [PAD, by, INNER_R, by + bh]
        d.rounded_rectangle(box, 14, fill=C['warn'] + (30,), outline=C['warn'] + (110,), width=1)
        d.rounded_rectangle([PAD, by, PAD + 4, by + bh], 2, fill=C['warn'] + (255,))
        draw_state_icon(d, PAD + 34, by + bh / 2, 13, 'warn', t)
        d.text((PAD + 62, by + 20), 'Установка софта завершилась с замечаниями: 2 программы не установились',
               font=font('semibold', 19), fill=C['text'] + (255,))
        d.text((PAD + 62, by + 48), ' · '.join(TASKS[3]['warn']),
               font=font('regular', 16.5), fill=C['warn'] + (240,))
        bx1 = INNER_R - 20
        d.text((bx1, by + bh / 2), 'Открыть журнал', font=font('medium', 16.5), fill=C['warn'], anchor='rm')

    # ---- список задач
    tasks_y = 234
    row_h, gap = 54, 6
    for i, task in enumerate(TASKS):
        state, frac = task_state(task, t)
        ry = tasks_y + i * (row_h + gap)
        appear = clamp01((t - 0.9 - i * 0.09) / 0.45)
        if appear <= 0:
            continue
        rise = int((1 - ease_out(appear)) * 14)
        alpha = int(255 * ease_out(appear))
        # фон строки: активная подсвечена
        box = [PAD, ry + rise, INNER_R, ry + row_h + rise]
        if state == 'run':
            d.rounded_rectangle(box, 12, fill=C['accent1'] + (24,), outline=C['accent1'] + (70,), width=1)
        else:
            d.rounded_rectangle(box, 12, fill=(255, 255, 255, 8))
        draw_state_icon(d, PAD + 30, ry + row_h / 2 + rise, 12, state, t)
        name_col = C['text'] if state != 'waiting' else C['muted']
        d.text((PAD + 58, ry + row_h / 2 + rise), task['name'], font=font('medium', 21),
               fill=name_col + (alpha,), anchor='lm')
        if state == 'run':
            chip, chip_col = 'идёт', C['run']
        elif state == 'ok':
            chip, chip_col = f'готово · {task["tend"][:5]}', C['ok']
        elif state == 'warn':
            chip, chip_col = f'замечания · {task["tend"][:5]}', C['warn']
        elif state == 'run':
            chip, chip_col = f'идёт · с {task["tstart"][:5]}', C['run']
        else:
            chip, chip_col = 'ждёт', C['dim']
        cw = tw(d, chip, 'medium', 16.5) + 30
        rounded_chip(d, [INNER_R - 18 - cw, ry + 14 + rise, INNER_R - 18, ry + row_h - 14 + rise],
                     chip, chip_col, bg_alpha=22)

    # ---- низ окна
    d.text((PAD, 660), 'Окно можно свернуть — установка продолжится', font=font('regular', 16.5),
           fill=C['dim'] + (255,))
    final = t >= 17.2
    b2 = 'Перезагрузить компьютер' if final else 'Свернуть в фон'
    b2w = tw(d, b2, 'semibold', 17) + 52
    b2_box = [INNER_R - b2w, 640, INNER_R, 682]
    d.rounded_rectangle(b2_box, 12, fill=C['accent1'] + (235,))
    d.text(((b2_box[0] + b2_box[2]) / 2, 662), b2, font=font('semibold', 17), fill=(12, 14, 24, 255), anchor='mm')
    b1 = 'Открыть журнал'
    b1w = tw(d, b1, 'medium', 17) + 48
    b1_box = [b2_box[0] - 14 - b1w, 640, b2_box[0] - 14, 682]
    d.rounded_rectangle(b1_box, 12, outline=(255, 255, 255, 46), width=1, fill=(255, 255, 255, 14))
    d.text(((b1_box[0] + b1_box[2]) / 2, 662), b1, font=font('medium', 17), fill=C['text'] + (235,), anchor='mm')

    # проявление окна целиком
    if card_reveal < 0.999:
        layer.putalpha(layer.getchannel('A').point(lambda v: int(v * card_reveal)))
    return layer


# ----------------------------------------------------------------------------- сборка кадра
def render_frame(bg, card, shadow, t):
    frame = background_frame(bg, t).convert('RGBA')

    # появление окна: масштаб и прозрачность
    reveal = ease_out(clamp01(t / 0.9))
    banner_ease = ease_io(clamp01((t - 16.6) / 0.5))

    shadow_layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    shadow_layer.putalpha(shadow.point(lambda v: int(v * reveal)))
    frame.alpha_composite(shadow_layer)

    card_layer = card.copy()
    if reveal < 0.999:
        s = 0.965 + 0.035 * reveal
        nw, nh = int(CARD_W * s), int(CARD_H * s)
        card_layer = card_layer.resize((nw, nh), Image.LANCZOS)
    content = draw_content(t, banner_ease, reveal)
    if reveal < 0.999:
        content = content.resize(card_layer.size, Image.LANCZOS)
    card_layer.alpha_composite(content)
    frame.alpha_composite(card_layer, (CARD_X + (CARD_W - card_layer.width) // 2,
                                       CARD_Y + (CARD_H - card_layer.height) // 2))

    # общее затемнение в начале и в конце
    fade = min(clamp01(t / 0.7), clamp01((DURATION - t) / 0.9))
    if fade < 0.999:
        black = Image.new('RGBA', (W, H), (0, 0, 0, int(255 * (1 - fade))))
        frame.alpha_composite(black)
    return frame.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--still', type=float, default=None, help='нарисовать один кадр на этой секунде')
    ap.add_argument('--fps', type=int, default=FPS)
    ap.add_argument('--duration', type=float, default=DURATION)
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    if not os.path.exists(BG_PATH):
        sys.exit(f'нет фона: {BG_PATH}. Сначала make_wallpapers.py')

    print('подготовка фона и подложки…')
    bg = load_bg()
    card, shadow = make_card(bg)

    if args.still is not None:
        p = os.path.join(OUT_DIR, f'still-{args.still:g}s.png')
        render_frame(bg, card, shadow, args.still).save(p)
        print(f'  {p}')
        return

    ffmpeg = None
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        pass
    if not ffmpeg:
        sys.exit('нет ffmpeg (pip install imageio-ffmpeg)')
    out = os.path.join(OUT_DIR, 'wad-demo.mp4')
    cmd = [ffmpeg, '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
           '-r', str(args.fps), '-i', '-', '-c:v', 'libx264', '-preset', 'medium',
           '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    total = int(args.duration * args.fps)
    print(f'рендер {total} кадров ({args.duration:g} с, {args.fps} к/с)…')
    for i in range(total):
        t = i / args.fps
        proc.stdin.write(render_frame(bg, card, shadow, t).tobytes())
        if i % 60 == 0:
            print(f'  {i}/{total}')
    proc.stdin.close()
    err = proc.stderr.read().decode('utf-8', 'ignore')
    code = proc.wait()
    if code != 0:
        print(err[-2000:])
        sys.exit(f'ffmpeg вернул {code}')
    print(f'  {out} — {os.path.getsize(out) // 1024} КБ')

    render_frame(bg, card, shadow, 21.0).save(os.path.join(OUT_DIR, 'poster.png'))
    print('  poster.png')


if __name__ == '__main__':
    main()
