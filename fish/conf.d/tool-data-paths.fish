# 仅影响 fish 及其子进程；桌面应用仍可能使用默认目录。
set -gx BUN_INSTALL "$HOME/.local/share/bun"
set -gx BUN_INSTALL_CACHE_DIR "$HOME/.cache/bun"
set -gx IPYTHONDIR "$HOME/.config/ipython"
set -gx MPLCONFIGDIR "$HOME/.config/matplotlib"
