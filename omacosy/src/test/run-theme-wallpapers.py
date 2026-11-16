#!/usr/bin/env python3
"""Exercise wallpaper selection with an isolated HOME and no desktop changes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="omacosy-wallpapers-") as tmp:
    home = Path(tmp)
    repo = home / "repo"
    (repo / "bin").mkdir(parents=True)
    for name in ("theme-set", "theme-bg-next"):
        shutil.copy2(REPO / "bin" / name, repo / "bin" / name)
    fragment = repo / "bin/ghostty-theme-fragment"
    fragment.write_text("#!/bin/sh\nexit 0\n")
    fragment.chmod(0o755)
    helper = home / ".local/bin/omacosy-helper"
    helper.parent.mkdir(parents=True)
    helper.write_text('#!/bin/sh\nprintf "%s" "$2" > "$HOME/applied"\n')
    helper.chmod(0o755)
    for name in ("rose-pine", "tokyo-night"):
        (repo / "themes" / name / "backgrounds").mkdir(parents=True)
    normal = repo / "themes/tokyo-night/backgrounds"
    for name in ("01.jpg", "02.png", "README.md"):
        (normal / name).touch()
    images = home / "Pictures/wallpaper"
    images.mkdir(parents=True)
    for name in ('a space.jpg', 'b"quote.PNG', 'c.heic', 'README.md'):
        (images / name).touch()
    (images / "nested").mkdir()
    (images / "nested/ignored.jpg").touch()
    env = dict(os.environ, HOME=str(home))

    def run(command, *args, success=True):
        result = subprocess.run(
            [str(repo / "bin" / command), *args], env=env,
            capture_output=True, text=True,
        )
        assert (result.returncode == 0) == success, result.stderr
        return result

    def selected():
        link = home / ".local/state/omacosy/background"
        value = Path(os.readlink(link))
        assert (home / "applied").read_text() == str(value)
        return value

    run("theme-set", "rose-pine")
    previous = selected()
    allowed = {images / name for name in ('a space.jpg', 'b"quote.PNG', 'c.heic')}
    assert previous in allowed
    for i in range(30):
        if i % 2:
            run("theme-set", "rose-pine")
        else:
            run("theme-bg-next")
        current = selected()
        assert current in allowed and current != previous
        previous = current
    for path in allowed - {previous}:
        path.unlink()
    run("theme-bg-next")
    assert selected() == previous
    previous.unlink()
    result = run("theme-bg-next", success=False)
    assert "theme has no backgrounds" in result.stderr
    run("theme-set", "tokyo-night")
    assert selected().name == "01.jpg"
    run("theme-bg-next")
    assert selected().name == "02.png"
    run("theme-bg-next")
    assert selected().name == "01.jpg"
    run("theme-set", "tokyo-night")
    assert selected().name == "01.jpg"
    run("theme-bg-next", str(normal / "02.png"))
    assert selected() == normal / "02.png"

print("PASS: random entry/next, no immediate repeats, single/empty collection, formats, spaces/quotes, sequential themes, explicit path")
