#!/usr/bin/env python3
"""Generates the procedural textures (PNG) and sound effects (WAV) used by the game.

Only uses the Python standard library. Run from the project root:

    python3 tools/generate_assets.py
"""
import math
import os
import random
import struct
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "sprites", "game")
SOUNDS = os.path.join(ROOT, "sounds")


# ---------------------------------------------------------------- PNG helpers

def write_png(path, w, h, pixels):
    """pixels: list of (r, g, b, a) tuples, row-major, top row first."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            raw += bytes((clamp(r), clamp(g), clamp(b), clamp(a)))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def clamp(v):
    return max(0, min(255, int(v)))


def value_noise(size, cells, seed):
    """Tileable value noise in [0, 1]."""
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(cells)] for _ in range(cells)]
    out = []
    for y in range(size):
        for x in range(size):
            fx = x / size * cells
            fy = y / size * cells
            x0, y0 = int(fx), int(fy)
            tx, ty = fx - x0, fy - y0
            tx = tx * tx * (3 - 2 * tx)
            ty = ty * ty * (3 - 2 * ty)
            a = grid[y0 % cells][x0 % cells]
            b = grid[y0 % cells][(x0 + 1) % cells]
            c = grid[(y0 + 1) % cells][x0 % cells]
            d = grid[(y0 + 1) % cells][(x0 + 1) % cells]
            out.append((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)
    return out


def fbm(size, seed, octaves=4):
    total = [0.0] * (size * size)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        n = value_noise(size, 4 * (2 ** o), seed + o * 17)
        for i in range(len(total)):
            total[i] += n[i] * amp
        norm += amp
        amp *= 0.5
    return [t / norm for t in total]


# ---------------------------------------------------------------- textures

S = 128


def rock(seed, base, dark):
    n = fbm(S, seed, 5)
    cracks = value_noise(S, 8, seed + 99)
    px = []
    for i, v in enumerate(n):
        c = cracks[i]
        crack = 1.0 if abs(c - 0.5) > 0.03 else 0.45
        t = v * crack
        px.append(tuple(dark[k] + (base[k] - dark[k]) * t for k in range(3)) + (255,))
    return px


def metal(seed, base, seam_every=64):
    n = fbm(S, seed, 3)
    px = []
    for y in range(S):
        for x in range(S):
            v = 0.8 + 0.25 * n[y * S + x]
            sx, sy = x % seam_every, y % seam_every
            if sx in (0, seam_every - 1) or sy in (0, seam_every - 1):
                v *= 0.45
            elif sx == 1 or sy == 1:
                v *= 1.25
            for rx, ry in ((6, 6), (seam_every - 7, 6), (6, seam_every - 7), (seam_every - 7, seam_every - 7)):
                if (sx - rx) ** 2 + (sy - ry) ** 2 <= 4:
                    v *= 1.4 if sx < rx or sy < ry else 0.6
            px.append((base[0] * v, base[1] * v, base[2] * v, 255))
    return px


def door(color):
    base = metal(5, (150, 150, 155), 128)
    px = []
    for y in range(S):
        for x in range(S):
            r, g, b, a = base[y * S + x]
            stripe = ((x + y) // 12) % 2 == 0
            if 40 <= y <= 88 and (x < 16 or x > 111):
                r, g, b = (color if stripe else (30, 30, 30))
            if 20 <= x <= 107 and 56 <= y <= 72:
                r, g, b = color[0] * 0.9, color[1] * 0.9, color[2] * 0.9
            if x in (63, 64):
                r, g, b = 20, 20, 20
            px.append((r, g, b, a))
    return px


def grate():
    n = fbm(S, 31, 3)
    px = []
    for y in range(S):
        for x in range(S):
            v = n[y * S + x]
            bar = (x % 16 < 4) or (y % 16 < 4)
            if bar:
                px.append((60 + 60 * v, 200 + 55 * v, 90 + 50 * v, 255))
            else:
                px.append((10, 40 + 30 * v, 15, 255))
    return px


def tech():
    base = metal(77, (90, 110, 150), 32)
    rnd = random.Random(4)
    lights = [(rnd.randrange(4, 28), rnd.randrange(4, 28)) for _ in range(4)]
    px = []
    for y in range(S):
        for x in range(S):
            r, g, b, a = base[y * S + x]
            lx, ly = x % 32, y % 32
            for (cx, cy) in lights:
                if abs(lx - cx) <= 1 and abs(ly - cy) <= 1:
                    r, g, b = 255, 200, 90
            px.append((r, g, b, a))
    return px


def glow(size=64):
    px = []
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.sqrt((x - c) ** 2 + (y - c) ** 2) / c
            a = max(0.0, 1.0 - d) ** 2
            core = max(0.0, 1.0 - d * 3)
            px.append((255, 255, 255, 255 * min(1.0, a + core)))
    return px


def solid_white(size=8):
    return [(255, 255, 255, 255)] * (size * size)


def build_textures():
    os.makedirs(SPRITES, exist_ok=True)
    write_png(os.path.join(SPRITES, "rock.png"), S, S, rock(1, (150, 118, 88), (40, 30, 24)))
    write_png(os.path.join(SPRITES, "rock_dark.png"), S, S, rock(2, (110, 100, 105), (25, 22, 28)))
    write_png(os.path.join(SPRITES, "lava_rock.png"), S, S, rock(3, (200, 90, 40), (50, 15, 10)))
    write_png(os.path.join(SPRITES, "metal.png"), S, S, metal(4, (130, 135, 140)))
    write_png(os.path.join(SPRITES, "tech.png"), S, S, tech())
    write_png(os.path.join(SPRITES, "door_blue.png"), S, S, door((50, 110, 255)))
    write_png(os.path.join(SPRITES, "door_red.png"), S, S, door((230, 40, 40)))
    write_png(os.path.join(SPRITES, "door_yellow.png"), S, S, door((240, 200, 40)))
    write_png(os.path.join(SPRITES, "grate.png"), S, S, grate())
    write_png(os.path.join(SPRITES, "glow.png"), 64, 64, glow())
    write_png(os.path.join(SPRITES, "white.png"), 8, 8, solid_white())


# ---------------------------------------------------------------- sounds

RATE = 22050


def write_wav(name, samples):
    os.makedirs(SOUNDS, exist_ok=True)
    with wave.open(os.path.join(SOUNDS, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def envelope(i, n, attack=0.005, curve=2.0):
    t = i / n
    a = min(1.0, i / (attack * RATE + 1))
    return a * (1 - t) ** curve


def laser():
    n = int(RATE * 0.18)
    out, phase = [], 0.0
    for i in range(n):
        f = 1800 * (1 - i / n) + 300
        phase += f / RATE
        s = 1.0 if (phase % 1) < 0.5 else -1.0
        out.append(0.35 * s * envelope(i, n))
    return out


def robot_shot():
    n = int(RATE * 0.25)
    out, phase = [], 0.0
    for i in range(n):
        f = 500 + 300 * math.sin(i / RATE * 60)
        phase += f / RATE
        out.append(0.35 * math.sin(phase * 2 * math.pi) * envelope(i, n))
    return out


def noise_burst(seconds, lowpass, gain, curve=1.5, seed=1):
    rnd = random.Random(seed)
    n = int(RATE * seconds)
    out, y = [], 0.0
    for i in range(n):
        y += lowpass * (rnd.uniform(-1, 1) - y)
        out.append(gain * y * envelope(i, n, 0.002, curve))
    return out


def explosion():
    base = noise_burst(1.2, 0.08, 2.6, 1.8, 3)
    n = len(base)
    return [s + 0.4 * math.sin(i / RATE * 2 * math.pi * 45) * envelope(i, n, 0.002, 3) for i, s in enumerate(base)]


def missile():
    whoosh = noise_burst(0.6, 0.25, 0.9, 1.0, 9)
    n = len(whoosh)
    return [s + 0.25 * math.sin(i / RATE * 2 * math.pi * (180 - 100 * i / n)) * envelope(i, n) for i, s in enumerate(whoosh)]


def hit():
    return noise_burst(0.2, 0.5, 0.9, 2.0, 5)


def pickup():
    n = int(RATE * 0.3)
    out = []
    for i in range(n):
        t = i / RATE
        f = 600 if t < 0.1 else (900 if t < 0.2 else 1200)
        out.append(0.3 * math.sin(t * 2 * math.pi * f) * envelope(i, n, 0.002, 0.8))
    return out


def door_sound():
    n = int(RATE * 0.8)
    rnd = random.Random(12)
    out, y = [], 0.0
    for i in range(n):
        y += 0.05 * (rnd.uniform(-1, 1) - y)
        hum = math.sin(i / RATE * 2 * math.pi * 70)
        out.append((1.5 * y + 0.3 * hum) * math.sin(math.pi * i / n))
    return out


def alarm():
    n = int(RATE * 1.0)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = 500 + 400 * (t * 2 if t < 0.5 else 2 - t * 2)
        phase += f / RATE
        out.append(0.3 * (1.0 if (phase % 1) < 0.5 else -1.0))
    return out


def build_sounds():
    write_wav("laser.wav", laser())
    write_wav("robot_shot.wav", robot_shot())
    write_wav("explosion.wav", explosion())
    write_wav("missile.wav", missile())
    write_wav("hit.wav", hit())
    write_wav("pickup.wav", pickup())
    write_wav("door.wav", door_sound())
    write_wav("alarm.wav", alarm())


if __name__ == "__main__":
    build_textures()
    build_sounds()
    print("assets written to", SPRITES, "and", SOUNDS)
