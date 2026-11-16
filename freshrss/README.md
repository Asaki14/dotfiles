# FreshRSS

A local FreshRSS instance with a reader extension that translates foreign-language articles into Chinese in the background. The Mac must be awake for feed updates and translation. Other devices can reach it through Tailscale Serve.

## Pieces

| Component | Files | Runs as |
|---|---|---|
| FreshRSS 1.30.4 | `compose.yaml` (official image, `127.0.0.1:8088`) | Docker container, feed updates at minutes 7 and 37 |
| Local Reader extension | `extensions/xExtension-LocalReader/` | Mounted read-only into the container; serves the instance's default user |
| Translation worker | `reader.py`, `reader-settings.json` | LaunchAgent `local.freshrss.reader`, every 30 seconds |
| Reader files | `reader-data/` (gitignored) | Shared with the container: articles, images, translations, queue |
| Credentials | `credentials.json` (gitignored, mode 0600) | Your FreshRSS login; never commit it |

FreshRSS data lives in the Docker volumes `freshrss_freshrss_data` and `freshrss_freshrss_extensions`. `down -v` deletes them.

## Setup

```sh
brew install colima docker docker-compose uv
colima start
docker-compose -f ~/.config/freshrss/compose.yaml up -d
open http://localhost:8088/        # create the admin user; it becomes the default user
~/.config/freshrss/install-reader.sh   # install the translation worker's LaunchAgent
```

To use it from an iPad or phone, run `tailscale serve --bg --https=8443 http://127.0.0.1:8088` and open `https://<mac-name>.<tailnet>.ts.net:8443/` (`tailscale status` shows the name).

## Reading and translation

Tap an article title to expand it. Prepared foreign-language articles show the Chinese translation with a `查看原文` toggle. Articles are queued when they become visible or when FreshRSS updates them; the page swaps in the translation when it is ready, and a failed job keeps the original with a retry button.

Translation runs through omp with the model in `reader-settings.json` at low thinking effort, so article text goes to that provider. One article is processed at a time with at most two model requests; translated blocks are reused, and links are replaced by placeholders and restored, rejecting any translation that alters them. Short feed excerpts are expanded to full text when the site allows it. Content is sanitized, and images are served through authenticated FreshRSS routes.

## Operation

```sh
# Refresh feeds now (replace <user> with your FreshRSS user)
docker exec --user www-data freshrss cli/actualize-user.php --user <user>

# Run the worker now; it never overlaps an active run
launchctl kickstart gui/$(id -u)/local.freshrss.reader

# Stop FreshRSS without deleting data
docker-compose -f ~/.config/freshrss/compose.yaml stop
```

The worker logs to `reader-data/worker.log`; per-article errors are also kept in each article's JSON file. Back up both Docker volumes and `reader-data/` to keep subscriptions, read states, translations and images.

## Tests

```sh
uv run --with beautifulsoup4 --with lxml_html_clean --with markdown --with markdownify --with readability-lxml python -m unittest -v test_reader
```
