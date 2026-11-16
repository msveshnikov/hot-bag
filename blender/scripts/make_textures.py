"""Cartoon tileable textures painted with numpy (system Python: numpy + pillow).
Written to assets/textures/. Big readable patterns, soft AO in the seams, no photo noise.
usage: python blender/scripts/make_textures.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(7)
S = 512


def save(name, rgb, size=S):
    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB")
    if img.size[0] != size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))
    print("tex", name)


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")
    # wrap-around blur: tile 3x3, blur, crop centre
    n = a.shape[0]
    big = Image.new("L", (n * 3, n * 3))
    for i in range(3):
        for j in range(3):
            big.paste(im, (i * n, j * n))
    big = big.filter(ImageFilter.GaussianBlur(r))
    return np.asarray(big.crop((n, n, 2 * n, 2 * n))).astype(np.float32) / 255


def value_noise(n, cells, seed):
    r = np.random.default_rng(seed)
    g = r.random((cells, cells))
    x = np.linspace(0, cells, n, endpoint=False)
    i0 = np.floor(x).astype(int)
    f = x - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[np.ix_(i0, i0)] * (1 - f)[None, :] + g[np.ix_(i0, i1)] * f[None, :]
    b = g[np.ix_(i1, i0)] * (1 - f)[None, :] + g[np.ix_(i1, i1)] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def voronoi_cells(n, pts):
    """returns (cell id, edge distance 0..1) for wrap-around points"""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    d1 = np.full((n, n), 9.0, np.float32)
    d2 = np.full((n, n), 9.0, np.float32)
    idx = np.zeros((n, n), np.int32)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(xx - px); dx = np.minimum(dx, 1 - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, 1 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, k, idx)
        d1 = np.where(closer, d, d1)
    return idx, d2 - d1


def cobble():
    # rounded cobbles on a jittered grid, warm grey-beige palette
    pts = []
    g = 9
    for i in range(g):
        for j in range(g):
            pts.append(((i + 0.5 + RNG.uniform(-.25, .25)) / g, (j + 0.5 + RNG.uniform(-.25, .25)) / g))
    idx, edge = voronoi_cells(S, pts)
    pal = [hexc(c) for c in ("#b9a89a", "#a8978a", "#c4b3a2", "#9d8f86", "#b3a08d", "#c9b8a6")]
    col = np.array([pal[RNG.integers(len(pal))] for _ in pts])[idx]
    mortar = hexc("#6f6158")
    t = np.clip(edge / 0.018, 0, 1)
    bump = np.sqrt(np.clip(edge / 0.05, 0, 1))  # domed stones
    shade = 0.78 + 0.22 * bump
    rgb = col * shade[..., None]
    rgb = rgb * t[..., None] + mortar * (1 - t[..., None])
    hl = blur(np.clip((bump - 0.7) * 3, 0, 1), 3)[..., None] * 0.08
    save("cobble", rgb + hl)


def asphalt():
    n = value_noise(S, 16, 3) * 0.5 + value_noise(S, 64, 4) * 0.5
    base = hexc("#4b4f57")
    rgb = base[None, None, :] * (0.92 + 0.12 * n[..., None])
    save("asphalt", rgb)


def sidewalk():
    # large square slabs, light warm grey
    yy, xx = np.mgrid[0:S, 0:S]
    k = 4
    cs = S // k
    gx = (xx % cs) / cs; gy = (yy % cs) / cs
    e = np.minimum(np.minimum(gx, 1 - gx), np.minimum(gy, 1 - gy))
    cell = (xx // cs) * 7 + (yy // cs) * 13
    var = (np.sin(cell * 12.9898) * 43758.5453) % 1
    base = hexc("#cfc6ba")
    rgb = base * (0.94 + 0.08 * var[..., None])
    groove = np.clip(e / 0.025, 0, 1)
    rgb = rgb * (0.72 + 0.28 * groove[..., None])
    save("sidewalk", rgb)


def roof_tiles():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    rows = 8
    rh = S / rows
    r = (yy // rh)
    off = (r % 2) * 0.5
    cols = 8
    u = ((xx / S * cols) + off) % 1
    v = (yy % rh) / rh
    # scalloped tile: darker at bottom edge of each row, round bottom
    curve = 1 - (2 * u - 1) ** 2
    edge = v - 0.85 * (0.85 + 0.15 * curve)
    shade = np.where(edge > 0, 0.62, 0.9 + 0.12 * (1 - v))
    side = np.clip(np.minimum(u, 1 - u) / 0.06, 0, 1)
    shade = shade * (0.8 + 0.2 * side)
    base = hexc("#c8613f")
    var = ((np.floor(xx / S * cols + off) * 3 + r * 7) * 0.618) % 1
    rgb = base * (shade * (0.93 + 0.1 * var))[..., None]
    save("roof_tiles", rgb)


def plaster():
    # very soft cloudy white; multiplied by facade colour in the material
    n = value_noise(S, 6, 11) * 0.6 + value_noise(S, 24, 12) * 0.4
    rgb = np.repeat((0.9 + 0.1 * n)[..., None], 3, -1)
    save("plaster", rgb)


def brick():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    rows = 16; rh = S / rows
    r = yy // rh
    u = ((xx / S * 8) + (r % 2) * 0.5) % 1
    v = (yy % rh) / rh
    e = np.minimum(np.minimum(u, 1 - u) * 4, np.minimum(v, 1 - v))
    m = np.clip(e / 0.12, 0, 1)
    var = ((np.floor(xx / S * 8 + (r % 2) * .5) * 5 + r * 3) * 0.618) % 1
    brickc = hexc("#b5563b") * (0.9 + 0.15 * var[..., None])
    rgb = brickc * m[..., None] + hexc("#d9c9b6") * (1 - m[..., None])
    save("brick", rgb)


def wood():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    planks = 6
    p = xx // (S / planks)
    u = (xx % (S / planks)) / (S / planks)
    grain = np.sin((yy / S * 6 + p * 1.7) * np.pi * 2 + value_noise(S, 8, 5) * 6) * 0.5 + 0.5
    base = hexc("#9a6a43")
    rgb = base * (0.85 + 0.1 * grain[..., None] + 0.06 * ((p * 0.37) % 1)[..., None])
    rgb *= (0.7 + 0.3 * np.clip(np.minimum(u, 1 - u) / 0.04, 0, 1))[..., None]
    save("wood", rgb)


def grass():
    n = value_noise(S, 8, 21) * 0.6 + value_noise(S, 32, 22) * 0.4
    rgb = hexc("#7cc35b") * (0.85 + 0.25 * n[..., None])
    save("grass", rgb)


def park_path():
    n = value_noise(S, 10, 31) * 0.5 + value_noise(S, 48, 32) * 0.5
    rgb = hexc("#d8bf94") * (0.88 + 0.16 * n[..., None])
    save("park_path", rgb)


def water():
    n = value_noise(S, 6, 41) * 0.5 + value_noise(S, 20, 42) * 0.5
    rgb = hexc("#3fa7c9") * (0.85 + 0.25 * n[..., None])
    save("water", rgb)


def stone():
    # large ashlar blocks for parapets, tower base, stairs
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    rows = 4; rh = S / rows
    r = yy // rh
    u = ((xx / S * 3) + (r % 2) * 0.5) % 1
    v = (yy % rh) / rh
    e = np.minimum(np.minimum(u, 1 - u) * 3, np.minimum(v, 1 - v))
    m = np.clip(e / 0.06, 0, 1)
    var = ((np.floor(xx / S * 3 + (r % 2) * .5) * 5 + r * 3) * 0.618) % 1
    rgb = hexc("#d6c3a3") * (0.9 + 0.12 * var[..., None]) * (0.7 + 0.3 * m[..., None])
    save("stone", rgb)


if __name__ == "__main__":
    for f in (cobble, asphalt, sidewalk, roof_tiles, plaster, brick, wood, grass, park_path, water, stone):
        f()
    print("DONE")
