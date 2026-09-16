"""Generate the soft directional fanart scrim in skin coordinates."""

import math
from pathlib import Path

from PIL import Image


def mask_alpha(x, y):
    angle = math.atan2(y - 1180, x + 160)
    distance = abs(math.atan2(math.sin(angle + 0.5), math.cos(angle + 0.5)))
    edge = max(0.0, min(1.0, (distance - math.radians(5)) / math.radians(18)))
    edge = edge * edge * (3 - 2 * edge)
    return round(255 * (0.16 + 0.46 * edge))


def main():
    width, height = 512, 288
    image = Image.new("RGBA", (width, height))
    image.putdata([
        (0, 0, 0, mask_alpha(-960 + (x + 0.5) * 3840 / width,
                            -540 + (y + 0.5) * 2160 / height))
        for y in range(height) for x in range(width)
    ])
    target = Path(__file__).resolve().parents[1] / "media/overlays/fanart-stage-mask.png"
    image.save(target, optimize=True)
    print(f"Generated {target.name}: {width} x {height}, {target.stat().st_size} bytes")


if __name__ == "__main__":
    main()
