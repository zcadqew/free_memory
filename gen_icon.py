#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
无依赖生成器：渲染"内存清理图标"并打包成多尺寸 .ico（16/32/48/256）。
纯 Python 标准库（struct / zlib / math），无需 Pillow / ImageMagick。
"""
import struct
import zlib
import math

# 调色板（黑底 Fluent）
TILE   = (14, 14, 14, 255)
SHADE  = (26, 26, 26, 120)
BORDER = (58, 58, 58, 255)
WHITE  = (255, 255, 255, 255)
CHIP   = (44, 44, 42, 255)
GOLDB  = (201, 136, 27, 255)
GOLD   = (239, 159, 39, 255)

# 模块级可变状态（每次 render 前赋值）
buf = bytearray()
N = 0
K = 0.0


def blend(x, y, r, g, b, a):
    x = int(x); y = int(y)
    if x < 0 or y < 0 or x >= N or y >= N or a <= 0:
        return
    i = (y * N + x) * 4
    sa = a / 255.0
    da = buf[i + 3] / 255.0
    oa = sa + da * (1 - sa)
    if oa <= 0:
        return
    for c, val in ((0, r), (1, g), (2, b)):
        buf[i + c] = int((val * sa + buf[i + c] * da * (1 - sa)) / oa + 0.5)
    buf[i + 3] = int(oa * 255 + 0.5)


def inside_rr(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    if x < x0 + r and y < y0 + r:
        return (x0 + r - x) ** 2 + (y0 + r - y) ** 2 <= r * r
    if x > x1 - r and y < y0 + r:
        return (x1 - r - x) ** 2 + (y0 + r - y) ** 2 <= r * r
    if x < x0 + r and y > y1 - r:
        return (x0 + r - x) ** 2 + (y1 - r - y) ** 2 <= r * r
    if x > x1 - r and y > y1 - r:
        return (x1 - r - x) ** 2 + (y1 - r - y) ** 2 <= r * r
    return True


def fill_rr(x0, y0, x1, y1, r, col):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            if inside_rr(x, y, x0, y0, x1, y1, r):
                blend(x, y, *col)


def stroke_rr(x0, y0, x1, y1, r, thick, col):
    t = thick
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            if inside_rr(x, y, x0, y0, x1, y1, r) and not inside_rr(
                x, y, x0 + t, y0 + t, x1 - t, y1 - t, max(r - t, 0)):
                blend(x, y, *col)


def fill_ellipse(cx, cy, rx, ry, col):
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                blend(x, y, *col)


def pip(x, y, poly):
    inside = False
    n = len(poly); j = n - 1
    for i in range(n):
        xi, yi = poly[i]; xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def fill_poly(poly, col):
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        for x in range(int(min(xs)), int(max(xs)) + 1):
            if pip(x, y, poly):
                blend(x, y, *col)


def star(cx, cy, R, r):
    s = r / math.sqrt(2)
    return [(cx, cy - R), (cx + s, cy - s), (cx + R, cy), (cx + s, cy + s),
            (cx, cy + R), (cx - s, cy + s), (cx - R, cy), (cx - s, cy - s)]


def sk(v):
    return v * K


def render(size):
    global buf, N, K
    N = size * 4          # 4x 超采样
    K = N / 680.0
    buf = bytearray(N * N * 4)

    tx0, ty0, tx1, ty1, tr = sk(120), sk(120), sk(560), sk(560), sk(96)
    fill_rr(tx0, ty0, tx1, ty1, tr, TILE)
    fill_ellipse(sk(340), sk(505), sk(310), sk(230), SHADE)
    fill_rr(sk(232), sk(250), sk(448), sk(426), sk(20), WHITE)
    for cx in (258, 316, 374):
        fill_rr(sk(cx), sk(286), sk(cx + 48), sk(390), sk(9), CHIP)
    fill_rr(sk(252), sk(420), sk(444), sk(428), sk(3), GOLDB)
    for px in (258, 274, 290, 306, 354, 370, 386, 402, 418, 434):
        fill_rr(sk(px), sk(424), sk(px + 9), sk(470), sk(2), GOLD)
    stroke_rr(tx0, ty0, tx1, ty1, tr, sk(3), BORDER)
    fill_poly([(sk(a), sk(b)) for a, b in star(500, 185, 38, 9)], WHITE)
    fill_poly([(sk(a), sk(b)) for a, b in star(455, 150, 18, 5)], (255, 255, 255, 217))
    # 裁剪到磁贴外透明
    for y in range(N):
        for x in range(N):
            if not inside_rr(x, y, tx0, ty0, tx1, ty1, tr):
                i = (y * N + x) * 4
                buf[i] = buf[i + 1] = buf[i + 2] = buf[i + 3] = 0
    return downsample(N, size)


def downsample(N, OUT):
    block = N // OUT
    out = bytearray(OUT * OUT * 4)
    for oy in range(OUT):
        for ox in range(OUT):
            rs = gs = bs = as_ = 0
            for dy in range(block):
                for dx in range(block):
                    i = ((oy * block + dy) * N + (ox * block + dx)) * 4
                    rs += buf[i]; gs += buf[i + 1]; bs += buf[i + 2]; as_ += buf[i + 3]
            n = block * block
            j = (oy * OUT + ox) * 4
            out[j] = rs // n; out[j + 1] = gs // n
            out[j + 2] = bs // n; out[j + 3] = as_ // n
    return out


def png_encode(w, h, data):
    def chunk(typ, payload):
        return (struct.pack('>I', len(payload)) + typ + payload +
                struct.pack('>I', zlib.crc32(typ + payload) & 0xffffffff))
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += data[y * stride:(y + 1) * stride]
    idat = zlib.compress(bytes(raw), 9)
    return sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')


def build_ico(images):
    # images: list of (size, png_bytes)
    count = len(images)
    entries = b''
    data = b''
    offset = 6 + count * 16
    for size, png in images:
        b = b''
        b += struct.pack('<BB', 0 if size >= 256 else size, 0 if size >= 256 else size)
        b += struct.pack('<BB', 0, 0)
        b += struct.pack('<H', 1)
        b += struct.pack('<H', 32)
        b += struct.pack('<I', len(png))
        b += struct.pack('<I', offset)
        entries += b
        data += png
        offset += len(png)
    return struct.pack('<HHH', 0, 1, count) + entries + data


def main():
    images = []
    for size in (256, 48, 32, 16):
        out = render(size)
        png = png_encode(size, size, out)
        images.append((size, png))
        print('  rendered %dx%d png=%d bytes' % (size, size, len(png)))
    ico = build_ico(images)
    with open('memory-cleanup-icon.ico', 'wb') as f:
        f.write(ico)
    # 同时输出 256 预览图便于检查
    with open('icon_preview.png', 'wb') as f:
        f.write(images[0][1])
    print('OK -> memory-cleanup-icon.ico  total=%d bytes, sizes=%s'
          % (len(ico), [s for s, _ in images]))


if __name__ == '__main__':
    main()
