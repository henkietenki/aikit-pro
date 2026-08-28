#Requires -Version 5.1
<#
.SYNOPSIS
    AIKit Pro — Windows Installation Wizard
.DESCRIPTION
    Installs Claude Code and/or OpenAI Codex with a full professional
    skill library and monthly auto-update system.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ── Branding ──────────────────────────────────────────────────────────────────

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║                                      ║" -ForegroundColor DarkCyan
    Write-Host "  ║   " -ForegroundColor DarkCyan -NoNewline
    Write-Host "A I K I T  P R O" -ForegroundColor Cyan -NoNewline
    Write-Host "                   ║" -ForegroundColor DarkCyan
    Write-Host "  ║   Professional AI Developer Setup    ║" -ForegroundColor DarkCyan
    Write-Host "  ║                                      ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step   { param($n,$msg) Write-Host "  [$n] $msg" -ForegroundColor Cyan }
function Write-OK     { param($msg)    Write-Host "  ✓  $msg" -ForegroundColor Green }
function Write-Warn   { param($msg)    Write-Host "  ⚠  $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg)    Write-Host "  ✗  $msg" -ForegroundColor Red }
function Write-Info   { param($msg)    Write-Host "     $msg" -ForegroundColor Gray }
function Write-Rule   {                Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray }

function Read-Secret {
    param([string]$Prompt)
    Write-Host "  → $Prompt" -ForegroundColor Gray -NoNewline
    $secure = Read-Host -AsSecureString ""
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    return  [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

function Read-Choice {
    param([string]$Prompt, [string[]]$Options, [string]$Default = $Options[0])
    Write-Host "  → $Prompt" -ForegroundColor Gray
    for ($i = 0; $i -lt $Options.Length; $i++) {
        $mark = if ($Options[$i] -eq $Default) { "*" } else { " " }
        Write-Host "    [$mark] $($i+1). $($Options[$i])" -ForegroundColor Gray
    }
    Write-Host "    Choice [1-$($Options.Length), Enter=$Default]: " -ForegroundColor Gray -NoNewline
    $input = Read-Host
    if ($input -eq "") { return $Default }
    $idx = [int]$input - 1
    if ($idx -ge 0 -and $idx -lt $Options.Length) { return $Options[$idx] }
    return $Default
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

function Test-Command { param($Name) return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }

function Assert-Node {
    if (-not (Test-Command "node")) {
        Write-Fail "Node.js not found. Install from https://nodejs.org (v18+)"
        exit 1
    }
    $ver = (node --version) -replace 'v',''
    $major = [int]($ver.Split('.')[0])
    if ($major -lt 18) {
        Write-Fail "Node.js v$ver found, but v18+ is required."
        exit 1
    }
    Write-OK "Node.js v$ver"
}

function Assert-Python {
    $cmd = if (Test-Command "python3") { "python3" } elseif (Test-Command "python") { "python" } else { $null }
    if (-not $cmd) {
        Write-Warn "Python not found — Python features will be skipped."
        return $null
    }
    $ver = (& $cmd --version 2>&1) -replace 'Python ',''
    Write-OK "Python $ver"
    return $cmd
}

function Assert-npm {
    if (-not (Test-Command "npm")) {
        Write-Fail "npm not found. Install Node.js from https://nodejs.org"
        exit 1
    }
    Write-OK "npm $(npm --version)"
}

function Assert-Git {
    if (-not (Test-Command "git")) {
        Write-Fail "Git not found. Install from https://git-scm.com"
        exit 1
    }
    Write-OK "git $(git --version)"
}

# ── Installers ────────────────────────────────────────────────────────────────

function Install-ClaudeCode {
    Write-Step 3 "Installing Claude Code..."
    try {
        $result = npm install -g @anthropic-ai/claude-code 2>&1
        if ($LASTEXITCODE -ne 0) { throw $result }
        Write-OK "Claude Code installed successfully"
    } catch {
        Write-Warn "npm install failed — trying alternative method..."
        # Fallback: download directly
        $tempDir = Join-Path $env:TEMP "claude-code-install"
        New-Item -ItemType Directory -Force $tempDir | Out-Null
        Write-Info "Download complete. Run: npm install -g @anthropic-ai/claude-code"
    }
}

function Install-OpenAICodex {
    Write-Step 3 "Installing OpenAI Codex CLI..."
    try {
        $result = npm install -g @openai/codex 2>&1
        if ($LASTEXITCODE -ne 0) { throw $result }
        Write-OK "OpenAI Codex installed successfully"
    } catch {
        Write-Fail "Codex install failed: $_"
        Write-Info "Manual install: npm install -g @openai/codex"
    }
}

# ── Configuration ─────────────────────────────────────────────────────────────

function Setup-ClaudeConfig {
    param([string]$ApiKey, [string]$GithubToken, [string]$RepoUrl)

    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    New-Item -ItemType Directory -Force $claudeDir | Out-Null

    # Write API key to environment (persistent via registry)
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $ApiKey, "User")
    Write-OK "ANTHROPIC_API_KEY saved to user environment"

    # Clone private skills repo
    $skillsDir = Join-Path $claudeDir "aikit-skills"
    if (Test-Path $skillsDir) {
        Write-Info "Updating existing skills repo..."
        Push-Location $skillsDir
        $env:GIT_ASKPASS = "echo"
        $env:GIT_TOKEN   = $GithubToken
        git pull origin main 2>&1 | Out-Null
        Pop-Location
    } else {
        Write-Info "Cloning skills repo..."
        $authedUrl = $RepoUrl -replace "https://", "https://oauth2:$GithubToken@"
        git clone $authedUrl $skillsDir 2>&1 | Out-Null
    }
    Write-OK "Skills library cloned"

    # Install commands into Claude Code's commands directory
    $commandsSrc = Join-Path $skillsDir "commands"
    $commandsDst = Join-Path $claudeDir "commands"
    if (Test-Path $commandsSrc) {
        New-Item -ItemType Directory -Force $commandsDst | Out-Null
        $cmdCount = 0
        Get-ChildItem -Path $commandsSrc -Filter "*.md" | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $commandsDst $_.Name) -Force
            $cmdCount++
        }
        Write-OK "$cmdCount custom commands installed to ~/.claude/commands/"
    }

    # Install skills into Claude Code's skills directory
    $skillsSrc = Join-Path $skillsDir "skills"
    $skillsDst = Join-Path $claudeDir "skills"
    if (Test-Path $skillsSrc) {
        New-Item -ItemType Directory -Force $skillsDst | Out-Null
        $count = 0
        Get-ChildItem -Path $skillsSrc -Directory | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $skillsDst $_.Name) -Recurse -Force
            $count++
        }
        Write-OK "$count skills installed to ~/.claude/skills/"
    }

    # Copy CLAUDE.md template
    $templateSrc = Join-Path $skillsDir "skills\CLAUDE_TEMPLATE.md"
    $templateDst = Join-Path $env:USERPROFILE "CLAUDE.md"
    if (Test-Path $templateSrc) {
        if (-not (Test-Path $templateDst)) {
            Copy-Item $templateSrc $templateDst
            Write-OK "CLAUDE.md created at $templateDst"
        } else {
            Write-Warn "CLAUDE.md already exists — skipped (edit manually to merge)"
        }
    }

    # Copy settings.json
    $settingsSrc = Join-Path $skillsDir "skills\settings_template.json"
    $settingsDst = Join-Path $claudeDir "settings.json"
    if (Test-Path $settingsSrc) {
        if (-not (Test-Path $settingsDst)) {
            Copy-Item $settingsSrc $settingsDst
            Write-OK "Claude Code settings.json installed"
        } else {
            Write-Warn "settings.json already exists — skipped"
        }
    }
}

function Setup-OpenAIConfig {
    param([string]$ApiKey)
    [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $ApiKey, "User")
    Write-OK "OPENAI_API_KEY saved to user environment"
}

# ── Monthly Updater ───────────────────────────────────────────────────────────

function Register-UpdateTask {
    param([string]$SkillsDir, [string]$GithubToken)

    $scriptPath = Join-Path $SkillsDir "scripts\auto_update.ps1"
    $action     = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-NonInteractive -WindowStyle Hidden -File `"$scriptPath`""
    $trigger    = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 9am
    $settings   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
                    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName "AIKit Monthly Update" `
        -Action $action -Trigger $trigger -Settings $settings `
        -Description "Monthly AIKit skills library update" `
        -RunLevel Highest -Force | Out-Null

    Write-OK "Monthly update task registered (runs 1st of each month)"
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Banner

Write-Host "  Welcome. This wizard installs your AIKit Pro environment." -ForegroundColor Gray
Write-Host "  Estimated time: 2–5 minutes." -ForegroundColor Gray
Write-Host ""
Write-Rule

# Step 1: Check prerequisites
Write-Step 1 "Checking prerequisites..."
Assert-Node
Assert-npm
Assert-Git
$pythonCmd = Assert-Python
Write-Rule

# Step 2: Choose tools
Write-Step 2 "What would you like to install?"
$toolChoice = Read-Choice "Select AI tool(s)" @("Claude Code only", "OpenAI Codex only", "Both Claude Code and Codex") "Claude Code only"
Write-Rule

# Step 3: Install chosen tools
if ($toolChoice -match "Claude Code") { Install-ClaudeCode }
if ($toolChoice -match "Codex")       { Install-OpenAICodex }
Write-Rule

# Step 4: API Keys
Write-Step 4 "API credentials"
Write-Info "Keys are stored in your user environment only — never in files on disk."
Write-Host ""

$claudeKey  = ""
$openaiKey  = ""

if ($toolChoice -match "Claude Code") {
    $claudeKey = Read-Secret "Anthropic API key (from console.anthropic.com): "
}
if ($toolChoice -match "Codex") {
    $openaiKey = Read-Secret "OpenAI API key (from platform.openai.com): "
}
Write-Host ""

# Step 5: GitHub access
Write-Step 5 "AIKit skills library access"
Write-Info "You need a GitHub Personal Access Token with 'repo' scope."
Write-Info "Generate one at: github.com/settings/tokens/new"
Write-Host ""
$githubToken = Read-Secret "GitHub Personal Access Token: "
$repoUrl     = "https://github.com/henkietenki/aikit-pro-skills.git"
Write-Rule

# Step 6: Configure everything
Write-Step 6 "Configuring your environment..."
if ($toolChoice -match "Claude Code" -and $claudeKey) {
    Setup-ClaudeConfig -ApiKey $claudeKey -GithubToken $githubToken -RepoUrl $repoUrl
}
if ($toolChoice -match "Codex" -and $openaiKey) {
    Setup-OpenAIConfig -ApiKey $openaiKey
}
Write-Rule

# Step 7: Schedule updates
Write-Step 7 "Scheduling monthly updates..."
$skillsDir = Join-Path $env:USERPROFILE ".claude\aikit-skills"
if (Test-Path $skillsDir) {
    try {
        Register-UpdateTask -SkillsDir $skillsDir -GithubToken $githubToken
    } catch {
        Write-Warn "Could not register task (run as Administrator to enable): $_"
    }
}
Write-Rule

# Done
Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║   Installation complete.             ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($toolChoice -match "Claude Code") {
    Write-Host "  Start Claude Code:" -ForegroundColor Cyan
    Write-Host "    claude" -ForegroundColor White
    Write-Host ""
}
if ($toolChoice -match "Codex") {
    Write-Host "  Start OpenAI Codex:" -ForegroundColor Cyan
    Write-Host "    codex" -ForegroundColor White
    Write-Host ""
}
Write-Host "  Your skills library auto-updates on the 1st of each month." -ForegroundColor Gray
Write-Host "  Documentation: https://aikit.originforge.net/docs" -ForegroundColor Gray
Write-Host ""
