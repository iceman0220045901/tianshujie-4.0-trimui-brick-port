import os, struct, sys, zlib
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
import importlib.util
_spec = importlib.util.spec_from_file_location("pngcheck", os.path.join(os.path.dirname(os.path.abspath(__file__)), "pngcheck.py"))
pngcheck = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pngcheck)


def decode_rgba(path):
    w, h, rgba = pngcheck.decode(path)
    return w, h, bytearray(rgba)


def encode_rgba(path, w, h, rgba):
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


def box_resize(w, h, rgba, nw, nh):
    """area-average downscale of RGBA"""
    out = bytearray(nw * nh * 4)
    xs0 = [(x * w) // nw for x in range(nw)]
    xs1 = [max(((x + 1) * w) // nw, xs0[x] + 1) for x in range(nw)]
    ys0 = [(y * h) // nh for y in range(nh)]
    ys1 = [max(((y + 1) * h) // nh, ys0[y] + 1) for y in range(nh)]
    for y in range(nh):
        o = y * nw * 4
        for x in range(nw):
            r = g = b = a = 0
            n = 0
            for sy in range(ys0[y], min(ys1[y], h)):
                base = sy * w * 4
                for sx in range(xs0[x], min(xs1[x], w)):
                    p = base + sx * 4
                    r += rgba[p]
                    g += rgba[p + 1]
                    b += rgba[p + 2]
                    a += rgba[p + 3]
                    n += 1
            q = o + x * 4
            out[q] = r // n
            out[q + 1] = g // n
            out[q + 2] = b // n
            out[q + 3] = a // n
    return out


def main():
    src_dir = sys.argv[1]
    out_dir = sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 360
    os.makedirs(out_dir, exist_ok=True)
    done = []
    for name in sorted(os.listdir(src_dir)):
        p = os.path.join(src_dir, name)
        if not os.path.isfile(p) or not name.lower().endswith(".png"):
            continue
        try:
            w, h, rgba = decode_rgba(p)
        except Exception as e:
            print("SKIP", name, "decode:", e)
            continue
        mx = max(w, h)
        if mx <= cap:
            continue
        k = cap / float(mx)
        nw = max(1, int(round(w * k)))
        nh = max(1, int(round(h * k)))
        small = box_resize(w, h, rgba, nw, nh)
        dst = os.path.join(out_dir, name)
        encode_rgba(dst, nw, nh, small)
        done.append((name, w, h, nw, nh))
        print(f"RESIZE {name}: {w}x{h} -> {nw}x{nh}")
    print("TOTAL", len(done))


if __name__ == "__main__":
    main()
