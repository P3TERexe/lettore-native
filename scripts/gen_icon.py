"""Genera icona tray PNG (16x16 template) e icona app (32x32) con stdlib.

Uso: python scripts/gen_icon.py
"""

import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def make_png(size: int, pixels: list[list[tuple[int, int, int, int]]]) -> bytes:
    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *p) for p in row) for row in pixels
    )
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(raw, 9))
        + png_chunk(b"IEND", b"")
    )


def speaker(size: int, rgb: tuple[int, int, int]) -> list[list[tuple[int, int, int, int]]]:
    """Disegna un altoparlante stilizzato."""
    px = [[(0, 0, 0, 0)] * size for _ in range(size)]
    body = (size * 0.19, size * 0.25, size * 0.62, size * 0.75)  # colonna
    x0, y0, x1, y1 = body
    for y in range(size):
        for x in range(size):
            fx, fy = x + 0.5, y + 0.5
            in_body = x0 <= fx <= x1 and y0 <= fy <= y1
            in_cone = (x1 <= fx) and (y0 <= fy <= y1) and (fy - y0) <= (y1 - y0) * (fx - x1) / (size - x1)
            if in_body or in_cone:
                px[y][x] = (*rgb, 255)
    return px


def main() -> int:
    out_dir = ROOT / "ui" / "assets"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "iconTemplate.png").write_bytes(make_png(16, speaker(16, (0, 0, 0))))
    (out_dir / "icon.png").write_bytes(make_png(32, speaker(32, (122, 162, 247))))
    print(f"Icona generata in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
