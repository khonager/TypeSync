# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from firebase_functions.params import SecretParam
from firebase_admin import initialize_app
import requests
import datetime
import base64
import json
import uuid
from urllib.parse import quote

# For cost control, you can set the maximum number of containers that can be
# running at the same time. This helps mitigate the impact of unexpected
# traffic spikes by instead downgrading performance. This limit is a per-function
# limit. You can override the limit for each function using the max_instances
# parameter in the decorator, e.g. @https_fn.on_request(max_instances=5).
set_global_options(max_instances=10)

initialize_app()


def _auth():
    from firebase_admin import auth

    return auth


def _firestore():
    from firebase_admin import firestore

    return firestore


def _storage():
    from firebase_admin import storage

    return storage

RESEND_API_URL = "https://api.resend.com/emails"
RESEND_FROM_EMAIL = "TypeSync <typesync@khonager.de>"
RESEND_API_KEY = SecretParam("RESEND_API_KEY")
REVENUECAT_WEBHOOK_AUTH_TOKEN = SecretParam("REVENUECAT_WEBHOOK_AUTH_TOKEN")
# A comma-separated allow-list of administrator email addresses.  Custom
# Firebase Auth claims (`admin: true`) are also supported.  Keeping this in a
# Functions secret means the mobile client never gets a list of admins or a
# credential that can grant access.
ADMIN_EMAILS = SecretParam("ADMIN_EMAILS")

ACCOUNT_DATA_COLLECTIONS = (
    "notes",
    "folders",
    "homework",
    "calendar_events",
    "timetable_entries",
    "tags",
)

REVENUECAT_PLAN_BY_ENTITLEMENT = {
    "TypeSync Lite": {"tier": 1, "limit": 1 * 1024 * 1024 * 1024},
    "light": {"tier": 1, "limit": 1 * 1024 * 1024 * 1024},
    "plus": {"tier": 2, "limit": 25 * 1024 * 1024 * 1024},
    "pro": {"tier": 3, "limit": 100 * 1024 * 1024 * 1024},
}

REVENUECAT_PLAN_BY_PRODUCT = {
    "monthly": "TypeSync Lite",
    "typesync_light_monthly": "TypeSync Lite",
    "typesync_plus_monthly": "plus",
    "typesync_pro_monthly": "pro",
}

FREE_PLAN = {
    "plan_id": "free",
    "tier": 0,
    "limit": 5 * 1024 * 1024,
}

PLAN_LIMIT_BY_ID = {
    "free": FREE_PLAN["limit"],
    "TypeSync Lite": REVENUECAT_PLAN_BY_ENTITLEMENT["TypeSync Lite"]["limit"],
    "light": REVENUECAT_PLAN_BY_ENTITLEMENT["light"]["limit"],
    "plus": REVENUECAT_PLAN_BY_ENTITLEMENT["plus"]["limit"],
    "pro": REVENUECAT_PLAN_BY_ENTITLEMENT["pro"]["limit"],
}

PLAN_LIMIT_BY_TIER = {
    0: FREE_PLAN["limit"],
    1: REVENUECAT_PLAN_BY_ENTITLEMENT["TypeSync Lite"]["limit"],
    2: REVENUECAT_PLAN_BY_ENTITLEMENT["plus"]["limit"],
    3: REVENUECAT_PLAN_BY_ENTITLEMENT["pro"]["limit"],
}

MAX_ADMIN_GRANT_DURATION_DAYS = 3650


def _plan_from_id(plan_id: str | None) -> dict:
    if plan_id == FREE_PLAN["plan_id"]:
        return FREE_PLAN
    return REVENUECAT_PLAN_BY_ENTITLEMENT.get(plan_id, FREE_PLAN)


def _plan_rank(plan_id: str | None) -> int:
    return _plan_from_id(plan_id)["tier"]


def _admin_emails() -> set[str]:
    return {
        email.strip().lower()
        for email in (ADMIN_EMAILS.value or "").split(",")
        if email.strip()
    }


def _is_admin_request(req: https_fn.CallableRequest) -> bool:
    if not req.auth:
        return False
    token = req.auth.token or {}
    if token.get("admin") is True:
        return True
    email = token.get("email")
    return isinstance(email, str) and email.lower() in _admin_emails()


def _iso_after_days(days: int | None) -> str | None:
    if days is None:
        return None
    return (
        datetime.datetime.now(datetime.timezone.utc)
        + datetime.timedelta(days=days)
    ).isoformat()


def _is_future_iso(value) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        expires_at = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return expires_at > datetime.datetime.now(datetime.timezone.utc)
    except ValueError:
        return False


def _effective_subscription(user_data: dict) -> dict:
    """Returns the highest currently-valid server-owned entitlement."""
    revenuecat_plan_id = user_data.get("revenueCatPlanId")
    if not isinstance(revenuecat_plan_id, str):
        # Backwards compatibility for accounts written before RevenueCat state
        # was kept separately from the effective entitlement.
        revenuecat_plan_id = (
            user_data.get("planId")
            if user_data.get("entitlementSource") == "revenuecat"
            else "free"
        )
    if revenuecat_plan_id not in PLAN_LIMIT_BY_ID:
        revenuecat_plan_id = "free"

    admin_plan_id = user_data.get("adminGrantPlanId")
    admin_active = (
        isinstance(admin_plan_id, str)
        and admin_plan_id in PLAN_LIMIT_BY_ID
        and admin_plan_id != "free"
        and (
            user_data.get("adminGrantExpiresAt") is None
            or _is_future_iso(user_data.get("adminGrantExpiresAt"))
        )
    )
    if admin_active and _plan_rank(admin_plan_id) >= _plan_rank(revenuecat_plan_id):
        plan_id = admin_plan_id
        source = "admin"
        expires_at = user_data.get("adminGrantExpiresAt")
        status = "granted"
    else:
        plan_id = revenuecat_plan_id
        source = "revenuecat" if plan_id != "free" else "free"
        expires_at = user_data.get("revenueCatExpiresAt")
        status = user_data.get("revenueCatSubscriptionStatus") or (
            "active" if plan_id != "free" else "inactive"
        )

    plan = _plan_from_id(plan_id)
    return {
        "subscriptionTier": plan["tier"],
        "planId": plan_id,
        "entitlementSource": source,
        "subscriptionStatus": status,
        "subscriptionExpiresAt": expires_at,
        "currentPeriodEnd": expires_at,
        "cloudStorageLimitBytes": plan["limit"],
    }


def _int_value(value, fallback=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def _storage_limit_from_user(user_data: dict) -> int:
    # Modern entitlement documents retain their source state. Resolve them on
    # the server at request time so an expired complimentary grant cannot keep
    # its old quota merely because the client has not refreshed yet.
    if "adminGrantPlanId" in user_data or "revenueCatPlanId" in user_data:
        return _effective_subscription(user_data)["cloudStorageLimitBytes"]

    explicit_limit = _int_value(user_data.get("cloudStorageLimitBytes"), 0)
    if explicit_limit > 0:
        return explicit_limit

    plan_id = user_data.get("planId")
    if isinstance(plan_id, str) and plan_id in PLAN_LIMIT_BY_ID:
        return PLAN_LIMIT_BY_ID[plan_id]

    tier = _int_value(user_data.get("subscriptionTier"), FREE_PLAN["tier"])
    return PLAN_LIMIT_BY_TIER.get(tier, FREE_PLAN["limit"])


def _storage_usage_for_prefix(bucket, uid: str) -> tuple[int, int]:
    total_bytes = 0
    object_count = 0
    for blob in bucket.list_blobs(prefix=f"users/{uid}/"):
        total_bytes += int(blob.size or 0)
        object_count += 1
    return total_bytes, object_count


def _json_response(
    payload: dict,
    status: int = 200,
    *,
    cors: bool = False,
) -> https_fn.Response:
    headers = {"Content-Type": "application/json"}
    if cors:
        headers.update(
            {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
            }
        )
    return https_fn.Response(
        json.dumps(payload),
        status=status,
        headers=headers,
    )


def _handle_cors_preflight(req: https_fn.Request) -> https_fn.Response | None:
    if req.method == "OPTIONS":
        return _json_response({}, cors=True)
    return None


def _request_json(req: https_fn.Request) -> dict:
    payload = req.get_json(silent=True)
    if not isinstance(payload, dict):
        raise ValueError("Invalid JSON body")
    return payload


def _revenuecat_auth_valid(req: https_fn.Request) -> bool:
    expected = REVENUECAT_WEBHOOK_AUTH_TOKEN.value
    if not expected:
        print("Missing REVENUECAT_WEBHOOK_AUTH_TOKEN configuration")
        return False

    auth_header = req.headers.get("Authorization", "")
    bearer = f"Bearer {expected}"
    return auth_header == expected or auth_header == bearer


def _ms_to_iso(value) -> str | None:
    if value is None:
        return None
    try:
        milliseconds = int(value)
    except (TypeError, ValueError):
        return None
    return datetime.datetime.fromtimestamp(
        milliseconds / 1000,
        datetime.timezone.utc,
    ).isoformat()


def _first_string(value) -> str | None:
    if isinstance(value, str) and value:
        return value
    if isinstance(value, list):
        for item in value:
            if isinstance(item, str) and item:
                return item
    return None


def _plan_id_from_revenuecat_event(event: dict) -> str | None:
    entitlement_id = _first_string(
        event.get("entitlement_ids")
        or event.get("entitlement_id")
        or event.get("entitlementIds")
    )
    if entitlement_id in REVENUECAT_PLAN_BY_ENTITLEMENT:
        return entitlement_id

    product_id = _first_string(
        event.get("product_id")
        or event.get("product_identifier")
        or event.get("productIdentifier")
    )
    return REVENUECAT_PLAN_BY_PRODUCT.get(product_id)


def _revenuecat_status(event_type: str, period_type: str | None) -> str:
    if event_type == "EXPIRATION":
        return "expired"
    if event_type == "BILLING_ISSUE":
        return "past_due"
    if event_type == "CANCELLATION":
        return "canceled"
    if period_type == "TRIAL":
        return "trialing"
    return "active"


def _revenuecat_update_payload(event: dict) -> tuple[str, dict]:
    app_user_id = (
        event.get("app_user_id")
        or event.get("appUserId")
        or event.get("original_app_user_id")
    )
    if not isinstance(app_user_id, str) or not app_user_id:
        raise ValueError("Missing RevenueCat app user id")

    event_type = str(event.get("type") or event.get("event_type") or "").upper()
    period_type = event.get("period_type")
    if isinstance(period_type, str):
        period_type = period_type.upper()

    plan_id = _plan_id_from_revenuecat_event(event)
    if plan_id is None:
        raise ValueError("RevenueCat event does not match a TypeSync plan")
    if event_type == "EXPIRATION":
        plan_id = FREE_PLAN["plan_id"]

    plan = (
        FREE_PLAN
        if plan_id == FREE_PLAN["plan_id"]
        else REVENUECAT_PLAN_BY_ENTITLEMENT[plan_id]
    )
    status = _revenuecat_status(event_type, period_type)
    expiration = _ms_to_iso(
        event.get("expiration_at_ms") or event.get("expirationAtMs")
    )
    event_timestamp_ms = _int_value(
        event.get("event_timestamp_ms") or event.get("eventTimestampMs"),
        0,
    )

    return app_user_id, {
        # Keep RevenueCat's state separate from the effective plan.  An admin
        # grant must survive later webhooks (including an expiration event).
        "revenueCatPlanId": plan_id,
        "revenueCatSubscriptionStatus": status,
        "revenueCatExpiresAt": expiration,
        "revenueCatEventTimestampMs": event_timestamp_ms,
        "revenueCatEventType": event_type,
        "revenueCatProductId": _first_string(
            event.get("product_id")
            or event.get("product_identifier")
            or event.get("productIdentifier")
        ),
        "revenueCatEntitlementIds": event.get("entitlement_ids")
        or event.get("entitlementIds")
        or [],
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


def _build_action_code_settings(data: dict) -> object:
    url = data.get("url")
    if not isinstance(url, str) or not url:
        raise ValueError("Missing action URL")

    kwargs = {
        "url": url,
        "handle_code_in_app": bool(data.get("handleCodeInApp", False)),
    }

    link_domain = data.get("linkDomain")
    if isinstance(link_domain, str) and link_domain:
        kwargs["link_domain"] = link_domain

    android_package_name = data.get("androidPackageName")
    if isinstance(android_package_name, str) and android_package_name:
        kwargs["android_package_name"] = android_package_name
        kwargs["android_install_app"] = bool(data.get("androidInstallApp", False))

    android_minimum_version = data.get("androidMinimumVersion")
    if isinstance(android_minimum_version, str) and android_minimum_version:
        kwargs["android_minimum_version"] = android_minimum_version

    ios_bundle_id = data.get("iOSBundleId")
    if isinstance(ios_bundle_id, str) and ios_bundle_id:
        kwargs["ios_bundle_id"] = ios_bundle_id

    return _auth().ActionCodeSettings(**kwargs)


def _resend_headers() -> dict[str, str]:
    api_key = RESEND_API_KEY.value
    if not api_key:
        raise RuntimeError("Missing RESEND_API_KEY configuration")
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def _send_resend_email(
    *,
    to_email: str,
    subject: str,
    html_body: str,
    text_body: str,
) -> None:
    response = requests.post(
        RESEND_API_URL,
        headers=_resend_headers(),
        json={
            "from": RESEND_FROM_EMAIL,
            "to": [to_email],
            "subject": subject,
            "html": html_body,
            "text": text_body,
        },
        timeout=20,
    )

    if response.status_code < 200 or response.status_code >= 300:
        print(f"Resend send failed: {response.status_code} {response.text}")
        raise RuntimeError("Email delivery failed")


def _password_reset_email_content(email: str, action_link: str) -> tuple[str, str, str]:
    subject = "Reset your TypeSync password"
    html_body = f"""
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #1f2937;">
      <h2 style="margin-bottom: 16px;">Reset your password</h2>
      <p style="line-height: 1.6;">We received a request to reset the TypeSync password for {email}.</p>
      <p style="line-height: 1.6;">Use the button below to choose a new password.</p>
      <p style="margin: 24px 0;">
        <a href="{action_link}" style="background: #111827; color: #ffffff; padding: 12px 20px; text-decoration: none; border-radius: 8px; display: inline-block;">
          Reset password
        </a>
      </p>
      <p style="line-height: 1.6;">If you did not request this, you can safely ignore this email.</p>
      <p style="font-size: 12px; color: #6b7280; line-height: 1.6;">If the button does not work, open this link manually:<br>{action_link}</p>
    </div>
    """.strip()
    text_body = (
        f"We received a request to reset the TypeSync password for {email}.\n\n"
        f"Reset your password here:\n{action_link}\n\n"
        "If you did not request this, you can ignore this email."
    )
    return subject, html_body, text_body


def _magic_link_email_content(action_link: str) -> tuple[str, str, str]:
    subject = "Your TypeSync sign-in link"
    html_body = f"""
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #1f2937;">
      <h2 style="margin-bottom: 16px;">Sign in to TypeSync</h2>
      <p style="line-height: 1.6;">Use the secure link below to sign in to your TypeSync account.</p>
      <p style="margin: 24px 0;">
        <a href="{action_link}" style="background: #111827; color: #ffffff; padding: 12px 20px; text-decoration: none; border-radius: 8px; display: inline-block;">
          Sign in
        </a>
      </p>
      <p style="line-height: 1.6;">If you did not request this link, you can safely ignore this email.</p>
      <p style="font-size: 12px; color: #6b7280; line-height: 1.6;">If the button does not work, open this link manually:<br>{action_link}</p>
    </div>
    """.strip()
    text_body = (
        "Use this secure link to sign in to TypeSync:\n"
        f"{action_link}\n\n"
        "If you did not request this link, you can ignore this email."
    )
    return subject, html_body, text_body


def _verification_email_content(action_link: str) -> tuple[str, str, str]:
    subject = "Verify your TypeSync email"
    html_body = f"""
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #1f2937;">
      <h2 style="margin-bottom: 16px;">Verify your email</h2>
      <p style="line-height: 1.6;">Confirm your email address to finish setting up TypeSync.</p>
      <p style="margin: 24px 0;">
        <a href="{action_link}" style="background: #111827; color: #ffffff; padding: 12px 20px; text-decoration: none; border-radius: 8px; display: inline-block;">
          Verify email
        </a>
      </p>
      <p style="line-height: 1.6;">If you did not create a TypeSync account, you can ignore this email.</p>
      <p style="font-size: 12px; color: #6b7280; line-height: 1.6;">If the button does not work, open this link manually:<br>{action_link}</p>
    </div>
    """.strip()
    text_body = (
        "Confirm your TypeSync email address here:\n"
        f"{action_link}\n\n"
        "If you did not create a TypeSync account, you can ignore this email."
    )
    return subject, html_body, text_body


def _send_password_reset_email_impl(data: dict) -> dict:
    email = (data.get("email") or "").strip()
    if not email:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Email is required."
        )

    settings = _build_action_code_settings(data)

    try:
        action_link = _auth().generate_password_reset_link(
            email,
            action_code_settings=settings,
        )
    except _auth().UserNotFoundError:
        return {"success": True}
    except _auth().InvalidRecipientEmailError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Invalid email address."
        )
    except Exception as exc:
        print(f"Generate password reset link failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to create password reset email."
        )

    subject, html_body, text_body = _password_reset_email_content(email, action_link)
    _send_resend_email(
        to_email=email,
        subject=subject,
        html_body=html_body,
        text_body=text_body,
    )
    return {"success": True}


def _send_magic_link_email_impl(data: dict) -> dict:
    email = (data.get("email") or "").strip()
    if not email:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Email is required."
        )

    settings = _build_action_code_settings(data)

    try:
        action_link = _auth().generate_sign_in_with_email_link(
            email,
            action_code_settings=settings,
        )
    except _auth().InvalidRecipientEmailError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Invalid email address."
        )
    except Exception as exc:
        print(f"Generate sign-in link failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to create sign-in email."
        )

    subject, html_body, text_body = _magic_link_email_content(action_link)
    _send_resend_email(
        to_email=email,
        subject=subject,
        html_body=html_body,
        text_body=text_body,
    )
    return {"success": True}


def _send_verification_email_impl(email: str, data: dict) -> dict:
    if not email:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Email is required."
        )

    settings = _build_action_code_settings(data)

    try:
        action_link = _auth().generate_email_verification_link(
            email,
            action_code_settings=settings,
        )
    except _auth().InvalidRecipientEmailError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Invalid email address."
        )
    except Exception as exc:
        print(f"Generate verification link failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to create verification email."
        )

    subject, html_body, text_body = _verification_email_content(action_link)
    _send_resend_email(
        to_email=email,
        subject=subject,
        html_body=html_body,
        text_body=text_body,
    )
    return {"success": True}


@https_fn.on_call(secrets=[RESEND_API_KEY])
def send_password_reset_email(req: https_fn.CallableRequest) -> dict:
    return _send_password_reset_email_impl(req.data or {})


@https_fn.on_request(secrets=[RESEND_API_KEY])
def send_password_reset_email_http(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        return _json_response(
            _send_password_reset_email_impl(_request_json(req)),
            cors=True,
        )
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=400, cors=True)
    except Exception as exc:
        print(f"Password reset HTTP handler failed: {exc}")
        return _json_response({"error": "Failed to send password reset email."}, status=500, cors=True)


@https_fn.on_call(secrets=[RESEND_API_KEY])
def send_sign_in_link_email(req: https_fn.CallableRequest) -> dict:
    return _send_magic_link_email_impl(req.data or {})


@https_fn.on_request(secrets=[RESEND_API_KEY])
def send_sign_in_link_email_http(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        return _json_response(
            _send_magic_link_email_impl(_request_json(req)),
            cors=True,
        )
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=400, cors=True)
    except Exception as exc:
        print(f"Magic link HTTP handler failed: {exc}")
        return _json_response({"error": "Failed to send sign-in email."}, status=500, cors=True)


@https_fn.on_call(secrets=[RESEND_API_KEY])
def send_verification_email(req: https_fn.CallableRequest) -> dict:
    if not req.auth or not req.auth.token.get("email"):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Authenticated user email is required."
        )
    return _send_verification_email_impl(req.auth.token.get("email"), req.data or {})


@https_fn.on_request(secrets=[RESEND_API_KEY])
def send_verification_email_http(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        uid = _verified_uid(req)
        user = _auth().get_user(uid)
        if not user.email:
            return _json_response({"error": "Authenticated user email is required."}, status=400, cors=True)
        return _json_response(
            _send_verification_email_impl(user.email, _request_json(req)),
            cors=True,
        )
    except https_fn.HttpsError as exc:
        status = 401 if exc.code == https_fn.FunctionsErrorCode.UNAUTHENTICATED else 400
        return _json_response({"error": exc.message}, status=status, cors=True)
    except Exception as exc:
        print(f"Verification email HTTP handler failed: {exc}")
        return _json_response({"error": "Failed to send verification email."}, status=500, cors=True)


def _bearer_token(req: https_fn.Request) -> str | None:
    auth_header = req.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None
    return auth_header[len("Bearer ") :].strip() or None


def _verified_uid(req: https_fn.Request) -> str:
    token = _bearer_token(req)
    if not token:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Missing bearer token."
        )

    try:
        decoded = _auth().verify_id_token(token)
    except Exception as exc:
        print(f"Auth verification failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Invalid auth token."
        )

    uid = decoded.get("uid")
    if not uid:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Authenticated user missing uid."
        )
    return uid


def _delete_query_documents(db, query) -> int:
    """Delete a query in bounded batches and return the number removed."""
    deleted = 0
    while True:
        documents = list(query.limit(400).stream())
        if not documents:
            return deleted

        batch = db.batch()
        for document in documents:
            batch.delete(document.reference)
        batch.commit()
        deleted += len(documents)


def _delete_account_resources(uid: str) -> dict:
    """Remove all server-owned data for a user, then remove the Auth user."""
    db = _firestore().client()
    deleted_documents = 0

    for collection_name in ACCOUNT_DATA_COLLECTIONS:
        query = db.collection(collection_name).where("userId", "==", uid)
        deleted_documents += _delete_query_documents(db, query)

    user_ref = db.collection("users").document(uid)
    deleted_documents += _delete_query_documents(
        db,
        user_ref.collection("settings"),
    )

    # Remove the legacy top-level settings document as well as the current
    # nested settings location.
    legacy_settings_ref = db.collection("settings").document(uid)
    if legacy_settings_ref.get().exists:
        legacy_settings_ref.delete()
        deleted_documents += 1

    deleted_storage_objects = 0
    bucket = _storage().bucket()
    for blob in bucket.list_blobs(prefix=f"users/{uid}/"):
        blob.delete()
        deleted_storage_objects += 1

    if user_ref.get().exists:
        user_ref.delete()
        deleted_documents += 1

    try:
        _auth().delete_user(uid)
    except _auth().UserNotFoundError:
        # This makes a retry safe if the first response was lost after Auth
        # deletion completed.
        pass

    return {
        "deletedDocuments": deleted_documents,
        "deletedStorageObjects": deleted_storage_objects,
    }


@https_fn.on_request()
def delete_account(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight

    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        uid = _verified_uid(req)
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=401, cors=True)

    try:
        result = _delete_account_resources(uid)
        return _json_response({"success": True, **result}, cors=True)
    except Exception as exc:
        print(f"Account deletion failed for uid={uid}: {exc}")
        return _json_response(
            {"error": "Failed to delete account data."},
            status=500,
            cors=True,
        )


@https_fn.on_request()
def upload_storage_object(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight

    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        uid = _verified_uid(req)
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=401, cors=True)

    try:
        payload = req.get_json(silent=True) or {}
        target_uid = payload.get("userId")
        destination_path = payload.get("destinationPath")
        data_b64 = payload.get("dataBase64")
        content_type = payload.get("contentType") or "application/octet-stream"
    except Exception as exc:
        print(f"Bad upload payload: {exc}")
        return _json_response({"error": "Invalid JSON body"}, status=400, cors=True)

    if target_uid != uid:
        return _json_response(
            {"error": "userId does not match authenticated user"},
            status=403,
            cors=True,
        )

    if not destination_path or not data_b64:
        return _json_response(
            {"error": "destinationPath and dataBase64 are required"},
            status=400,
            cors=True,
        )

    object_path = f"users/{uid}/{destination_path}"

    try:
        file_bytes = base64.b64decode(data_b64)
    except Exception as exc:
        print(f"Base64 decode failed: {exc}")
        return _json_response({"error": "Invalid base64 payload"}, status=400, cors=True)

    download_token = str(uuid.uuid4())
    bucket = _storage().bucket()
    blob = bucket.blob(object_path)

    try:
        existing_size = 0
        if blob.exists():
            blob.reload()
            existing_size = int(blob.size or 0)
    except Exception as exc:
        print(f"Existing object lookup failed: {exc}")
        return _json_response(
            {"error": f"Could not inspect existing object: {exc}"},
            status=500,
            cors=True,
        )

    upload_size = len(file_bytes)
    quota_delta = max(upload_size - existing_size, 0)
    db = _firestore().client()
    firestore_module = _firestore()
    user_ref = db.collection("users").document(uid)
    user_snapshot = user_ref.get()
    user_data = user_snapshot.to_dict() or {}
    baseline_usage = None
    if not user_snapshot.exists or "storageUsedBytes" not in user_data:
        baseline_usage, _ = _storage_usage_for_prefix(bucket, uid)
    transaction = db.transaction()

    @firestore_module.transactional
    def reserve_storage(transaction):
        snapshot = user_ref.get(transaction=transaction)
        user_data = snapshot.to_dict() or {}
        current_usage = _int_value(
            user_data.get("storageUsedBytes"),
            baseline_usage or 0,
        )
        storage_limit = _storage_limit_from_user(user_data)
        effective_subscription = (
            _effective_subscription(user_data)
            if (
                "adminGrantPlanId" in user_data
                or "revenueCatPlanId" in user_data
            )
            else None
        )
        next_usage = current_usage + quota_delta
        if next_usage > storage_limit:
            raise ValueError(
                json.dumps(
                    {
                        "code": "quota-exceeded",
                        "usedBytes": current_usage,
                        "requestedBytes": upload_size,
                        "limitBytes": storage_limit,
                    }
                )
            )
        if quota_delta > 0 or baseline_usage is not None or effective_subscription:
            transaction.set(
                user_ref,
                {
                    "storageUsedBytes": next_usage,
                    **(effective_subscription or {}),
                },
                merge=True,
            )
        return next_usage, storage_limit

    try:
        storage_used_bytes, storage_limit_bytes = reserve_storage(transaction)
    except ValueError as exc:
        try:
            payload = json.loads(str(exc))
        except Exception:
            payload = {"error": str(exc)}
        return _json_response(payload, status=403, cors=True)

    try:
        blob.metadata = {"firebaseStorageDownloadTokens": download_token}
        blob.upload_from_string(file_bytes, content_type=content_type)

        bucket_name = bucket.name
        download_url = (
            f"https://firebasestorage.googleapis.com/v0/b/{bucket_name}/o/"
            f"{quote(object_path, safe='')}?alt=media&token={download_token}"
        )

        return _json_response(
            {
                "downloadUrl": download_url,
                "size": len(file_bytes),
                "bucket": bucket_name,
                "path": object_path,
                "storageUsedBytes": storage_used_bytes,
                "storageLimitBytes": storage_limit_bytes,
            },
            cors=True,
        )
    except Exception as exc:
        if quota_delta > 0:
            try:
                user_ref.update(
                    {"storageUsedBytes": max(storage_used_bytes - quota_delta, 0)}
                )
            except Exception as rollback_exc:
                print(f"Storage usage rollback failed: {rollback_exc}")
        print(f"Storage upload failed: {exc}")
        return _json_response({"error": f"Upload failed: {exc}"}, status=500, cors=True)


@https_fn.on_request()
def delete_storage_object(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight

    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        uid = _verified_uid(req)
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=401, cors=True)

    try:
        payload = req.get_json(silent=True) or {}
        target_uid = payload.get("userId")
        object_path = payload.get("objectPath")
    except Exception as exc:
        print(f"Bad delete payload: {exc}")
        return _json_response({"error": "Invalid JSON body"}, status=400, cors=True)

    if target_uid != uid:
        return _json_response(
            {"error": "userId does not match authenticated user"},
            status=403,
            cors=True,
        )

    if not object_path or not isinstance(object_path, str):
        return _json_response({"error": "objectPath is required"}, status=400, cors=True)

    expected_prefix = f"users/{uid}/"
    if not object_path.startswith(expected_prefix):
        return _json_response(
            {"error": "objectPath is outside the authenticated user scope"},
            status=403,
            cors=True,
        )

    try:
        bucket = _storage().bucket()
        blob = bucket.blob(object_path)
        if not blob.exists():
            return _json_response({"error": "Object not found"}, status=404, cors=True)

        blob.reload()
        size = int(blob.size or 0)
        blob.delete()
        db = _firestore().client()
        user_ref = db.collection("users").document(uid)
        user_snapshot = user_ref.get()
        user_data = user_snapshot.to_dict() or {}
        current_usage = _int_value(user_data.get("storageUsedBytes"), 0)
        storage_used_bytes = max(current_usage - size, 0)
        user_ref.set({"storageUsedBytes": storage_used_bytes}, merge=True)

        return _json_response(
            {
                "deleted": True,
                "size": size,
                "bucket": bucket.name,
                "path": object_path,
                "storageUsedBytes": storage_used_bytes,
            },
            cors=True,
        )
    except Exception as exc:
        print(f"Delete storage object failed: {exc}")
        return _json_response({"error": f"Delete failed: {exc}"}, status=500, cors=True)


@https_fn.on_request()
def audit_storage_usage(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight

    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        uid = _verified_uid(req)
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=401, cors=True)

    try:
        payload = req.get_json(silent=True) or {}
        target_uid = payload.get("userId")
    except Exception as exc:
        print(f"Bad audit payload: {exc}")
        return _json_response({"error": "Invalid JSON body"}, status=400, cors=True)

    if target_uid != uid:
        return _json_response(
            {"error": "userId does not match authenticated user"},
            status=403,
            cors=True,
        )

    try:
        bucket = _storage().bucket()
        total_bytes, object_count = _storage_usage_for_prefix(bucket, uid)

        _firestore().client().collection("users").document(uid).set(
            {"storageUsedBytes": total_bytes},
            merge=True,
        )

        return _json_response(
            {
                "storageUsedBytes": total_bytes,
                "storedFileBytes": total_bytes,
                "storedFileCount": object_count,
            },
            cors=True,
        )
    except Exception as exc:
        print(f"Storage audit failed: {exc}")
        return _json_response({"error": f"Audit failed: {exc}"}, status=500, cors=True)


@https_fn.on_request(secrets=[REVENUECAT_WEBHOOK_AUTH_TOKEN])
def revenuecat_webhook(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405)

    if not _revenuecat_auth_valid(req):
        return _json_response({"error": "Unauthorized"}, status=401)

    try:
        payload = _request_json(req)
        event = payload.get("event", payload)
        if not isinstance(event, dict):
            raise ValueError("Missing RevenueCat event payload")

        uid, revenuecat_updates = _revenuecat_update_payload(event)
        user_ref = _firestore().client().collection("users").document(uid)
        existing = user_ref.get().to_dict() or {}
        incoming_event_timestamp = _int_value(
            revenuecat_updates.get("revenueCatEventTimestampMs"),
            0,
        )
        recorded_event_timestamp = _int_value(
            existing.get("revenueCatEventTimestampMs"),
            0,
        )
        if (
            incoming_event_timestamp > 0
            and recorded_event_timestamp > incoming_event_timestamp
        ):
            # RevenueCat retries webhooks and delivery order is not guaranteed.
            # Do not let an older expiration/cancellation undo a newer renewal.
            return _json_response(
                {"success": True, "userId": uid, "ignored": True}
            )
        combined = {**existing, **revenuecat_updates}
        updates = {**revenuecat_updates, **_effective_subscription(combined)}
        user_ref.set(updates, merge=True)
        return _json_response({"success": True, "userId": uid})
    except ValueError as exc:
        return _json_response({"error": str(exc)}, status=400)
    except Exception as exc:
        print(f"RevenueCat webhook failed: {exc}")
        return _json_response(
            {"error": "Failed to process RevenueCat webhook."},
            status=500,
        )


@https_fn.on_call(secrets=[ADMIN_EMAILS])
def get_admin_status(req: https_fn.CallableRequest) -> dict:
    """Lets the app reveal administration controls only to an administrator."""
    return {"isAdmin": _is_admin_request(req)}


@https_fn.on_call(secrets=[ADMIN_EMAILS])
def set_admin_entitlement(req: https_fn.CallableRequest) -> dict:
    """Grants or revokes a bounded complimentary plan for a registered user."""
    if not req.auth:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Sign in before managing entitlements.",
        )
    if not _is_admin_request(req):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="Administrator access is required.",
        )

    data = req.data or {}
    email = data.get("email")
    plan_id = data.get("planId")
    duration_days = data.get("durationDays")
    if not isinstance(email, str) or not email.strip():
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="A target account email is required.",
        )
    if plan_id not in PLAN_LIMIT_BY_ID:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Choose a valid TypeSync plan.",
        )
    # Callable payloads can decode whole JSON numbers as floats in some
    # Firebase Functions runtimes. Normalize those values before validating so
    # the preset 30-day and one-year grants are treated the same as custom ones.
    if isinstance(duration_days, float) and duration_days.is_integer():
        duration_days = int(duration_days)
    if duration_days is not None and (
        type(duration_days) is not int
        or duration_days < 1
        or duration_days > MAX_ADMIN_GRANT_DURATION_DAYS
    ):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message=(
                "Grant duration must be between 1 and "
                f"{MAX_ADMIN_GRANT_DURATION_DAYS} days."
            ),
        )

    try:
        target_user = _auth().get_user_by_email(email.strip())
    except _auth().UserNotFoundError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="No TypeSync account exists for that email address.",
        )
    except Exception as exc:
        print(f"Admin entitlement user lookup failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not find the target account.",
        )

    db = _firestore().client()
    user_ref = db.collection("users").document(target_user.uid)
    existing = user_ref.get().to_dict() or {}
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if plan_id == "free":
        grant_updates = {
            "adminGrantPlanId": _firestore().DELETE_FIELD,
            "adminGrantExpiresAt": _firestore().DELETE_FIELD,
            "adminGrantGrantedBy": _firestore().DELETE_FIELD,
            "adminGrantGrantedAt": _firestore().DELETE_FIELD,
        }
        combined = {
            **existing,
            "adminGrantPlanId": "free",
            "adminGrantExpiresAt": None,
        }
        action = "revoked"
    else:
        expires_at = _iso_after_days(duration_days)
        grant_updates = {
            "adminGrantPlanId": plan_id,
            "adminGrantExpiresAt": expires_at,
            "adminGrantGrantedBy": req.auth.uid,
            "adminGrantGrantedAt": now,
        }
        combined = {**existing, **grant_updates}
        action = "granted"

    effective = _effective_subscription(combined)
    user_ref.set({**grant_updates, **effective, "updatedAt": now}, merge=True)
    return {
        "success": True,
        "action": action,
        "userId": target_user.uid,
        "email": target_user.email,
        "effectivePlanId": effective["planId"],
        "expiresAt": effective["subscriptionExpiresAt"],
    }


@https_fn.on_call()
def verify_gumroad_license(req: https_fn.CallableRequest) -> dict:
    """Disabled: RevenueCat is the sole self-service billing authority."""
    raise https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
        message="Gumroad license activation is no longer supported.",
    )

@https_fn.on_call()
def check_patreon_subscription(req: https_fn.CallableRequest) -> dict:
    """Disabled: RevenueCat is the sole self-service billing authority."""
    raise https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
        message="Patreon subscription activation is no longer supported.",
    )
