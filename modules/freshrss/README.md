# freshrss

[English](README.md) | [简体中文](README.zh-CN.md)

RSS reading and Chinese translation.

## Install

```bash
./install.sh --modules freshrss
```

Run from the repository root. Homebrew packages: `colima`, `docker`, `docker-compose`, `uv`.

## Files and destinations

| Source | Destination |
|---|---|
| [`home/.config/freshrss/.gitignore`](home/.config/freshrss/.gitignore) | `~/.config/freshrss/.gitignore` |
| [`home/.config/freshrss/README.md`](home/.config/freshrss/README.md) | `~/.config/freshrss/README.md` |
| [`home/.config/freshrss/compose.yaml`](home/.config/freshrss/compose.yaml) | `~/.config/freshrss/compose.yaml` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/Controllers/localReaderController.php`](home/.config/freshrss/extensions/xExtension-LocalReader/Controllers/localReaderController.php) | `~/.config/freshrss/extensions/xExtension-LocalReader/Controllers/localReaderController.php` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/extension.php`](home/.config/freshrss/extensions/xExtension-LocalReader/extension.php) | `~/.config/freshrss/extensions/xExtension-LocalReader/extension.php` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/metadata.json`](home/.config/freshrss/extensions/xExtension-LocalReader/metadata.json) | `~/.config/freshrss/extensions/xExtension-LocalReader/metadata.json` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.css`](home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.css) | `~/.config/freshrss/extensions/xExtension-LocalReader/static/reader.css` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.js`](home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.js) | `~/.config/freshrss/extensions/xExtension-LocalReader/static/reader.js` |
| [`home/.config/freshrss/reader-settings.json`](home/.config/freshrss/reader-settings.json) | `~/.config/freshrss/reader-settings.json` |
| [`home/.config/freshrss/reader.py`](home/.config/freshrss/reader.py) | `~/.config/freshrss/reader.py` |
| [`home/.config/freshrss/test_reader.py`](home/.config/freshrss/test_reader.py) | `~/.config/freshrss/test_reader.py` |

## Setup

The installer also selects omp; install omp itself and authenticate a provider separately. Start Colima, create the shared data directories, then start FreshRSS:

```bash
colima start
mkdir -p ~/.config/freshrss/reader-data/{articles,images,translations,queue}
docker-compose -f ~/.config/freshrss/compose.yaml up -d
```

Open `http://127.0.0.1:8088`, finish FreshRSS setup, create the account **`reader`**, and enable **Local Reader** in its extension settings. The extension restricts its routes to this exact account name. Review the mounted directory permissions so the container web user can write the queue. Run `uv run ~/.config/freshrss/reader.py` to process queued articles. Repeat it on your own schedule; this module does not install the LaunchAgent described in the exported source README. Set your model in `reader-settings.json`; article text is sent to that model provider. Docker volumes retain subscriptions and reading state; do not use `down -v` unless deleting them intentionally. Remote access, HTTPS and credentials are your own setup.
