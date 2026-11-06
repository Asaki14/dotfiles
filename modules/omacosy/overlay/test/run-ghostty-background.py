#!/usr/bin/env python3
"""Check all theme fragments without changing the live config or windows."""
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "bin/ghostty-theme-fragment"
# GHOSTTY_FG_DIM=0 pins the dim off, so a live ~/.local/state value cannot skew the run
ENV = dict(os.environ, GHOSTTY_THEME_NO_RELOAD="1", GHOSTTY_FG_DIM="0")

with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "ghostty.conf"
    for theme in sorted((REPO / "themes").iterdir()):
        palette = tomllib.loads((theme / "colors.toml").read_text())
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        lines = out.read_text().splitlines()
        actual = dict(line.split(" = ", 1) for line in lines if " = " in line)
        mappings = {
            "background": "background",
            "foreground": "foreground", "cursor-color": "cursor",
            "cursor-text": "background", "selection-background": "selection_background",
            "selection-foreground": "selection_foreground", "unfocused-split-fill": "color0",
            "split-divider-color": "color8",
        }
        for key, source in mappings.items():
            assert actual[key] == palette[source], (theme.name, key)
        for i in range(16):
            assert f"palette = {i}={palette[f'color{i}']}" in lines
        assert not any(line.startswith("background-opacity") for line in lines)
        previous = out.read_bytes()
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        assert out.read_bytes() == previous
        print(f"PASS: {theme.name}: background {palette['background']} verbatim; other settings unchanged")
        # the dim mixes the foreground toward the background: darker, never past it
        dimmed_env = dict(ENV, GHOSTTY_FG_DIM="0.25")
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=dimmed_env, check=True)
        dimmed = dict(
            line.split(" = ", 1) for line in out.read_text().splitlines() if " = " in line
        )["foreground"]
        assert dimmed != palette["foreground"], theme.name
        chans = lambda h: [int(h[i:i + 2], 16) for i in (1, 3, 5)]
        for got, src, bg in zip(chans(dimmed), chans(palette["foreground"]), chans(palette["background"])):
            assert round(src - (src - bg) * 0.25) == got, (theme.name, dimmed)
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        print(f"PASS: {theme.name}: foreground {palette['foreground']} -> {dimmed} at dim 0.25")
    invalid = Path(tmp) / "invalid"
    invalid.mkdir()
    (invalid / "colors.toml").write_text('background = "invalid"\n')
    result = subprocess.run([str(SCRIPT), str(invalid), str(out)], env=ENV, capture_output=True)
    assert result.returncode != 0
    assert out.read_bytes() == previous
    print("PASS: invalid background rejected without overwriting output")
