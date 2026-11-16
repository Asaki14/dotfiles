#!/usr/bin/env python3
"""Check live status colors across desktop themes without touching user data.

Run with dooit's Python interpreter so its Textual dependencies are available.
"""
import asyncio
import os
from pathlib import Path
import sys
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]


async def check(root: Path):
    # Set HOME before importing dooit: its CSS cache paths are module constants.
    os.environ["HOME"] = str(root)
    sys.path.insert(0, str(REPO / "config/dooit"))
    import omacosy
    from dooit.ui.tui import Dooit
    from dooit.ui.screens import HelpScreen

    themes = sorted((REPO / "themes").iterdir())
    omacosy.COLORS = themes[0] / "colors.toml"
    config = root / "config.py"
    config.write_text("from omacosy import follow_omacosy_theme\n")
    app = Dooit(config=config, db_path=str(root / "dooit.db"))
    assert app.CSS_PATH.is_relative_to(root)
    async with app.run_test() as pilot:
        await pilot.pause()
        labels = [widget.render().plain for widget in app.bar.bar_widgets]
        assert labels[0].strip() == "NORMAL"
        for theme in themes[1:] + themes[:1]:
            omacosy.COLORS = theme / "colors.toml"
            await pilot.pause(1.2)
            palette = tomllib.loads(omacosy.COLORS.read_text())
            assert app.api.vars.mode == "NORMAL"
            assert [w.render().plain for w in app.bar.bar_widgets][0] == labels[0]
            assert app.bar.bar_widgets[-1].render().plain == labels[-1]
            for index in (0, 2, 4):
                text = app.bar.bar_widgets[index].render()
                style = text.get_style_at_offset(app.console, 1)
                assert style.bgcolor.get_truecolor().hex == palette["accent"], (
                    theme.name, text.plain, style.bgcolor, palette["accent"]
                )
            assert app.api.css.theme.background1 == "default"
            print(f"PASS: {theme.name}: mode, clock and user update without changing mode")
        await pilot.press("?")
        await pilot.pause()
        assert isinstance(app.screen, HelpScreen)
        omacosy.COLORS = themes[1] / "colors.toml"
        await pilot.pause(1.2)
        palette = tomllib.loads(omacosy.COLORS.read_text())
        await pilot.press("escape")
        await pilot.pause(1.2)
        assert app.api.vars.mode == "NORMAL"
        for index in (0, 2, 4):
            text = app.bar.bar_widgets[index].render()
            style = text.get_style_at_offset(app.console, 1)
            assert style.bgcolor.get_truecolor().hex == palette["accent"], (
                "returning from help", text.plain, style.bgcolor, palette["accent"]
            )
        print("PASS: theme changed on help screen updates status after returning")


with tempfile.TemporaryDirectory(prefix="dooit-theme-test-") as tmp:
    asyncio.run(check(Path(tmp)))
