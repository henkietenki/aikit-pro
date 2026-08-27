"""
Transactional email via SendGrid.
Replace SENDGRID_API_KEY with your key; all templates are inline here
so there's no external template dependency.
"""

import logging
import httpx

log = logging.getLogger(__name__)

SENDGRID_URL = "https://api.sendgrid.com/v3/mail/send"

INSTALL_WIN  = "irm https://aikit.originforge.net/install.ps1 | iex"
INSTALL_MAC  = "curl -fsSL https://aikit.originforge.net/install.sh | bash"
DOCS_URL     = "https://aikit.originforge.net/docs"
PORTAL_URL   = "https://aikit.originforge.net/account"


class EmailSender:
    def __init__(self, api_key: str, from_email: str, github_org: str = ""):
        self._api_key    = api_key
        self._from       = from_email
        self._github_org = github_org

    async def send_welcome(self, to_email: str, name: str, github_username: str) -> None:
        first_name = name.split()[0] if name else "there"
        subject    = "Your AIKit Pro access is ready"
        invite_url = f"https://github.com/henkietenki/aikit-pro-skills/invitations" if self._github_org else "https://github.com/notifications"
        body       = f"""\
Hi {first_name},

Your AIKit Pro subscription is confirmed and your GitHub account
(@{github_username}) has been invited to the private repository.

──────────────────────────────────────
Accept your GitHub invitation
──────────────────────────────────────

Check your GitHub notifications or visit:
{invite_url}

Once accepted, run the installer:

  Windows (PowerShell):
    {INSTALL_WIN}

  macOS / Linux:
    {INSTALL_MAC}

──────────────────────────────────────
What's included
──────────────────────────────────────

• Claude Code pre-configured with 30+ professional skills
• Optional OpenAI Codex setup
• Monthly skills updates (auto-applied)
• Full documentation at {DOCS_URL}

──────────────────────────────────────

Manage your subscription: {PORTAL_URL}

If you didn't sign up for this, reply to this email and we'll sort it out.

— The AIKit Team
"""
        await self._send(to_email, subject, body)
        log.info(f"Welcome email sent to {to_email}")

    async def send_access_restored(self, to_email: str, github_username: str) -> None:
        subject = "AIKit Pro — access restored"
        body    = f"""\
Your AIKit Pro payment came through and your access (@{github_username})
has been restored.

Manage your subscription: {PORTAL_URL}

— The AIKit Team
"""
        await self._send(to_email, subject, body)

    async def send_payment_failed(self, to_email: str, github_username: str) -> None:
        subject = "AIKit Pro — access suspended"
        body    = f"""\
We weren't able to collect your AIKit Pro payment after several attempts,
so your access (@{github_username}) has been suspended.

To restore access, update your payment details and resubscribe:
{PORTAL_URL}

Your settings and configuration are preserved — access is restored
immediately after a successful payment.

— The AIKit Team
"""
        await self._send(to_email, subject, body)
        log.info(f"Payment failed email sent to {to_email}")

    async def send_access_revoked(self, to_email: str, github_username: str) -> None:
        subject = "AIKit Pro — subscription ended"
        body    = f"""\
Your AIKit Pro subscription has ended and access for @{github_username}
has been removed.

You can resubscribe at any time: https://aikit.originforge.net/#pricing

Your local configuration and skills remain on your machine.

— The AIKit Team
"""
        await self._send(to_email, subject, body)
        log.info(f"Revocation email sent to {to_email}")

    # ── Transport ──────────────────────────────────────────────────────────────

    async def _send(self, to: str, subject: str, text_body: str) -> None:
        payload = {
            "personalizations": [{"to": [{"email": to}]}],
            "from":             {"email": self._from, "name": "AIKit Pro"},
            "subject":          subject,
            "content":          [{"type": "text/plain", "value": text_body}],
        }
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                SENDGRID_URL,
                json=payload,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type":  "application/json",
                },
            )
        if resp.status_code not in (200, 202):
            log.error(f"SendGrid error: {resp.status_code} {resp.text}")
