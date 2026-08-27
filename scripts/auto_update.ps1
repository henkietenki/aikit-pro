#Requires -Version 5.1
<#
.SYNOPSIS
    AIKit Pro — Monthly Skills Auto-Update (Windows)
.DESCRIPTION
    Pulls the latest skills library from GitHub and merges any CLAUDE_TEMPLATE.md
    changes while preserving the user's Local Overrides section.
    Registered as a scheduled task on the 1st of each month.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$SkillsDir   = Join-Path $env:USERPROFILE ".claude\aikit-skills"
$ClaudeMd    = Join-Path $env:USERPROFILE "CLAUDE.md"
$TemplateSrc = Join-Path $SkillsDir "skills\CLAUDE_TEMPLATE.md"
$LogFile     = Join-Path $env:USERPROFILE ".claude\update.log"

function Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts  $Level  $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# ── Pull latest skills ────────────────────────────────────────────────────────

Log "AIKit monthly update starting"

if (-not (Test-Path $SkillsDir)) {
    Log "Skills directory not found: $SkillsDir" "ERROR"
    exit 1
}

Push-Location $SkillsDir
try {
    $result = git pull origin main 2>&1
    Log "git pull: $($result | Select-Object -Last 1)"
} catch {
    Log "git pull failed: $_" "ERROR"
    exit 1
} finally {
    Pop-Location
}

# ── Merge CLAUDE.md — preserve Local Overrides ───────────────────────────────

if (-not (Test-Path $TemplateSrc)) {
    Log "Template not found at $TemplateSrc — skipping CLAUDE.md merge" "WARN"
    Log "AIKit monthly update complete (no CLAUDE.md changes)"
    exit 0
}

$newTemplate = Get-Content -Raw $TemplateSrc

if (-not (Test-Path $ClaudeMd)) {
    # First time — just copy the template
    Copy-Item $TemplateSrc $ClaudeMd
    Log "CLAUDE.md created from template"
} else {
    # Extract the existing Local Overrides section (everything after the heading)
    $existingContent  = Get-Content -Raw $ClaudeMd
    $overrideHeading  = "## Local Overrides"
    $overrideIdx      = $existingContent.IndexOf($overrideHeading)

    if ($overrideIdx -ge 0) {
        $userOverrides = $existingContent.Substring($overrideIdx + $overrideHeading.Length).TrimStart("`r`n")
    } else {
        $userOverrides = ""
    }

    # Build merged file: new template up to (and including) the heading, then user overrides
    $templateHeadingIdx = $newTemplate.IndexOf($overrideHeading)
    if ($templateHeadingIdx -ge 0) {
        $base    = $newTemplate.Substring(0, $templateHeadingIdx + $overrideHeading.Length)
        $merged  = $base + "`n`n" + $userOverrides
        $merged  = $merged.TrimEnd() + "`n"

        # Only write if content changed (ignoring the overrides section)
        $existingBase = if ($overrideIdx -ge 0) {
            $existingContent.Substring(0, $overrideIdx + $overrideHeading.Length)
        } else {
            $existingContent
        }

        if ($base.Trim() -ne $existingBase.Trim()) {
            Set-Content -Path $ClaudeMd -Value $merged -NoNewline -Encoding UTF8
            Log "CLAUDE.md updated (Local Overrides preserved)"
        } else {
            Log "CLAUDE.md already up to date"
        }
    } else {
        Log "Template has no Local Overrides heading — skipping merge to be safe" "WARN"
    }
}

Log "AIKit monthly update complete"
