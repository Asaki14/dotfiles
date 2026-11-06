#!/usr/bin/env python3
"""Render the Tern omp theme for every palette without touching the live file or Tern."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "bin/tern-theme-fragment"
ENV = dict(os.environ, TERN_THEME_NO_RELOAD="1")


def resolve(theme, value):
    return value if value.startswith("#") else theme["vars"][value]


with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "omacosy.json"
    for theme_dir in sorted((REPO / "themes").iterdir()):
        palette = tomllib.loads((theme_dir / "colors.toml").read_text())
        subprocess.run([str(SCRIPT), str(theme_dir), str(out)], env=ENV, check=True)
        theme = json.loads(out.read_text())
        terminal = theme["terminal"]
        # these are the colours Tern gives the terminal grid
        assert resolve(theme, terminal["background"]) == palette["background"], theme_dir.name
        assert resolve(theme, terminal["foreground"]) == palette["foreground"], theme_dir.name
        ansi = [resolve(theme, c) for c in terminal["ansi"]]
        assert ansi == [palette[f"color{i}"] for i in range(16)], (theme_dir.name, ansi)
        # every colour role must resolve, or omp rejects the theme
        for role, value in theme["colors"].items():
            assert resolve(theme, value).startswith("#"), (theme_dir.name, role)
        previous = out.read_bytes()
        subprocess.run([str(SCRIPT), str(theme_dir), str(out)], env=ENV, check=True)
        assert out.read_bytes() == previous
        print(f"PASS: {theme_dir.name}: yellow {ansi[3]}, blue {ansi[4]}, idempotent")
    invalid = Path(tmp) / "invalid"
    invalid.mkdir()
    (invalid / "colors.toml").write_text('accent = "purple"\n')
    result = subprocess.run([str(SCRIPT), str(invalid), str(out)], env=ENV, capture_output=True)
    assert result.returncode != 0
    assert out.read_bytes() == previous
    print("PASS: invalid palette rejected without overwriting output")
