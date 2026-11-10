import os, sys, struct, zlib, importlib.util

here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("pngcheck", os.path.join(here, "pngcheck.py"))
pngcheck = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pngcheck)

WA, HA = 1024, 768
PIC = 576
Y0 = (HA - PIC) // 2
Y1 = Y0 + PIC


def decode(p):
    w, h, rgba = pngcheck.decode(p)
    return w, h, bytearray(rgba)


def bilinear(w, h, buf, x0, y0, cw, ch, nw, nh):
    out = bytearray(nw * nh * 4)
    for y in range(nh):
        sy = y0 + (y + 0.5) * ch / nh - 0.5
        yy0 = int(sy) if sy >= 0 else 0
        yy1 = min(yy0 + 1, h - 1)
        fy = sy - yy0
        for x in range(nw):
            sx = x0 + (x + 0.5) * cw / nw - 0.5
            xx0 = int(sx) if sx >= 0 else 0
            xx1 = min(xx0 + 1, w - 1)
            fx = sx - xx0
            o = (y * nw + x) * 4
            for k in range(4):
                p00 = (yy0 * w + xx0) * 4 + k
                p01 = (yy0 * w + xx1) * 4 + k
                p10 = (yy1 * w + xx0) * 4 + k
                p11 = (yy1 * w + xx1) * 4 + k
                v = (buf[p00] * (1 - fx) + buf[p01] * fx) * (1 - fy) + (buf[p10] * (1 - fx) + buf[p11] * fx) * fy
                out[o + k] = max(0, min(255, int(round(v))))
    return out


def encode(path, w, h, rgba):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgba[y * w * 4:(y + 1) * w * 4]

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)


def main():
    src = sys.argv[1]        # 已带可见机框的 crt-visible.png
    dst = sys.argv[2]
    hole = (43, 36, 1096, 819)   # crt.png 的镂空位置，crt-visible 同轮廓
    w, h, buf = decode(src)
    if (w, h) != (1140, 856):
        print("WARN src", w, h)

    canvas = bytearray(WA * HA * 4)

    # 上边带 = 源图 0..hole_top-1 全宽，拉成 1024x96
    ch = hole[1]
    band = bilinear(w, h, buf, 0, 0, w, ch, WA, Y0)
    canvas[0:WA * Y0 * 4] = band

    # 下边带 = 源图 hole_bottom.. 底 全宽，拉成 1024x96
    yb = hole[3]
    chb = h - yb
    band2 = bilinear(w, h, buf, 0, yb, w, chb, WA, HA - Y1)
    canvas[Y1 * WA * 4:] = band2

    encode(dst, WA, HA, canvas)
    print("WROTE", dst)


main()
