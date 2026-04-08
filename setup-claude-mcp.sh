#!/usr/bin/env bash
# =============================================================================
# setup-claude-mcp.sh
# Automated setup for Claude Desktop + local MCP servers on Linux Mint 22.3
#
# Companion to: Claude-Desktop-MCP-Setup-Guide.md
# Section references below (e.g. "§3.1") match that guide.
#
# Usage:
#   chmod +x setup-claude-mcp.sh
#   ./setup-claude-mcp.sh
#
# This script is idempotent — safe to re-run on a partially set-up machine.
# Each phase checks whether its work is already done before acting.
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
info() { echo -e "  ${BLUE}→${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()  { echo -e "  ${RED}✗${RESET} $*"; }

header() {
  echo
  echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  $*${RESET}"
  echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
}

# Ask y/N — returns 0 for yes, 1 for no
ask() {
  local prompt="$1"
  local reply
  echo -en "  ${BOLD}${prompt} [y/N]${RESET} "
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Preflight ─────────────────────────────────────────────────────────────────
header "Claude Desktop + MCP Setup Script"
echo
echo -e "  This script automates the setup steps from:"
echo -e "  ${BLUE}Claude-Desktop-MCP-Setup-Guide.md${RESET}"
echo
echo -e "  It will check what is already installed and skip those steps."
echo -e "  Each phase asks for confirmation before making changes."
echo
echo -e "  ${YELLOW}Requirements:${RESET} Linux Mint 22.3 (Ubuntu 24.04-based), sudo access."
echo

if ! ask "Ready to begin?"; then
  echo
  info "Exited without making any changes."
  exit 0
fi

# ── Phase 0: Preflight checks ─────────────────────────────────────────────────
header "Phase 0 — Preflight checks"
echo

check_cmd() {
  local cmd="$1" label="$2"
  if command -v "$cmd" &>/dev/null; then
    ok "$label is installed ($(command -v "$cmd"))"
    return 0
  else
    warn "$label not found"
    return 1
  fi
check_cmd() {
  local cmd="$1" label="$2"
  if command -v "$cmd" &>/dev/null; then
    ok "$label is installed ($(command -v "$cmd"))"
    return 0
  else
    warn "$label not found"
    return 1
  fi
}

check_cmd curl   "curl"
check_cmd wget   "wget"
check_cmd python3 "python3"
check_cmd podman  "podman"

if [ -d "$HOME/.nvm" ]; then
  ok "nvm directory found at ~/.nvm"
else
  warn "nvm not found at ~/.nvm"
fi

if [ -f "$HOME/.config/Claude/claude_desktop_config.json" ]; then
  ok "Claude Desktop config found"
else
  warn "Claude Desktop config not found (will be created)"
fi

if [ -f "$HOME/.claude-secrets" ]; then
  ok "~/.claude-secrets exists"
else
  warn "~/.claude-secrets not found (will be created)"
fi

echo

# ── Phase 1: Core tools ───────────────────────────────────────────────────────
header "Phase 1 — Core tools (§2.2, §3.1–§3.4)"
echo
info "This phase installs: curl/wget, nvm + Node.js 24, Python MCP tools,"
info "Podman, the GitHub MCP container image, and uv/uvx."
echo

if ! ask "Run Phase 1 (core tools)?"; then
  warn "Skipping Phase 1."
else

  # §2.2 — curl and wget
  echo
  info "§2.2 — Checking curl and wget..."
  MISSING_APT=()
  command -v curl &>/dev/null || MISSING_APT+=(curl)
  command -v wget &>/dev/null || MISSING_APT+=(wget)
  if [ ${#MISSING_APT[@]} -gt 0 ]; then
    info "Installing: ${MISSING_APT[*]}"
    sudo apt install -y "${MISSING_APT[@]}"
    ok "Installed ${MISSING_APT[*]}"
  else
    ok "curl and wget already installed — skipping"
  fi

  # §3.1 — nvm and Node.js
  echo
  info "§3.1 — Checking nvm and Node.js 24..."
  if [ -d "$HOME/.nvm" ]; then
    ok "nvm already installed — skipping nvm install"
  else
    info "Installing nvm v0.40.1..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    ok "nvm installed"
  fi

  # Source nvm so it is available in this script session
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  if command -v node &>/dev/null && [[ "$(node --version)" == v24* ]]; then
    ok "Node.js 24 already active — skipping"
  else
    info "Installing Node.js 24 via nvm..."
    nvm install 24
    nvm use 24
    ok "Node.js $(node --version) installed and active"
  fi

  # §3.2 — Python MCP tools
  echo
  info "§3.2 — Checking Python MCP tools..."
  PY_TOOLS=("mcp-server-fetch" "mcp-server-git" "xlsxwriter")
  for tool in "${PY_TOOLS[@]}"; do
    pkg_name="$tool"
    # xlsxwriter installs as XlsxWriter, check by import
    if [ "$tool" = "xlsxwriter" ]; then
      if python3 -c "import xlsxwriter" 2>/dev/null; then
        ok "xlsxwriter already installed — skipping"
        continue
      fi
    else
      if pip show "$tool" &>/dev/null 2>&1; then
        ok "$tool already installed — skipping"
        continue
      fi
    fi
    info "Installing $tool..."
    pip install "$tool" --break-system-packages
    ok "$tool installed"
  done

  # §3.3 — Podman
  echo
  info "§3.3 — Checking Podman..."
  if command -v podman &>/dev/null; then
    ok "Podman already installed — skipping apt install"
  else
    info "Installing Podman..."
    sudo apt install -y podman
    ok "Podman installed"
  fi

  info "Enabling Podman user socket..."
  if systemctl --user is-active podman.socket &>/dev/null; then
    ok "Podman socket already active"
  else
    systemctl --user enable --now podman.socket
    ok "Podman socket enabled and started"
  fi

  info "Checking for GitHub MCP server container image..."
  if podman images --format '{{.Repository}}' | grep -q 'github/github-mcp-server'; then
    ok "GitHub MCP server image already present — skipping pull"
  else
    info "Pulling ghcr.io/github/github-mcp-server (this may take a minute)..."
    podman pull ghcr.io/github/github-mcp-server
    ok "GitHub MCP server image pulled"
  fi

  # §3.4 — uv / uvx
  echo
  info "§3.4 — Checking uv/uvx..."
  if command -v uv &>/dev/null; then
    ok "uv already installed — skipping"
  else
    info "Installing uv via astral.sh..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add uv to PATH for remainder of this script
    export PATH="$HOME/.local/bin:$PATH"
    ok "uv installed"
  fi

fi  # end Phase 1

# ── Phase 2: Claude Desktop ───────────────────────────────────────────────────
header "Phase 2 — Claude Desktop (§4)"
echo
info "Installs the community Linux port of Claude Desktop via APT repo."
info "Source: https://github.com/aaddrick/claude-desktop-debian"
echo

if command -v claude-desktop &>/dev/null || dpkg -l claude-desktop &>/dev/null 2>&1; then
  ok "Claude Desktop already installed — skipping"
else
  if ! ask "Install Claude Desktop?"; then
    warn "Skipping Phase 2."
  else
    info "§4 Step 1 — Adding GPG signing key..."
    curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg
    ok "GPG key added"

    info "§4 Step 2 — Adding APT repository..."
    echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] \
https://aaddrick.github.io/claude-desktop-debian stable main" \
      | sudo tee /etc/apt/sources.list.d/claude-desktop.list
    ok "APT repo added"

    info "§4 Step 3 — Installing claude-desktop..."
    sudo apt update && sudo apt install -y claude-desktop
    ok "Claude Desktop installed"
  fi
fi

# ── Phase 3: MCP configuration ────────────────────────────────────────────────
header "Phase 3 — MCP configuration (§5)"
echo
info "Creates wrapper scripts for GitHub and Brave Search MCP servers,"
info "then writes ~/.config/Claude/claude_desktop_config.json with correct paths."
echo

if ! ask "Run Phase 3 (MCP configuration)?"; then
  warn "Skipping Phase 3."
else

  # Detect nvm node bin path
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  if ! command -v node &>/dev/null; then
    err "Node.js not found — cannot determine node bin path."
    err "Complete Phase 1 first, then re-run this script."
    exit 1
  fi

  NODE_VERSION=$(node --version)
  NODE_BIN="$HOME/.nvm/versions/node/${NODE_VERSION}/bin"
  ok "Detected node bin path: $NODE_BIN"

  # §5.3 — Wrapper scripts
  echo
  info "§5.3 — Creating wrapper scripts directory..."
  mkdir -p "$HOME/.config/Claude/wrappers"
  ok "~/.config/Claude/wrappers/ ready"

  GITHUB_WRAPPER="$HOME/.config/Claude/wrappers/github-mcp.sh"
  if [ -f "$GITHUB_WRAPPER" ]; then
    ok "github-mcp.sh already exists — skipping"
  else
    cat > "$GITHUB_WRAPPER" << 'WRAPPER_EOF'
#!/usr/bin/env bash
source "$HOME/.claude-secrets"
exec podman run -i --rm \
  -e GITHUB_PERSONAL_ACCESS_TOKEN \
  ghcr.io/github/github-mcp-server
WRAPPER_EOF
    chmod +x "$GITHUB_WRAPPER"
    ok "github-mcp.sh created and made executable"
  fi

  BRAVE_WRAPPER="$HOME/.config/Claude/wrappers/brave-search-mcp.sh"
  if [ -f "$BRAVE_WRAPPER" ]; then
    ok "brave-search-mcp.sh already exists — skipping"
  else
    # Write with NODE_BIN substituted at creation time
    cat > "$BRAVE_WRAPPER" << WRAPPER_EOF
#!/usr/bin/env bash
NODE_BIN="${NODE_BIN}"
source "\$HOME/.claude-secrets"
exec "\$NODE_BIN/npx" -y @modelcontextprotocol/server-brave-search
WRAPPER_EOF
    chmod +x "$BRAVE_WRAPPER"
    ok "brave-search-mcp.sh created and made executable"
  fi

  # Podman MCP server — check if installed
  PODMAN_MCP_BIN="$HOME/.venv/bin/podman-mcp-server"
  if [ ! -f "$PODMAN_MCP_BIN" ]; then
    warn "podman-mcp-server not found at $PODMAN_MCP_BIN"
    info "Installing podman-mcp-server into ~/.venv ..."
    python3 -m venv "$HOME/.venv"
    "$HOME/.venv/bin/pip" install podman-mcp-server
    ok "podman-mcp-server installed"
  else
    ok "podman-mcp-server found at $PODMAN_MCP_BIN"
  fi

  # §5.5 — Write claude_desktop_config.json
  echo
  CONFIG_FILE="$HOME/.config/Claude/claude_desktop_config.json"
  if [ -f "$CONFIG_FILE" ]; then
    warn "$CONFIG_FILE already exists."
    if ! ask "Overwrite existing claude_desktop_config.json?"; then
      warn "Skipping config file — existing file kept."
    else
      cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
      info "Backed up existing config to ${CONFIG_FILE}.bak"
      WRITE_CONFIG=true
    fi
  else
    WRITE_CONFIG=true
  fi

  if [ "${WRITE_CONFIG:-false}" = true ]; then
    mkdir -p "$HOME/.config/Claude"
    cat > "$CONFIG_FILE" << CONFIG_EOF
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$HOME"],
      "env": {
        "PATH": "${NODE_BIN}:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "excel": {
      "command": "npx",
      "args": ["--yes", "@negokaz/excel-mcp-server"],
      "env": {
        "EXCEL_MCP_PAGING_CELLS_LIMIT": "4000",
        "PATH": "${NODE_BIN}:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "git": {
      "command": "$HOME/.local/bin/mcp-server-git",
      "env": {
        "PATH": "${NODE_BIN}:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "github": {
      "command": "$HOME/.config/Claude/wrappers/github-mcp.sh",
      "args": []
    },
    "fetch": {
      "command": "$HOME/.local/bin/mcp-server-fetch",
      "env": {
        "PATH": "${NODE_BIN}:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "brave-search": {
      "command": "$HOME/.config/Claude/wrappers/brave-search-mcp.sh",
      "args": []
    },
    "podman": {
      "command": "$HOME/.venv/bin/podman-mcp-server",
      "args": [],
      "env": {
        "PODMAN_SOCK": "/run/user/$(id -u)/podman/podman.sock"
      }
    },
    "shell": {
      "command": "uvx",
      "args": ["mcp-shell-server"],
      "env": {
        "ALLOW_COMMANDS": "python3,sqlite3,ls,cat,grep,find,wc,pwd"
      }
    }
  }
}
CONFIG_EOF
    ok "claude_desktop_config.json written with node path: $NODE_BIN"
  fi

fi  # end Phase 3

# ── Phase 4: Secrets ──────────────────────────────────────────────────────────
header "Phase 4 — Secrets (§5.4)"
echo
info "Creates ~/.claude-secrets with your GitHub token and Brave API key."
info "Tokens are entered interactively (not shown on screen)."
info "File is created with chmod 600 (readable by you only)."
echo

SECRETS_FILE="$HOME/.claude-secrets"

if [ -f "$SECRETS_FILE" ]; then
  warn "~/.claude-secrets already exists."
  info "Current contents (values masked):"
  grep -oP '^export \K[A-Z_]+' "$SECRETS_FILE" | while read -r key; do
    echo -e "    export $key=***"
  done
  echo
  if ! ask "Re-enter secrets (will overwrite existing file)?"; then
    warn "Skipping Phase 4 — existing secrets file kept."
    WRITE_SECRETS=false
  else
    WRITE_SECRETS=true
  fi
else
  WRITE_SECRETS=true
fi

if [ "${WRITE_SECRETS:-false}" = true ]; then

  if ! ask "Run Phase 4 (enter secrets)?"; then
    warn "Skipping Phase 4."
  else
    echo
    info "Enter your GitHub Personal Access Token:"
    info "(Get one at: github.com → Settings → Developer Settings → Personal Access Tokens)"
    echo -en "  Token: "
    read -rs GITHUB_TOKEN
    echo

    if [ -z "$GITHUB_TOKEN" ]; then
      warn "No GitHub token entered — writing placeholder. Edit ~/.claude-secrets manually."
      GITHUB_TOKEN="your_github_token_here"
    fi

    echo
    info "Enter your Brave Search API key:"
    info "(Get one at: brave.com/search/api — free tier: 2,000 queries/month)"
    echo -en "  Key: "
    read -rs BRAVE_KEY
    echo

    if [ -z "$BRAVE_KEY" ]; then
      warn "No Brave key entered — writing placeholder. Edit ~/.claude-secrets manually."
      BRAVE_KEY="your_brave_key_here"
    fi

    cat > "$SECRETS_FILE" << SECRETS_EOF
# ~/.claude-secrets — never commit, never share
# Loaded at runtime by wrapper scripts in ~/.config/Claude/wrappers/
export GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_TOKEN}
export BRAVE_API_KEY=${BRAVE_KEY}
SECRETS_EOF

    chmod 600 "$SECRETS_FILE"
    ok "~/.claude-secrets written with chmod 600"
  fi
fi

# ── Phase 5: CLAUDE.md template ──────────────────────────────────────────────
header "Phase 5 — Global CLAUDE.md template (§8)"
echo
info "Creates ~/CLAUDE.md — the global instruction file Claude reads each session."
info "If it already exists, it will not be overwritten."
echo

CLAUDE_MD="$HOME/CLAUDE.md"

if [ -f "$CLAUDE_MD" ]; then
  ok "~/CLAUDE.md already exists — skipping (yours is preserved)."
else
  if ! ask "Create ~/CLAUDE.md template?"; then
    warn "Skipping Phase 5."
  else
    cat > "$CLAUDE_MD" << 'CLAUDEMD_EOF'
## Environment

- OS: Linux Mint 22.3
- Local Claude Desktop with local MCP servers (filesystem, excel, git, github,
  fetch, brave-search, podman, shell)
- I have local read/write access to my home directory
- Do NOT assume a web interface unless I say so

## Who I Am

<!-- Describe your background, how technical you are, communication preferences -->

## How to Work

- Read ~/.config/Claude/claude_desktop_config.json at the start of any session
  where MCP tools or system configuration is relevant
- Review any project files or chats provided for context before responding
- Do not guess or give knee-jerk responses. Research first, then act
- When uncertain, state your confidence level: certain / high / low / unknown
- If stuck, stop and ask rather than proceed on a guess

## File Handling

- xlsx files: the excel MCP server cannot create files from scratch. Seed new
  files with: python3 -c "import xlsxwriter; wb = xlsxwriter.Workbook('/path/to/file.xlsx'); wb.add_worksheet('SheetName'); wb.close()"
  Then write content via the excel MCP. Never use openpyxl.
- For other binary formats (pdf, docx): use Python scripts with vetted libraries

## Commands

- When giving me bash or terminal commands: one line only, clean, copy-paste
  ready with no editing required.

## Agentic Task Rules

- Before executing any multi-step or agentic task, STOP and present a numbered
  plan of what you intend to do and what tools/files will be affected.
- Wait for explicit approval before taking any action.
- Never perform destructive actions (delete, overwrite, move files) without
  explicit per-action confirmation, regardless of prior approvals.
CLAUDEMD_EOF
    ok "~/CLAUDE.md template created — edit it to describe yourself."
  fi
fi

# ── Phase 6: Verification ─────────────────────────────────────────────────────
header "Phase 6 — Verification summary (§11)"
echo
info "Checking installed components..."
echo

PASS=0; FAIL=0

check_phase() {
  local label="$1" result="$2"
  if [ "$result" = "ok" ]; then
    ok "$label"
    ((PASS++)) || true
  else
    err "$label — $result"
    ((FAIL++)) || true
  fi
}

# Source nvm one more time for final checks
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# Node
if command -v node &>/dev/null && [[ "$(node --version)" == v24* ]]; then
  check_phase "Node.js 24 ($(node --version))" "ok"
else
  check_phase "Node.js 24" "not found or wrong version"
fi

# Python tools
for tool in mcp-server-fetch mcp-server-git; do
  BIN="$HOME/.local/bin/$tool"
  if [ -f "$BIN" ]; then
    check_phase "$tool" "ok"
  else
    check_phase "$tool" "not found at $BIN"
  fi
done

if python3 -c "import xlsxwriter" 2>/dev/null; then
  check_phase "xlsxwriter" "ok"
else
  check_phase "xlsxwriter" "not importable"
fi

# Podman
if command -v podman &>/dev/null; then
  check_phase "Podman ($(podman --version))" "ok"
else
  check_phase "Podman" "not found"
fi

if systemctl --user is-active podman.socket &>/dev/null; then
  check_phase "Podman socket (active)" "ok"
else
  check_phase "Podman socket" "not active — run: systemctl --user enable --now podman.socket"
fi

if podman images --format '{{.Repository}}' 2>/dev/null | grep -q 'github/github-mcp-server'; then
  check_phase "GitHub MCP container image" "ok"
else
  check_phase "GitHub MCP container image" "not found — run: podman pull ghcr.io/github/github-mcp-server"
fi

# uv
if command -v uv &>/dev/null; then
  check_phase "uv ($(uv --version))" "ok"
else
  check_phase "uv" "not found"
fi

# Claude Desktop
if command -v claude-desktop &>/dev/null || dpkg -l claude-desktop &>/dev/null 2>&1; then
  check_phase "Claude Desktop" "ok"
else
  check_phase "Claude Desktop" "not installed"
fi

# Wrapper scripts
for w in github-mcp.sh brave-search-mcp.sh; do
  WF="$HOME/.config/Claude/wrappers/$w"
  if [ -f "$WF" ] && [ -x "$WF" ]; then
    check_phase "Wrapper: $w" "ok"
  else
    check_phase "Wrapper: $w" "missing or not executable"
  fi
done

# Config file
if [ -f "$HOME/.config/Claude/claude_desktop_config.json" ]; then
  check_phase "claude_desktop_config.json" "ok"
else
  check_phase "claude_desktop_config.json" "not found"
fi

# Secrets file
if [ -f "$HOME/.claude-secrets" ]; then
  PERMS=$(stat -c '%a' "$HOME/.claude-secrets")
  if [ "$PERMS" = "600" ]; then
    check_phase "~/.claude-secrets (chmod 600)" "ok"
  else
    check_phase "~/.claude-secrets" "permissions are $PERMS — should be 600. Run: chmod 600 ~/.claude-secrets"
  fi
else
  check_phase "~/.claude-secrets" "not found"
fi

# CLAUDE.md
if [ -f "$HOME/CLAUDE.md" ]; then
  check_phase "~/CLAUDE.md" "ok"
else
  check_phase "~/CLAUDE.md" "not found"
fi

echo
echo -e "  ${BOLD}Result: ${GREEN}${PASS} passed${RESET}  ${RED}${FAIL} failed${RESET}"

# ── What still needs manual steps ─────────────────────────────────────────────
header "What still needs manual steps"
echo
echo -e "  The following cannot be automated — complete these before using Claude Desktop:"
echo
echo -e "  ${YELLOW}1.${RESET} ${BOLD}Get a GitHub Personal Access Token${RESET} (if not done yet)"
echo -e "     github.com → Settings → Developer Settings → Personal Access Tokens"
echo -e "     Minimum scopes needed: repo, read:org"
echo
echo -e "  ${YELLOW}2.${RESET} ${BOLD}Get a Brave Search API key${RESET} (if not done yet)"
echo -e "     brave.com/search/api — free tier: 2,000 queries/month"
echo
echo -e "  ${YELLOW}3.${RESET} ${BOLD}Edit ~/CLAUDE.md${RESET} to describe yourself"
echo -e "     Fill in the 'Who I Am' section with your background and preferences."
echo
echo -e "  ${YELLOW}4.${RESET} ${BOLD}Launch Claude Desktop and log in${RESET}"
echo -e "     Open from the application menu. Sign in with your Anthropic account."
echo
echo -e "  ${YELLOW}5.${RESET} ${BOLD}Verify MCP servers are active${RESET} (§11)"
echo -e "     In a new chat, ask Claude:"
echo -e "       'List the files in my home directory'  → tests filesystem MCP"
echo -e "       'What GitHub repos do I own?'          → tests github MCP"
echo -e "       'Search the web for Linux Mint'        → tests brave-search MCP"
echo -e "       'List running containers'              → tests podman MCP"
echo -e "       'Run the command: pwd'                 → tests shell MCP"
echo
echo -e "  ${YELLOW}6.${RESET} ${BOLD}If any MCP server is missing${RESET}, check its log:"
echo -e "     cat ~/.config/Claude/logs/mcp-server-[name].log"
echo
echo -e "  ${YELLOW}⚠${RESET}  ${BOLD}After any Cowork session, restart Claude Desktop${RESET} before using"
echo -e "     filesystem MCP tools. See §9.1 of the setup guide."
echo

ok "Setup script complete."
echo
