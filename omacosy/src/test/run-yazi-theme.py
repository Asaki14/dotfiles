#!/usr/bin/env python3
"""Render the yazi flavor for every palette without touching the live flavor or yazi."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "bin/yazi-theme-fragment"
ENV = dict(os.environ, YAZI_THEME_NO_RELOAD="1")
# template token -> colors.toml key, mirrors the list in the script
MAPPING = {
    "accent": "accent", "fg": "foreground", "bg": "background",
    "surface": "color0", "red": "color1", "green": "color2", "yellow": "color3",
    "blue": "color4", "magenta": "color5", "cyan": "color6", "muted": "color8",
}

with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "omacosy.yazi"
    for theme in sorted((REPO / "themes").iterdir()):
        palette = tomllib.loads((theme / "colors.toml").read_text())
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        flavor_text = (out / "flavor.toml").read_text()
        tm_text = (out / "tmtheme.xml").read_text()
        for name, text in (("flavor.toml", flavor_text), ("tmtheme.xml", tm_text)):
            assert not re.search(r"@[a-z_]+@", text), (theme.name, name)
        # both files must parse: yazi refuses a flavor it cannot read
        flavor = tomllib.loads(flavor_text)
        tm = plistlib.loads(tm_text.encode())
        # the accent drives the hovered row, active tab and mode badge, like rmpc
        accent, bg = palette["accent"], palette["background"]
        assert flavor["indicator"]["current"] == {"fg": bg, "bg": accent}, theme.name
        assert flavor["tabs"]["active"]["bg"] == accent, theme.name
        assert flavor["mode"]["normal_main"]["bg"] == accent, theme.name
        assert tm["settings"][0]["settings"]["foreground"] == palette["foreground"], theme.name
        used = set(re.findall(r"#[0-9a-fA-F]{6}", flavor_text + tm_text))
        allowed = {palette[key] for key in MAPPING.values()}
        assert used <= allowed, (theme.name, used - allowed)
        previous = {p.name: p.read_bytes() for p in out.iterdir()}
        subprocess.run([str(SCRIPT), str(theme), str(out)], env=ENV, check=True)
        assert {p.name: p.read_bytes() for p in out.iterdir()} == previous
        print(f"PASS: {theme.name}: accent {accent}, {len(used)} palette colours, idempotent")
    invalid = Path(tmp) / "invalid"
    invalid.mkdir()
    (invalid / "colors.toml").write_text('accent = "purple"\n')
    result = subprocess.run([str(SCRIPT), str(invalid), str(out)], env=ENV, capture_output=True)
    assert result.returncode != 0
    assert {p.name: p.read_bytes() for p in out.iterdir()} == previous
    print("PASS: invalid palette rejected without overwriting output")
