import os, sys, struct, zlib, importlib.util

here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("pngcheck", os.path.join(here, "pngcheck.py"))
pngcheck = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pngcheck)


def decode(path):
    w, h, rgba = pngcheck.decode(path)
    return w, h, bytearray(rgba)


def encode(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


def main():
    src = sys.argv[1]                      # 模拟器遮罩原图
    dst = sys.argv[2]                      # 输出
    panel_w = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    panel_h = int(sys.argv[4]) if len(sys.argv) > 4 else 768
    pic_h = int(sys.argv[5]) if len(sys.argv) > 5 else 576   # 画面高度，画面满宽居中

    w, h, rgba = decode(src)
    if (w, h) != (panel_w, panel_h):
        print("WARN size %dx%d != %dx%d" % (w, h, panel_w, panel_h))

    y0 = (panel_h - pic_h) // 2            # 画面顶边
    y1 = y0 + pic_h

    # 只保留画面上下两条边带，画面区域在其宽度范围内全部设为透明
    for y in range(y0, y1):
        base = y * w * 4
        for x in range(w):
            p = base + x * 4
            rgba[p] = 0
            rgba[p + 1] = 0
            rgba[p + 2] = 0
            rgba[p + 3] = 0

    # 统计保留下来的边框覆盖范围
    opaque_rows = []
    for y in range(h):
        row = y * w * 4
        if any(rgba[row + x * 4 + 3] > 0 for x in range(w)):
            opaque_rows.append(y)
    print("bars rows: %s .. %s and %s .. %s" % (opaque_rows[0], y0 - 1, y1, opaque_rows[-1]))

    encode(dst, w, h, rgba)
    print("WROTE", dst, w, h)


main()
