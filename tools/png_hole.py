import sys, os, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngcheck import decode


def hole_bbox(w, h, rgba):
    """从中心做连通填充，取最大透明连通块的包围盒"""
    visited = bytearray(w * h)
    cx, cy = w // 2, h // 2
    if rgba[(cy * w + cx) * 4 + 3] > 8:
        return None
    stack = [(cx, cy)]
    visited[cy * w + cx] = 1
    x0, y0, x1, y1 = cx, cy, cx, cy
    while stack:
        x, y = stack.pop()
        if x < x0: x0 = x
        if x > x1: x1 = x
        if y < y0: y0 = y
        if y > y1: y1 = y
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx]:
                if rgba[(ny * w + nx) * 4 + 3] <= 8:
                    visited[ny * w + nx] = 1
                    stack.append((nx, ny))
    return x0, y0, x1, y1


folder = sys.argv[1]
print('file        canvas   hole x0,y0,x1,y1      hole w*h    aspect')
for f in sorted(glob.glob(os.path.join(folder, '*.png'))):
    w, h, rgba = decode(f)
    bb = hole_bbox(w, h, rgba)
    if bb is None:
        print('%-10s %dx%d  center NOT transparent' % (os.path.basename(f), w, h))
        continue
    x0, y0, x1, y1 = bb
    hw, hh = x1 - x0 + 1, y1 - y0 + 1
    print('%-10s %dx%d  (%d,%d)-(%d,%d)  %dx%d  %.4f' % (
        os.path.basename(f), w, h, x0, y0, x1, y1, hw, hh, hw / float(hh)))
