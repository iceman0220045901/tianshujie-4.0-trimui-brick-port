import sys, struct, zlib, os

W, H = 1024, 768
PIC = 576
Y0 = (H - PIC) // 2          # 96
Y1 = Y0 + PIC                # 672


def px(buf, x, y, r, g, b, a=255):
    p = (y * W + x) * 4
    buf[p] = r
    buf[p + 1] = g
    buf[p + 2] = b
    buf[p + 3] = a


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(round(v))))


def top_value(d):
    """d = 距离画面顶边的像素数（0 在最上，Y0-1 贴着画面）"""
    # 上部机身：从深到略亮
    if d < 70:
        return 30 + int(12 * (d / 70.0))
    if d < 76:
        # 一道凹槽
        return 26
    if d < 78:
        return 40
    # 内沿渐亮到画面边缘
    k = (d - 78) / float(Y0 - 1 - 78)
    return clamp(52 + 96 * (k ** 1.7))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "bars-crt.png"
    buf = bytearray(W * H * 4)   # 全透明

    for y in range(Y0):
        d = y
        v = top_value(d)
        for x in range(W):
            # 左右两侧略暗，做出机身弧面
            e = min(x, W - 1 - x)
            shade = 1.0 if e > 40 else 0.82 + 0.18 * (e / 40.0)
            val = clamp(v * shade)
            px(buf, x, y, val, val, val, 255)

    for y in range(Y1, H):
        d = (H - 1) - y
        v = top_value(d)
        for x in range(W):
            e = min(x, W - 1 - x)
            shade = 1.0 if e > 40 else 0.82 + 0.18 * (e / 40.0)
            val = clamp(v * shade)
            px(buf, x, y, val, val, val, 255)

    # 画面上下边缘各一道极亮的玻璃高光
    for x in range(W):
        px(buf, x, Y0 - 1, 150, 150, 150, 255)
        px(buf, x, Y1, 150, 150, 150, 255)

    raw = bytearray()
    for y in range(H):
        raw.append(0)
        raw += buf[y * W * 4:(y + 1) * W * 4]

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += chunk(b"IEND", b"")
    with open(out, "wb") as f:
        f.write(data)
    print("WROTE", out, W, H, "pic", Y0, "..", Y1 - 1)


main()
