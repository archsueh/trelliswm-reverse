#!/usr/bin/env python3
"""Generate AppIcon.iconset from scratch — no PIL, no external assets.

The icon is a small fractal split tree, i.e. the derived layout grammar itself.
Standard library only: PNG is written directly (zlib + struct).
"""
import os
import struct
import sys
import zlib

PAPER = (246, 243, 236, 255)
EDGE = (27, 36, 48, 255)
TILES = [
    (198, 220, 248, 255),   # blue
    (196, 232, 220, 255),   # teal
    (250, 226, 190, 255),   # amber
    (224, 214, 244, 255),   # violet
    (232, 224, 208, 255),   # desktop / floating layer
]


def png_chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path, size, buf):
    stride = size * 4
    raw = b"".join(b"\x00" + bytes(buf[y * stride:(y + 1) * stride])
                   for y in range(size))
    out = (b"\x89PNG\r\n\x1a\n"
           + png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + png_chunk(b"IDAT", zlib.compress(raw, 9))
           + png_chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(out)


def rounded(buf, size, x0, y0, x1, y1, radius, color, border=None):
    """Fill a rounded rect in normalised-pixel coordinates; optional 1px border."""
    x0, y0, x1, y1 = (int(round(v * size)) for v in (x0, y0, x1, y1))
    r = int(round(radius * size))
    r = max(0, min(r, (x1 - x0) // 2, (y1 - y0) // 2))
    rgba = bytes(color)
    edge = bytes(border) if border else None
    for y in range(max(0, y0), min(size, y1)):
        for x in range(max(0, x0), min(size, x1)):
            dx = 0
            dy = 0
            if x < x0 + r:
                dx = x0 + r - x
            elif x >= x1 - r:
                dx = x - (x1 - 1 - r)
            if y < y0 + r:
                dy = y0 + r - y
            elif y >= y1 - r:
                dy = y - (y1 - 1 - r)
            if dx * dx + dy * dy > r * r and r > 0:
                continue
            on_edge = (x - x0 < 2 or x1 - 1 - x < 2 or
                       y - y0 < 2 or y1 - 1 - y < 2)
            px = edge if (edge and on_edge) else rgba
            off = (y * size + x) * 4
            buf[off:off + 4] = px


def render(size):
    buf = bytearray(size * size * 4)  # transparent
    rounded(buf, size, 0.0, 0.0, 1.0, 1.0, 0.225, PAPER)

    g = 0.018
    tiles = [
        (0.105, 0.105, 0.340, 0.430, TILES[0]),
        (0.358, 0.105, 0.592, 0.430, TILES[1]),
        (0.105, 0.448, 0.340, 0.895, TILES[2]),
        (0.358, 0.448, 0.592, 0.895, TILES[3]),
        (0.610, 0.105, 0.895, 0.895, TILES[4]),
    ]
    # Nested split guide: a thin dark inset on the left three-deep branch.
    rounded(buf, size, 0.092, 0.092, 0.605, 0.908, 0.030, (222, 226, 232, 255))
    for (x0, y0, x1, y1, color) in tiles:
        rounded(buf, size, x0, y0, x1, y1, 0.022, color, border=EDGE)
    # A single accent bar marking the framed node.
    rounded(buf, size, 0.628, 0.130, 0.877, 0.168, 0.012, (32, 92, 176, 255))
    return buf


SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset"
    # The WorkBuddy PYTHONPATH shim rejects exist_ok=True with a spurious EEXIST.
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    cache = {}
    for name, size in SIZES.items():
        if size not in cache:
            cache[size] = render(size)
        write_png(os.path.join(outdir, name), size, cache[size])
    print("iconset: %d files in %s" % (len(SIZES), outdir))


if __name__ == "__main__":
    main()
