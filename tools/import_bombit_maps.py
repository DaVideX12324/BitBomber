"""Import układów map z Bomb It 7 (TMX w zdekompilowanym SWF) do resources/maps/*.json.

Użycie:
    python tools/import_bombit_maps.py <bomb-it-7/scripts/_assets> [resources/maps]

Bierzemy tylko układ pól (bez grafiki i bez „organów” — elementów map, na razie ich nie ma):
  warstwa wall   → '#' (obramowanie)
  warstwa base   → niższy numer kafla = '#' blok stały, wyższy = 'b' miejsce na skrzynkę
                   (jak AbstractMapAsset.createBaseLayer: frame < beginNum + fixedPropNum - 1)
  warstwa center → 'C' blok 3×3 (Race: 3×1) — x..x+w-1, y-2..y-2+h-1 (Center.addMap)
  reszta         → '.' (puste, zawsze wolne)
Spawny jak GameConfig.ROBOT_KILL_POSITION: rogi (1,1), (15,1), (1,13), (15,13).
Dodatkowo zapisuje classic.json — dawna arena BitBombera (17×17, wzór szachownicy).
"""
import base64
import glob
import json
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

THEMES = {
    "Classroom": "classroom",
    "Forest": "forest",
    "Race": "race",
    "Ranch": "ranch",
    "Christmas": "christmas",
    "Sand": "sand",
    "Cake": "cake",
    "FashionShop": "fashion_shop",
    "ToyShop": "toy_shop",
}
CENTER_SIZE = {"Race": (3, 1)}
SPAWNS_17x15 = [[1, 1], [15, 1], [1, 13], [15, 13]]


def layer(root, name, w, h):
    for lay in root.findall("layer"):
        if lay.get("name") == name:
            raw = zlib.decompress(base64.b64decode(lay.find("data").text.strip()))
            return struct.unpack("<%dI" % (w * h), raw)
    return (0,) * (w * h)


def convert(path, theme):
    root = ET.parse(path).getroot()
    w, h = int(root.get("width")), int(root.get("height"))
    grid = [["." for _ in range(w)] for _ in range(h)]
    base = layer(root, "base", w, h)
    used = sorted({g for g in base if g})
    assert len(used) == 2, (path, used)
    hard, box = used
    for i, g in enumerate(base):
        if g:
            grid[i // w][i % w] = "#" if g == hard else "b"
    for i, g in enumerate(layer(root, "wall", w, h)):
        if g:
            grid[i // w][i % w] = "#"
    cw, ch = CENTER_SIZE.get(theme, (3, 3))
    for i, g in enumerate(layer(root, "center", w, h)):
        if g:
            x, y = i % w, i // w
            for dy in range(ch):
                for dx in range(cw):
                    grid[y - 2 + dy][x + dx] = "C"
    for sx, sy in SPAWNS_17x15:
        assert grid[sy][sx] == ".", (path, sx, sy, grid[sy][sx])
    return ["".join(r) for r in grid]


def classic():
    cols = rows = 17
    spawns = [[1, 1], [cols - 2, rows - 2], [1, rows - 2], [cols - 2, 1]]

    def solid(x, y):
        return x in (0, cols - 1) or y in (0, rows - 1) or (x % 2 == 0 and y % 2 == 0)

    out = []
    for y in range(rows):
        row = ""
        for x in range(cols):
            if solid(x, y):
                row += "#"
            elif any(abs(x - sx) + abs(y - sy) <= 2 for sx, sy in spawns):
                row += "."
            elif (solid(x - 1, y) and solid(x + 1, y)) or (solid(x, y - 1) and solid(x, y + 1)):
                row += "b"
            else:
                row += "."
        out.append(row)
    return {"name_key": "bb.map.classic", "variant": 0, "spawns": spawns, "rows": out}


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "resources", "maps")
    os.makedirs(dst, exist_ok=True)
    maps = {"classic": classic()}
    for path in sorted(glob.glob(os.path.join(src, "*mapdata.*_CONFIG*.bin"))):
        m = re.search(r"mapdata\.(\w+)_CONFIG(\d)\.bin$", path)
        theme, variant = m.group(1), int(m.group(2))
        if theme not in THEMES:
            continue
        key = THEMES[theme]
        maps["%s_%d" % (key, variant)] = {
            "name_key": "bb.map." + key,
            "variant": variant,
            "source": "Bomb It 7: %s_CONFIG%d" % (theme, variant),
            "spawns": SPAWNS_17x15,
            "rows": convert(path, theme),
        }
    for name, data in sorted(maps.items()):
        with open(os.path.join(dst, name + ".json"), "w", encoding="utf-8", newline="\n") as f:
            rows = data.pop("rows")
            text = json.dumps(data, ensure_ascii=False)[:-1]
            text += ', "rows": [\n' + ",\n".join('\t"%s"' % r for r in rows) + "\n]}\n"
            f.write(text)
        print(name)


if __name__ == "__main__":
    main()
