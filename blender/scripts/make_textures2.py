"""Run 2 textures (business district, residential district). System Python: numpy + pillow.
usage: python blender/scripts/make_textures2.py
panel  - prefab concrete panels with soft seams (multiplied by the facade colour)
plaza  - big light stone plaza slabs with thin joints
glass  - soft vertical sky reflection streaks for glass towers
"""
import numpy as np
from make_textures import save, blur, value_noise, S


def panel():
    n = S
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    # 2 x 2 panels per tile, joints 1.2 % wide, slight per-panel tone
    gx = np.minimum(np.abs((xx * 2) % 1 - 0.0), np.abs((xx * 2) % 1 - 1.0))
    gy = np.minimum(np.abs((yy * 2) % 1 - 0.0), np.abs((yy * 2) % 1 - 1.0))
    seam = np.clip(1 - np.minimum(gx, gy) / 0.012, 0, 1)
    seam = blur(seam, 2)
    pid = (np.floor(xx * 2) + 2 * np.floor(yy * 2)).astype(int)
    tone = np.array([1.0, 0.965, 0.985, 0.95])[pid % 4]
    noise = value_noise(n, 24, 3) * 0.05
    v = tone * (0.97 + noise) - seam * 0.22
    rgb = np.stack([v, v * 0.995, v * 0.985], -1)
    save("panel", rgb)


def plaza():
    n = S
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    # running-bond slabs: 2 columns x 4 rows, every other row shifted by half
    row = np.floor(yy * 4)
    sx = (xx * 2 + 0.5 * (row % 2)) % 1
    sy = (yy * 4) % 1
    joint = np.clip(1 - np.minimum(np.minimum(sx, 1 - sx) * 2, np.minimum(sy, 1 - sy)) / 0.018, 0, 1)
    joint = blur(joint, 1.5)
    sid = (np.floor(xx * 2 + 0.5 * (row % 2)) * 7 + row * 3).astype(int)
    tone = 0.93 + 0.05 * np.sin(sid * 1.7)
    noise = value_noise(n, 32, 5) * 0.04
    v = tone + noise - joint * 0.25
    rgb = np.stack([v, v * 0.985, v * 0.96], -1)
    save("plaza", rgb)


def glass():
    n = S
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    streak = value_noise(n, 8, 11)[0:1, :].repeat(n, 0)
    v = 0.86 + 0.14 * streak - 0.08 * yy
    rgb = np.stack([v * 0.95, v, v * 1.02], -1)
    save("glass", np.clip(rgb, 0, 1))


if __name__ == "__main__":
    panel()
    plaza()
    glass()
