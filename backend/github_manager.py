"""
GitHub repository collaborator management via the REST API.
Uses the Collaborators API (personal account) rather than the Org Membership API.
"""

import logging
import httpx

log = logging.getLogger(__name__)

GITHUB_API = "https://api.github.com"


class GitHubManager:
    def __init__(self, token: str, owner: str, repo: str):
        self.owner = owner
        self.repo  = repo
        self._base = f"{GITHUB_API}/repos/{owner}/{repo}/collaborators"
        self._headers = {
            "Authorization":        f"Bearer {token}",
            "Accept":               "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    # ── Public Methods ─────────────────────────────────────────────────────────

    async def invite_member(self, github_username: str) -> bool:
        """
        Adds a user as a collaborator on the private skills repo (push permission).
        They receive an email invitation and must accept before cloning.
        Returns True on success.
        """
        async with httpx.AsyncClient(headers=self._headers, timeout=15) as client:
            if await self._is_collaborator(client, github_username):
                log.info(f"@{github_username} is already a collaborator")
                return True

            resp = await client.put(
                f"{self._base}/{github_username}",
                json={"permission": "pull"},
            )
            if resp.status_code in (201, 204):
                log.info(f"Collaborator invite sent to @{github_username}")
                return True
            else:
                log.error(f"Invite failed for @{github_username}: {resp.status_code} {resp.text}")
                return False

    async def remove_member(self, github_username: str) -> bool:
        """Removes a user as a collaborator. Returns True on success."""
        async with httpx.AsyncClient(headers=self._headers, timeout=15) as client:
            resp = await client.delete(f"{self._base}/{github_username}")
            if resp.status_code == 204:
                log.info(f"@{github_username} removed as collaborator")
                return True
            elif resp.status_code == 404:
                log.warning(f"@{github_username} was not a collaborator — nothing to remove")
                return True
            else:
                log.error(f"Remove failed for @{github_username}: {resp.status_code} {resp.text}")
                return False

    async def is_member(self, github_username: str) -> bool:
        """Returns True if the user is an active collaborator."""
        async with httpx.AsyncClient(headers=self._headers, timeout=10) as client:
            return await self._is_collaborator(client, github_username)

    async def list_members(self) -> list[str]:
        """Returns a list of all current collaborator logins."""
        members = []
        async with httpx.AsyncClient(headers=self._headers, timeout=30) as client:
            page = 1
            while True:
                resp = await client.get(
                    self._base,
                    params={"per_page": 100, "page": page, "affiliation": "direct"},
                )
                if resp.status_code != 200:
                    break
                data = resp.json()
                if not data:
                    break
                members.extend(m["login"] for m in data)
                page += 1
        return members

    # ── Private Helpers ────────────────────────────────────────────────────────

    async def _is_collaborator(self, client: httpx.AsyncClient, username: str) -> bool:
        resp = await client.get(f"{self._base}/{username}")
        return resp.status_code == 204
