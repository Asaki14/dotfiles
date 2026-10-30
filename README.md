<div align="center">
  <h1>Dotfiles</h1>
  <p><b>A macOS desktop, terminal and AI agent setup.</b></p>
  <p><a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a></p>
</div>

- Tool-based modules with individual installation
- Linked desktop and terminal themes through omacosy
- omp settings, original extensions and skills

## Modules

| Module | Purpose | Main tools |
|---|---|---|
| [omacosy](modules/omacosy/README.md) | Desktop and theme system | omacosy, Ghostty, AeroSpace, Karabiner |
| [fish](modules/fish/README.md) | Interactive shell and shortcuts | fish, Fisher |
| [nvim](modules/nvim/README.md) | Editing, search and completion | Neovim, lazy.nvim, Telescope |
| [yazi](modules/yazi/README.md) | File management and previews | Yazi, smart-enter, compress |
| [cli](modules/cli/README.md) | Everyday command-line tools | git, btop, fastfetch, gh, md-tui |
| [linearmouse](modules/linearmouse/README.md) | Mouse configuration | LinearMouse |
| [music](modules/music/README.md) | Local music library and playback | MPD, rmpc, beets, cava |
| [tern](modules/tern/README.md) | Terminal input-source policy | Tern, Swift, Luau |
| [freshrss](modules/freshrss/README.md) | RSS reading and Chinese translation | FreshRSS, Docker, omp |
| [raycast](modules/raycast/README.md) | System script commands | Raycast |
| [codexbar](modules/codexbar/README.md) | AI account usage in the menu bar | CodexBar |
| [omp](modules/omp/README.md) | Coding agent settings and extensions | oh-my-pi |
| [skills](modules/skills/README.md) | Project structure and skill improvement | project-scaffold, skill-improve |

## Install

Requires macOS, Git and Homebrew. Read Before installing below first.

```bash
git clone https://github.com/Asaki14/dotfiles.git
cd dotfiles
./install.sh
```

Select modules with fzf, or the numbered menu when fzf is unavailable.

```bash
./install.sh --list
./install.sh --all
./install.sh --modules fish,nvim,yazi
./install.sh --modules fish,nvim --dry-run
./install.sh --modules fish,nvim --no-brew
```

`--modules` also selects module dependencies. `--dry-run` prints actions without installing packages or writing files. `--no-brew` skips all Homebrew calls, including those in upstream omacosy; install the dependencies yourself first.

Files under `home/` are linked individually into `$HOME`. Conflicting existing files move to `~/.dotfiles-backup/<timestamp>-<pid>/`. Keep this checkout in place: moving it breaks the links. omacosy also runs its upstream installer, as described below.

## Before installing

- omacosy changes macOS defaults, loads LaunchAgents, compiles helpers, sets wallpaper and overwrites desktop configuration. File backups do not restore those system settings. Read the [omacosy module](modules/omacosy/README.md) first.
- [Tern](https://stencil.so/tern) is in closed beta and must be installed separately. Install [omp](https://github.com/can1357/oh-my-pi) separately too, then authenticate your model providers.
- The omp config enables `approvalMode: yolo`, and fish’s `cc` alias enables permission bypass. Adjust both to your approval requirements before use.
- The FreshRSS extension requires an account named `reader`. See the [FreshRSS module](modules/freshrss/README.md) for initialization and background processing.
- Configure weather through `OMACOSY_WEATHER_LOCATION`, `OMACOSY_WEATHER_LAT` and `OMACOSY_WEATHER_LON` in the weather process environment.
- Keep Git identity in `~/.gitconfig.local`, outside this repository:

```gitconfig
[user]
    name = Your Name
    email = you@example.com
```

## Use

Edit the linked configuration files in each module. Each module README covers its commands and setup. [History](HISTORY.md) records changes to the desktop, AI agents, browsers and notes.

## Credits

- [xrce/dots](https://github.com/xrce/dots), the starting point in February 2026.
- [paulsp94/omacosy](https://github.com/paulsp94/omacosy), desktop and theme foundation by Paul Spende, MIT. The installer retains the upstream checkout and its license.
- [tw93/Waza](https://github.com/tw93/Waza) and [tw93/Kami](https://github.com/tw93/Kami), engineering and document skills.
- [mattpocock/skills](https://github.com/mattpocock/skills), grilling and skill-writing references.
- [zenbu-labs/terminal-browser](https://github.com/zenbu-labs/terminal-browser), browser skill.
- [lennney/stop-that-shit](https://github.com/lennney/stop-that-shit), bounded agent work.
- [Asaki14/omp-mnemopi-memory](https://github.com/Asaki14/omp-mnemopi-memory), my separate memory extension.
- [Raycast extension authors](modules/raycast/README.md) and [Yazi plugin authors](modules/yazi/README.md).

## License

[MIT](LICENSE). Upstream omacosy code remains under its MIT license; third-party tools and plugins retain their own licenses.
