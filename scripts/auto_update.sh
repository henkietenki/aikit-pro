#!/usr/bin/env bash
# AIKit Pro — Monthly Skills Auto-Update (macOS/Linux)
# Pulls the latest skills library and merges CLAUDE_TEMPLATE.md
# while preserving the user's Local Overrides section.
# Runs via cron on the 1st of each month.

set -euo pipefail

SKILLS_DIR="$HOME/.claude/aikit-skills"
CLAUDE_MD="$HOME/CLAUDE.md"
TEMPLATE_SRC="$SKILLS_DIR/skills/CLAUDE_TEMPLATE.md"
LOG_FILE="$HOME/.claude/update.log"

log() {
    local level="${2:-INFO}"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$ts  $level  $1" | tee -a "$LOG_FILE"
}

# ── Pull latest skills ────────────────────────────────────────────────────────

log "AIKit monthly update starting"

if [[ ! -d "$SKILLS_DIR" ]]; then
    log "Skills directory not found: $SKILLS_DIR" "ERROR"
    exit 1
fi

cd "$SKILLS_DIR"
pull_result=$(git pull origin main 2>&1 | tail -1)
log "git pull: $pull_result"

# ── Merge CLAUDE.md — preserve Local Overrides ───────────────────────────────

if [[ ! -f "$TEMPLATE_SRC" ]]; then
    log "Template not found at $TEMPLATE_SRC — skipping CLAUDE.md merge" "WARN"
    log "AIKit monthly update complete (no CLAUDE.md changes)"
    exit 0
fi

if [[ ! -f "$CLAUDE_MD" ]]; then
    # First time — just copy
    cp "$TEMPLATE_SRC" "$CLAUDE_MD"
    log "CLAUDE.md created from template"
else
    OVERRIDE_HEADING="## Local Overrides"
    NEW_TEMPLATE=$(cat "$TEMPLATE_SRC")

    if grep -qF "$OVERRIDE_HEADING" "$CLAUDE_MD"; then
        # Extract user's overrides (everything after the heading)
        USER_OVERRIDES=$(awk "/$OVERRIDE_HEADING/{found=1; next} found{print}" "$CLAUDE_MD")
    else
        USER_OVERRIDES=""
    fi

    if grep -qF "$OVERRIDE_HEADING" "$TEMPLATE_SRC"; then
        # Get the template up to and including the heading
        BASE=$(awk "/$OVERRIDE_HEADING/{print; exit} {print}" "$TEMPLATE_SRC")

        # Check if the template base actually changed
        EXISTING_BASE=$(awk "/$OVERRIDE_HEADING/{print; exit} {print}" "$CLAUDE_MD")

        if [[ "$BASE" != "$EXISTING_BASE" ]]; then
            # Write merged file
            {
                echo "$BASE"
                echo ""
                echo "$USER_OVERRIDES"
            } | sed -e 's/[[:space:]]*$//' > "$CLAUDE_MD"
            echo "" >> "$CLAUDE_MD"  # ensure trailing newline
            log "CLAUDE.md updated (Local Overrides preserved)"
        else
            log "CLAUDE.md already up to date"
        fi
    else
        log "Template has no Local Overrides heading — skipping merge to be safe" "WARN"
    fi
fi

# ── Copy commands to Claude Code commands directory ──────────────────────────

COMMANDS_SRC="$SKILLS_DIR/commands"
COMMANDS_DST="$HOME/.claude/commands"

if [[ -d "$COMMANDS_SRC" ]]; then
    mkdir -p "$COMMANDS_DST"
    cmd_count=0
    for f in "$COMMANDS_SRC"/*.md; do
        [[ -f "$f" ]] || continue
        cp "$f" "$COMMANDS_DST/$(basename "$f")"
        cmd_count=$((cmd_count + 1))
    done
    log "Installed $cmd_count commands to $COMMANDS_DST"
fi

# ── Copy skills to Claude Code skills directory ───────────────────────────────

SKILLS_SRC="$SKILLS_DIR/skills"
SKILLS_DST="$HOME/.claude/skills"

if [[ -d "$SKILLS_SRC" ]]; then
    mkdir -p "$SKILLS_DST"
    copied=0
    for skill_dir in "$SKILLS_SRC"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name=$(basename "$skill_dir")
        cp -r "$skill_dir" "$SKILLS_DST/$skill_name"
        copied=$((copied + 1))
    done
    log "Installed $copied skills to $SKILLS_DST"
else
    log "Skills source not found: $SKILLS_SRC" "WARN"
fi

log "AIKit monthly update complete"
