# FreshRSS

The Mac and iPad use the same FreshRSS account at https://rss.example.com/. Tailscale must be connected. The Mac must be awake for access, feed updates and translation.

## Services and data

| Component | Configuration or data | Operation |
|---|---|---|
| FreshRSS 1.30.4 | `compose.yaml`; official `freshrss/freshrss` image | Feed updates at minutes 7 and 37, Asia/Shanghai time |
| Private HTTPS | Tailscale Serve port 8443 to `127.0.0.1:8088` | Accessible within the tailnet; no public Funnel |
| Local Reader extension | `extensions/xExtension-LocalReader/` | Shared translated text, original-text toggle and responsive typography |
| Translation worker | `reader.py`, `reader-settings.json` | macOS LaunchAgent `local.freshrss.reader`, checked every 30 seconds |
| Reader files | `reader-data/articles/`, `images/`, `translations/`, `queue/` | Shared with the container; article images require a FreshRSS login |
| Credentials | `credentials.json`, mode 0600 | Account `reader`; do not commit or share this file |

FreshRSS database files remain in Docker volumes `freshrss_freshrss_data` and `freshrss_freshrss_extensions`. Colima starts at user login; the container uses `restart: unless-stopped`. Do not use `down -v` unless intentionally deleting FreshRSS data.

## Reading and translation

Tap an article title to expand it. Prepared foreign-language articles show the Chinese translation and a **View original** control labelled `查看原文`. Unprocessed archive articles are queued when their content becomes visible. New and changed articles are queued by FreshRSS update hooks, without requiring a browser to be open. The page checks processing status and replaces the original with the finished translation. Failed jobs retain the original text and expose a retry button.

Translation uses the existing OMP account with `openai-codex/gpt-6-luna` at low thinking effort. Article text is sent to that provider; this is not an offline model. The Mac stores the resulting translations and images. The worker processes one article at a time with at most two simultaneous model requests. Existing translated blocks are reused. Link destinations are replaced by placeholders for translation and restored before publication; missing or altered links reject that translation.

The worker extracts full text for short feed excerpts when the original site permits access. It also preserves the Ruanyf weekly's Markdown source. Paywalled or inaccessible full text can remain an excerpt. Content is sanitized before display. Images use authenticated FreshRSS routes rather than Mac file paths. SHA-1 identifies cached articles, images and translation blocks for compatibility with the migrated cache; it is not used for passwords or authentication.

## Operation

```sh
# Start FreshRSS after a manual stop
colima start
docker-compose -f ~/.config/freshrss/compose.yaml up -d

# Refresh feeds now
docker exec --user www-data freshrss cli/actualize-user.php --user reader

# Run the reader worker now, without overlapping an active run
launchctl kickstart gui/$(id -u)/local.freshrss.reader

# Stop FreshRSS without deleting data
docker-compose -f ~/.config/freshrss/compose.yaml stop
```

The LaunchAgent is `~/Library/LaunchAgents/local.freshrss.reader.plist`. Its stdout and errors go to `reader-data/worker.log`; per-article errors are also recorded in the article JSON file. The queue directory is writable by the container's web user; other reader directories are written by the Mac worker. Passwords are outside these mounts.

Back up both Docker volumes and this configuration directory, including `reader-data/`, to retain subscriptions, read/favourite states, translations and images.

## Migration and verification

The 6 subscriptions and 3 user categories are managed in FreshRSS. Newsboat was uninstalled, its old tab was closed, and its theme integration was removed. Desktop news shortcut templates now open FreshRSS in the browser.

The migration imported all 30 cached reader pages, both existing translation maps and 274 image files. Pending translations were completed. An additional existing archive article exercised the update hook. At cutover, the reader contained 14 native-language pages and 17 translated pages, with no pending or failed jobs. Older FreshRSS archive articles remain available and are prepared when opened.

The original scripts, settings, database and image/translation cache are preserved under `backups/newsboat-20261025-090001/`. `freshrss-sources.json` records the source articles used for the import. The earlier subscription migration backup remains in `newsboat-before-freshrss/`. Neither backup is used by the running reader.

Verified authenticated HTTPS login, cached images, title expansion, Chinese typography at 820-pixel and 1366-pixel browser widths without horizontal page overflow, original-text toggling, background OMP translation under launchd, rejection of a prepare request without a CSRF token, and unauthenticated image redirection to login. Verification article read states were restored. Actual iPad touch behaviour must be checked on the device.

Run the 7 deterministic content regression tests with:

```sh
uv run --with beautifulsoup4 --with lxml_html_clean --with markdown --with markdownify --with readability-lxml python -m unittest -v test_reader
```
