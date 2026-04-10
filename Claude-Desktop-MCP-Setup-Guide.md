# Claude Desktop + Local MCP Servers
## Complete Setup Guide for Linux Mint 21.x and 22.x (Debian-based)

*April 2026 | Based on working production configurations on Linux Mint 21.3 and 22.3*

> **Note:** This guide documents real, tested setups. Every config file, wrapper script, and gotcha is drawn from active working systems running Claude Desktop (Linux community port) with seven local MCP servers.

---

## A Note on Paths in This Guide

Most paths in this guide use `~` or `$HOME`, which automatically resolve to your home directory regardless of your username — so commands can be copied and run as-is.

The one exception is `claude_desktop_config.json`. JSON does not expand shell variables, so absolute paths in that file must use your actual home directory path. A single setup command handles this for you — see Section 5.5.

---

## 1. Overview

This guide walks you through replicating a fully configured local AI workspace on any Linux Mint machine. The setup gives Claude Desktop access to seven local MCP (Model Context Protocol) servers that extend what Claude can do — reading and writing files, running Excel operations, interacting with GitHub, searching the web, fetching URLs, managing containers, and executing git commands.

**What you will have when done:**

- Claude Desktop for Linux (community Debian port) installed and running
- Seven active MCP servers: filesystem, excel, git, github, fetch, brave-search, podman
- API keys and tokens stored securely in a dedicated secrets file, separate from all config
- A global CLAUDE.md instruction file that shapes Claude's behavior
- A clear understanding of key operational gotchas specific to the Linux port

---

## 2. Prerequisites

### 2.1 System Requirements

Linux Mint 21.x (based on Ubuntu 22.04) or Linux Mint 22.x (based on Ubuntu 24.04). The steps below assume a standard desktop install with sudo access. Where the two versions differ, this guide calls it out explicitly — see Section 3.2 for the main difference in Python tool installation.

### 2.2 Install curl, wget, and npm

Several installation steps depend on `curl`, `wget`, and `npm`. They are not always present by default on a fresh Linux Mint install.

**curl** is a command-line tool for downloading files and making web requests. It is used here to install nvm and uv.

**wget** is similar to curl — a download tool used here when a direct file download is needed.

**npm** (Node Package Manager) is the tool used to install Node.js packages, including several of the MCP servers. It is installed automatically as part of Node.js via nvm (Section 3.1) — you do not need to install it separately.

Check what you have:

```bash
curl --version; wget --version; npm --version
```

Install anything missing:

```bash
sudo apt install curl wget -y
```

> **Note:** `npm` should not be installed via apt — its system version is too old. Install it via nvm as described in Section 3.1.

### 2.3 Accounts and API Keys You Will Need

Gather these before starting — some require sign-up and approval:

| Service | Required For | Where to Get It |
|---|---|---|
| GitHub Personal Access Token | github MCP | github.com → Settings → Developer Settings → Personal Access Tokens |
| Brave Search API Key | brave-search MCP | brave.com/search/api — free tier available (2,000 queries/month) |
| Anthropic Claude Pro account | Claude Desktop login | claude.ai — Pro subscription required for extended usage |

---

## 3. Install Core Tools

### 3.1 Node.js via nvm (Required)

Do NOT install Node.js from the system package manager — the version is too old. Use nvm (Node Version Manager) instead. nvm lets you install and switch between Node.js versions without affecting system packages:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 24
nvm use 24
node --version   # should show v24.x.x
npm --version    # npm is installed automatically alongside node
```

> **Note:** The PATH entries in `claude_desktop_config.json` must point to the nvm node binary, not `/usr/bin/node`. The exact path includes the node version number — use this command to find yours after installation: `echo "$HOME/.nvm/versions/node/$(node --version)/bin"`

### 3.2 Python Tools

How you install Python-based MCP tools depends on which version of Linux Mint you are running. The underlying reason is that Linux Mint 21.x ships with an older Python packaging system that is more restrictive about installing packages into the system Python environment.

---

**Linux Mint 22.x — use pip with the `--break-system-packages` flag:**

```bash
pip install xlsxwriter --break-system-packages
pip install mcp-server-fetch --break-system-packages
pip install mcp-server-git --break-system-packages
```

---

**Linux Mint 21.x — use pipx instead:**

`pipx` is a tool that installs each Python application into its own isolated environment and automatically makes it available on your PATH. It avoids the system Python restrictions that make plain `pip` unreliable on 21.x.

First install pipx:

```bash
sudo apt install pipx
```

Then install the tools:

```bash
pipx install xlsxwriter
pipx install mcp-server-fetch
pipx install mcp-server-git
```

Confirm the tools are on your PATH after installation:

```bash
pipx ensurepath
source ~/.bashrc
which mcp-server-fetch && which mcp-server-git
```

> **Note:** Both methods place the `mcp-server-fetch` and `mcp-server-git` binaries in `~/.local/bin`, so the `claude_desktop_config.json` paths in Section 5.5 work identically on both versions.

---

> ⚠️ **Never use openpyxl to create .xlsx files** — it produces files unreadable in LibreOffice Calc and Office 365. Always use xlsxwriter for seeding new spreadsheets.

### 3.3 Podman

Podman is a daemonless container engine — it runs software containers without needing a background service running as root. It is used here to run the GitHub MCP server, which is distributed as a container image rather than an installable package.

```bash
sudo apt install podman -y
systemctl --user enable --now podman.socket
podman --version   # confirm installed
```

**Pull the GitHub MCP server image** so it is available before Claude Desktop first tries to use it:

```bash
podman pull ghcr.io/github/github-mcp-server
```

This downloads the container image to your local machine. Without this step, the first time Claude tries to use the github MCP server it will attempt to pull the image on demand, which may time out or fail silently. Verify it pulled correctly:

```bash
podman images | grep github-mcp-server
```

You should see a line showing the image name and a recent timestamp.

### 3.4 uv / uvx (for shell MCP server, optional)

`uv` is a fast Python package and tool runner. `uvx` (part of uv) lets you run Python-based tools in temporary isolated environments without permanently installing them. The optional shell MCP server uses `uvx` to launch itself.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv --version   # confirm installed
```

---

## 4. Install Claude Desktop (Linux Community Port)

Anthropic's official Claude Desktop is only released for macOS and Windows. The Linux version is maintained by the community at https://github.com/aaddrick/claude-desktop-debian.

> **Why install Claude Desktop here, after the core tools?** Claude Desktop can technically be installed at any point — it doesn't depend on Node.js, Python, or Podman to install. We place it here because by this point all the tools it will reference in its config file are already installed and their paths are known. That makes Section 5 (configuration) a single clean pass with no need to go back and fix paths later. If you prefer to install the app first and explore it before setting up MCP, that's fine — just return here to complete the configuration.

The recommended installation method is via the project's APT repository rather than downloading a `.deb` file manually. The APT method integrates with Linux Mint's package manager, so future Claude Desktop updates arrive automatically alongside your other system updates via `sudo apt update && sudo apt upgrade`.

**Step 1** — add the GPG signing key so your system can verify the package:

```bash
curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg | sudo gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg
```

**Step 2** — add the repository to your package sources:

```bash
echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] https://aaddrick.github.io/claude-desktop-debian stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop.list
```

**Step 3** — update package lists and install:

```bash
sudo apt update && sudo apt install claude-desktop
```

To update Claude Desktop in future, just run:

```bash
sudo apt update && sudo apt upgrade
```

> ⚠️ The Linux port behaves differently from the official Mac/Windows app in a few important ways — see Section 9 (Gotchas) for details.

---

## 5. MCP Server Configuration

### 5.1 The Security Model — Config vs. Secrets

This setup keeps a clean separation between configuration and secrets:

- **`~/.config/Claude/claude_desktop_config.json`** — contains only paths, package names, and non-sensitive settings. This file is safe to back up or share (for example, as a template for setting up another machine). It contains no tokens or API keys.

- **`~/.claude-secrets`** — contains your actual API tokens and keys. This is the only file that is sensitive. It is never referenced directly in the config; wrapper scripts load it at runtime.

> 🔒 **Protect `~/.claude-secrets`:** lock permissions with `chmod 600 ~/.claude-secrets` and never commit it to a git repository or share it.

### 5.2 The Secrets File

Create the secrets file and add your keys:

```bash
nano ~/.claude-secrets
```

Add these lines (fill in your actual keys):

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_your_token_here
export BRAVE_API_KEY=BSA_your_key_here
```

Lock down the file permissions:

```bash
chmod 600 ~/.claude-secrets
```

### 5.3 Wrapper Scripts

Two MCP servers (github and brave-search) use wrapper scripts that load the secrets file at runtime and then launch the server. This keeps tokens completely out of the config file.

Create the wrappers directory:

```bash
mkdir -p ~/.config/Claude/wrappers
```

#### GitHub wrapper: `~/.config/Claude/wrappers/github-mcp.sh`

```bash
#!/bin/bash
# Loads GitHub token from ~/.claude-secrets and runs the GitHub MCP server via podman
if [ -f "$HOME/.claude-secrets" ]; then
    source "$HOME/.claude-secrets"
else
    echo "ERROR: ~/.claude-secrets not found" >&2; exit 1
fi
if [ -z "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
    echo "ERROR: GITHUB_PERSONAL_ACCESS_TOKEN not set in ~/.claude-secrets" >&2; exit 1
fi
exec podman run -i --rm \
    -e GITHUB_PERSONAL_ACCESS_TOKEN \
    ghcr.io/github/github-mcp-server
```

#### Brave Search wrapper: `~/.config/Claude/wrappers/brave-search-mcp.sh`

```bash
#!/bin/bash
# Loads Brave API key from ~/.claude-secrets and runs the Brave Search MCP server
if [ -f "$HOME/.claude-secrets" ]; then
    source "$HOME/.claude-secrets"
else
    echo "ERROR: ~/.claude-secrets not found" >&2; exit 1
fi
if [ -z "$BRAVE_API_KEY" ]; then
    echo "ERROR: BRAVE_API_KEY not set in ~/.claude-secrets" >&2; exit 1
fi
export BRAVE_API_KEY
export PATH="$HOME/.nvm/versions/node/$(node --version)/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
exec npx -y @modelcontextprotocol/server-brave-search
```

Make both scripts executable:

```bash
chmod +x ~/.config/Claude/wrappers/github-mcp.sh && chmod +x ~/.config/Claude/wrappers/brave-search-mcp.sh
```

### 5.4 Install the podman-mcp-server Python Package

```bash
python3 -m venv ~/.venv && ~/.venv/bin/pip install podman-mcp-server
~/.venv/bin/podman-mcp-server --version   # confirm
```

### 5.5 Generate the claude_desktop_config.json

Because JSON does not expand shell variables, the config file needs your actual home directory path written into it. This command generates the file correctly for any user:

```bash
cat > ~/.config/Claude/claude_desktop_config.json << EOF
{
  "mcpServers": {
    "podman": {
      "command": "$HOME/.venv/bin/podman-mcp-server",
      "args": [],
      "env": {
        "PODMAN_SOCK": "/run/user/$(id -u)/podman/podman.sock"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$HOME"],
      "env": {
        "PATH": "$HOME/.nvm/versions/node/$(node --version)/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "excel": {
      "command": "npx",
      "args": ["--yes", "@negokaz/excel-mcp-server"],
      "env": {
        "EXCEL_MCP_PAGING_CELLS_LIMIT": "4000",
        "PATH": "$HOME/.nvm/versions/node/$(node --version)/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "github": {
      "command": "$HOME/.config/Claude/wrappers/github-mcp.sh",
      "args": []
    },
    "fetch": {
      "command": "$HOME/.local/bin/mcp-server-fetch",
      "env": {
        "PATH": "$HOME/.nvm/versions/node/$(node --version)/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "git": {
      "command": "$HOME/.local/bin/mcp-server-git",
      "env": {
        "PATH": "$HOME/.nvm/versions/node/$(node --version)/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }
    },
    "brave-search": {
      "command": "$HOME/.config/Claude/wrappers/brave-search-mcp.sh",
      "args": []
    },
    "shell": {
      "command": "uvx",
      "args": ["mcp-shell-server"],
      "env": {
        "ALLOW_COMMANDS": "python3,sqlite3,ls,cat,grep,find,wc,pwd"
      }
    }
  },
  "preferences": {
    "chromeExtensionEnabled": false,
    "coworkScheduledTasksEnabled": true,
    "ccdScheduledTasksEnabled": true,
    "sidebarMode": "chat",
    "coworkWebSearchEnabled": true
  }
}
EOF
```

> **Note:** The `$(id -u)` part resolves your numeric user ID, used in the podman socket path. The `$(node --version)` part inserts your exact installed node version. Both are resolved at the time you run the command, so the resulting file contains clean absolute paths with no variables.

Verify the file looks correct after generating it:

```bash
cat ~/.config/Claude/claude_desktop_config.json
```

### 5.6 Shell MCP Server — Permissions and Scope

The shell MCP server (`mcp-shell-server`) lets Claude run bash commands on your machine. This is powerful but potentially dangerous if left unrestricted — Claude could in principle run any command your user account can run.

The `ALLOW_COMMANDS` environment variable in the config is the safety gate. It is a comma-separated whitelist of the only commands Claude is permitted to execute. In the config above, the allowed set is:

```
python3, sqlite3, ls, cat, grep, find, wc, pwd
```

These are all read-oriented or Python execution — no package managers, no file deletion, no network tools, no compilers.

**To customize the allowed commands** for your own needs, edit that line in the config. Some examples of commands you might add depending on your work:

- `git` — if you want Claude to run git commands via shell rather than the dedicated git MCP
- `pip` — if you want Claude to install Python packages (use with caution)
- `npm` — similarly, for Node packages
- `cargo`, `rustc` — for Rust development workflows

> ⚠️ **Think carefully before adding commands to this list.** Any command here can be run by Claude without you typing it. Keep the list as short as your actual needs require.

**Commands not on the whitelist must be run by you manually in a terminal.** This is by design — it keeps you in control of anything that modifies the system, installs software, or has side effects beyond reading files. Claude will tell you what command to run and why; you decide whether to run it.

### 5.7 MCP Is Not Claude-Specific

The MCP servers configured in this guide are built on the open Model Context Protocol standard — they are not tied to Claude. Other AI tools and interfaces that support MCP can connect to the same servers without any changes to this setup. Local model runners such as Ollama, and desktop AI interfaces that support MCP, can point at these same servers using their own configuration files in a format similar to `claude_desktop_config.json`. The servers themselves — filesystem, git, Excel, Podman, and the rest — simply sit and wait for any MCP-compatible client to call them. This means the infrastructure you build here is reusable across whatever AI tools you choose to run alongside Claude.

---

## 6. Excel MCP — Important Workflow

The `@negokaz/excel-mcp-server` cannot create `.xlsx` files from scratch. Always use this two-step process:

**Step 1** — seed the file using xlsxwriter (creates a valid empty workbook):

```bash
python3 -c "import xlsxwriter; wb = xlsxwriter.Workbook('/path/to/file.xlsx'); wb.add_worksheet('Sheet1'); wb.close()"
```

**Step 2** — write content using the excel MCP server tools (reads and writes via Excelize, which is LibreOffice-compatible).

> ⚠️ Never use openpyxl to seed or create xlsx files. It produces files that fail to open correctly in both LibreOffice Calc and Microsoft Office 365.

---

## 7. What Claude Can and Cannot Do With Files — and the Role of Claude Pro

### 7.1 Local MCP File Capabilities

**Plain text files** (`.md`, `.txt`, `.json`, `.py`, `.js`, `.sh`, config files, etc.) — Claude can read and write these directly via the filesystem MCP. No special tools needed.

**Spreadsheets (`.xlsx`)** — handled by the dedicated excel MCP server, which understands the format natively. Claude can read cell data, write values, create sheets, and format content — but cannot create the file from scratch (use the xlsxwriter seed step in Section 6).

**Binary document formats (`.docx`, `.pdf`)** — the filesystem MCP cannot interpret these. They are binary formats, not plain text. Claude cannot read their content or write them directly through the local MCP setup. Workarounds when working locally:

- For `.docx`: Claude can generate a JavaScript script using the `docx` npm library, which you then run yourself in a terminal (`node script.js`). Claude writes the script; you execute it.
- For `.pdf`: similarly, Claude can write a Python script using a library like `reportlab` or `pypdf2` for you to run.
- LibreOffice can also convert between formats from the command line if you need to go from `.docx` to `.pdf` or vice versa.

### 7.2 Claude Pro Expands What Claude Desktop Can Do

The local MCP setup described in this guide gives Claude access to your machine's files, tools, and services. With a **Claude Pro subscription**, Claude Desktop gains an additional layer of capabilities on top of that — the two work together rather than one replacing the other.

With Pro, Claude Desktop can use:

- **Cowork** — Claude's agentic task execution mode, which can run multi-step workflows combining both local MCP tools and cloud-side capabilities in a single session. For example, Cowork can read a local file via the filesystem MCP, process it using a cloud code execution environment, and write results back locally.
- **Claude's cloud-side code execution environment** — the same sandboxed environment available on claude.ai, which can run scripts, generate binary files like `.docx` and `.pdf` directly, and handle tasks that would otherwise require you to run scripts manually.
- **Claude.ai MCP connectors** — Anthropic's hosted integrations (Gmail, Google Calendar, and others) can be used from within Claude Desktop sessions, alongside your local MCP servers.

In practice this means a Pro user on Claude Desktop gets the full combined toolkit: local filesystem access, local git/github/Excel/podman tools, plus cloud execution and hosted connectors — all available in the same conversation.

**Without Pro**, the local MCP setup carries more of the load. Tasks that Pro would handle via cloud execution (like generating a `.docx` directly) instead require you to run scripts manually in a terminal. This works well but does consume more of your local token budget for the back-and-forth involved.

> **Note:** This guide covers setting up the local MCP side. The full capabilities of Cowork, cloud connectors, and Pro features are a separate topic not covered here — but the local MCP foundation built in this guide is what makes Claude Desktop genuinely useful with or without them.

---

## 8. The Global CLAUDE.md Instruction File

Claude Desktop reads a file called `CLAUDE.md` from your home directory at startup. This file shapes Claude's behavior globally — across all projects and conversations. Think of it as a standing briefing that Claude reads before every session.

Create it at:

```
~/CLAUDE.md
```

**Recommended sections to include:**

- **Environment** — OS, available MCP servers, file access scope
- **Who you are** — your background, how technical you are, communication preferences
- **How to work** — research-first approach, confidence labeling, when to stop and ask
- **File handling rules** — xlsx seeding workflow, libraries to avoid
- **Command format preferences** — e.g. single-line copy-paste-ready bash commands
- **Agentic task rules** — require plan approval before execution, no destructive actions without confirmation

> **Note:** Per-project `CLAUDE.md` files can be placed in any project directory. They layer on top of the global one. This is how you scope Claude's behavior to specific projects without changing global settings.

---

## 9. Key Gotchas — Linux Port Specific

### 9.1 Cowork Session Hijacking

When Claude's Cowork feature runs, it overrides the filesystem MCP's allowed directory to a session-scoped sandbox path. This persists at the MCP process level — it is NOT cleared by opening a new chat tab.

> ⚠️ **After any Cowork session, do a full Claude Desktop restart before using filesystem MCP tools.**
> Command: `pkill -f "claude"` then relaunch from the app menu.

To verify filesystem access at the start of any session, ask Claude to run: `filesystem:list_allowed_directories`

### 9.2 No Automatic Approval UI

The official Mac/Windows Claude Desktop shows a permission/approval dialog before agentic actions. The Linux port does not. Claude will proceed without asking unless you explicitly instruct it to pause.

**Reliable workaround** — include this in every agentic or Cowork prompt:

```
Before doing anything, show me your step-by-step plan and wait for my approval before proceeding.
```

### 9.3 MCP Server Startup Failures Are Silent

If an MCP server fails to start, Claude Desktop gives no visible error in the UI — it simply won't have access to that tool. Check logs to diagnose:

```
~/.config/Claude/logs/mcp-server-[name].log
```

Common causes: wrong PATH in config, missing npm package, podman socket not running, GitHub MCP image not pulled, secrets file missing or not readable.

### 9.4 PATH Must Be Explicit

MCP servers launched by Claude Desktop do not inherit your shell's PATH. Every server that uses npx or local binaries needs an explicit `PATH` entry in its `env` block in the config — pointing to the nvm node binary directory.

### 9.5 Google Drive MCP — Known Reliability Issue

The `@modelcontextprotocol/server-gdrive` package has OAuth reliability issues on Linux that can cause it to crash on startup and cascade to break other MCP servers. If you need Google Drive access, consider using `rclone` to mount it locally and access it via the filesystem MCP instead.

To disable gdrive without removing it from config, rename the key:

```json
"gdrive_DISABLED": { ... }
```

### 9.6 GitHub Token Security

The GitHub Personal Access Token appears in plain text if placed directly in `claude_desktop_config.json`. The wrapper script pattern (Section 5.3) avoids this entirely — the config file only references the wrapper script path, and the token is loaded from `~/.claude-secrets` at runtime. Always use the wrapper approach.

---

## 10. MCP Server Quick Reference

| Server | What It Does | How It Runs | Notes |
|---|---|---|---|
| filesystem | Read/write files under your home directory | npx (Node) | Scoped to home dir; Cowork can hijack — restart after Cowork |
| excel | Read/write .xlsx spreadsheets | npx (Node/Go binary) | Cannot create files; seed with xlsxwriter first |
| git | Git operations on local repos | Python binary | Installed via pip/pipx as mcp-server-git |
| github | GitHub API — issues, PRs, repos | Podman container | Token loaded from ~/.claude-secrets via wrapper script |
| fetch | Fetch URLs / web pages | Python binary | Installed via pip/pipx as mcp-server-fetch |
| brave-search | Web search via Brave API | npx (Node) | API key loaded from ~/.claude-secrets via wrapper script |
| podman | Container management | Python venv binary | Requires podman.socket running as user service |
| shell | Run whitelisted bash commands | uvx (Python) | Restricted by ALLOW_COMMANDS — see Section 5.6 |

---

## 11. Verification Checklist

After completing setup, verify each component:

1. Launch Claude Desktop and open a new chat
2. Ask Claude: "List the files in my home directory" — tests filesystem MCP
3. Ask Claude: "Search the web for Linux Mint latest version" — tests brave-search MCP
4. Ask Claude: "What GitHub repos do I own?" — tests github MCP
5. Ask Claude: "List running containers" — tests podman MCP
6. Ask Claude: "Run the command: pwd" — tests shell MCP
7. If any tool is missing, check `~/.config/Claude/logs/mcp-server-[name].log` for errors

---

## 12. Useful Diagnostic Commands

**Check which node is active:**
```bash
which node && node --version
```

**Print your nvm node bin path (use this to verify PATH entries in config):**
```bash
echo "$HOME/.nvm/versions/node/$(node --version)/bin"
```

**Check podman socket:**
```bash
systemctl --user status podman.socket
```

**Confirm GitHub MCP container image is present:**
```bash
podman images | grep github-mcp-server
```

**View MCP server logs:**
```bash
cat ~/.config/Claude/logs/mcp-server-filesystem.log
cat ~/.config/Claude/logs/mcp-server-github.log
cat ~/.config/Claude/logs/mcp-server-shell.log
```

**Full Claude Desktop restart (required after Cowork):**
```bash
pkill -f "claude" && sleep 2   # then relaunch from app menu
```

**Validate secrets file is readable:**
```bash
source ~/.claude-secrets && echo "GitHub token starts with: ${GITHUB_PERSONAL_ACCESS_TOKEN:0:4}"
```

---

*This document reflects working configurations tested on Linux Mint 21.3 and 22.3, April 2026.*
*Community port of Claude Desktop: https://github.com/aaddrick/claude-desktop-debian*
