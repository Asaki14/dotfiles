"""Use terminal backgrounds with desktop component and highlight colors.

Enable `from omacosy import follow_omacosy_theme` in dooit's config.py.
The timer reloads the palette; primary and secondary both use its accent.
"""

import os
import tomllib
from pathlib import Path
from textual.css.query import NoMatches

from dooit.api.theme import DooitThemeBase
from dooit.ui.api import DooitAPI, timer
from dooit.ui.api.events import ModeChanged, Startup

COLORS = Path.home() / ".config/omarchy/current/theme/colors.toml"

_last_seen = None
_status_pending = False


def _mix(a: str, b: str, t: float) -> str:
    """Blend hex colour a toward b by t (0..1)."""
    ca = [int(a[i : i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


class OmacosyTheme(DooitThemeBase):
    background1 = background2 = background3 = "default"

    @classmethod
    def to_css(cls) -> str:
        # Rich uses "default"; Textual CSS spells the terminal default differently.
        return super().to_css().replace(": default;", ": ansi_default;")


def _theme_from(palette: dict) -> type[DooitThemeBase]:
    fg = palette["foreground"]
    red, yellow = palette["color1"], palette["color3"]
    return type(
        "OmacosyTheme",
        (OmacosyTheme,),
        {
            "_name": "omacosy",
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
            "secondary": palette["accent"],
        },
    )


@timer(1)
def follow_omacosy_theme(api: DooitAPI):
    global _last_seen, _status_pending
    try:
        # The symlink changes on theme-set; mtime also catches in-place edits.
        seen = (os.path.realpath(COLORS), COLORS.stat().st_mtime)
    except OSError:
        return ""
    if seen != _last_seen:
        try:
            palette = tomllib.loads(COLORS.read_text())
            theme = _theme_from(palette)
        except (OSError, tomllib.TOMLDecodeError, KeyError, ValueError):
            return ""
        api.app.ansi_color = True
        api.css.set_theme(theme)
        _last_seen = seen
        _status_pending = True
    if not _status_pending:
        return ""
    # Event-driven status widgets cache Rich colors independently of the CSS.
    # Refresh only visible bar callbacks, not every Startup subscriber.
    try:
        bar_functions = {widget.func for widget in api.app.bar.bar_widgets}
    except NoMatches:
        # Startup and help screens have no status bar; retry after returning.
        return ""
    for event in (ModeChanged(api.vars.mode), Startup()):
        for handler in api.plugin_manager.events[type(event)]:
            if handler in bar_functions:
                api.plugin_manager._update_dooit_value(handler, event)
    _status_pending = False
    return ""
