"""把 /dev/fb0 抓的 32bpp 原始帧转成 PNG（无第三方库，zlib 手写）。

用法: python raw2png.py <raw> <w> <h> <stride> <bpp_order> <out.png>
bpp_order: bgra / rgba / argb
"""
import struct
import sys
import zlib

raw, w, h, stride, order, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6]
data = open(raw, 'rb').read()

rows = []
for y in range(h):
    off = y * stride
    line = data[off:off + w * 4]
    if len(line) < w * 4:
        line = line + b'\x00' * (w * 4 - len(line))
    px = bytearray(w * 3)
    for x in range(w):
        b, g, r, a = line[x * 4:x * 4 + 4]
        if order == 'rgba':
            r, g, b = line[x * 4], line[x * 4 + 1], line[x * 4 + 2]
        elif order == 'argb':
            a, r, g, b = line[x * 4:x * 4 + 4]
        px[x * 3] = r
        px[x * 3 + 1] = g
        px[x * 3 + 2] = b
    rows.append(bytes(px))

raw_idat = b''.join(b'\x00' + r for r in rows)


def chunk(tag, payload):
    return struct.pack('>I', len(payload)) + tag + payload + struct.pack('>I', zlib.crc32(tag + payload) & 0xFFFFFFFF)


png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw_idat, 6))
png += chunk(b'IEND', b'')
open(out, 'wb').write(png)
print('wrote', out, len(png), 'bytes')
