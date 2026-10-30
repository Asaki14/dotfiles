# chrome-devtools-axi 0.1.29 never sends the `pageId` that chrome-devtools-mcp
# made required in 1.x, so every call fails with "Required at pageId". Pin the
# MCP below 1.0 instead of letting the default `npx ...@latest` pull a broken pair.
set -l _cda_mcp "$HOME/.npm-global/lib/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
test -f "$_cda_mcp"; and set -gx CHROME_DEVTOOLS_AXI_MCP_PATH "$_cda_mcp"

# Headed, with a persistent profile so site logins survive between runs.
set -gx CHROME_DEVTOOLS_AXI_HEADED 1
set -gx CHROME_DEVTOOLS_AXI_USER_DATA_DIR "$HOME/.local/share/chrome-devtools-axi/profile"

# Automation browser channel: Chrome Beta has its own app id (com.google.Chrome.beta),
# so AeroSpace can route its windows to the external monitor (aerospace.toml on-window-detected).
set -gx CHROME_DEVTOOLS_AXI_CHANNEL beta
