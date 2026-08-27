"""
Monthly access audit.
Compares GitHub repo collaborators against Stripe active subscriptions.
Collaborators without an active subscription are removed (or listed if DRY_RUN=true).
"""

import asyncio
import os
import httpx
import stripe

GITHUB_API = "https://api.github.com"
OWNER      = os.environ["GITHUB_OWNER"]
REPO       = os.environ["GITHUB_REPO"]
GH_TOKEN   = os.environ["GITHUB_TOKEN"]
DRY_RUN    = os.environ.get("DRY_RUN", "false").lower() == "true"

stripe.api_key = os.environ["STRIPE_SECRET"]

GH_HEADERS = {
    "Authorization":        f"Bearer {GH_TOKEN}",
    "Accept":               "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}

COLLAB_URL = f"{GITHUB_API}/repos/{OWNER}/{REPO}/collaborators"


async def get_collaborators(client: httpx.AsyncClient) -> list[str]:
    members, page = [], 1
    while True:
        resp = await client.get(
            COLLAB_URL,
            params={"per_page": 100, "page": page, "affiliation": "direct"},
        )
        data = resp.json()
        if not data:
            break
        members.extend(m["login"].lower() for m in data)
        page += 1
    return members


def get_active_subscribers() -> set[str]:
    """Returns a set of GitHub usernames with active Stripe subscriptions."""
    active = set()
    subs   = stripe.Subscription.list(status="active", limit=100, expand=["data.customer"])
    for sub in subs.auto_paging_iter():
        username = sub.get("metadata", {}).get("github_username")
        if username:
            active.add(username.lower())
    return active


async def remove_collaborator(client: httpx.AsyncClient, username: str) -> None:
    resp = await client.delete(f"{COLLAB_URL}/{username}")
    if resp.status_code == 204:
        print(f"  ✓ Removed: @{username}")
    else:
        print(f"  ✗ Failed to remove @{username}: {resp.status_code}")


async def main():
    print(f"\nAIKit Access Audit — {'DRY RUN' if DRY_RUN else 'LIVE'}")
    print(f"Repo: {OWNER}/{REPO}")
    print("─" * 40)

    async with httpx.AsyncClient(headers=GH_HEADERS, timeout=30) as client:
        collaborators = await get_collaborators(client)
        subscribers   = get_active_subscribers()

        stale = [m for m in collaborators if m not in subscribers]

        print(f"Total collaborators:  {len(collaborators)}")
        print(f"Active subscribers:   {len(subscribers)}")
        print(f"Stale (to remove):    {len(stale)}")
        print()

        if not stale:
            print("All collaborators have active subscriptions. Nothing to do.")
            return

        print("Stale collaborators:")
        for username in stale:
            print(f"  @{username}")

        if DRY_RUN:
            print("\nDry run — no collaborators removed.")
        else:
            print("\nRemoving stale collaborators...")
            for username in stale:
                await remove_collaborator(client, username)

    print("\nAudit complete.")


if __name__ == "__main__":
    asyncio.run(main())
