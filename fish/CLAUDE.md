# Repository Guidelines

## Project Structure & Module Organization

This repository contains Fish shell configuration files under `~/.config/fish`.

- `config.fish` is the main interactive shell entrypoint for paths, aliases, key bindings, proxy helpers, Starship setup, and local environment exports.
- `conf.d/` contains Fish files loaded automatically by Fish. Keep machine-local files such as `conf.d/api_keys.local.fish` untracked.
- `functions/` stores autoloaded Fish functions, currently including `functions/fisher.fish`.
- `completions/` stores command completion scripts, such as `completions/fisher.fish` and `completions/fastanime.fish`.
- `fish_plugins` lists Fisher-managed plugins. Keep this file small and declarative.
- `fish_variables` holds Fish universal variables, machine state Fish writes itself; it is gitignored and stays local.

## Build, Test, and Development Commands

There is no build step. Use Fish's parser and targeted shell startup checks:

- `fish -n config.fish functions/*.fish completions/*.fish` checks syntax without executing scripts.
- `fish -c 'source config.fish'` loads the main config in a fresh Fish process.
- `fisher list` shows installed Fisher plugins.
- `fisher update` updates plugins listed in `fish_plugins`; review generated changes before committing.

## Coding Style & Naming Conventions

Write Fish scripts with 4-space indentation inside functions and conditionals. Prefer Fish-native commands (`set`, `test`, `string`, `contains`) over POSIX shell syntax. Use lowercase function and alias names unless wrapping an upstream command. Keep aliases short and obvious; use functions when behavior has arguments or side effects. Export environment variables with `set -x` or `set -gx` intentionally, and keep comments brief.

## Testing Guidelines

Run `fish -n ...` before committing any `.fish` change. For interactive behavior, start a new Fish shell and verify affected aliases, functions, completions, and environment variables manually. When editing plugin configuration, run `fisher list` and confirm `fish_plugins` still reflects the intended plugin set.

## Commit & Pull Request Guidelines

Recent history uses concise Conventional Commit-style subjects, for example `fix: load api keys from unlocked rbw vault` and `chore: clean config leftovers`. Use `fix:`, `chore:`, `refactor:`, or another clear type, followed by a short imperative summary. Pull requests should describe the shell behavior changed, list manual verification commands, and call out any local-only setup required.

## Security & Configuration Tips

Do not commit API keys, tokens, vault paths, or host-specific secrets. Put local exports in `conf.d/api_keys.local.fish`, which is gitignored. Before committing, inspect `git diff -- config.fish fish_variables conf.d/` for accidental personal data.
