#!/usr/bin/env python3
"""Generate mark#palettes#Tailwind() from Tailwind's OKLCH theme colors."""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

# Change these two sequences to choose or reorder the generated palette.
HUES = (
    "red", "orange", "amber", "yellow", "lime", "green", "emerald", "teal",
    "cyan", "sky", "blue", "indigo", "violet", "purple", "fuchsia", "pink",
    "rose",
)
SHADES = (200, 400, 600, 800)

COLOR_RE = re.compile(
    r"--color-([a-z]+)-(\d+):\s*oklch\("
    r"([\d.]+)%\s+([\d.]+)\s+([\d.]+)\);"
)
XTERM_STEPS = (0, 95, 135, 175, 215, 255)


def parse_colors(source: str) -> dict[tuple[str, int], tuple[float, float, float]]:
    colors = {}
    for hue, shade, lightness, chroma, angle in COLOR_RE.findall(source):
        colors[(hue, int(shade))] = (
            float(lightness) / 100,
            float(chroma),
            float(angle),
        )
    return colors


def oklch_to_srgb(oklch: tuple[float, float, float]) -> tuple[int, int, int]:
    lightness, chroma, angle = oklch
    radians = math.radians(angle)
    a = chroma * math.cos(radians)
    b = chroma * math.sin(radians)

    l_root = lightness + 0.3963377774 * a + 0.2158037573 * b
    m_root = lightness - 0.1055613458 * a - 0.0638541728 * b
    s_root = lightness - 0.0894841775 * a - 1.2914855480 * b
    l_value, m_value, s_value = l_root**3, m_root**3, s_root**3

    linear = (
        4.0767416621 * l_value - 3.3077115913 * m_value + 0.2309699292 * s_value,
        -1.2684380046 * l_value + 2.6097574011 * m_value - 0.3413193965 * s_value,
        -0.0041960863 * l_value - 0.7034186147 * m_value + 1.7076147010 * s_value,
    )

    def encode(channel: float) -> int:
        channel = max(0.0, min(1.0, channel))
        value = (
            12.92 * channel
            if channel <= 0.0031308
            else 1.055 * channel ** (1 / 2.4) - 0.055
        )
        return round(value * 255)

    return tuple(encode(channel) for channel in linear)


def xterm_palette() -> list[tuple[int, tuple[int, int, int]]]:
    colors = []
    for red in XTERM_STEPS:
        for green in XTERM_STEPS:
            for blue in XTERM_STEPS:
                index = 16 + 36 * XTERM_STEPS.index(red)
                index += 6 * XTERM_STEPS.index(green) + XTERM_STEPS.index(blue)
                colors.append((index, (red, green, blue)))
    colors.extend((232 + offset, (value, value, value))
                  for offset, value in enumerate(range(8, 239, 10)))
    return colors


def srgb_to_oklab(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    def decode(channel: int) -> float:
        value = channel / 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    red, green, blue = (decode(channel) for channel in rgb)
    l_value = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
    m_value = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
    s_value = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
    l_root, m_root, s_root = (
        math.copysign(abs(value) ** (1 / 3), value)
        for value in (l_value, m_value, s_value)
    )
    return (
        0.2104542553 * l_root + 0.7936177850 * m_root - 0.0040720468 * s_root,
        1.9779984951 * l_root - 2.4285922050 * m_root + 0.4505937099 * s_root,
        0.0259040371 * l_root + 0.7827717662 * m_root - 0.8086757660 * s_root,
    )


XTERM_OKLAB = tuple(
    (index, srgb_to_oklab(rgb)) for index, rgb in xterm_palette()
)


def nearest_xterm(rgb: tuple[int, int, int]) -> int:
    target = srgb_to_oklab(rgb)
    return min(
        XTERM_OKLAB,
        key=lambda item: sum((left - right) ** 2
                             for left, right in zip(target, item[1])),
    )[0]


def foreground(rgb: tuple[int, int, int]) -> str:
    def luminance(channel: int) -> float:
        value = channel / 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    relative = sum(
        weight * luminance(channel)
        for weight, channel in zip((0.2126, 0.7152, 0.0722), rgb)
    )
    black_contrast = (relative + 0.05) / 0.05
    white_contrast = 1.05 / (relative + 0.05)
    return "Black" if black_contrast >= white_contrast else "White"


def vim_entry(rgb: tuple[int, int, int], index: int, duplicate: bool) -> str:
    gui = "#" + "".join(f"{channel:02x}" for channel in rgb)
    fg = foreground(rgb)
    if duplicate:
        return (
            r"\   { 'co': 16777216,"
            f"                                          'guifg':'{fg}',   'guibg':'{gui}' }}"
        )
    return (
        r"\   { 'co': 256,    "
        f"'ctermfg':'{fg}',      'ctermbg':'{index}',{' ' * (3 - len(str(index)))}"
        f"   'guifg':'{fg}',   'guibg':'{gui}' }}"
    )


def generate(colors: dict[tuple[str, int], tuple[float, float, float]]) -> str:
    missing = [(hue, shade) for hue in HUES for shade in SHADES
               if (hue, shade) not in colors]
    if missing:
        names = ", ".join(f"{hue}-{shade}" for hue, shade in missing)
        raise ValueError(f"missing requested colors: {names}")

    lines = ["function! mark#palettes#Tailwind()", "\tlet l:palette = ["]
    used_indexes = set()
    for hue in HUES:
        for shade in SHADES:
            rgb = oklch_to_srgb(colors[(hue, shade)])
            index = nearest_xterm(rgb)
            lines.append("\t" + vim_entry(rgb, index, index in used_indexes) + ",")
            used_indexes.add(index)
    lines.extend((
        "\t\\]",
        "",
        "\tif ! has('gui_running')",
        "\t\tcall filter(l:palette, 'v:val.co <= &t_Co')",
        "\tendif",
        '\treturn map(l:palette, \'ingo#dict#Unlet(v:val, "co")\')',
        "endfunction",
    ))
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source",
        nargs="?",
        type=Path,
        default=Path(__file__).with_name("tailwind-colors.css"),
        help="Tailwind CSS theme file (default: tools/tailwind-colors.css)",
    )
    args = parser.parse_args()
    print(generate(parse_colors(args.source.read_text(encoding="utf-8"))))


if __name__ == "__main__":
    main()
