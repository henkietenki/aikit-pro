"""
Monthly skills curator.
Reads the current skills manifest, checks for upstream updates,
and writes fresh skill files to the skills/ directory.

Add new skill sources to SKILL_SOURCES below.
Each source is a dict with a 'type' and source-specific config.
"""

import asyncio
import hashlib
import io
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

import httpx

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

SKILLS_DIR = Path(__file__).parent.parent / "skills"
DRY_RUN    = os.environ.get("DRY_RUN", "false").lower() == "true"


# ── Skill Sources ─────────────────────────────────────────────────────────────
# Each source fetches content from an upstream URL and stores it in skills/.
# 'type' determines the fetch strategy.
# Static skills (agent_researcher.md etc.) are NOT listed here — they ship
# directly in skills/claude/ and are never overwritten by the curator.

SKILL_SOURCES = [
    # Claude Code official README
    {
        "type":     "github_raw",
        "name":     "claude-code-readme",
        "filename": "claude_code_readme.md",
        "url":      "https://raw.githubusercontent.com/anthropics/claude-code/main/README.md",
        "dest":     "reference/",
    },
    # Claude Code CHANGELOG — pick up new model IDs, flag names, command changes
    {
        "type":     "github_raw",
        "name":     "claude-code-changelog",
        "filename": "claude_code_changelog.md",
        "url":      "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md",
        "dest":     "reference/",
    },
    # MCP servers list from the official Model Context Protocol repo
    {
        "type":     "github_raw",
        "name":     "mcp-servers-list",
        "filename": "mcp_servers.md",
        "url":      "https://raw.githubusercontent.com/modelcontextprotocol/servers/main/README.md",
        "dest":     "reference/",
    },
    # Anthropic cookbook — recipes and patterns for building with Claude
    {
        "type":     "github_raw",
        "name":     "anthropic-cookbook",
        "filename": "anthropic_cookbook.md",
        "url":      "https://raw.githubusercontent.com/anthropics/anthropic-cookbook/main/README.md",
        "dest":     "reference/",
    },
]


# ── Fetchers ──────────────────────────────────────────────────────────────────

async def fetch_github_raw(client: httpx.AsyncClient, source: dict) -> str | None:
    resp = await client.get(source["url"], follow_redirects=True)
    if resp.status_code == 200:
        return resp.text
    print(f"  ✗ Failed to fetch {source['name']}: {resp.status_code}")
    return None


async def fetch_github_releases(client: httpx.AsyncClient, source: dict) -> str | None:
    """Fetch the latest N releases from GitHub API and format as markdown."""
    repo = source["repo"]
    n    = source.get("count", 5)
    url  = f"https://api.github.com/repos/{repo}/releases?per_page={n}"
    headers = {"Accept": "application/vnd.github+json"}
    token = os.environ.get("ANTHROPIC_DOCS_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    resp = await client.get(url, headers=headers, follow_redirects=True)
    if resp.status_code != 200:
        print(f"  ✗ Failed to fetch releases for {repo}: {resp.status_code}")
        return None
    releases = resp.json()
    lines = [f"# {source['name']} — Recent Releases\n"]
    for r in releases:
        tag     = r.get("tag_name", "")
        name    = r.get("name") or tag
        date    = (r.get("published_at") or "")[:10]
        body    = (r.get("body") or "").strip()
        lines.append(f"## {name} ({date})\n")
        if body:
            lines.append(body + "\n")
    return "\n".join(lines)


# ── Utilities ─────────────────────────────────────────────────────────────────

def file_hash(path: Path) -> str:
    if not path.exists():
        return ""
    return hashlib.md5(path.read_bytes()).hexdigest()


def write_skill(path: Path, content: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    new_hash = hashlib.md5(content.encode()).hexdigest()
    old_hash = file_hash(path)

    if new_hash == old_hash:
        return False  # no change

    if not DRY_RUN:
        path.write_text(content, encoding="utf-8")
    return True


def list_static_skills() -> list[dict]:
    """Return metadata for all hand-authored skills in skills/claude/."""
    static_dir = SKILLS_DIR / "claude"
    if not static_dir.exists():
        return []
    skills = []
    for f in sorted(static_dir.glob("*.md")):
        skills.append({"name": f.stem, "path": str(f.relative_to(SKILLS_DIR))})
    return skills


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    updated_count = 0
    print(f"Skills curator — {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"Mode: {'DRY RUN' if DRY_RUN else 'LIVE'}")
    print(f"Sources: {len(SKILL_SOURCES)}")
    print("─" * 40)

    async with httpx.AsyncClient(timeout=30) as client:
        for source in SKILL_SOURCES:
            print(f"  {source['name']}...", end=" ")

            content = None
            if source["type"] == "github_raw":
                content = await fetch_github_raw(client, source)
            elif source["type"] == "github_releases":
                content = await fetch_github_releases(client, source)

            if content is None:
                continue

            dest_path = SKILLS_DIR / source.get("dest", "") / source["filename"]
            changed   = write_skill(dest_path, content)

            if changed:
                print("updated")
                updated_count += 1
            else:
                print("no change")

    print("─" * 40)

    # Report static skills that ship with AIKit
    static = list_static_skills()
    if static:
        print(f"Static skills ({len(static)}):")
        for s in static:
            print(f"  ✓ {s['name']}  ({s['path']})")
        print("─" * 40)

    print(f"Done. {updated_count} reference skill(s) updated.")

    # Write update manifest
    manifest = {
        "last_updated":   datetime.utcnow().isoformat() + "Z",
        "updated_count":  updated_count,
        "dry_run":        DRY_RUN,
        "static_skills":  static,
        "sources":        [s["name"] for s in SKILL_SOURCES],
    }
    if not DRY_RUN:
        (SKILLS_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
