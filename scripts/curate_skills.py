"""
Monthly skills curator.
Reads the current skills manifest, checks for upstream updates,
and writes fresh skill files to the skills/ directory.

Add new skill sources to SKILL_SOURCES below.
Each source is a dict with a 'type' and source-specific config.
"""

import asyncio
import hashlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import httpx

SKILLS_DIR = Path(__file__).parent.parent / "skills"
DRY_RUN    = os.environ.get("DRY_RUN", "false").lower() == "true"


# ── Skill Sources ─────────────────────────────────────────────────────────────
# Add new sources here. 'type' determines the fetch strategy.

SKILL_SOURCES = [
    {
        "type":     "github_raw",
        "name":     "claude-code-guide",
        "filename": "claude_code_guide.md",
        "url":      "https://raw.githubusercontent.com/anthropics/claude-code/main/README.md",
        "dest":     "claude/",
    },
    # Add more sources:
    # {
    #     "type":     "github_release",
    #     "name":     "custom-skill",
    #     "repo":     "owner/repo",
    #     "asset":    "skills.tar.gz",
    #     "dest":     "claude/",
    # },
]


# ── Fetchers ──────────────────────────────────────────────────────────────────

async def fetch_github_raw(client: httpx.AsyncClient, source: dict) -> str | None:
    resp = await client.get(source["url"], follow_redirects=True)
    if resp.status_code == 200:
        return resp.text
    print(f"  ✗ Failed to fetch {source['name']}: {resp.status_code}")
    return None


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
    print(f"Done. {updated_count} skill(s) updated.")

    # Write update manifest
    manifest = {
        "last_updated": datetime.utcnow().isoformat() + "Z",
        "updated_count": updated_count,
        "dry_run": DRY_RUN,
    }
    if not DRY_RUN:
        (SKILLS_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
