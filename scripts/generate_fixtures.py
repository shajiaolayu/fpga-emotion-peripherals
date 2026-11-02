"""Generate public synthetic inputs. No image, score or parameter comes from a model."""
from pathlib import Path
import math
import random


def write_mem(path: Path, values: list[int], width: int) -> None:
    mask = (1 << (width * 4)) - 1
    path.write_text("".join(f"{value & mask:0{width}x}\n" for value in values), encoding="ascii")


def make_frame(tag: int) -> list[int]:
    return [
        (((x * 3 + y + tag * 11) % 32) << 11)
        | (((x + y * 5 + tag * 17) % 64) << 5)
        | ((x * 7 + y * 3 + tag * 13) % 32)
        for y in range(240) for x in range(320)
    ]


def reference_gray(frame: list[int]) -> list[int]:
    """Independent integer reference for RGB565 expansion, luminance and 4x4 averaging."""
    luminance = []
    for pixel in frame:
        r, g, b = (pixel >> 11) & 31, (pixel >> 5) & 63, pixel & 31
        r, g, b = (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)
        luminance.append((77 * r + 150 * g + 29 * b + 128) // 256)
    return [
        (sum(luminance[(24 + 4 * y + dy) * 320 + 64 + 4 * x + dx]
             for dy in range(4) for dx in range(4)) + 8) // 16
        for y in range(48) for x in range(48)
    ]


def generate(destination: Path) -> None:
    for tag in range(2):
        frame = make_frame(tag)
        write_mem(destination / f"camera{tag}.mem", frame, 4)
        write_mem(destination / f"gray{tag}.mem", reference_gray(frame), 2)
    vectors = [
        [0] * 7, [-8192] * 7, [-32768, -16384, -8192, 0, 8192, 16384, 32768],
        [2147483647, -2147483648, 0, -1, 1, 42, -42],
        [-2147483648] * 7, [2147483647] * 7,
        [-10000, -20000, -30000, -40000, -50000, -60000, -70000],
    ]
    rng = random.Random(5640)
    vectors += [[rng.randint(-100000, 100000) for _ in range(7)] for _ in range(32)]
    expected = []
    for row in vectors:
        maximum = max(row)
        exp = [math.exp((value - maximum) / 8192.0) for value in row]
        expected.extend(round(1000 * value / sum(exp)) for value in exp)
    write_mem(destination / "formatter_scores.mem", [n for row in vectors for n in row], 8)
    write_mem(destination / "formatter_expected.mem", expected, 3)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    generate(args.destination)
