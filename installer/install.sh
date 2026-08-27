#!/usr/bin/env bash
# AIKit Pro — macOS/Linux Installation Wizard
# Usage: curl -fsSL https://aikit.pro/install.sh | bash

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; BCYAN='\033[1;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; GRAY='\033[0;37m'; RESET='\033[0m'

banner() {
    clear
    echo ""
    echo -e "  ${BCYAN}╔══════════════════════════════════════╗${RESET}"
    echo -e "  ${BCYAN}║                                      ║${RESET}"
    echo -e "  ${BCYAN}║   ${CYAN}A I K I T  P R O${BCYAN}                   ║${RESET}"
    echo -e "  ${BCYAN}║   Professional AI Developer Setup    ║${RESET}"
    echo -e "  ${BCYAN}║                                      ║${RESET}"
    echo -e "  ${BCYAN}╚══════════════════════════════════════╝${RESET}"
    echo ""
}

step()  { echo -e "  ${CYAN}[$1]${RESET} $2"; }
ok()    { echo -e "  ${GREEN}✓${RESET}  $1"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail()  { echo -e "  ${RED}✗${RESET}  $1"; exit 1; }
info()  { echo -e "     ${GRAY}$1${RESET}"; }
rule()  { echo -e "  ${GRAY}─────────────────────────────────────${RESET}"; }

read_secret() {
    local prompt="$1"
    local secret
    echo -en "  ${GRAY}→ $prompt${RESET}"
    read -rs secret
    echo ""
    echo "$secret"
}

read_choice() {
    local prompt="$1"; shift
    local options=("$@")
    local default="${options[0]}"
    echo -e "  ${GRAY}→ $prompt${RESET}"
    for i in "${!options[@]}"; do
        local mark=" "; [[ "${options[$i]}" == "$default" ]] && mark="*"
        echo -e "    ${GRAY}[$mark] $((i+1)). ${options[$i]}${RESET}"
    done
    echo -en "    ${GRAY}Choice [1-${#options[@]}, Enter=$default]: ${RESET}"
    read -r choice
    if [[ -z "$choice" ]]; then echo "$default"; return; fi
    local idx=$((choice - 1))
    if [[ $idx -ge 0 && $idx -lt ${#options[@]} ]]; then
        echo "${options[$idx]}"
    else
        echo "$default"
    fi
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

check_node() {
    if ! command -v node &>/dev/null; then
        fail "Node.js not found. Install from https://nodejs.org (v18+)"
    fi
    local ver; ver=$(node --version | sed 's/v//')
    local major; major=$(echo "$ver" | cut -d. -f1)
    if [[ $major -lt 18 ]]; then
        fail "Node.js v$ver found, but v18+ is required."
    fi
    ok "Node.js v$ver"
}

check_npm() {
    if ! command -v npm &>/dev/null; then
        fail "npm not found. Install Node.js from https://nodejs.org"
    fi
    ok "npm $(npm --version)"
}

check_git() {
    if ! command -v git &>/dev/null; then
        fail "Git not found. Install from https://git-scm.com"
    fi
    ok "git $(git --version | awk '{print $3}')"
}

check_python() {
    if command -v python3 &>/dev/null; then
        ok "Python $(python3 --version | awk '{print $2}')"
        echo "python3"
    elif command -v python &>/dev/null; then
        ok "Python $(python --version 2>&1 | awk '{print $2}')"
        echo "python"
    else
        warn "Python not found — Python features will be skipped."
        echo ""
    fi
}

# ── Installers ────────────────────────────────────────────────────────────────

install_claude_code() {
    step 3 "Installing Claude Code..."
    if npm install -g @anthropic-ai/claude-code 2>&1; then
        ok "Claude Code installed"
    else
        fail "Claude Code install failed. Check npm permissions."
    fi
}

install_codex() {
    step 3 "Installing OpenAI Codex CLI..."
    if npm install -g @openai/codex 2>&1; then
        ok "OpenAI Codex installed"
    else
        warn "Codex install failed. Try: sudo npm install -g @openai/codex"
    fi
}

# ── Configuration ─────────────────────────────────────────────────────────────

setup_claude() {
    local api_key="$1" github_token="$2" repo_url="$3"
    local claude_dir="$HOME/.claude"
    mkdir -p "$claude_dir"

    # Save API key to shell profile
    local profile_file
    if [[ -f "$HOME/.zshrc" ]]; then profile_file="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then profile_file="$HOME/.bashrc"
    else profile_file="$HOME/.profile"; fi

    if ! grep -q "ANTHROPIC_API_KEY" "$profile_file" 2>/dev/null; then
        echo "" >> "$profile_file"
        echo "export ANTHROPIC_API_KEY=\"$api_key\"" >> "$profile_file"
        ok "ANTHROPIC_API_KEY added to $profile_file"
    else
        # Update existing
        sed -i'' -e "s|export ANTHROPIC_API_KEY=.*|export ANTHROPIC_API_KEY=\"$api_key\"|" "$profile_file"
        ok "ANTHROPIC_API_KEY updated in $profile_file"
    fi

    # Clone skills repo
    local skills_dir="$claude_dir/aikit-skills"
    local authed_url="${repo_url/https:\/\//https:\/\/oauth2:$github_token@}"

    if [[ -d "$skills_dir/.git" ]]; then
        info "Updating existing skills repo..."
        git -C "$skills_dir" pull origin main &>/dev/null
    else
        info "Cloning skills library..."
        git clone "$authed_url" "$skills_dir" &>/dev/null
    fi
    ok "Skills library ready"

    # Copy templates
    local tmpl="$skills_dir/skills/CLAUDE_TEMPLATE.md"
    [[ -f "$tmpl" && ! -f "$HOME/CLAUDE.md" ]] && cp "$tmpl" "$HOME/CLAUDE.md" && ok "CLAUDE.md created"

    local settings_tmpl="$skills_dir/skills/settings_template.json"
    [[ -f "$settings_tmpl" && ! -f "$claude_dir/settings.json" ]] \
        && cp "$settings_tmpl" "$claude_dir/settings.json" && ok "settings.json installed"
}

setup_openai() {
    local api_key="$1"
    local profile_file
    if [[ -f "$HOME/.zshrc" ]]; then profile_file="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then profile_file="$HOME/.bashrc"
    else profile_file="$HOME/.profile"; fi

    if ! grep -q "OPENAI_API_KEY" "$profile_file" 2>/dev/null; then
        echo "export OPENAI_API_KEY=\"$api_key\"" >> "$profile_file"
    else
        sed -i'' -e "s|export OPENAI_API_KEY=.*|export OPENAI_API_KEY=\"$api_key\"|" "$profile_file"
    fi
    ok "OPENAI_API_KEY saved"
}

# ── Monthly Updater ───────────────────────────────────────────────────────────

register_cron() {
    local skills_dir="$1"
    local update_script="$skills_dir/scripts/auto_update.sh"

    if [[ ! -f "$update_script" ]]; then
        warn "Update script not found — skipping cron registration"
        return
    fi
    chmod +x "$update_script"

    # Add monthly cron job if not already present
    local cron_entry="0 9 1 * * bash \"$update_script\" >> ~/.claude/update.log 2>&1"
    if crontab -l 2>/dev/null | grep -q "aikit"; then
        warn "Cron job already exists — skipped"
    else
        (crontab -l 2>/dev/null; echo "# AIKit monthly update"; echo "$cron_entry") | crontab -
        ok "Monthly update cron job registered (1st of each month at 9am)"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

banner

echo -e "  ${GRAY}Welcome. This wizard installs your AIKit Pro environment.${RESET}"
echo -e "  ${GRAY}Estimated time: 2–5 minutes.${RESET}"
echo ""
rule

# Step 1: Prerequisites
step 1 "Checking prerequisites..."
check_node; check_npm; check_git
PYTHON_CMD=$(check_python)
rule

# Step 2: Choose tools
step 2 "What would you like to install?"
TOOL_CHOICE=$(read_choice "Select AI tool(s)" \
    "Claude Code only" "OpenAI Codex only" "Both Claude Code and Codex")
rule

# Step 3: Install
[[ "$TOOL_CHOICE" == *"Claude Code"* ]] && install_claude_code
[[ "$TOOL_CHOICE" == *"Codex"* ]]       && install_codex
rule

# Step 4: API Keys
step 4 "API credentials"
info "Keys are added to your shell profile — never written to plain files."
echo ""
CLAUDE_KEY=""; OPENAI_KEY=""
[[ "$TOOL_CHOICE" == *"Claude Code"* ]] && CLAUDE_KEY=$(read_secret "Anthropic API key (console.anthropic.com): ")
[[ "$TOOL_CHOICE" == *"Codex"* ]]       && OPENAI_KEY=$(read_secret "OpenAI API key (platform.openai.com): ")
echo ""

# Step 5: GitHub
step 5 "AIKit skills library access"
info "GitHub Personal Access Token with 'repo' scope (github.com/settings/tokens/new)"
echo ""
GITHUB_TOKEN=$(read_secret "GitHub Personal Access Token: ")
REPO_URL="https://github.com/henkietenki/aikit-pro-skills.git"
rule

# Step 6: Configure
step 6 "Configuring your environment..."
[[ -n "$CLAUDE_KEY" ]]  && setup_claude "$CLAUDE_KEY" "$GITHUB_TOKEN" "$REPO_URL"
[[ -n "$OPENAI_KEY" ]]  && setup_openai "$OPENAI_KEY"
rule

# Step 7: Cron
step 7 "Scheduling monthly updates..."
SKILLS_DIR="$HOME/.claude/aikit-skills"
[[ -d "$SKILLS_DIR" ]] && register_cron "$SKILLS_DIR"
rule

# Done
echo ""
echo -e "  ${GREEN}╔══════════════════════════════════════╗${RESET}"
echo -e "  ${GREEN}║   Installation complete.             ║${RESET}"
echo -e "  ${GREEN}╚══════════════════════════════════════╝${RESET}"
echo ""
[[ "$TOOL_CHOICE" == *"Claude Code"* ]] && echo -e "  ${CYAN}Start Claude Code:${RESET}\n    source ~/.zshrc && claude\n"
[[ "$TOOL_CHOICE" == *"Codex"* ]]       && echo -e "  ${CYAN}Start Codex:${RESET}\n    source ~/.zshrc && codex\n"
echo -e "  ${GRAY}Skills auto-update on the 1st of each month.${RESET}"
echo -e "  ${GRAY}Docs: https://aikit.originforge.net/docs${RESET}"
echo ""
