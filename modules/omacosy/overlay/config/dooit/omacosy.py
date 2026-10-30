"""Make dooit follow the omacosy theme.

Linked to ~/Library/Application Support/dooit/omacosy.py by install.sh
(dooit's platformdirs config dir); enable it with
`from omacosy import follow_omacosy_theme` in config.py there
(dooit registers every timer/event function visible in config.py).

dooit has no external reload command, so a 1 s timer watches
~/.config/omarchy/current/theme/colors.toml (theme-set swaps that symlink)
and, on change, rebuilds the dooit theme from the palette. set_theme
rewrites dooit's stylesheet, which the running app hot-reloads.
"""

import os
import tomllib
from pathlib import Path

from dooit.api.theme import DooitThemeBase
from dooit.ui.api import DooitAPI, timer

COLORS = Path.home() / ".config/omarchy/current/theme/colors.toml"

_last_seen = None


def _mix(a: str, b: str, t: float) -> str:
    """Blend hex colour a toward b by t (0..1)."""
    ca = [int(a[i : i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


def _theme_from(palette: dict) -> type[DooitThemeBase]:
    bg = palette["background"]
    fg = palette["foreground"]
    red, yellow = palette["color1"], palette["color3"]
    return type(
        "OmacosyTheme",
        (DooitThemeBase,),
        {
            "_name": "omacosy",
            "background1": bg,
            "background2": _mix(bg, fg, 0.08),
            "background3": _mix(bg, fg, 0.16),
            "foreground1": palette["color7"],
            "foreground2": fg,
            "foreground3": palette["color15"],
            "red": red,
            "orange": _mix(red, yellow, 0.5),
            "yellow": yellow,
            "green": palette["color2"],
            "blue": palette["color4"],
            "purple": palette["color5"],
            "magenta": palette["color5"],
            "cyan": palette["color6"],
            "primary": palette["accent"],
            "secondary": palette["color5"],
        },
    )


@timer(1)
def follow_omacosy_theme(api: DooitAPI):
    global _last_seen
    try:
        # the symlink target changes on theme-set; mtime catches in-place edits
        seen = (os.path.realpath(COLORS), COLORS.stat().st_mtime)
    except OSError:
        return ""
    if seen == _last_seen:
        return ""
    try:
        palette = tomllib.loads(COLORS.read_text())
        theme = _theme_from(palette)
    except (OSError, tomllib.TOMLDecodeError, KeyError, ValueError):
        return ""
    _last_seen = seen
    api.css.set_theme(theme)
    return ""
