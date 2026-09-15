# -*- coding: utf-8 -*-
"""Демо-ролик UI_Update (WAD V.2).

Сценарий по утверждённому чек-листу:
  1. Интро из видео («Здравствуйте» → … → «Приступаем») на размытом фоне.
  2. Без обзора задач и QR-экрана: сразу главное рабочее окно (светлый Fluent).
  3. В окне — 4 ключевые категории со статусами (спиннер / ✓ / !), в шапке кнопка
     «Сайт разработчика» с микро-попапом.
  4. Двухрежимный нижний бар: процент установки → на 100% плавно становится
     таймером «Перезагрузка через X сек»; рядом «Свернуть в фон».
  5. После перезагрузки — автоматически открытый HTML-отчёт (dashboard) с
     промо-кнопкой «Сайт разработчика».

Переиспользует помощников из make_wad_flow.py (шрифты, палитра, обои, Mica, тень).
"""
import os
import sys
import math
import argparse
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import make_wad_flow as B
from PIL import ImageDraw as _ID

W, H = B.W, B.H
FPS = B.FPS
WIN_W, WIN_H = B.WIN_W, B.WIN_H
WIN_X, WIN_Y = B.WIN_X, B.WIN_Y
RADIUS, TITLE_H, PAD = B.RADIUS, B.TITLE_H, B.PAD
C = B.C
rgba = B.rgba
rrect = B.rrect
font = B.font
tw = B.tw
ease_io = B.ease_io
ease_out = B.ease_out

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.normpath(os.path.join(HERE, '..')), 'demo')

# ---------------------------------------------------------------- хронология
T_TEXT_END = 16.95
T_WIN_APPEAR = 17.70
T_START = 19.30
INSTALL_LEN = 22.0
T_DONE = T_START + INSTALL_LEN            # 41.30
T_COUNTDOWN = T_DONE + 1.2                # 42.50 — бар становится таймером
COUNTDOWN_LEN = 4.5
COUNTDOWN_REAL = 60
T_RESTART = T_COUNTDOWN + COUNTDOWN_LEN   # 47.00
T_FADE = 1.6
T_REPORT = T_RESTART + T_FADE + 1.2       # 49.80 — после входа открылся отчёт
T_END = T_REPORT + 8.2                    # 58.00

POP_T0, POP_T1 = 24.0, 28.5               # микро-попап «Сайт разработчика»

# 4 ключевые категории (как в Stable 1.3): имя, начало, конец (локальное время)
ROWS = [
    ('Оптимизация и настройка ОС', 0.0, 5.0),
    ('Установка системных компонентов', 5.0, 10.0),
    ('Установка софта', 10.0, 17.0),
    ('Установка и активация Microsoft Office', 17.0, 22.0),
]
WARN_APPS = 'ShareX · K-Lite Codec Pack'


def row_state(i, tl):
    name, t0, t1 = ROWS[i]
    if tl < t0:
        return 'wait', 0.0
    if tl < t1:
        return 'run', (tl - t0) / (t1 - t0)
    return ('warn' if i == 2 else 'ok'), 1.0


def overall(tl):
    tot = 0.0
    for i, (name, t0, t1) in enumerate(ROWS):
        tot += max(0.0, min(1.0, (tl - t0) / (t1 - t0))) * ((t1 - t0) / INSTALL_LEN)
    return max(0.0, min(1.0, tot))


# ---------------------------------------------------------------- шапка + кнопка сайта
def draw_site_button(layer, d, t, pressed):
    """Кнопка «Сайт разработчика» в шапке, слева от системных значков."""
    cyy = 26 + 14
    bw = tw('Сайт разработчика', 'medium', 14) + 46
    bx1 = WIN_W - PAD - 100
    bx0 = bx1 - bw
    layer.alpha_composite(rrect((WIN_W, WIN_H), [bx0, cyy - 16, bx1, cyy + 16], 16,
                                fill=C['accent'] + (26 if not pressed else 60,),
                                outline=C['accent'] + (90,)))
    # компактный знак GitHub: круглое «тело» с ушками
    gx, gy = bx0 + 17, cyy
    d.ellipse([gx - 7, gy - 7, gx + 7, gy + 7], fill=C['accent'] + (255,))
    d.polygon([(gx - 6, gy - 5), (gx - 2, gy - 8), (gx - 1, gy - 4)], fill=C['accent'] + (255,))
    d.polygon([(gx + 6, gy - 5), (gx + 2, gy - 8), (gx + 1, gy - 4)], fill=C['accent'] + (255,))
    d.ellipse([gx - 3, gy - 1, gx + 3, gy + 5], fill=(255, 255, 255, 235))
    d.text((bx0 + 32, cyy), 'Сайт разработчика', font=font('medium', 14),
           fill=C['accent'] + (255,), anchor='lm')
    return bx0, cyy


def draw_popup(layer, t):
    """Микро-попап у кнопки сайта: пара слов + ссылка, без простыней."""
    if not (POP_T0 <= t <= POP_T1):
        return
    a = ease_out(min(1.0, (t - POP_T0) / 0.35)) * (1 - ease_io(max(0.0, min(1.0, (t - (POP_T1 - 0.4)) / 0.4))))
    if a <= 0.01:
        return
    pw, ph = 360, 132
    px, py = WIN_W - PAD - 100 - pw + 60, 60
    pop = rgba((pw, ph))
    pd = ImageDraw.Draw(pop)
    pop.alpha_composite(rrect((pw, ph), [0, 0, pw - 1, ph - 1], 12, fill=(255, 255, 255, 250),
                              outline=(0, 0, 0, 30)))
    pd.text((20, 24), 'Репозиторий проекта на GitHub', font=font('semibold', 17), fill=C['text'] + (255,))
    pd.text((20, 50), 'Исходный код и обновления', font=font('regular', 14), fill=C['text3'] + (255,))
    pop.alpha_composite(rrect((pw, ph), [20, ph - 52, 20 + tw('Открыть в браузере', 'semibold', 15) + 40, ph - 18], 8,
                              fill=C['accent'] + (255,)), (0, 0))
    pd.text((20 + 14, ph - 35), 'Открыть в браузере', font=font('semibold', 15),
            fill=(255, 255, 255, 255), anchor='lm')
    pop.putalpha(pop.getchannel('A').point(lambda v: int(v * a)))
    layer.alpha_composite(pop, (int(px), int(py + 8 * (1 - a))))


# ---------------------------------------------------------------- главное окно
def scene_main(wallpaper, mica, shadow, t):
    tl = t - T_START
    appear = ease_out(max(0.0, min(1.0, (t - T_WIN_APPEAR) / (T_START - T_WIN_APPEAR))))

    frame = wallpaper.copy().convert('RGBA')
    sh = rgba((W, H))
    sh.putalpha(shadow.point(lambda v: int(v * appear)))
    frame.alpha_composite(sh)

    card = mica.copy()
    content = rgba((WIN_W, WIN_H))
    d = ImageDraw.Draw(content)
    B.draw_window_chrome(content, d, 'установка Windows', t)
    sbx, sby = draw_site_button(content, d, t, POP_T0 <= t <= POP_T1)

    x = PAD
    y = TITLE_H + 46
    d.text((x, y), 'Менеджер автоматической настройки', font=font('semibold', 30), fill=C['text'] + (255,))

    # ---- 4 категории со статусами
    ry = y + 64
    rh = 74
    for i, (name, t0, t1) in enumerate(ROWS):
        st, frac = row_state(i, tl)
        e = ease_out(max(0.0, min(1.0, (appear - 0.10 - i * 0.06) / 0.5)))
        if e <= 0.01:
            continue
        yy = ry + i * (rh + 12)
        content.alpha_composite(rrect((WIN_W, WIN_H), [x, yy, WIN_W - PAD, yy + rh], 10,
                                      fill=(255, 255, 255, int(150 * e)), outline=(0, 0, 0, int(16 * e))))
        # иконка статуса
        ix, iy = x + 34, yy + rh / 2
        if st == 'wait':
            d.ellipse([ix - 9, iy - 9, ix + 9, iy + 9], outline=C['text3'] + (int(120 * e),), width=2)
        elif st == 'run':
            ang = (t * 4.0) % 6.283
            for k in range(8):
                a2 = ang + k * 6.283 / 8
                al = int((40 + 200 * (k / 8)) * e)
                d.line([(ix + 6 * math.cos(a2), iy + 6 * math.sin(a2)),
                        (ix + 10 * math.cos(a2), iy + 10 * math.sin(a2))],
                       fill=C['accent'] + (al,), width=2)
        elif st == 'ok':
            d.ellipse([ix - 11, iy - 11, ix + 11, iy + 11], fill=C['ok'] + (int(255 * e),))
            d.line([(ix - 5, iy), (ix - 1, iy + 5), (ix + 6, iy - 5)], fill=(255, 255, 255, int(255 * e)), width=2, joint='curve')
        else:  # warn
            d.ellipse([ix - 11, iy - 11, ix + 11, iy + 11], fill=C['warn'] + (int(255 * e),))
            d.text((ix, iy + 1), '!', font=font('bold', 15), fill=(255, 255, 255, int(255 * e)), anchor='mm')
        d.text((x + 66, yy + rh / 2 - 11), name, font=font('semibold', 18), fill=C['text'] + (int(255 * e),))
        if st == 'run':
            d.text((x + 66, yy + rh / 2 + 14), 'выполняется…', font=font('regular', 14), fill=C['text3'] + (int(235 * e),))
        elif st == 'ok':
            d.text((x + 66, yy + rh / 2 + 14), 'готово', font=font('regular', 14), fill=C['ok'] + (int(235 * e),))
        elif st == 'warn':
            d.text((x + 66, yy + rh / 2 + 14), 'готово с замечаниями', font=font('regular', 14), fill=C['warn'] + (int(235 * e),))
        else:
            d.text((x + 66, yy + rh / 2 + 14), 'ожидание', font=font('regular', 14), fill=C['text3'] + (int(200 * e),))
        # время справа
        if st in ('ok', 'warn'):
            d.text((WIN_W - PAD - 24, yy + rh / 2), f'[{(12 + i * 7) % 24:02d}:{30 + i * 9:02d}]',
                   font=font('regular', 14), fill=C['text3'] + (int(220 * e),), anchor='rm')

    # ---- двухрежимный нижний бар
    by = WIN_H - PAD - 46
    cd0 = T_COUNTDOWN - T_START
    if tl >= cd0:
        k = min(1.0, (tl - cd0) / COUNTDOWN_LEN)
        left = int(math.ceil(COUNTDOWN_REAL * (1 - k)))
        cap = f'Перезагрузка через {left} сек' if left > 0 else 'Перезагрузка…'
        d.text((x, by - 26), cap, font=font('semibold', 17), fill=C['text'] + (255,))
        d.text((WIN_W - PAD - 200, by - 26), 'можно ничего не нажимать', font=font('regular', 13.5),
               fill=C['text3'] + (220,), anchor='ra')
        content.alpha_composite(rrect((WIN_W, WIN_H), [x, by, WIN_W - PAD - 190, by + 10], 5, fill=(0, 0, 0, 22)))
        fw = (WIN_W - PAD - 190 - x) * k
        if fw > 2:
            content.alpha_composite(rrect((WIN_W, WIN_H), [x, by, x + fw, by + 10], 5, fill=C['accent'] + (255,)))
    else:
        pr = overall(tl)
        d.text((x, by - 26), 'Установка…', font=font('semibold', 17), fill=C['text'] + (255,))
        d.text((WIN_W - PAD - 200, by - 30), f'{int(pr * 100)}%', font=font('bold', 30), fill=C['accent'] + (255,), anchor='ra')
        content.alpha_composite(rrect((WIN_W, WIN_H), [x, by, WIN_W - PAD - 190, by + 10], 5, fill=(0, 0, 0, 22)))
        fw = (WIN_W - PAD - 190 - x) * pr
        if fw > 2:
            content.alpha_composite(rrect((WIN_W, WIN_H), [x, by, x + fw, by + 10], 5, fill=C['accent'] + (255,)))

    # кнопка «Свернуть в фон»
    label = 'Свернуть в фон'
    bw = tw(label, 'semibold', 15) + 44
    content.alpha_composite(rrect((WIN_W, WIN_H), [WIN_W - PAD - bw, by - 8, WIN_W - PAD, by + 34], 8,
                                fill=C['accent'] + (255,)))
    d.text((WIN_W - PAD - bw / 2, by + 13), label, font=font('semibold', 15), fill=(255, 255, 255, 255), anchor='mm')

    draw_popup(content, t)

    if appear < 0.999:
        content.putalpha(content.getchannel('A').point(lambda v: int(v * appear)))
        card.putalpha(card.getchannel('A').point(lambda v: int(v * appear)))
    card.alpha_composite(content)
    frame.alpha_composite(card, (WIN_X, WIN_Y))
    return frame


# ---------------------------------------------------------------- отчёт после входа
def scene_report(wallpaper, mica, shadow, t):
    a = ease_out(max(0.0, min(1.0, (t - T_REPORT) / 0.7)))
    if a <= 0.01:
        return wallpaper.copy().convert('RGBA')
    frame = wallpaper.copy().convert('RGBA')
    sh = rgba((W, H))
    sh.putalpha(shadow.point(lambda v: int(v * a)))
    frame.alpha_composite(sh)

    RW, RH = 1280, 800
    RX, RY = (W - RW) // 2, (H - RH) // 2
    card = Image.new('RGBA', (RW, RH), (0, 0, 0, 0))
    card.paste(Image.new('RGB', (RW, RH), (252, 253, 255)), (0, 0), B.mask_rrect((RW, RH), RADIUS))
    content = rgba((RW, RH))
    d = ImageDraw.Draw(content)

    # шапка браузера
    d.text((28, 26), 'WAD — отчёт об установке', font=font('semibold', 16), fill=C['text2'] + (255,))
    d.line([(0, 56), (RW, 56)], fill=(0, 0, 0, 20), width=1)
    d.text((28, 40), 'C:\\Users\\User\\Documents\\WAD_Report.html', font=font('regular', 13), fill=C['text3'] + (255,))

    x = 40
    y = 92
    d.text((x, y), 'Всё готово', font=font('semibold', 34), fill=C['text'] + (255,))
    d.text((x, y + 46), 'Установка завершена 14.09.2026 · 4 категории · 2 замечания', font=font('regular', 16), fill=C['text2'] + (255,))

    # промо-банер «Сайт разработчика»
    content.alpha_composite(rrect((RW, RH), [RW - 340, y, RW - 40, y + 64], 10, fill=C['accent'] + (255,)))
    d.text(((RW - 340 + RW - 40) / 2, y + 32), 'Сайт разработчика', font=font('semibold', 18),
           fill=(255, 255, 255, 255), anchor='mm')

    # карточки статусов по категориям
    cy = y + 110
    cw = (RW - 80 - 3 * 20) / 4
    for i, (name, t0, t1) in enumerate(ROWS):
        st = 'warn' if i == 2 else 'ok'
        bx = x + i * (cw + 20)
        content.alpha_composite(rrect((RW, RH), [bx, cy, bx + cw, cy + 130], 10,
                                      fill=(255, 255, 255, 200), outline=(0, 0, 0, 16)))
        col = C['warn'] if st == 'warn' else C['ok']
        d.ellipse([bx + 20, cy + 20, bx + 44, cy + 44], fill=col + (255,))
        if st == 'ok':
            d.line([(bx + 26, cy + 32), (bx + 31, cy + 38), (bx + 39, cy + 26)], fill=(255, 255, 255, 255), width=2, joint='curve')
        else:
            d.text((bx + 32, cy + 33), '!', font=font('bold', 15), fill=(255, 255, 255, 255), anchor='mm')
        short = ['Оптимизация ОС', 'Системные компоненты', 'Софт', 'Microsoft Office'][i]
        d.text((bx + 20, cy + 62), short, font=font('semibold', 16), fill=C['text'] + (255,))
        d.text((bx + 20, cy + 88), ('замечания' if st == 'warn' else 'готово'), font=font('regular', 14), fill=col + (255,))

    # детализация замечаний
    ey = cy + 160
    content.alpha_composite(rrect((RW, RH), [x, ey, RW - 40, ey + 92], 10,
                                  fill=(255, 249, 240, 235), outline=C['warn'] + (120,)))
    d.rectangle([x, ey + 12, x + 3, ey + 80], fill=C['warn'] + (255,))
    d.text((x + 24, ey + 16), 'Установилось не всё: 2 программы', font=font('semibold', 16), fill=C['text'] + (255,))
    d.text((x + 24, ey + 44), WARN_APPS, font=font('regular', 15), fill=C['warn'] + (255,))
    d.text((x + 24, ey + 66), 'Подробности — в журнале установки в папке «Документы»', font=font('regular', 13.5), fill=C['text2'] + (255,))

    content.putalpha(content.getchannel('A').point(lambda v: int(v * a)))
    card.alpha_composite(content)
    frame.alpha_composite(card, (RX, RY + int(20 * (1 - a))))
    return frame


# ---------------------------------------------------------------- сборка кадра
def render_frame(wp, mica, shadow, t):
    wallpaper = B.wallpaper_at(wp, t)

    if t < T_TEXT_END:
        frame, layer = B.scene_text(wallpaper, t)
        frame.alpha_composite(layer)
        return frame.convert('RGB')

    if t < T_RESTART:
        return scene_main(wallpaper, mica, shadow, t).convert('RGB')

    # окно растворяется, проступает «Перезагрузка», затем после входа — отчёт
    k = ease_io(min(1.0, (t - T_RESTART) / T_FADE))
    main = scene_main(wallpaper, mica, shadow, min(t, T_RESTART)).convert('RGBA')
    frame = Image.blend(main, wallpaper.convert('RGBA'), k).convert('RGBA')

    # надпись «Перезагрузка» (видна между растворением и отчётом)
    ra = ease_out(max(0.0, min(1.0, (t - (T_RESTART + 0.5)) / 0.7))) * (1 - ease_io(max(0.0, min(1.0, (t - (T_REPORT - 0.2)) / 0.5))))
    if ra > 0.01:
        layer = rgba((W, H))
        d = ImageDraw.Draw(layer)
        d.text((W / 2, H / 2 - 20), 'Перезагрузка', font=font('semibold', 88), fill=C['text'] + (int(255 * ra),), anchor='mm')
        d.text((W / 2, H / 2 + 66), 'WAD завершает настройку — компьютер включится снова сам',
               font=font('regular', 21), fill=C['text2'] + (int(255 * ra),), anchor='mm')
        frame.alpha_composite(layer)

    rep = scene_report(wallpaper, mica, shadow, t)
    frame = Image.composite(rep, frame, rep)
    return frame.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--still', type=float)
    ap.add_argument('--fps', type=int, default=FPS)
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    B.ensure_fonts()
    print('рисую обои…')
    wp = B.build_wallpaper_layers()
    wallpaper = B.compose_wallpaper(wp, 0.0)
    wallpaper.save(os.path.join(OUT_DIR, 'wallpaper-win11.png'))
    mica = B.build_mica(wallpaper)
    shadow = B.build_shadow()

    if args.still is not None:
        p = os.path.join(OUT_DIR, f'v2-{args.still:g}s.png')
        render_frame(wp, mica, shadow, args.still).save(p)
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
        proc.stdin.write(render_frame(wp, mica, shadow, i / args.fps).tobytes())
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
