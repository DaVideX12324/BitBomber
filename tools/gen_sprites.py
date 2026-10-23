"""Generator grafiki BitBombera (Pillow): kafle motywów map, postacie, bomba, ogień, power-upy.

Użycie:  python tools/gen_sprites.py [resources/sprites]
Wszystko rysowane w SS× rozdzielczości i zmniejszane (antyaliasing). Deterministyczne (stały seed),
więc ponowne uruchomienie daje te same pliki.

Wyjście (64×64 na pole, jak GRID_SIZE):
  tiles/<motyw>/{floor,floor_alt,block,wall,center,box}.png
  players/player_<1-4>.png        — arkusz 3 kolumny (stoi, krok A, krok B) × 4 wiersze (dół, lewo, prawo, góra)
  objects/bomb.png, objects/explosion_{center,arm,end}.png (ramię poziomo, koniec w prawo)
  objects/powerup_<typ>.png
  ui/*.png                         — 9-patch panele, przyciski, pola i pasek (motyw resources/ui/bb_theme.tres)
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

T = 64        # rozmiar pola w grze
SS = 4        # nadpróbkowanie
S = T * SS

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "resources", "sprites")


# ---------------------------------------------------------------------------
# Pomocnicze
# ---------------------------------------------------------------------------

class Draw:
    """ImageDraw z mieszaniem alfy: każdy kształt rysowany na osobnej warstwie i nakładany
    alpha_composite (ImageDraw na RGBA podmienia piksele — półprzezroczysty odblask robił dziury)."""

    def __init__(self, im):
        self.im = im

    def __getattr__(self, name):
        def call(*args, **kwargs):
            layer = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
            result = getattr(ImageDraw.Draw(layer), name)(*args, **kwargs)
            self.im.alpha_composite(layer)
            return result
        return call


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f, a=None):
    """f > 1 rozjaśnia (w stronę bieli), f < 1 przyciemnia."""
    r, g, b = c[:3]
    if f >= 1:
        k = f - 1
        r, g, b = r + (255 - r) * k, g + (255 - g) * k, b + (255 - b) * k
    else:
        r, g, b = r * f, g * f, b * f
    return (int(max(0, min(255, r))), int(max(0, min(255, g))), int(max(0, min(255, b))), c[3] if a is None else a)


def canvas(size=S):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def save(img, rel, size=T):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if img.size[0] != size:
        img = img.resize((size * img.size[0] // img.size[0] if img.size[0] == img.size[1] else img.size[0] // SS,
                          size if img.size[0] == img.size[1] else img.size[1] // SS), Image.LANCZOS)
    img.save(path)


def down(img):
    return img.resize((img.size[0] // SS, img.size[1] // SS), Image.LANCZOS)


def vgrad(size, top, bottom):
    """Pionowy gradient RGBA (numpy)."""
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, float)[None, None, :]
    b = np.array(bottom, float)[None, None, :]
    arr = (a * (1 - t) + b * t).repeat(w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def radial(size, center, radius, inner, outer):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    d = np.clip(d, 0, 1)[:, :, None]
    a = np.array(inner, float)[None, None, :]
    b = np.array(outer, float)[None, None, :]
    return Image.fromarray((a * (1 - d) + b * d).astype(np.uint8), "RGBA")


def mask_rr(size, box, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, r, fill=255)
    return m


def paste_masked(dst, src, mask):
    dst.alpha_composite(Image.composite(src, Image.new("RGBA", src.size, (0, 0, 0, 0)), mask))


def noise_layer(rng, color_a, color_b, count, rmin, rmax, size=S, alpha=60):
    img = canvas(size)
    d = Draw(img)
    for _ in range(count):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        r = rng.uniform(rmin, rmax)
        c = color_a if rng.random() < 0.5 else color_b
        d.ellipse((x - r, y - r, x + r, y + r), fill=(c[0], c[1], c[2], alpha))
    return img


def soft_shadow(img, box, alpha=90, blur=6):
    sh = canvas(img.size[0])
    Draw(sh).ellipse(box, fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur * SS / 2))
    img.alpha_composite(sh)


# ---------------------------------------------------------------------------
# Podłogi
# ---------------------------------------------------------------------------

def floor_tile(style, base, rng, alt=False):
    c = shade(base, 0.94) if alt else base
    img = Image.new("RGBA", (S, S), c)
    d = Draw(img)
    if style == "checker":
        img.alpha_composite(noise_layer(rng, shade(c, 1.15), shade(c, 0.85), 90, 2, 6, alpha=35))
    elif style == "grass":
        img.alpha_composite(noise_layer(rng, shade(c, 1.2), shade(c, 0.8), 120, 3, 9, alpha=45))
        for _ in range(26):
            x, y = rng.uniform(8, S - 8), rng.uniform(14, S - 4)
            h = rng.uniform(12, 26)
            lean = rng.uniform(-6, 6)
            col = shade(c, rng.choice([0.75, 1.25, 1.35]))
            d.line([(x, y), (x + lean, y - h)], fill=col, width=5)
            d.line([(x + 6, y), (x + 6 + lean * 0.5, y - h * 0.7)], fill=col, width=5)
        if rng.random() < 0.35:   # kwiatek
            x, y = rng.uniform(40, S - 40), rng.uniform(40, S - 40)
            fc = rng.choice([hexc("#ffe66d"), hexc("#ffffff"), hexc("#ff8fab")])
            for k in range(5):
                a = k * 2 * math.pi / 5
                d.ellipse((x + math.cos(a) * 9 - 7, y + math.sin(a) * 9 - 7, x + math.cos(a) * 9 + 7, y + math.sin(a) * 9 + 7), fill=fc)
            d.ellipse((x - 6, y - 6, x + 6, y + 6), fill=hexc("#f4a261"))
    elif style == "planks":
        n = 4
        ph = S / n
        for i in range(n):
            pc = shade(c, [1.0, 0.92, 1.05, 0.96][(i + (1 if alt else 0)) % 4])
            d.rectangle((0, i * ph, S, (i + 1) * ph), fill=pc)
            for _ in range(5):
                y = i * ph + rng.uniform(8, ph - 8)
                d.line([(rng.uniform(0, 60), y), (rng.uniform(S - 80, S), y + rng.uniform(-4, 4))], fill=shade(pc, 0.85), width=3)
            d.line([(0, (i + 1) * ph - 2), (S, (i + 1) * ph - 2)], fill=shade(c, 0.6), width=5)
            jx = rng.uniform(40, S - 40)
            d.line([(jx, i * ph), (jx, (i + 1) * ph)], fill=shade(c, 0.65), width=4)
    elif style == "snow":
        img.alpha_composite(noise_layer(rng, shade(c, 0.93), hexc("#ffffff"), 60, 6, 18, alpha=70))
        for _ in range(10):
            x, y = rng.uniform(6, S - 6), rng.uniform(6, S - 6)
            d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 255, 255, 230))
    elif style == "sand":
        img.alpha_composite(noise_layer(rng, shade(c, 1.12), shade(c, 0.86), 220, 1.5, 4, alpha=80))
        for _ in range(2):
            y = rng.uniform(40, S - 40)
            d.arc((rng.uniform(-60, 40), y - 30, rng.uniform(S - 40, S + 60), y + 30), 200, 340, fill=shade(c, 0.88), width=4)
    elif style == "asphalt":
        img.alpha_composite(noise_layer(rng, shade(c, 1.35), shade(c, 0.7), 260, 1.5, 3.5, alpha=90))
        if alt:
            d.rectangle((S / 2 - 6, 30, S / 2 + 6, S - 30), fill=(235, 235, 220, 200))
    elif style == "tiles":
        img.alpha_composite(noise_layer(rng, shade(c, 1.05), shade(c, 0.95), 40, 10, 30, alpha=40))
        for k in (0, S / 2):
            d.line([(k, 0), (k, S)], fill=shade(c, 0.8), width=5)
            d.line([(0, k), (S, k)], fill=shade(c, 0.8), width=5)
        d.line([(8, 8), (S / 2 - 16, 8)], fill=shade(c, 1.25), width=4)
        d.line([(S / 2 + 8, S / 2 + 8), (S - 16, S / 2 + 8)], fill=shade(c, 1.25), width=4)
    elif style == "carpet":
        dot = shade(c, 1.35) if not alt else hexc("#ffd166")
        for gy in range(4):
            for gx in range(4):
                x, y = gx * S / 4 + S / 8, gy * S / 4 + S / 8
                if (gx + gy) % 2 == 0:
                    d.regular_polygon((x, y, 10), 4, rotation=45, fill=dot)
                else:
                    d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=shade(c, 0.8))
    elif style == "dirt":
        img.alpha_composite(noise_layer(rng, shade(c, 1.18), shade(c, 0.78), 160, 2, 7, alpha=70))
        for _ in range(4):
            x, y = rng.uniform(20, S - 20), rng.uniform(20, S - 20)
            d.ellipse((x - 7, y - 5, x + 7, y + 5), fill=shade(c, 0.7))
            d.ellipse((x - 5, y - 5, x + 3, y), fill=shade(c, 1.2))
    # Delikatna fuga między polami
    d.rectangle((0, 0, S - 1, S - 1), outline=shade(c, 0.86), width=3)
    return down(img)


# ---------------------------------------------------------------------------
# Bloki (wypukłe: lico na górze, bok na dole)
# ---------------------------------------------------------------------------

SIDE = 14 * SS // 4 * 4    # wysokość boku bloku


def raised_block(top_color, side_color, radius=10):
    img = canvas()
    m_side = mask_rr((S, S), (2, 2, S - 3, S - 3), radius * SS // 4 * 4)
    paste_masked(img, vgrad((S, S), shade(side_color, 1.05), shade(side_color, 0.7)), m_side)
    top_box = (2, 2, S - 3, S - 3 - SIDE)
    m_top = mask_rr((S, S), top_box, radius * SS // 4 * 4)
    paste_masked(img, vgrad((S, S), shade(top_color, 1.12), shade(top_color, 0.92)), m_top)
    d = Draw(img)
    d.rounded_rectangle(top_box, radius * SS // 4 * 4, outline=shade(top_color, 1.3), width=4)
    d.rounded_rectangle((2, 2, S - 3, S - 3), radius * SS // 4 * 4, outline=shade(side_color, 0.45), width=5)
    return img, m_top, top_box


def block_tile(style, base, rng, kind="block"):
    if kind == "wall":
        base = shade(base, 0.78)
    top, side = base, shade(base, 0.62)
    img, m_top, (x0, y0, x1, y1) = raised_block(top, side)
    d = Draw(img)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if style == "stone":
        detail = noise_layer(rng, shade(top, 1.2), shade(top, 0.8), 70, 4, 12, alpha=55)
        paste_masked(img, detail, m_top)
        for _ in range(3):
            px, py = rng.uniform(x0 + 30, x1 - 30), rng.uniform(y0 + 30, y1 - 30)
            pts = [(px, py)]
            for _ in range(3):
                px += rng.uniform(-24, 24); py += rng.uniform(8, 22)
                pts.append((px, py))
            d.line(pts, fill=shade(top, 0.6), width=4)
        if rng.random() < 0.6:   # mech
            moss = noise_layer(rng, hexc("#4f8a2e"), hexc("#6aa83d"), 25, 6, 14, alpha=170)
            mm = Image.new("L", (S, S), 0)
            ImageDraw.Draw(mm).rectangle((x0, y0, x1, y0 + 40), fill=255)
            paste_masked(img, moss, Image.fromarray(np.minimum(np.array(mm), np.array(m_top))))
    elif style == "steel":
        for (rx, ry) in [(x0 + 26, y0 + 26), (x1 - 26, y0 + 26), (x0 + 26, y1 - 26), (x1 - 26, y1 - 26)]:
            d.ellipse((rx - 9, ry - 9, rx + 9, ry + 9), fill=shade(top, 0.7))
            d.ellipse((rx - 6, ry - 8, rx + 4, ry), fill=shade(top, 1.4))
        d.line([(x0 + 50, y0 + 40), (x1 - 40, y1 - 50)], fill=shade(top, 1.25), width=6)
    elif style == "ice":
        paste_masked(img, radial((S, S), (x0 + 60, y0 + 50), 220, shade(top, 1.5, 255), shade(top, 0.95, 255)), m_top)
        for k in range(3):
            o = 40 + k * 46
            d.line([(x0 + o, y0 + 20), (x0 + o - 40, y1 - 20)], fill=(255, 255, 255, 120), width=8 - k * 2)
    elif style == "brick":
        bh = (y1 - y0) / 4
        for i in range(1, 4):
            d.line([(x0 + 6, y0 + i * bh), (x1 - 6, y0 + i * bh)], fill=shade(top, 0.7), width=5)
        for i in range(4):
            off = 0 if i % 2 == 0 else (x1 - x0) / 4
            for k in range(1, 3):
                x = x0 + off + k * (x1 - x0) / 2.5
                if x0 + 10 < x < x1 - 10:
                    d.line([(x, y0 + i * bh), (x, y0 + (i + 1) * bh)], fill=shade(top, 0.7), width=5)
        if kind != "wall":   # flaga zamku z piasku
            d.line([(cx, y0 + 20), (cx, y0 - 0)], fill=shade(top, 0.5), width=4)
    elif style == "chocolate":
        for k in (1, 2):
            x = x0 + (x1 - x0) * k / 3
            y = y0 + (y1 - y0) * k / 3
            d.line([(x, y0 + 8), (x, y1 - 8)], fill=shade(top, 0.65), width=6)
            d.line([(x0 + 8, y), (x1 - 8, y)], fill=shade(top, 0.65), width=6)
            d.line([(x + 6, y0 + 8), (x + 6, y1 - 8)], fill=shade(top, 1.25), width=3)
            d.line([(x0 + 8, y + 6), (x1 - 8, y + 6)], fill=shade(top, 1.25), width=3)
    elif style == "wood":
        for i in range(1, 4):
            y = y0 + (y1 - y0) * i / 4
            d.line([(x0 + 6, y), (x1 - 6, y)], fill=shade(top, 0.65), width=5)
        for _ in range(8):
            y = rng.uniform(y0 + 10, y1 - 10)
            d.line([(x0 + rng.uniform(10, 60), y), (x1 - rng.uniform(10, 60), y + rng.uniform(-3, 3))], fill=shade(top, 0.85), width=3)
    elif style == "marble":
        for _ in range(4):
            px, py = rng.uniform(x0, x1), y0 + 10
            pts = [(px, py)]
            while py < y1 - 10:
                px += rng.uniform(-30, 30); py += rng.uniform(15, 35)
                pts.append((px, min(py, y1 - 10)))
            d.line(pts, fill=(150, 150, 160, 140), width=3)
    elif style == "tire":
        img = canvas()
        for k, oy in enumerate((S * 0.62, S * 0.42)):
            d2 = Draw(img)
            rx, ry = S * 0.44, S * 0.2
            d2.ellipse((S / 2 - rx, oy - ry + 26, S / 2 + rx, oy + ry + 26), fill=shade(base, 0.6))
            d2.rectangle((S / 2 - rx, oy, S / 2 + rx, oy + 26), fill=shade(base, 0.8))
            d2.ellipse((S / 2 - rx, oy - ry, S / 2 + rx, oy + ry), fill=shade(base, 1.0), outline=shade(base, 1.6), width=4)
            d2.ellipse((S / 2 - rx * 0.45, oy - ry * 0.45, S / 2 + rx * 0.45, oy + ry * 0.45), fill=(25, 25, 28, 255))
            for a in range(0, 360, 30):
                t = math.radians(a)
                d2.line([(S / 2 + math.cos(t) * rx * 0.6, oy + math.sin(t) * ry * 0.6),
                         (S / 2 + math.cos(t) * rx * 0.92, oy + math.sin(t) * ry * 0.92)], fill=shade(base, 1.5), width=4)
        if kind == "wall":
            img = Image.alpha_composite(Image.new("RGBA", (S, S), shade(base, 1.2)), img)
        d = Draw(img)
    elif style == "toyblock":
        colors = [hexc("#e63946"), hexc("#457b9d"), hexc("#f4a261"), hexc("#2a9d8f")]
        top = rng.choice(colors) if kind == "block" else base
        img, m_top, (x0, y0, x1, y1) = raised_block(top, shade(top, 0.6), radius=6)
        d = Draw(img)
        d.rounded_rectangle((x0 + 30, y0 + 24, x1 - 30, y1 - 24), 20, outline=(255, 255, 255, 230), width=8)
        d.ellipse((cx - 22, (y0 + y1) / 2 - 22, cx + 22, (y0 + y1) / 2 + 22), fill=(255, 255, 255, 230))
    if kind == "center":
        # Środek mapy: złote zdobienie
        d.ellipse((cx - 50, cy - 50, cx + 50, cy + 50), outline=hexc("#f4d35e"), width=10)
        d.regular_polygon((cx, cy, 26), 4, rotation=45, fill=hexc("#f4d35e"))
        d.regular_polygon((cx, cy, 14), 4, rotation=45, fill=shade(hexc("#f4d35e"), 1.4))
    return down(img)


# ---------------------------------------------------------------------------
# Skrzynki (zniszczalne)
# ---------------------------------------------------------------------------

def box_tile(style, base, rng, accent=None):
    img = canvas()
    soft_shadow(img, (20, S - 70, S - 20, S - 6), alpha=80, blur=5)
    inset = 16
    top_box = (inset, inset, S - inset, S - inset - SIDE)
    full = (inset, inset, S - inset, S - inset)
    d = Draw(img)
    if style == "crate":
        d.rounded_rectangle(full, 12, fill=shade(base, 0.62))
        d.rounded_rectangle(top_box, 12, fill=base)
        x0, y0, x1, y1 = top_box
        for i in range(1, 3):
            y = y0 + (y1 - y0) * i / 3
            d.line([(x0 + 8, y), (x1 - 8, y)], fill=shade(base, 0.7), width=4)
        d.rounded_rectangle(top_box, 12, outline=shade(base, 0.5), width=14)
        d.line([(x0 + 14, y1 - 14), (x1 - 14, y0 + 14)], fill=shade(base, 0.5), width=14)
        d.line([(x0 + 14, y1 - 18), (x1 - 18, y0 + 14)], fill=shade(base, 1.18), width=5)
        for (nx, ny) in [(x0 + 14, y0 + 14), (x1 - 14, y0 + 14), (x0 + 14, y1 - 14), (x1 - 14, y1 - 14)]:
            d.ellipse((nx - 6, ny - 6, nx + 6, ny + 6), fill=hexc("#d8d8d8"))
        d.rounded_rectangle(full, 12, outline=shade(base, 0.35), width=5)
    elif style == "gift":
        acc = accent or hexc("#ffd166")
        d.rounded_rectangle(full, 10, fill=shade(base, 0.62))
        d.rounded_rectangle(top_box, 10, fill=base)
        x0, y0, x1, y1 = top_box
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        d.rectangle((cx - 12, y0, cx + 12, S - inset), fill=acc)
        d.rectangle((x0, cy - 12, x1, cy + 12), fill=acc)
        d.rectangle((cx - 12, y1, cx + 12, S - inset), fill=shade(acc, 0.7))
        for sgn in (-1, 1):
            d.ellipse((cx + sgn * 34 - 22, cy - 34, cx + sgn * 34 + 22, cy + 2), outline=acc, width=10)
        d.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), fill=shade(acc, 1.2))
        d.line([(x0 + 14, y0 + 14), (x0 + 40, y0 + 14)], fill=shade(base, 1.4), width=6)
        d.rounded_rectangle(full, 10, outline=shade(base, 0.4), width=5)
    elif style == "hay":
        d.rounded_rectangle(full, 26, fill=shade(base, 0.7))
        d.rounded_rectangle(top_box, 26, fill=base)
        x0, y0, x1, y1 = top_box
        for _ in range(40):
            x = rng.uniform(x0 + 10, x1 - 10); y = rng.uniform(y0 + 10, y1 - 10)
            d.line([(x, y), (x + rng.uniform(-18, 18), y + rng.uniform(-6, 6))], fill=shade(base, rng.choice([0.75, 1.25])), width=3)
        for k in (0.33, 0.67):
            x = x0 + (x1 - x0) * k
            d.line([(x, y0), (x, S - inset)], fill=hexc("#8d5a2b"), width=8)
        d.rounded_rectangle(full, 26, outline=shade(base, 0.45), width=5)
    elif style == "cardboard":
        d.rounded_rectangle(full, 8, fill=shade(base, 0.68))
        d.rounded_rectangle(top_box, 8, fill=base)
        x0, y0, x1, y1 = top_box
        cx = (x0 + x1) / 2
        d.line([(cx, y0), (cx, y1)], fill=shade(base, 0.75), width=4)
        d.rectangle((cx - 16, y0, cx + 16, y1), fill=(222, 200, 150, 200))
        d.rectangle((cx - 16, y1, cx + 16, S - inset), fill=(190, 170, 125, 200))
        d.line([(x0 + 20, y0 + 30), (x0 + 56, y0 + 30)], fill=shade(base, 0.6), width=4)
        d.line([(x0 + 20, y0 + 42), (x0 + 46, y0 + 42)], fill=shade(base, 0.6), width=4)
        d.rounded_rectangle(full, 8, outline=shade(base, 0.45), width=5)
    return down(img)


# ---------------------------------------------------------------------------
# Motywy (id mapy bez numeru wariantu)
# ---------------------------------------------------------------------------

THEMES = {
    #               podłoga                      blok                        skrzynka
    "classic":      (("checker", "#3a4256"),     ("steel", "#8a93a8"),       ("crate", "#b07a45", None)),
    "forest":       (("grass", "#5d9b3d"),       ("stone", "#8d918a"),       ("crate", "#a8743f", None)),
    "cake":         (("checker", "#f4c2cf"),     ("chocolate", "#6e412b"),   ("gift", "#fff3e6", hexc("#ef6f9a"))),
    "christmas":    (("snow", "#e6eef7"),        ("ice", "#8fcbed"),         ("gift", "#d62839", hexc("#ffd166"))),
    "classroom":    (("planks", "#bf915e"),      ("wood", "#5f4330"),        ("cardboard", "#c9a46b", None)),
    "fashion_shop": (("tiles", "#eadfcc"),       ("marble", "#f1efea"),      ("gift", "#9b5de5", hexc("#f15bb5"))),
    "race":         (("asphalt", "#4a4d53"),     ("tire", "#2c2c30"),        ("crate", "#c4462f", None)),
    "ranch":        (("dirt", "#a27b50"),        ("stone", "#9b958a"),       ("hay", "#e7c45a", None)),
    "sand":         (("sand", "#ead49c"),        ("brick", "#d4ad62"),       ("crate", "#b98950", None)),
    "toy_shop":     (("carpet", "#5b7fc4"),      ("toyblock", "#e63946"),    ("gift", "#ffd166", hexc("#3a86ff"))),
}


def gen_tiles():
    for theme, ((fs, fc), (bs, bc), (xs, xc, acc)) in THEMES.items():
        rng = random.Random(theme)
        base = hexc(fc)
        out = "tiles/%s/" % theme
        floor_tile(fs, base, rng).save(_p(out + "floor.png"))
        floor_tile(fs, base, rng, alt=True).save(_p(out + "floor_alt.png"))
        block_tile(bs, hexc(bc), rng, "block").save(_p(out + "block.png"))
        block_tile(bs, hexc(bc), rng, "wall").save(_p(out + "wall.png"))
        block_tile(bs, hexc(bc), rng, "center").save(_p(out + "center.png"))
        box_tile(xs, hexc(xc), rng, acc).save(_p(out + "box.png"))


def _p(rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


# ---------------------------------------------------------------------------
# Postacie: arkusz 3×4 (kolumny: stoi, krok A, krok B; wiersze: dół, lewo, prawo, góra)
# ---------------------------------------------------------------------------

PLAYER_COLORS = {1: "#3b82f6", 2: "#ef4444", 3: "#22c55e", 4: "#a855f7"}


def player_frame(color, facing, step):
    img = canvas()
    d = Draw(img)
    c = hexc(color)
    bob = 0 if step == 0 else -6
    cx = S / 2
    soft_shadow(img, (cx - 70, S - 46, cx + 70, S - 10), alpha=100, blur=4)
    d = Draw(img)
    # Stopy
    fy = S - 34
    if facing in ("down", "up"):
        off = [0, 14, -14][step]
        for sgn, o in ((-1, off), (1, -off)):
            d.ellipse((cx + sgn * 34 - 22, fy - 16 + o * 0.5, cx + sgn * 34 + 22, fy + 14 + o * 0.5), fill=shade(c, 0.45))
    else:
        dirx = -1 if facing == "left" else 1
        off = [0, 18, -18][step]
        d.ellipse((cx - 30 + off, fy - 16, cx + 18 + off, fy + 14), fill=shade(c, 0.4))
        d.ellipse((cx - 18 - off, fy - 18, cx + 30 - off, fy + 12), fill=shade(c, 0.5))
    # Tułów
    by = S - 112 + bob
    body = (cx - 52, by, cx + 52, by + 72)
    body_img = canvas()
    paste_masked(body_img, vgrad((S, S), shade(c, 1.15), shade(c, 0.75)), mask_rr((S, S), body, 30))
    img.alpha_composite(body_img)
    d = Draw(img)
    d.rounded_rectangle(body, 30, outline=shade(c, 0.4), width=5)
    d.rectangle((cx - 52, by + 30, cx + 52, by + 40), fill=shade(c, 0.5))   # pasek
    d.rounded_rectangle((cx - 12, by + 28, cx + 12, by + 42), 4, fill=hexc("#f4d35e"))
    # Ręce
    swing = [0, 10, -10][step]
    if facing in ("down", "up"):
        for sgn in (-1, 1):
            hy = by + 24 + sgn * swing * 0.6
            d.ellipse((cx + sgn * 62 - 16, hy - 16, cx + sgn * 62 + 16, hy + 16), fill=hexc("#f5f5f5"), outline=shade(c, 0.4), width=4)
    else:
        dirx = -1 if facing == "left" else 1
        hy = by + 28
        d.ellipse((cx + dirx * (10 + swing) - 16, hy - 16, cx + dirx * (10 + swing) + 16, hy + 16), fill=hexc("#f5f5f5"), outline=shade(c, 0.4), width=4)
    # Głowa (hełm)
    hy0 = 18 + bob
    head = (cx - 74, hy0 + 20, cx + 74, hy0 + 150)
    head_img = canvas()
    paste_masked(head_img, radial((S, S), (cx - 30, hy0 + 50), 170, (255, 255, 255, 255), (205, 210, 222, 255)), mask_rr((S, S), head, 62))
    img.alpha_composite(head_img)
    d = Draw(img)
    d.rounded_rectangle(head, 62, outline=(70, 74, 90, 255), width=6)
    # Antena
    d.line([(cx, hy0 + 22), (cx, hy0 - 2)], fill=(70, 74, 90, 255), width=6)
    d.ellipse((cx - 16, hy0 - 22, cx + 16, hy0 + 10), fill=c, outline=shade(c, 0.4), width=4)
    d.ellipse((cx - 8, hy0 - 16, cx + 2, hy0 - 6), fill=(255, 255, 255, 200))
    # Wizjer i oczy
    if facing == "down":
        visor = (cx - 52, hy0 + 64, cx + 52, hy0 + 124)
        d.rounded_rectangle(visor, 26, fill=(28, 32, 48, 255))
        for sgn in (-1, 1):
            d.rounded_rectangle((cx + sgn * 22 - 8, hy0 + 76, cx + sgn * 22 + 8, hy0 + 108), 8, fill=(255, 255, 255, 255))
        d.ellipse((cx - 44, hy0 + 68, cx - 20, hy0 + 80), fill=(255, 255, 255, 70))
        d.ellipse((cx - 64, hy0 + 112, cx - 46, hy0 + 126), fill=(255, 140, 160, 120))
        d.ellipse((cx + 46, hy0 + 112, cx + 64, hy0 + 126), fill=(255, 140, 160, 120))
    elif facing in ("left", "right"):
        dirx = -1 if facing == "left" else 1
        vx0 = cx + dirx * 8
        visor = (min(vx0, vx0 + dirx * 70), hy0 + 64, max(vx0, vx0 + dirx * 70), hy0 + 124)
        d.rounded_rectangle(visor, 24, fill=(28, 32, 48, 255))
        ex = cx + dirx * 44
        d.rounded_rectangle((ex - 8, hy0 + 76, ex + 8, hy0 + 108), 8, fill=(255, 255, 255, 255))
    else:   # up: tył hełmu
        d.arc((cx - 50, hy0 + 50, cx + 50, hy0 + 140), 200, 340, fill=(180, 186, 200, 255), width=6)
    return img


def gen_players():
    facings = ["down", "left", "right", "up"]
    for pid, color in PLAYER_COLORS.items():
        sheet = Image.new("RGBA", (T * 3, T * 4), (0, 0, 0, 0))
        for row, f in enumerate(facings):
            for col in range(3):
                sheet.alpha_composite(down(player_frame(color, f, col)), (col * T, row * T))
        sheet.save(_p("players/player_%d.png" % pid))


# ---------------------------------------------------------------------------
# Bomba, ogień
# ---------------------------------------------------------------------------

def gen_bomb():
    img = canvas()
    cx, cy, r = S / 2, S / 2 + 14, 84
    soft_shadow(img, (cx - 74, cy + 52, cx + 74, cy + 92), alpha=110, blur=4)
    ball = radial((S, S), (cx - 30, cy - 34), 150, (110, 118, 150, 255), (14, 14, 22, 255))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    paste_masked(img, ball, m)
    d = Draw(img)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(8, 8, 12, 255), width=5)
    d.ellipse((cx - 52, cy - 58, cx - 18, cy - 30), fill=(255, 255, 255, 150))
    # Nasadka i lont
    d.rounded_rectangle((cx + 18, cy - r - 4, cx + 62, cy - r + 26), 8, fill=(150, 156, 172, 255), outline=(40, 40, 50, 255), width=4)
    d.line([(cx + 40, cy - r - 2), (cx + 52, cy - r - 30), (cx + 74, cy - r - 40)], fill=(150, 110, 70, 255), width=8, joint="curve")
    # Iskra
    sx, sy = cx + 78, cy - r - 44
    for a in range(0, 360, 45):
        t = math.radians(a)
        L = 24 if a % 90 == 0 else 14
        d.line([(sx, sy), (sx + math.cos(t) * L, sy + math.sin(t) * L)], fill=(255, 210, 80, 255), width=6)
    d.ellipse((sx - 10, sy - 10, sx + 10, sy + 10), fill=(255, 250, 220, 255))
    down(img).save(_p("objects/bomb.png"))


def flame_band(img, x0, x1, cy, half, rounded_end=False):
    """Pozioma wiązka ognia: biały rdzeń → żółty → pomarańcz → czerwony brzeg."""
    layers = [(half, (230, 70, 20, 230)), (half * 0.78, (255, 140, 30, 255)), (half * 0.52, (255, 215, 70, 255)), (half * 0.26, (255, 255, 225, 255))]
    for h, col in layers:
        lay = canvas()
        d = Draw(lay)
        if rounded_end:
            d.rectangle((x0, cy - h, x1 - h, cy + h), fill=col)
            d.ellipse((x1 - 2 * h, cy - h, x1, cy + h), fill=col)
        else:
            d.rectangle((x0, cy - h, x1, cy + h), fill=col)
        img.alpha_composite(lay)


def gen_explosion():
    # Środek
    img = canvas()
    glow = radial((S, S), (S / 2, S / 2), S * 0.5, (255, 160, 40, 200), (255, 80, 20, 0))
    img.alpha_composite(glow)
    flame_band(img, 0, S, S / 2, S * 0.36)
    rot = img.rotate(90)
    img.alpha_composite(rot)
    d = Draw(img)
    d.ellipse((S / 2 - 70, S / 2 - 70, S / 2 + 70, S / 2 + 70), fill=(255, 220, 90, 255))
    d.ellipse((S / 2 - 44, S / 2 - 44, S / 2 + 44, S / 2 + 44), fill=(255, 255, 235, 255))
    down(img).save(_p("objects/explosion_center.png"))
    # Ramię
    img = canvas()
    flame_band(img, 0, S, S / 2, S * 0.36)
    down(img).save(_p("objects/explosion_arm.png"))
    # Koniec (w prawo)
    img = canvas()
    flame_band(img, 0, S - 16, S / 2, S * 0.36, rounded_end=True)
    down(img).save(_p("objects/explosion_end.png"))


# ---------------------------------------------------------------------------
# Power-upy
# ---------------------------------------------------------------------------

POWERUPS = {
    "bomb_up":  "#f97316",
    "range_up": "#facc15",
    "speed_up": "#22c55e",
    "life_up":  "#f43f5e",
    "kick":     "#3b82f6",
    "shield":   "#7dd3fc",
    "star":     "#fde047",
    "quiz":     "#8b5cf6",
}


def glyph(d, kind, cx, cy, s):
    W = (255, 255, 255, 255)
    O = (40, 30, 30, 255)
    if kind == "bomb_up":
        d.ellipse((cx - s * 0.5, cy - s * 0.35, cx + s * 0.5, cy + s * 0.65), fill=(30, 30, 40, 255), outline=W, width=6)
        d.line([(cx + s * 0.2, cy - s * 0.3), (cx + s * 0.45, cy - s * 0.65)], fill=W, width=8)
        d.ellipse((cx - s * 0.3, cy - s * 0.15, cx - s * 0.05, cy + s * 0.08), fill=(255, 255, 255, 170))
    elif kind == "range_up":
        pts = [(cx, cy - s * 0.85), (cx + s * 0.45, cy - s * 0.1), (cx + s * 0.5, cy + s * 0.35), (cx, cy + s * 0.8),
               (cx - s * 0.5, cy + s * 0.35), (cx - s * 0.35, cy - s * 0.2), (cx - s * 0.12, cy + s * 0.05)]
        d.polygon(pts, fill=(255, 120, 30, 255), outline=W, width=6)
        d.polygon([(cx, cy - s * 0.2), (cx + s * 0.22, cy + s * 0.3), (cx, cy + s * 0.6), (cx - s * 0.22, cy + s * 0.3)], fill=(255, 240, 150, 255))
    elif kind == "speed_up":
        pts = [(cx + s * 0.15, cy - s * 0.85), (cx - s * 0.45, cy + s * 0.1), (cx - s * 0.02, cy + s * 0.1),
               (cx - s * 0.18, cy + s * 0.85), (cx + s * 0.48, cy - s * 0.15), (cx + s * 0.05, cy - s * 0.15)]
        d.polygon(pts, fill=W, outline=O, width=4)
    elif kind == "life_up":
        r = s * 0.32
        d.ellipse((cx - 2 * r, cy - r * 1.6, cx, cy + r * 0.4), fill=W)
        d.ellipse((cx, cy - r * 1.6, cx + 2 * r, cy + r * 0.4), fill=W)
        d.polygon([(cx - 2 * r + 4, cy - r * 0.3), (cx + 2 * r - 4, cy - r * 0.3), (cx, cy + s * 0.8)], fill=W)
    elif kind == "kick":
        # But: cholewka, przód z zaokrąglonym czubkiem, podeszwa, sznurówki; kreski ruchu z tyłu
        B = (30, 30, 40, 255)
        d.polygon([(cx - s * 0.3, cy - s * 0.75), (cx + s * 0.12, cy - s * 0.75), (cx + s * 0.12, cy - s * 0.05),
                   (cx + s * 0.45, cy + s * 0.05), (cx + s * 0.45, cy + s * 0.42), (cx - s * 0.38, cy + s * 0.42)], fill=W, outline=B, width=4)
        d.ellipse((cx + s * 0.2, cy - s * 0.06, cx + s * 0.75, cy + s * 0.48), fill=W, outline=B, width=4)
        d.rectangle((cx + s * 0.1, cy - s * 0.02, cx + s * 0.5, cy + s * 0.4), fill=W)
        d.rounded_rectangle((cx - s * 0.42, cy + s * 0.38, cx + s * 0.76, cy + s * 0.6), 10, fill=B)
        for k in range(3):
            y = cy - s * 0.55 + k * s * 0.2
            d.line([(cx - s * 0.22, y), (cx + s * 0.06, y + s * 0.06)], fill=B, width=5)
        for k in range(3):
            y = cy - s * 0.35 + k * s * 0.28
            d.line([(cx - s * 0.95, y), (cx - s * 0.55, y)], fill=W, width=6)
    elif kind == "shield":
        pts = [(cx, cy - s * 0.8), (cx + s * 0.62, cy - s * 0.5), (cx + s * 0.5, cy + s * 0.25), (cx, cy + s * 0.85),
               (cx - s * 0.5, cy + s * 0.25), (cx - s * 0.62, cy - s * 0.5)]
        d.polygon(pts, fill=W, outline=O, width=4)
        d.polygon([(cx, cy - s * 0.55), (cx + s * 0.38, cy - s * 0.35), (cx + s * 0.3, cy + s * 0.15), (cx, cy + s * 0.55)], fill=(120, 190, 240, 255))
    elif kind == "star":
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = s * (0.85 if k % 2 == 0 else 0.38)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        d.polygon(pts, fill=W, outline=(200, 140, 0, 255), width=5)
    elif kind == "quiz":
        # Znak zapytania: łuk + nóżka + kropka, z ciemnym obrysem
        r = s * 0.4
        top = cy - s * 0.45
        for col, w, dot in ((O, 26, s * 0.17), (W, 16, s * 0.12)):
            d.arc((cx - r, top - r, cx + r, top + r), 195, 90, fill=col, width=w)
            d.line([(cx, top + r - w / 2), (cx, cy + s * 0.25)], fill=col, width=w)
            d.ellipse((cx - dot, cy + s * 0.6 - dot, cx + dot, cy + s * 0.6 + dot), fill=col)


def gen_powerups():
    for kind, col in POWERUPS.items():
        img = canvas()
        c = hexc(col)
        soft_shadow(img, (40, S - 50, S - 40, S - 14), alpha=90, blur=4)
        box = (26, 18, S - 26, S - 34)
        tile = canvas()
        paste_masked(tile, vgrad((S, S), shade(c, 1.25), shade(c, 0.7)), mask_rr((S, S), box, 40))
        img.alpha_composite(tile)
        d = Draw(img)
        d.rounded_rectangle(box, 40, outline=shade(c, 0.4), width=8)
        d.rounded_rectangle((box[0] + 16, box[1] + 10, box[2] - 16, box[1] + 60), 28, fill=(255, 255, 255, 70))
        glyph(d, kind, S / 2, (box[1] + box[3]) / 2, 70)
        down(img).save(_p("objects/powerup_%s.png" % kind))


# ---------------------------------------------------------------------------
# UI (tekstury 9-patch dla motywu resources/ui/bb_theme.tres)
# ---------------------------------------------------------------------------

## Kolory UI: granatowe panele, złote zaznaczenie, zielony „Zagraj”, czerwone wyjście
UI_PANEL   = ("#28305e", "#151a36", "#0b0e20")      # góra, dół, obrys
UI_BUTTONS = {
    "button":         ("#3a4687", "#283166", "#0e1230"),
    "button_hover":   ("#4b59a8", "#33407f", "#0e1230"),
    "button_pressed": ("#fcd34d", "#f59e0b", "#5a3300"),
    "button_primary": ("#4ade80", "#16a34a", "#0b3d1d"),
    "button_primary_hover": ("#86efac", "#22c55e", "#0b3d1d"),
    "button_danger":  ("#f87171", "#dc2626", "#4a0d0d"),
    "button_danger_hover": ("#fca5a5", "#ef4444", "#4a0d0d"),
    "button_disabled": ("#3a3f55", "#2c3044", "#14161f"),
}


def ui_box(w, h, r, top, bottom, edge, lip=0, gloss=0.42):
    """Zaokrąglony prostokąt w stylu klocków z planszy: gradient, ciemny obrys, jasna linia w środku,
    połysk u góry (gloss = do jakiej części wysokości, 0 = bez) i opcjonalna „warga” (ciemniejszy spód
    jak bok bloku). Wymiary w px końcowych. Przy 9-patch połysk musi się mieścić w górnym marginesie."""
    W, H, R, L = w * SS, h * SS, r * SS, lip * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    top, bottom, edge = hexc(top), hexc(bottom), hexc(edge)
    if L:
        paste_masked(img, Image.new("RGBA", (W, H), shade(bottom, 0.55)), mask_rr((W, H), (0, 0, W - 1, H - 1), R))
    body = (0, 0, W - 1, H - 1 - L)
    paste_masked(img, vgrad((W, H), top, bottom), mask_rr((W, H), body, R))
    d = Draw(img)
    if gloss:
        d.rounded_rectangle((3 * SS, 3 * SS, W - 3 * SS, (H - L) * gloss), R * 0.8, fill=(255, 255, 255, 34))
    d.rounded_rectangle((2 * SS, 2 * SS, W - 1 - 2 * SS, H - 1 - L - 2 * SS), R - 2 * SS, outline=(255, 255, 255, 46), width=SS)
    d.rounded_rectangle((0, 0, W - 1, H - 1), R, outline=edge, width=int(2.5 * SS))
    return down(img)


def gen_ui():
    t, b, e = UI_PANEL
    ui_box(96, 96, 22, t, b, e, gloss=0.2).save(_p("ui/panel.png"))     # margines 9-patch 28 px
    ui_box(64, 64, 14, t, b, e, gloss=0).save(_p("ui/card.png"))
    for name, (top, bottom, edge) in UI_BUTTONS.items():
        ui_box(64, 64, 16, top, bottom, edge, lip=5).save(_p("ui/%s.png" % name))
    # Pole tekstowe / tło paska: wklęsłe, bez wargi i połysku
    ui_box(48, 48, 12, "#0a0d1c", "#141936", "#05070f", gloss=0).save(_p("ui/field.png"))
    ui_box(32, 20, 9, "#fde68a", "#f59e0b", "#7a4a00").save(_p("ui/bar_fill.png"))


if __name__ == "__main__":
    gen_tiles()
    gen_players()
    gen_bomb()
    gen_explosion()
    gen_powerups()
    gen_ui()
    print("OK ->", os.path.abspath(OUT))
