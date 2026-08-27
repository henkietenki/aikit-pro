"""
Stripe event routing.
Each handler receives the full Stripe event object plus the GitHub manager
and email sender — no global state needed.
"""

import logging
from typing import Any

log = logging.getLogger(__name__)


async def handle_stripe_event(event: dict, github, emailer) -> None:
    event_type = event["type"]
    data       = event["data"]["object"]

    handlers = {
        "checkout.session.completed":    _on_checkout_complete,
        "invoice.payment_succeeded":     _on_payment_succeeded,
        "invoice.payment_failed":        _on_payment_failed,
        "customer.subscription.deleted": _on_subscription_cancelled,
    }

    handler = handlers.get(event_type)
    if handler:
        await handler(data, github, emailer)
    else:
        log.debug(f"Unhandled event type: {event_type}")


# ── Handlers ──────────────────────────────────────────────────────────────────

async def _on_checkout_complete(session: dict, github, emailer) -> None:
    """First-time purchase: invite user to GitHub org and send welcome email."""
    github_username = _get_github_username(session)
    customer_email  = session.get("customer_details", {}).get("email", "")
    customer_name   = session.get("customer_details", {}).get("name", "")

    if not github_username:
        log.warning(f"checkout.session.completed — no github_username in metadata for {customer_email}")
        return

    log.info(f"New subscriber: {customer_email} → @{github_username}")

    success = await github.invite_member(github_username)
    if success:
        await emailer.send_welcome(
            to_email=customer_email,
            name=customer_name,
            github_username=github_username,
        )
        log.info(f"GitHub invite sent to @{github_username}")
    else:
        log.error(f"Failed to invite @{github_username} — check GitHub token/org config")


async def _on_payment_succeeded(invoice: dict, github, emailer) -> None:
    """Recurring renewal: ensure the member still has access (reinstate if suspended)."""
    subscription_id = invoice.get("subscription")
    if not subscription_id:
        return

    import stripe
    sub = stripe.Subscription.retrieve(subscription_id)
    github_username = sub.get("metadata", {}).get("github_username")
    customer_email  = invoice.get("customer_email", "")

    if not github_username:
        return

    is_member = await github.is_member(github_username)
    if not is_member:
        log.info(f"Reinstating @{github_username} after successful renewal")
        await github.invite_member(github_username)
        await emailer.send_access_restored(customer_email, github_username)


async def _on_payment_failed(invoice: dict, github, emailer) -> None:
    """
    Payment failed. Stripe retries automatically (up to 4 times over ~4 weeks).
    We only revoke access when 'next_payment_attempt' is None — meaning all
    retries are exhausted and the subscription is about to be cancelled.
    """
    if invoice.get("next_payment_attempt") is not None:
        # Still retrying — don't revoke yet
        log.info(f"Payment failed but retries remain — no action taken")
        return

    subscription_id = invoice.get("subscription")
    if not subscription_id:
        return

    import stripe
    sub = stripe.Subscription.retrieve(subscription_id)
    github_username = sub.get("metadata", {}).get("github_username")
    customer_email  = invoice.get("customer_email", "")

    if not github_username:
        return

    log.info(f"All payment retries exhausted for @{github_username} — revoking access")
    await github.remove_member(github_username)
    await emailer.send_payment_failed(customer_email, github_username)


async def _on_subscription_cancelled(subscription: dict, github, emailer) -> None:
    """Subscription cancelled: remove from GitHub org immediately."""
    github_username = subscription.get("metadata", {}).get("github_username")
    customer_email  = subscription.get("customer", "")

    if not github_username:
        return

    log.info(f"Subscription cancelled — removing @{github_username}")
    await github.remove_member(github_username)
    await emailer.send_access_revoked(customer_email, github_username)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_github_username(obj: dict) -> str:
    """Safely extract github_username from any Stripe object's metadata."""
    meta = obj.get("metadata") or {}
    if meta.get("github_username"):
        return meta["github_username"]

    # Also check nested subscription metadata
    sub_data = obj.get("subscription_data") or {}
    sub_meta = sub_data.get("metadata") or {}
    return sub_meta.get("github_username", "")
