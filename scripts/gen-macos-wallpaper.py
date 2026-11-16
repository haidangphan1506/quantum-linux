#!/usr/bin/env python3
# Hình nền gốc theo phong cách macOS 27 (các lớp lụa uốn lượn: trái vàng nâu ấm, phải xanh
# xám lạnh, mép sáng màu kem). Tự vẽ bằng toán học — không dùng ảnh của Apple.
# Không cần numpy: vẽ ra PPM rồi dùng ffmpeg làm mềm + thêm hạt và lưu PNG.
#
#   scripts/gen-macos-wallpaper.py [thư_mục_ra] [rộng] [cao]
#   -> <thư_mục_ra>/quantum-silk-light.png và quantum-silk-dark.png
import math
import os
import subprocess
import sys
import tempfile

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Pictures/Wallpapers")
W = int(sys.argv[2]) if len(sys.argv) > 2 else 2560
H = int(sys.argv[3]) if len(sys.argv) > 3 else 1600


def hexc(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smooth(t):
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return t * t * (3 - 2 * t)


# Bảng màu: (tối, sáng) cho phía ấm và phía lạnh
PALETTE = {
    "light": {
        "warm": (hexc("#5f4535"), hexc("#efe4d4")), "gold": hexc("#c9a062"),
        "cool": (hexc("#34344d"), hexc("#c3cad6")), "rim": hexc("#fbf7f0"),
    },
    "dark": {
        "warm": (hexc("#2a1f19"), hexc("#8a6f55")), "gold": hexc("#7a5a32"),
        "cool": (hexc("#15152a"), hexc("#5a6178")), "rim": hexc("#d9d2c6"),
    },
}

# Các đường biên giữa các lớp: y(u) theo tỉ lệ chiều cao, hình chữ S đi lên về bên phải.
# Cùng một dạng sóng, lệch nhau một khoảng -> các lớp không bao giờ cắt nhau.
N = 6
GAP = 0.40


def curve(k, u):
    base = -0.62 + k * GAP - 1.05 * u
    wave = 0.27 * math.sin(2 * math.pi * (0.72 * u + 0.06 * k) + 0.9)
    wave += 0.045 * math.sin(2 * math.pi * (1.7 * u - 0.04 * k) + 0.3)
    return base + wave


def render(mode):
    P = PALETTE[mode]
    rows = bytearray(W * H * 3)
    cols = [[curve(k, x / W) for k in range(N)] for x in range(W)]
    rim_w = 2.8 / H                      # độ dày mép sáng (theo tỉ lệ chiều cao)
    i = 0
    for y in range(H):
        v = y / H
        for x in range(W):
            u = x / W
            cs = cols[x]
            # lớp chứa điểm: giữa đường k (trên) và k+1 (dưới)
            k = 0
            while k < N - 1 and v > cs[k + 1]:
                k += 1
            top = cs[k]
            bot = cs[k + 1] if k < N - 1 else top + GAP
            t = (v - top) / (bot - top) if bot > top else 0
            t = 0.0 if t < 0 else 1.0 if t > 1 else t
            # bóng đổ ngay dưới lớp phía trên, sáng dần tới mép của lớp kế tiếp
            light = 0.04 + 0.96 * smooth(t) ** 1.8
            # trái/trên ấm -> chỉ góc dưới phải lạnh
            s = smooth((u * 0.75 + v * 0.65 + k * 0.04 - 0.78) * 1.6)
            dark_c = mix(P["warm"][0], P["cool"][0], s)
            lite_c = mix(P["warm"][1], P["cool"][1], s)
            c = mix(dark_c, lite_c, light)
            # ánh vàng ở mép trái
            g = max(0.0, 1 - u * 2.2) * (0.55 + 0.45 * light)
            c = mix(c, P["gold"], g * 0.55)
            # mép sáng mảnh dọc theo đường biên
            d = abs(v - bot) if k < N - 1 else 1
            if d < rim_w * 4:
                r = math.exp(-(d / rim_w) ** 2)
                c = mix(c, P["rim"], r * 0.9)
                # viền tối rất mảnh ngay dưới mép sáng: tạo độ dày như tờ giấy
                if v > bot:
                    sh = math.exp(-((d - rim_w * 2) / rim_w) ** 2)
                    c = mix(c, dark_c, sh * 0.25)
            rows[i] = int(min(1, c[0]) * 255)
            rows[i + 1] = int(min(1, c[1]) * 255)
            rows[i + 2] = int(min(1, c[2]) * 255)
            i += 3
    return rows


def main():
    os.makedirs(OUT, exist_ok=True)
    for mode in ("light", "dark"):
        data = render(mode)
        with tempfile.NamedTemporaryFile(suffix=".ppm", delete=False) as f:
            f.write(b"P6\n%d %d\n255\n" % (W, H))
            f.write(data)
            ppm = f.name
        out = os.path.join(OUT, f"quantum-silk-{mode}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ppm,
                        "-vf", "gblur=sigma=1.4,noise=alls=4:allf=t", out], check=True)
        os.unlink(ppm)
        print(out)


if __name__ == "__main__":
    main()
