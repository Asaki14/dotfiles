#!/usr/bin/env python3
"""Render the rmpc theme for every palette without touching the live file or instance."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "bin/rmpc-theme-fragment"
ENV = dict(os.environ, RMPC_THEME_NO_RELOAD="1")
# template token -> colors.toml key, mirrors the list in the script
MAPPING = {
    "accent": "accent", "fg": "foreground", "bg": "background",
    "surface": "color0", "red": "color1", "green": "color2", "yellow": "color3",
    "blue": "color4", "magenta": "color5", "cyan": "color6", "muted": "color8",
}

with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "omacosy.ron"
    for theme in sorted((REPO / "themes").iterdir()):
        palette = tomllib.loads((theme / "colors.toml").read_text())
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        text = out.read_text()
        assert not re.search(r"@[a-z_]+@", text), theme.name
        # the accent drives every highlight: playing row, tabs, progress, cava
        for needle in (
            f'current_item_style: (fg: "{palette["background"]}", bg: "{palette["accent"]}"',
            f'active_style: (fg: "{palette["background"]}", bg: "{palette["accent"]}"',
            f'elapsed_style: (fg: "{palette["accent"]}")',
            f'bar_color: Single("{palette["accent"]}")',
            'background_color: None',
        ):
            assert needle in text, (theme.name, needle)
        used = set(re.findall(r"#[0-9a-fA-F]{6}", text))
        allowed = {palette[key] for key in MAPPING.values()}
        assert used <= allowed, (theme.name, used - allowed)
        previous = out.read_bytes()
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        assert out.read_bytes() == previous
        print(f"PASS: {theme.name}: accent {palette['accent']}, {len(used)} palette colours, idempotent")
    invalid = Path(tmp) / "invalid"
    invalid.mkdir()
    (invalid / "colors.toml").write_text('accent = "purple"\n')
    result = subprocess.run([str(SCRIPT), str(invalid), str(out)], env=ENV, capture_output=True)
    assert result.returncode != 0
    assert out.read_bytes() == previous
    print("PASS: invalid palette rejected without overwriting output")
