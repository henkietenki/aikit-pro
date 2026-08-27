"""
AIKit Pro — Access Control Backend
FastAPI server that handles Stripe webhooks, manages GitHub org membership,
and serves signup/status endpoints.
"""

import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr
import stripe

from stripe_handler import handle_stripe_event
from github_manager import GitHubManager
from email_sender import EmailSender

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

STRIPE_SECRET_KEY     = os.environ["STRIPE_SECRET_KEY"]
STRIPE_WEBHOOK_SECRET = os.environ["STRIPE_WEBHOOK_SECRET"]
STRIPE_PRICE_MONTHLY  = os.environ["STRIPE_PRICE_MONTHLY"]  # price_xxx
STRIPE_PRICE_ANNUAL   = os.environ["STRIPE_PRICE_ANNUAL"]   # price_xxx

stripe.api_key = STRIPE_SECRET_KEY

github  = GitHubManager(
    token=os.environ["GITHUB_TOKEN"],
    owner=os.environ["GITHUB_OWNER"],
    repo=os.environ["GITHUB_REPO"],
)
emailer = EmailSender(
    api_key=os.environ["SENDGRID_API_KEY"],
    from_email=os.environ["FROM_EMAIL"],
    github_org=os.environ["GITHUB_OWNER"],
)

# ── App ───────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("AIKit backend starting up")
    yield
    log.info("AIKit backend shutting down")

app = FastAPI(title="AIKit Pro API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[os.environ.get("FRONTEND_URL", "https://aikit.originforge.net")],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# ── Models ────────────────────────────────────────────────────────────────────

class SignupRequest(BaseModel):
    name:            str
    email:           EmailStr
    github_username: str
    plan:            str  # "monthly" | "annual"

class SignupResponse(BaseModel):
    checkout_url: str

# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "service": "aikit-pro"}


@app.post("/signup", response_model=SignupResponse)
async def signup(body: SignupRequest):
    """
    Creates a Stripe Checkout session for a new subscriber.
    The GitHub username is stored in Stripe metadata so we can grant
    access automatically when payment succeeds.
    """
    price_id = STRIPE_PRICE_MONTHLY if body.plan == "monthly" else STRIPE_PRICE_ANNUAL

    try:
        # Check if customer already exists
        existing = stripe.Customer.search(query=f"email:'{body.email}'")
        if existing.data:
            customer_id = existing.data[0].id
        else:
            customer = stripe.Customer.create(
                name=body.name,
                email=body.email,
                metadata={"github_username": body.github_username},
            )
            customer_id = customer.id

        session = stripe.checkout.Session.create(
            customer=customer_id,
            mode="subscription",
            line_items=[{"price": price_id, "quantity": 1}],
            subscription_data={
                "metadata": {
                    "github_username": body.github_username,
                    "plan":            body.plan,
                }
            },
            success_url=f"{os.environ.get('FRONTEND_URL', 'https://aikit.originforge.net')}/success?session_id={{CHECKOUT_SESSION_ID}}",
            cancel_url=f"{os.environ.get('FRONTEND_URL', 'https://aikit.originforge.net')}/#pricing",
        )
    except stripe.error.StripeError as e:
        log.error(f"Stripe error during signup: {e}")
        raise HTTPException(status_code=502, detail="Payment provider error")

    log.info(f"Checkout session created for {body.email} ({body.plan})")
    return {"checkout_url": session.url}


@app.post("/webhook/stripe")
async def stripe_webhook(request: Request, stripe_signature: str = Header(None)):
    """
    Stripe sends events here:
      checkout.session.completed   → initial signup, grant GitHub access
      invoice.payment_succeeded    → renewal, reinstate if suspended
      customer.subscription.deleted → cancel, revoke GitHub access
      invoice.payment_failed       → after final retry, revoke access
    """
    payload = await request.body()

    try:
        event = stripe.Webhook.construct_event(payload, stripe_signature, STRIPE_WEBHOOK_SECRET)
    except stripe.error.SignatureVerificationError:
        log.warning("Invalid Stripe webhook signature")
        raise HTTPException(status_code=400, detail="Invalid signature")
    except Exception as e:
        log.error(f"Webhook parse error: {e}")
        raise HTTPException(status_code=400, detail="Malformed event")

    log.info(f"Stripe event received: {event['type']}")

    try:
        await handle_stripe_event(event, github, emailer)
    except Exception as e:
        log.error(f"Event handler error: {e}")
        # Return 200 anyway to prevent Stripe retrying — log and monitor instead
        return JSONResponse({"status": "logged", "error": str(e)})

    return JSONResponse({"status": "ok"})


@app.get("/member/{github_username}")
async def check_member(github_username: str):
    """Returns whether a GitHub user currently has org access."""
    is_member = await github.is_member(github_username)
    return {"github_username": github_username, "active": is_member}
